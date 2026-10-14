//
//  SessionEngineTests.swift
//  SessionKitTests
//
//  Two or three engines passing frames through `TestRelay`, which does what
//  the real relay does: delivers a frame to the addressed peer with the
//  routing id replaced by the sender's.
//

import Foundation
import CryptoKit
import Testing
@testable import SessionKit

/// A phone: identity, routing id, contacts, engine.
final class Phone {
    let key = Curve25519.KeyAgreement.PrivateKey()
    let id: Data
    var contacts: [Data: Curve25519.KeyAgreement.PublicKey] = [:]
    private(set) var engine: SessionEngine!
    var events: [SessionEngine.Event] = []

    init(id: UInt8) {
        self.id = Data(repeating: id, count: RoutingID.size)
        restart()
    }

    /// A fresh engine with the same identity, as after an app relaunch.
    func restart() {
        engine = SessionEngine(localStatic: key, localRoutingID: id, contactKey: { [unowned self] in contacts[$0] })
    }

    func pair(with other: Phone) {
        contacts[other.id] = other.key.publicKey
        other.contacts[id] = key.publicKey
    }
}

/// Delivers frames between phones until nothing is left in flight.
final class TestRelay {
    private var phones: [Data: Phone] = [:]
    private var inFlight: [(from: Phone, frame: Data)] = []
    private(set) var framesSeen: [Data] = []
    var online: Set<Data> = []

    func connect(_ phone: Phone) {
        phones[phone.id] = phone
        online.insert(phone.id)
    }

    func submit(_ output: SessionEngine.Output, from phone: Phone) {
        phone.events += output.events
        inFlight += output.frames.map { (phone, $0) }
    }

    func run() throws {
        while !inFlight.isEmpty {
            let (sender, data) = inFlight.removeFirst()
            framesSeen.append(data)
            let frame = try RelayFrame(decoding: data)
            guard online.contains(frame.peer), let recipient = phones[frame.peer] else {
                let reply = try RelayFrame(kind: .peerUnavailable, peer: frame.peer).encoded()
                framesSeen.append(reply)
                submit(sender.engine.receive(reply), from: sender)
                continue
            }
            let delivered = try RelayFrame(kind: frame.kind, peer: sender.id, body: frame.body).encoded()
            framesSeen.append(delivered)
            submit(recipient.engine.receive(delivered), from: recipient)
        }
    }
}

@Suite("SessionEngine")
struct SessionEngineTests {

    let ada = Phone(id: 0x0A), bob = Phone(id: 0x0B)
    let relay = TestRelay()

    init() {
        ada.pair(with: bob)
        relay.connect(ada)
        relay.connect(bob)
    }

    @Test("Opening a chat establishes a session; text flows both ways")
    func openAndTalk() throws {
        relay.submit(try ada.engine.open(bob.id), from: ada)
        try relay.run()
        #expect(ada.events == [.established(peer: bob.id)])
        #expect(bob.events == [.established(peer: ada.id)])

        relay.submit(try ada.engine.send(.text("hi Bob"), to: bob.id), from: ada)
        relay.submit(try bob.engine.send(.text("hi Ada 👋"), to: ada.id), from: bob)
        try relay.run()

        #expect(bob.events.last == .received(peer: ada.id, .text("hi Bob")))
        #expect(ada.events.last == .received(peer: bob.id, .text("hi Ada 👋")))
    }

