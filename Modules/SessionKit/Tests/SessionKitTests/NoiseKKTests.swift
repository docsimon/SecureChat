//
//  NoiseKKTests.swift
//  SessionKitTests
//
//  The handshake against the published test vector for
//  Noise_KK_25519_ChaChaPoly_SHA256 (cacophony's vectors, the set the Noise
//  implementations cross-check against), then the failures that matter.
//

import Foundation
import CryptoKit
import Testing
@testable import SessionKit

@Suite("Noise KK")
struct NoiseKKTests {

    // From cacophony/vectors/cacophony.txt, protocol_name
    // "Noise_KK_25519_ChaChaPoly_SHA256".
    enum Vector {
        static let prologue = hex("4a6f686e2047616c74")
        static let initStatic = hex("e61ef9919cde45dd5f82166404bd08e38bceb5dfdfded0a34c8df7ed542214d1")
        static let initEphemeral = hex("893e28b9dc6ca8d611ab664754b8ceb7bac5117349a4439a6b0569da977c464a")
        static let respStatic = hex("4a3acbfdb163dec651dfa3194dece676d437029c62a408b4c5ea9114246e4893")
        static let respEphemeral = hex("bbdb4cdbd309f1a1f2e1456967fe288cadd6f712d65dc7b7793d5e63da6b375b")
        static let handshakeHash = hex("24c6b51ecb76277140ca018b5985bc9f03de321dae2d34dcae433dafef0131d9")
        /// (payload, ciphertext), alternating initiator → responder first.
        static let messages: [(Data, Data)] = [
            (hex("4c756477696720766f6e204d69736573"),
             hex("ca35def5ae56cec33dc2036731ab14896bc4c75dbb07a61f879f8e3afa4c79440177015efc1fe7a37c629af7120a96274e6ab7afcc9261901d0e09ae32a5bb96")),
            (hex("4d757272617920526f746862617264"),
             hex("95ebc60d2b1fa672c1f46a8aa265ef51bfe38e7ccb39ec5be34069f144808843b274d3429adc47ca093ba63ef90f8da89fda108db471dccfa4894aa7b00003")),
            (hex("462e20412e20486179656b"),
             hex("966b05bc69ec01b8454d3160a214e6f24a3d884eb31ec2408af63f")),
            (hex("4361726c204d656e676572"),
             hex("0ad887fba4f611bbb4afe44ba3556b8164332ca7d5934634d63d80")),
            (hex("4a65616e2d426170746973746520536179"),
             hex("012b28ae646ae7830e2c5472cb023eab071c1db3d8413ec69b513b83832f974c2d")),
            (hex("457567656e2042f6686d20766f6e2042617765726b"),
             hex("bb3e6a48160d9c5971d37f975727294e0d868342db31832e54d07191ab0ca3c3703b5ed3d9")),
        ]
    }

    private func key(_ data: Data) throws -> Curve25519.KeyAgreement.PrivateKey {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    @Test("Matches the published test vector, handshake and transport")
    func testVector() throws {
        let initStatic = try key(Vector.initStatic), respStatic = try key(Vector.respStatic)
        var initiator = NoiseKKInitiator(prologue: Vector.prologue, localStatic: initStatic,
                                         remoteStatic: respStatic.publicKey,
                                         ephemeral: try key(Vector.initEphemeral))
        var responder = NoiseKKResponder(prologue: Vector.prologue, localStatic: respStatic,
                                         remoteStatic: initStatic.publicKey,
                                         ephemeral: try key(Vector.respEphemeral))

        let m1 = try initiator.writeMessage1(payload: Vector.messages[0].0)
        #expect(m1 == Vector.messages[0].1)
        #expect(try responder.readMessage1(m1) == Vector.messages[0].0)

        let (m2, responderTransport) = try responder.writeMessage2(payload: Vector.messages[1].0)
        #expect(m2 == Vector.messages[1].1)
        let (payload2, initiatorTransport) = try initiator.readMessage2(m2)
        #expect(payload2 == Vector.messages[1].0)

        #expect(initiatorTransport.handshakeHash == Vector.handshakeHash)
        #expect(responderTransport.handshakeHash == Vector.handshakeHash)

        var a = initiatorTransport, b = responderTransport
        for (index, (payload, ciphertext)) in Vector.messages.enumerated().dropFirst(2) {
            if index % 2 == 0 {
                let sent = try a.send.encrypt(payload)
                #expect(sent == ciphertext)
                #expect(try b.receive.decrypt(sent) == payload)
            } else {
                let sent = try b.send.encrypt(payload)
                #expect(sent == ciphertext)
                #expect(try a.receive.decrypt(sent) == payload)
            }
        }
    }

    @Test("A sender whose static key the responder does not expect is refused at message 1")
    func wrongInitiatorKeyIsRefused() throws {
        let stranger = Curve25519.KeyAgreement.PrivateKey()
        let expected = Curve25519.KeyAgreement.PrivateKey()
        let responderKey = Curve25519.KeyAgreement.PrivateKey()
        var initiator = NoiseKKInitiator(prologue: Data(), localStatic: stranger,
                                         remoteStatic: responderKey.publicKey)
        var responder = NoiseKKResponder(prologue: Data(), localStatic: responderKey,
                                         remoteStatic: expected.publicKey)

        let m1 = try initiator.writeMessage1()

        #expect(throws: NoiseError.decryptFailed) { try responder.readMessage1(m1) }
    }

    @Test("A different prologue fails the handshake")
    func prologueIsBound() throws {
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        var initiator = NoiseKKInitiator(prologue: Data("v1".utf8), localStatic: a, remoteStatic: b.publicKey)
        var responder = NoiseKKResponder(prologue: Data("v2".utf8), localStatic: b, remoteStatic: a.publicKey)

        let m1 = try initiator.writeMessage1()

        #expect(throws: NoiseError.decryptFailed) { try responder.readMessage1(m1) }
    }

    @Test("A tampered or replayed transport message is refused, and the next good one still opens")
    func transportRefusesTamperingAndReplay() throws {
        var (sender, receiver) = try handshake()
        let first = try sender.send.encrypt(Data("one".utf8))
        let second = try sender.send.encrypt(Data("two".utf8))

        var tampered = first
        tampered[tampered.startIndex] ^= 0x01
        #expect(throws: NoiseError.decryptFailed) { try receiver.receive.decrypt(tampered) }
        #expect(try receiver.receive.decrypt(first) == Data("one".utf8))
        #expect(throws: NoiseError.decryptFailed) { try receiver.receive.decrypt(first) }
        #expect(try receiver.receive.decrypt(second) == Data("two".utf8))
    }

    private func handshake() throws -> (NoiseTransport, NoiseTransport) {
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        var initiator = NoiseKKInitiator(prologue: Data(), localStatic: a, remoteStatic: b.publicKey)
        var responder = NoiseKKResponder(prologue: Data(), localStatic: b, remoteStatic: a.publicKey)
        _ = try responder.readMessage1(try initiator.writeMessage1())
        let (m2, responderTransport) = try responder.writeMessage2()
        return (try initiator.readMessage2(m2).transport, responderTransport)
    }
}

func hex(_ string: String) -> Data {
    var data = Data()
    var index = string.startIndex
    while index < string.endIndex {
        let next = string.index(index, offsetBy: 2)
        data.append(UInt8(string[index..<next], radix: 16)!)
        index = next
    }
    return data
}
