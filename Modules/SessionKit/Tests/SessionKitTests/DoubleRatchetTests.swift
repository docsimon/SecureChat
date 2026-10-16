//
//  DoubleRatchetTests.swift
//  SessionKitTests
//
//  The ratchet alone, two states passing messages by hand. There is no
//  published test vector for this exact construction (our KDF labels, keys
//  in the handshake payloads), so the properties are checked one by one,
//  and a known-answer test pins the bytes against accidental change.
//

import Foundation
import CryptoKit
import Testing
@testable import SessionKit

@Suite("DoubleRatchet")
struct DoubleRatchetTests {

    typealias PrivateKey = Curve25519.KeyAgreement.PrivateKey

    /// What the engine does after a handshake: the initiator's first key
    /// travelled in handshake 1, the responder's in handshake 2.
    static func pair(secret: Data = Data(repeating: 7, count: 32), binding: Data = Data(repeating: 9, count: 32),
                     makeKey: @escaping () -> PrivateKey = { PrivateKey() }) throws -> (DoubleRatchet, DoubleRatchet) {
        let adaKey = PrivateKey(), bobKey = PrivateKey()
        let ada = try DoubleRatchet.initiator(secret: secret, sessionBinding: binding, ownKey: adaKey,
                                              remoteKey: bobKey.publicKey, makeKey: makeKey)
        let bob = try DoubleRatchet.responder(secret: secret, sessionBinding: binding, ownKey: bobKey,
                                              remoteKey: adaKey.publicKey, makeKey: makeKey)
        return (ada, bob)
    }

    private func text(_ s: String) -> Data { Data(s.utf8) }
    private func header(_ message: Data) -> Data { message.prefix(DoubleRatchet.headerSize) }
    private func ratchetKey(_ message: Data) -> Data { message.prefix(32) }

    @Test("Both can send at once, and a conversation with many turns reads on both sides")
    func conversation() throws {
        var (ada, bob) = try Self.pair()
        // The responder speaks first: no need to wait for the initiator.
        #expect(try ada.decrypt(try bob.encrypt(text("bob first"))) == text("bob first"))
        for turn in 0..<5 {
            for i in 0..<3 {
                #expect(try bob.decrypt(try ada.encrypt(text("ada \(turn).\(i)"))) == text("ada \(turn).\(i)"))
            }
            #expect(try ada.decrypt(try bob.encrypt(text("bob \(turn)"))) == text("bob \(turn)"))
        }
    }

    @Test("Every message has its own key, and every change of direction a new ratchet key")
    func keysChange() throws {
        var (ada, bob) = try Self.pair()
        let first = try ada.encrypt(text("same")), second = try ada.encrypt(text("same"))
        #expect(first.dropFirst(DoubleRatchet.headerSize) != second.dropFirst(DoubleRatchet.headerSize))
        #expect(ratchetKey(first) == ratchetKey(second), "same direction, same ratchet key")
        _ = try bob.decrypt(first)
        _ = try bob.decrypt(second)
        let reply = try bob.encrypt(text("reply"))
        _ = try ada.decrypt(reply)
        let third = try ada.encrypt(text("same"))
        #expect(ratchetKey(third) != ratchetKey(first), "a new DH step after Bob answered")
    }

    @Test("Forward secrecy: a state stolen now cannot open messages it already read")
    func forwardSecrecy() throws {
        var (ada, bob) = try Self.pair()
        let early = try ada.encrypt(text("before the theft"))
        _ = try bob.decrypt(early)
        var stolen = bob
        #expect(throws: RatchetError.self) { try stolen.decrypt(early) }
    }

    /// Bob only makes a new ratchet key when Ada turns to a new one, so it
    /// takes a full round trip after the theft: until then the stolen
    /// private key still opens Ada's messages.
    @Test("Healing: a state stolen once loses access after a round trip it did not see")
    func postCompromiseSecurity() throws {
        var (ada, bob) = try Self.pair()
        _ = try bob.decrypt(try ada.encrypt(text("hello")))
        var stolen = bob   // the attacker copies Bob's whole state, then only watches

        // Bob answers with the ratchet key the attacker holds; Ada's answer
        // to that is still readable with it.
        _ = try ada.decrypt(try bob.encrypt(text("reply")))
        let exposed = try ada.encrypt(text("still exposed"))
        #expect(try stolen.decrypt(exposed) == text("still exposed"))
        _ = try bob.decrypt(exposed)

        // Bob turned to a key the attacker never saw; Ada answers that.
        _ = try ada.decrypt(try bob.encrypt(text("new key")))
        let healed = try ada.encrypt(text("after healing"))
        #expect(try bob.decrypt(healed) == text("after healing"))
        #expect(throws: RatchetError.self) { try stolen.decrypt(healed) }
    }

