//
//  DoubleRatchet.swift
//  SessionKit
//
//  The Double Ratchet (Signal's specification, revision 4) for the messages
//  of one session (session-workflow.md, "Double Ratchet"). Every message is
//  sealed with its own key, derived from a chain that only moves forward and
//  forgotten once used; every change of direction mixes a fresh X25519
//  exchange into the root chain.
//
//  It lives as long as the session, in memory only (option A, 2026-10-16):
//  the next session starts from a new Noise handshake. Its messages travel
//  inside Noise transport messages, which arrive in order or not at all, so
//  there are no skipped message keys to keep: a message out of order is
//  refused (MAX_SKIP = 0).
//
//  Header (40 bytes, in the clear inside the Noise ciphertext):
//    [0..31]   the sender's current ratchet public key
//    [32..35]  PN: messages sent on the sender's previous chain (big endian)
//    [36..39]  N: this message's number on its chain (big endian)
//

import Foundation
import CryptoKit

public enum RatchetError: Error, Equatable {
    case malformedMessage
    case invalidPublicKey
    /// Not the next message: out of order, replayed or skipped.
    case unexpectedMessage
    case decryptFailed
}

struct DoubleRatchet {

    static let headerSize = 32 + 4 + 4
    /// Header plus the ChaChaPoly tag.
    static let overhead = headerSize + 16

    typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey
    typealias PublicKey = Curve25519.KeyAgreement.PublicKey

    private var rootKey: Data
    private var ownKey: PrivateKey
    private var remoteKey: PublicKey
    private var sendChain: Data
    /// Nil until the peer's first message on a key of theirs we ratcheted to.
    private var receiveChain: Data?
    private var sent: UInt32 = 0
    private var received: UInt32 = 0
    private var previousSent: UInt32 = 0
    /// Binds every message to this session (the Noise handshake hash).
    private let sessionBinding: Data
    private let makeKey: () -> PrivateKey

    /// The phone that sent handshake 1. `ownKey` went out in its payload,
    /// `remoteKey` came back in handshake 2's.
    static func initiator(secret: Data, sessionBinding: Data, ownKey: PrivateKey, remoteKey: PublicKey,
                          makeKey: @escaping () -> PrivateKey = { PrivateKey() }) throws -> DoubleRatchet {
        let (root, send) = kdfRoot(secret, try dh(ownKey, remoteKey))
        return DoubleRatchet(rootKey: root, ownKey: ownKey, remoteKey: remoteKey, sendChain: send,
                             receiveChain: nil, sessionBinding: sessionBinding, makeKey: makeKey)
    }

    /// The phone that answered. It receives on the chain the initiator sends
    /// on, then ratchets once at once, so both can send straight away.
    static func responder(secret: Data, sessionBinding: Data, ownKey: PrivateKey, remoteKey: PublicKey,
                          makeKey: @escaping () -> PrivateKey = { PrivateKey() }) throws -> DoubleRatchet {
        let (root1, receive) = kdfRoot(secret, try dh(ownKey, remoteKey))
        let next = makeKey()
        let (root2, send) = kdfRoot(root1, try dh(next, remoteKey))
        return DoubleRatchet(rootKey: root2, ownKey: next, remoteKey: remoteKey, sendChain: send,
                             receiveChain: receive, sessionBinding: sessionBinding, makeKey: makeKey)
    }

    private init(rootKey: Data, ownKey: PrivateKey, remoteKey: PublicKey, sendChain: Data,
                 receiveChain: Data?, sessionBinding: Data, makeKey: @escaping () -> PrivateKey) {
        self.rootKey = rootKey
        self.ownKey = ownKey
        self.remoteKey = remoteKey
        self.sendChain = sendChain
        self.receiveChain = receiveChain
        self.sessionBinding = sessionBinding
        self.makeKey = makeKey
    }

    /// Header followed by the ciphertext. The message key is gone on return.
    mutating func encrypt(_ plaintext: Data) throws -> Data {
        guard sent < .max else { throw RatchetError.unexpectedMessage }
        let (messageKey, next) = Self.kdfChain(sendChain)
        sendChain = next
        let header = ownKey.publicKey.rawRepresentation + bigEndian(previousSent) + bigEndian(sent)
        sent += 1
        return header + (try Self.seal(plaintext, messageKey: messageKey, associatedData: sessionBinding + header))
    }

