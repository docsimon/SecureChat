//
//  NoiseKK.swift
//  SessionKit
//
//  Noise_KK_25519_ChaChaPoly_SHA256, written to the Noise specification
//  (revision 34) on CryptoKit. Only what KK needs: no PSK, no fallback, no
//  other patterns. Checked against the published test vector
//  (NoiseKKTests).
//
//    -> s
//    <- s
//    ...
//    -> e, es, ss
//    <- e, ee, se
//

import Foundation
import CryptoKit

public enum NoiseError: Error, Equatable {
    /// Authentication failed: wrong key, tampered or replayed message.
    case decryptFailed
    /// A message too short to hold what the pattern says it holds.
    case malformedMessage
    case invalidPublicKey
    /// 2^64 - 1 messages in one direction. Unreachable in practice.
    case nonceExhausted
}

/// The two directions of an established session.
public struct NoiseTransport {
    public internal(set) var send: CipherState
    public internal(set) var receive: CipherState
    /// Identical on both sides when the handshake succeeded.
    public let handshakeHash: Data
}

/// Starts the handshake: the phone that opened the chat.
public struct NoiseKKInitiator {
    private var symmetric: SymmetricState
    private let localStatic: Curve25519.KeyAgreement.PrivateKey
    private let remoteStatic: Curve25519.KeyAgreement.PublicKey
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey

    /// - Parameter ephemeral: injectable for the test vector only; leave the default.
    public init(prologue: Data,
                localStatic: Curve25519.KeyAgreement.PrivateKey,
                remoteStatic: Curve25519.KeyAgreement.PublicKey,
                ephemeral: Curve25519.KeyAgreement.PrivateKey = .init()) {
        self.localStatic = localStatic
        self.remoteStatic = remoteStatic
        self.ephemeral = ephemeral
        symmetric = SymmetricState(prologue: prologue,
                                   initiatorStatic: localStatic.publicKey,
                                   responderStatic: remoteStatic)
    }

    /// `-> e, es, ss`
    public mutating func writeMessage1(payload: Data = Data()) throws -> Data {
        let e = ephemeral.publicKey.rawRepresentation
        symmetric.mixHash(e)
        symmetric.mixKey(try dh(ephemeral, remoteStatic))
        symmetric.mixKey(try dh(localStatic, remoteStatic))
        return e + (try symmetric.encryptAndHash(payload))
    }

    /// `<- e, ee, se`. Returns the responder's payload and the transport.
    public mutating func readMessage2(_ message: Data) throws -> (payload: Data, transport: NoiseTransport) {
        let (re, rest) = try splitEphemeral(message)
        symmetric.mixHash(re.rawRepresentation)
        symmetric.mixKey(try dh(ephemeral, re))
        symmetric.mixKey(try dh(localStatic, re))
        let payload = try symmetric.decryptAndHash(rest)
        let (c1, c2) = symmetric.split()
        return (payload, NoiseTransport(send: c1, receive: c2, handshakeHash: symmetric.h))
    }
}

/// Answers the handshake.
public struct NoiseKKResponder {
    private var symmetric: SymmetricState
    private let localStatic: Curve25519.KeyAgreement.PrivateKey
    private let remoteStatic: Curve25519.KeyAgreement.PublicKey
    private let ephemeral: Curve25519.KeyAgreement.PrivateKey
    private var remoteEphemeral: Curve25519.KeyAgreement.PublicKey?

    /// - Parameter ephemeral: injectable for the test vector only; leave the default.
    public init(prologue: Data,
                localStatic: Curve25519.KeyAgreement.PrivateKey,
                remoteStatic: Curve25519.KeyAgreement.PublicKey,
                ephemeral: Curve25519.KeyAgreement.PrivateKey = .init()) {
        self.localStatic = localStatic
        self.remoteStatic = remoteStatic
        self.ephemeral = ephemeral
        symmetric = SymmetricState(prologue: prologue,
                                   initiatorStatic: remoteStatic,
                                   responderStatic: localStatic.publicKey)
    }

    /// `-> e, es, ss`. Throws `.decryptFailed` when the sender does not hold
    /// the static key we expect for them.
    public mutating func readMessage1(_ message: Data) throws -> Data {
        let (re, rest) = try splitEphemeral(message)
        remoteEphemeral = re
        symmetric.mixHash(re.rawRepresentation)
        symmetric.mixKey(try dh(localStatic, re))
        symmetric.mixKey(try dh(localStatic, remoteStatic))
        return try symmetric.decryptAndHash(rest)
    }

    /// `<- e, ee, se`. Call after `readMessage1`.
    public mutating func writeMessage2(payload: Data = Data()) throws -> (message: Data, transport: NoiseTransport) {
        guard let remoteEphemeral else { throw NoiseError.malformedMessage }
        let e = ephemeral.publicKey.rawRepresentation
        symmetric.mixHash(e)
        symmetric.mixKey(try dh(ephemeral, remoteEphemeral))
        symmetric.mixKey(try dh(ephemeral, remoteStatic))
        let message = e + (try symmetric.encryptAndHash(payload))
        let (c1, c2) = symmetric.split()
        return (message, NoiseTransport(send: c2, receive: c1, handshakeHash: symmetric.h))
    }
}