    @Test("A message written before the session opens is sent once it does")
    func queuedUntilEstablished() throws {
        relay.submit(try ada.engine.send(.text("first"), to: bob.id), from: ada)
        relay.submit(try ada.engine.send(.text("second"), to: bob.id), from: ada)
        try relay.run()

        #expect(bob.events == [.established(peer: ada.id),
                               .received(peer: ada.id, .text("first")),
                               .received(peer: ada.id, .text("second"))])
    }

    @Test("A stranger is refused without an answer, so it learns nothing")
    func strangerIsRefusedSilently() throws {
        let eve = Phone(id: 0x0E)
        eve.contacts[ada.id] = ada.key.publicKey   // Eve photographed Ada's code
        relay.connect(eve)

        relay.submit(try eve.engine.open(ada.id), from: eve)
        try relay.run()

        #expect(ada.events == [.refused(peer: eve.id, .notAContact)])
        #expect(eve.events.isEmpty, "no reply of any kind")
    }

    @Test("Someone using a contact's routing id without their key cannot open a session")
    func wrongKeyForAContactIsRefused() throws {
        relay.submit(try ada.engine.open(bob.id), from: ada)
        try relay.run()
        let impostor = Phone(id: 0x0B)            // Bob's routing id, not Bob's key
        impostor.contacts[ada.id] = ada.key.publicKey

        let output = try impostor.engine.open(ada.id)
        let delivered = try RelayFrame(kind: .deliver, peer: bob.id,
                                       body: RelayFrame(decoding: output.frames[0]).body).encoded()
        let answer = ada.engine.receive(delivered)

        #expect(answer.frames.isEmpty)
        #expect(answer.events == [.refused(peer: bob.id, .handshakeFailed)])
        #expect(ada.engine.isEstablished(with: bob.id), "the real session survives a forged first message")
    }

    @Test("Both open the chat at once: one session, messages flow")
    func simultaneousOpen() throws {
        relay.submit(try ada.engine.send(.text("from Ada"), to: bob.id), from: ada)
        relay.submit(try bob.engine.send(.text("from Bob"), to: ada.id), from: bob)
        try relay.run()

        #expect(ada.events.filter { $0 == .established(peer: bob.id) }.count == 1)
        #expect(bob.events.filter { $0 == .established(peer: ada.id) }.count == 1)
        #expect(ada.events.contains(.received(peer: bob.id, .text("from Bob"))))
        #expect(bob.events.contains(.received(peer: ada.id, .text("from Ada"))))
    }

    @Test("An offline contact: the relay says so and nothing is kept")
    func peerUnavailable() throws {
        relay.online.remove(bob.id)

        relay.submit(try ada.engine.send(.text("are you there?"), to: bob.id), from: ada)
        try relay.run()

        #expect(ada.events == [.peerUnavailable(peer: bob.id, dropped: [.text("are you there?")])])
        #expect(!ada.engine.isEstablished(with: bob.id))
    }

    @Test("A peer that restarted opens a new session, which replaces the old one")
    func peerRestart() throws {
        relay.submit(try ada.engine.open(bob.id), from: ada)
        try relay.run()

        bob.restart()
        relay.submit(try bob.engine.send(.text("back"), to: ada.id), from: bob)
        try relay.run()
        relay.submit(try ada.engine.send(.text("welcome back"), to: bob.id), from: ada)
        try relay.run()

        #expect(bob.events.last == .received(peer: ada.id, .text("welcome back")))
        #expect(ada.events.contains(.received(peer: bob.id, .text("back"))))
    }

    @Test("A message that fails to decrypt ends the session; the next send starts a new one")
    func decryptFailureEndsSession() throws {
        relay.submit(try ada.engine.open(bob.id), from: ada)
        try relay.run()

        var output = try ada.engine.send(.text("x"), to: bob.id)
        var bytes = [UInt8](output.frames[0])
        bytes[RelayFrame.headerSize + SessionPacket.headerSize + 10] ^= 0x01   // inside the ciphertext
        output.frames[0] = Data(bytes)
        relay.submit(output, from: ada)
        try relay.run()
        #expect(bob.events.last == .ended(peer: ada.id, .decryptFailed))

        relay.submit(try bob.engine.send(.text("again"), to: ada.id), from: bob)
        try relay.run()
        #expect(ada.events.last == .received(peer: bob.id, .text("again")))
    }

    @Test("Every frame on the wire has the same size, whatever the message length")
    func framesAreAllTheSameSize() throws {
        relay.submit(try ada.engine.send(.text("a"), to: bob.id), from: ada)
        relay.submit(try ada.engine.send(.text(String(repeating: "🧑‍🧑‍🧒", count: 300)), to: bob.id), from: ada)
        let carol = Phone(id: 0x0C)   // a contact who is not connected
        bob.pair(with: carol)
        relay.submit(try bob.engine.send(.text("unavailable reply"), to: carol.id), from: bob)
        try relay.run()

        #expect(relay.framesSeen.count > 4)
        #expect(Set(relay.framesSeen.map(\.count)) == [RelayFrame.size])
    }

    @Test("Text longer than one frame holds is refused before anything is sent")
    func tooLong() throws {
        let tooBig = String(repeating: "a", count: SessionContent.maxContentBytes + 1)
        #expect(throws: FrameError.tooLong) { try ada.engine.send(.text(tooBig), to: bob.id) }
        let justFits = String(repeating: "a", count: SessionContent.maxContentBytes)
        relay.submit(try ada.engine.send(.text(justFits), to: bob.id), from: ada)
        try relay.run()
        #expect(bob.events.last == .received(peer: ada.id, .text(justFits)))
    }

    @Test("Opening or writing to someone who is not a contact throws, and nothing is left queued")
    func requiresAContact() throws {
        let stranger = Phone(id: 0x0C)
        #expect(throws: SessionError.notAContact) { try ada.engine.open(stranger.id) }
        #expect(throws: SessionError.notAContact) { try ada.engine.send(.text("hi"), to: stranger.id) }

        ada.pair(with: stranger)
        relay.connect(stranger)
        relay.submit(try ada.engine.open(stranger.id), from: ada)
        try relay.run()
        #expect(stranger.events == [.established(peer: ada.id)], "no earlier message was waiting in a queue")
    }

    @Test("A contact who stays silent: the handshake can be abandoned, and a later attempt starts afresh")
    func unansweredHandshake() throws {
        bob.contacts = [:]                        // Bob removed Ada: he stays silent
        relay.submit(try ada.engine.send(.text("hello?"), to: bob.id), from: ada)
        try relay.run()
        #expect(ada.engine.isHandshaking(with: bob.id))
        #expect(try ada.engine.open(bob.id).frames.isEmpty, "stuck until abandoned")

        relay.submit(ada.engine.abandonHandshake(with: bob.id), from: ada)
        #expect(ada.events.last == .unanswered(peer: bob.id, dropped: [.text("hello?")]))

        bob.contacts[ada.id] = ada.key.publicKey  // Bob adds her back
        relay.submit(try ada.engine.send(.text("second try"), to: bob.id), from: ada)
        try relay.run()
        #expect(bob.events.last == .received(peer: ada.id, .text("second try")))
        #expect(ada.engine.abandonHandshake(with: bob.id) == SessionEngine.Output(), "nothing to abandon once open")
    }
}

@Suite("Frames")
struct FrameTests {
    @Test("Routing id round-trips an account UUID")
    func routingID() {
        let uuid = UUID()
        #expect(RoutingID.of(accountUUID: uuid).count == RoutingID.size)
        #expect(RoutingID.accountUUID(RoutingID.of(accountUUID: uuid)) == uuid)
    }

    @Test("Frames of the wrong size, version or kind are refused")
    func malformedFrames() throws {
        let good = try RelayFrame(kind: .deliver, peer: Data(count: 16), body: Data([1, 2, 3])).encoded()
        #expect(throws: FrameError.wrongSize(good.count - 1)) { try RelayFrame(decoding: good.dropLast()) }
        var badVersion = good; badVersion[0] = 2
        #expect(throws: FrameError.unsupportedVersion(2)) { try RelayFrame(decoding: badVersion) }
        var badKind = good; badKind[1] = 9
        #expect(throws: FrameError.unknownKind(9)) { try RelayFrame(decoding: badKind) }
    }
}
