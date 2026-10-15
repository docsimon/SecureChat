//
//  LiveRelayTests.swift
//  SessionKitTests
//
//  Two SessionServices talking through a REAL relay (RelayServer in docker,
//  started with RELAY_DEV_CLAIMED_ACCOUNTS=true). Skipped unless asked for:
//
//    TEST_RUNNER_SESSIONKIT_LIVE_RELAY=ws://localhost:8081/relay \
//      xcodebuild test -scheme SessionKit -destination '<a Simulator>'
//
//  Development identities only; nothing reaches App Attest or the Auth Server.
//

import Foundation
import CryptoKit
import Testing
@testable import SessionKit

@MainActor
@Suite("Live relay", .enabled(if: ProcessInfo.processInfo.environment["SESSIONKIT_LIVE_RELAY"] != nil))
struct LiveRelayTests {

    final class Device {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let account = UUID()
        var contacts: [UUID: Data] = [:]
        var events: [SessionService.Event] = []
        var service: SessionService!

        @MainActor
        func start(relay: URL, handshakeTimeout: UInt64 = SessionService.handshakeTimeout) {
            service = SessionService(transport: RelayClient(url: relay, credential: .developmentAccount(account)),
                                     localIdentity: key, localAccount: account,
                                     handshakeTimeout: handshakeTimeout,
                                     contactKey: { [unowned self] in contacts[$0] })
            service.onEvent = { [unowned self] in events.append($0) }
            service.connect()
        }
    }

    let relay = URL(string: ProcessInfo.processInfo.environment["SESSIONKIT_LIVE_RELAY"] ?? "ws://localhost:8081/relay")!

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(condition())
    }

    @Test("Two devices open a session through the relay and exchange text")
    func talkThroughTheRelay() async throws {
        let ada = Device(), bob = Device()
        ada.contacts[bob.account] = bob.key.publicKey.rawRepresentation
        bob.contacts[ada.account] = ada.key.publicKey.rawRepresentation
        ada.start(relay: relay)
        bob.start(relay: relay)
        try await waitUntil { ada.service.relayState == .connected && bob.service.relayState == .connected }

        try ada.service.send("hello through the relay", to: bob.account)
        try await waitUntil { bob.events.contains(.received(ada.account, .text("hello through the relay"))) }
        try bob.service.send("loud and clear", to: ada.account)
        try await waitUntil { ada.events.contains(.received(bob.account, .text("loud and clear"))) }

        #expect(ada.service.established.contains(bob.account))
        #expect(bob.service.established.contains(ada.account))
        ada.service.disconnect()
        bob.service.disconnect()
    }

    @Test("A contact who is not connected is reported offline")
    func offlineContact() async throws {
        let ada = Device(), carol = Device()
        ada.contacts[carol.account] = carol.key.publicKey.rawRepresentation
        ada.start(relay: relay)
        try await waitUntil { ada.service.relayState == .connected }

        try ada.service.send("anyone?", to: carol.account)

        try await waitUntil { ada.events.contains(.peerUnavailable(carol.account, dropped: [.text("anyone?")])) }
        ada.service.disconnect()
    }

    @Test("Contact left: after a two-way exchange, the other side is told when one leaves")
    func contactLeft() async throws {
        let ada = Device(), bob = Device()
        ada.contacts[bob.account] = bob.key.publicKey.rawRepresentation
        bob.contacts[ada.account] = ada.key.publicKey.rawRepresentation
        ada.start(relay: relay)
        bob.start(relay: relay)
        try await waitUntil { ada.service.relayState == .connected && bob.service.relayState == .connected }
        try ada.service.send("hi", to: bob.account)
        try await waitUntil { ada.service.established.contains(bob.account) }

        bob.service.disconnect()

        try await waitUntil { ada.events.contains(.peerUnavailable(bob.account, dropped: [])) }
        #expect(!ada.service.established.contains(bob.account))
        ada.service.disconnect()
    }

    @Test("Contact left: someone who only wrote to us is not told when we leave")
    func oneWayLearnsNothing() async throws {
        // Bob does not have Ada (he removed her): he reads her handshake and
        // stays silent.
        let ada = Device(), bob = Device()
        ada.contacts[bob.account] = bob.key.publicKey.rawRepresentation
        ada.start(relay: relay, handshakeTimeout: 300_000_000)
        bob.start(relay: relay)
        try await waitUntil { ada.service.relayState == .connected && bob.service.relayState == .connected }
        try ada.service.send("it's Ada", to: bob.account)
        try await waitUntil { bob.events.contains(.refused(ada.account, .notAContact)) }
        try await waitUntil { ada.events.contains(.unanswered(bob.account, dropped: [.text("it's Ada")])) }

        bob.service.disconnect()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        #expect(!ada.events.contains { if case .peerUnavailable = $0 { return true } else { return false } },
                "Ada must not learn that Bob left")
        ada.service.disconnect()
    }
}