// MARK: - CipherState

public struct CipherState {
    private let key: SymmetricKey
    private var nonce: UInt64 = 0

    init(key: SymmetricKey) {
        self.key = key
    }

    public mutating func encrypt(_ plaintext: Data, associatedData: Data = Data()) throws -> Data {
        guard nonce < .max else { throw NoiseError.nonceExhausted }
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: Self.chaChaNonce(nonce),
                                      authenticating: associatedData)
        nonce += 1
        return box.ciphertext + box.tag
    }

    /// The nonce only advances on success, as the specification requires.
    public mutating func decrypt(_ ciphertext: Data, associatedData: Data = Data()) throws -> Data {
        guard nonce < .max else { throw NoiseError.nonceExhausted }
        guard ciphertext.count >= 16 else { throw NoiseError.malformedMessage }
        do {
            let box = try ChaChaPoly.SealedBox(nonce: Self.chaChaNonce(nonce),
                                               ciphertext: ciphertext.dropLast(16),
                                               tag: ciphertext.suffix(16))
            let plaintext = try ChaChaPoly.open(box, using: key, authenticating: associatedData)
            nonce += 1
            return plaintext
        } catch {
            throw NoiseError.decryptFailed
        }
    }

    /// 32 zero bits followed by the counter, little endian (§12.4).
    private static func chaChaNonce(_ n: UInt64) -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: n.littleEndian) { bytes.append(contentsOf: $0) }
        // 12 bytes by construction.
        return try! ChaChaPoly.Nonce(data: bytes)
    }
}

// MARK: - SymmetricState

private struct SymmetricState {
    static let protocolName = Data("Noise_KK_25519_ChaChaPoly_SHA256".utf8)

    var ck: Data
    var h: Data
    var cipher: CipherState?

    /// InitializeSymmetric, the prologue, then KK's pre-messages: the
    /// initiator's static key, then the responder's.
    init(prologue: Data,
         initiatorStatic: Curve25519.KeyAgreement.PublicKey,
         responderStatic: Curve25519.KeyAgreement.PublicKey) {
        // The name is exactly HASHLEN (32) bytes, so it is used as is.
        h = Self.protocolName
        ck = h
        mixHash(prologue)
        mixHash(initiatorStatic.rawRepresentation)
        mixHash(responderStatic.rawRepresentation)
    }

    mutating func mixHash(_ data: Data) {
        h = Data(SHA256.hash(data: h + data))
    }

    mutating func mixKey(_ inputKeyMaterial: Data) {
        let (newChainingKey, key) = hkdf(ck, inputKeyMaterial)
        ck = newChainingKey
        cipher = CipherState(key: SymmetricKey(data: key))
    }

    mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        // KK always has a key by the time a payload is written.
        guard var cipher else { throw NoiseError.malformedMessage }
        let ciphertext = try cipher.encrypt(plaintext, associatedData: h)
        self.cipher = cipher
        mixHash(ciphertext)
        return ciphertext
    }

    mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        guard var cipher else { throw NoiseError.malformedMessage }
        let plaintext = try cipher.decrypt(ciphertext, associatedData: h)
        self.cipher = cipher
        mixHash(ciphertext)
        return plaintext
    }

    func split() -> (CipherState, CipherState) {
        let (k1, k2) = hkdf(ck, Data())
        return (CipherState(key: SymmetricKey(data: k1)), CipherState(key: SymmetricKey(data: k2)))
    }

    /// HKDF with two outputs, as defined in §4.3 on HMAC-SHA256.
    private func hkdf(_ chainingKey: Data, _ inputKeyMaterial: Data) -> (Data, Data) {
        let tempKey = SymmetricKey(data: hmac(SymmetricKey(data: chainingKey), inputKeyMaterial))
        let output1 = hmac(tempKey, Data([0x01]))
        let output2 = hmac(tempKey, output1 + Data([0x02]))
        return (output1, output2)
    }

    private func hmac(_ key: SymmetricKey, _ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }
}

// MARK: - Helpers

private func dh(_ privateKey: Curve25519.KeyAgreement.PrivateKey,
                _ publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
    let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    return secret.withUnsafeBytes { Data($0) }
}

private func splitEphemeral(_ message: Data) throws -> (Curve25519.KeyAgreement.PublicKey, Data) {
    guard message.count >= 32 + 16 else { throw NoiseError.malformedMessage }
    let start = message.startIndex
    guard let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: message[start..<start + 32]) else {
        throw NoiseError.invalidPublicKey
    }
    return (key, Data(message[(start + 32)...]))
}