    @Test("A tampered message is refused and changes nothing: the next good one opens")
    func tampering() throws {
        var (ada, bob) = try Self.pair()
        let good = try ada.encrypt(text("intact"))
        for index in [0, 33, 39, DoubleRatchet.headerSize + 1, good.count - 1] {
            var bad = good
            bad[bad.startIndex + index] ^= 0x01
            #expect(throws: RatchetError.self) { try bob.decrypt(bad) }
        }
        #expect(try bob.decrypt(good) == text("intact"))
    }

    @Test("Replayed, skipped and reordered messages are refused")
    func order() throws {
        var (ada, bob) = try Self.pair()
        let one = try ada.encrypt(text("1")), two = try ada.encrypt(text("2")), three = try ada.encrypt(text("3"))
        #expect(throws: RatchetError.unexpectedMessage) { try bob.decrypt(two) }
        #expect(try bob.decrypt(one) == text("1"))
        #expect(throws: RatchetError.unexpectedMessage) { try bob.decrypt(one) }
        #expect(throws: RatchetError.unexpectedMessage) { try bob.decrypt(three) }
        #expect(try bob.decrypt(two) == text("2"))

        // A new ratchet key while one of the old chain is still missing.
        _ = try ada.decrypt(try bob.encrypt(text("turn")))
        let fromNewChain = try ada.encrypt(text("4"))
        #expect(throws: RatchetError.unexpectedMessage) { try bob.decrypt(fromNewChain) }
        #expect(try bob.decrypt(three) == text("3"))
        #expect(try bob.decrypt(fromNewChain) == text("4"))
    }

    @Test("A message belongs to its session: another session's state cannot open it")
    func boundToTheSession() throws {
        var (ada, _) = try Self.pair(binding: Data(repeating: 1, count: 32))
        let message = try ada.encrypt(text("this session only"))
        // Same secret and keys could not be reached anyway; the binding alone
        // must also refuse it.
        var (_, other) = try Self.pair(binding: Data(repeating: 2, count: 32))
        #expect(throws: RatchetError.self) { try other.decrypt(message) }
    }

    @Test("Malformed messages are refused")
    func malformed() throws {
        var (_, bob) = try Self.pair()
        #expect(throws: RatchetError.malformedMessage) { try bob.decrypt(Data(count: DoubleRatchet.overhead - 1)) }
    }

    @Test("Known answer: the bytes for fixed keys do not change by accident")
    func knownAnswer() throws {
        func key(_ byte: UInt8) throws -> PrivateKey { try PrivateKey(rawRepresentation: Data(repeating: byte, count: 32)) }
        var next: UInt8 = 0x30
        let makeKey = { () -> PrivateKey in next += 1; return try! key(next) }
        let secret = Data(repeating: 0x11, count: 32), binding = Data(repeating: 0x22, count: 32)
        var ada = try DoubleRatchet.initiator(secret: secret, sessionBinding: binding, ownKey: try key(0x01),
                                              remoteKey: try key(0x02).publicKey, makeKey: makeKey)
        var bob = try DoubleRatchet.responder(secret: secret, sessionBinding: binding, ownKey: try key(0x02),
                                              remoteKey: try key(0x01).publicKey, makeKey: makeKey)
        let fromAda = try ada.encrypt(text("ada"))
        let fromBob = try bob.encrypt(text("bob"))
        #expect(try bob.decrypt(fromAda) == text("ada"))
        #expect(try ada.decrypt(fromBob) == text("bob"))
        #expect(fromAda.hexString == Self.expectedFromAda)
        #expect(fromBob.hexString == Self.expectedFromBob)
    }

    static let expectedFromAda = "a4e09292b651c278b9772c569f5fa9bb13d906b46ab68c9df9dc2b4409f8a209"
        + "0000000000000000" + "4007feb5e7cbc0bf5c45e1fb224df1fffd8935"
    static let expectedFromBob = "04f5f29162c31a8defa18e6e742224ee806fc1718a278be859ba5620402b8f3a"
        + "0000000000000000" + "ca023e998c014f46d07284d2265fd4a6dfec1e"
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