    /// Changes nothing unless it succeeds: a refused message leaves the
    /// state as it was.
    mutating func decrypt(_ message: Data) throws -> Data {
        guard message.count >= Self.overhead else { throw RatchetError.malformedMessage }
        let bytes = [UInt8](message)
        guard let key = try? PublicKey(rawRepresentation: bytes[0..<32]) else {
            throw RatchetError.invalidPublicKey
        }
        let previous = uint32(bytes[32..<36]), number = uint32(bytes[36..<40])
        var next = self
        if key.rawRepresentation != remoteKey.rawRepresentation {
            // Every message of the chain it replaces must have arrived.
            guard previous == received else {
                throw RatchetError.unexpectedMessage
            }
            try next.step(to: key)
        }
        guard let chain = next.receiveChain, number == next.received else { throw RatchetError.unexpectedMessage }
        let (messageKey, following) = Self.kdfChain(chain)
        let plaintext = try Self.open(Data(bytes[Self.headerSize...]), messageKey: messageKey,
                                      associatedData: sessionBinding + Data(bytes[0..<Self.headerSize]))
        next.receiveChain = following
        next.received += 1
        self = next
        return plaintext
    }

    /// The DH ratchet: the peer turned to a new key.
    private mutating func step(to key: PublicKey) throws {
        previousSent = sent
        sent = 0
        received = 0
        remoteKey = key
        let (root1, receive) = Self.kdfRoot(rootKey, try dh(ownKey, remoteKey))
        ownKey = makeKey()
        let (root2, send) = Self.kdfRoot(root1, try dh(ownKey, remoteKey))
        rootKey = root2
        receiveChain = receive
        sendChain = send
    }

    // MARK: KDFs

    /// KDF_RK: HKDF-SHA256, the root key as salt.
    static func kdfRoot(_ rootKey: Data, _ dhOutput: Data) -> (rootKey: Data, chainKey: Data) {
        let output = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: dhOutput), salt: rootKey,
                                            info: Data("SecureChat ratchet root".utf8), outputByteCount: 64)
            .withUnsafeBytes { Data($0) }
        return (output.prefix(32), output.suffix(32))
    }

    /// KDF_CK: HMAC-SHA256 with constant inputs, as the specification suggests.
    static func kdfChain(_ chainKey: Data) -> (messageKey: Data, chainKey: Data) {
        let key = SymmetricKey(data: chainKey)
        return (Data(HMAC<SHA256>.authenticationCode(for: Data([0x01]), using: key)),
                Data(HMAC<SHA256>.authenticationCode(for: Data([0x02]), using: key)))
    }

    /// ChaChaPoly key and nonce, both from the message key, used once.
    private static func messageCipher(_ messageKey: Data) -> (SymmetricKey, ChaChaPoly.Nonce) {
        let output = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: messageKey), salt: Data(count: 32),
                                            info: Data("SecureChat ratchet message".utf8), outputByteCount: 44)
            .withUnsafeBytes { Data($0) }
        // 12 bytes by construction.
        return (SymmetricKey(data: output.prefix(32)), try! ChaChaPoly.Nonce(data: output.suffix(12)))
    }

    static func seal(_ plaintext: Data, messageKey: Data, associatedData: Data) throws -> Data {
        let (key, nonce) = messageCipher(messageKey)
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: associatedData)
        return box.ciphertext + box.tag
    }

    static func open(_ ciphertext: Data, messageKey: Data, associatedData: Data) throws -> Data {
        let (key, nonce) = messageCipher(messageKey)
        do {
            let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext.dropLast(16),
                                               tag: ciphertext.suffix(16))
            return try ChaChaPoly.open(box, using: key, authenticating: associatedData)
        } catch {
            throw RatchetError.decryptFailed
        }
    }
}

private func dh(_ privateKey: Curve25519.KeyAgreement.PrivateKey,
                _ publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
    try privateKey.sharedSecretFromKeyAgreement(with: publicKey).withUnsafeBytes { Data($0) }
}

private func bigEndian(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

private func uint32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    bytes.reduce(0) { $0 << 8 | UInt32($1) }
}
