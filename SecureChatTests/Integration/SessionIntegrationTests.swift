//
//  SessionIntegrationTests.swift
//  SecureChatTests
//
//  Registration, pairing and sessions together: two devices register, pair
//  face to face, connect to the relay with a session token from the Auth
//  Server, and chat. Real code from the view model down to the frames; the
//  Auth Server and the relay are in process (IntegrationFakes.swift).
//

import XCTest
import PairingKit
import SessionKit
@testable import SecureChat

@MainActor
final class SessionIntegrationTests: XCTestCase {

    private var server: FakeAuthServer!
    private var relay: InProcessRelay!
    private var suiteNames: [String] = []
    private var connections: [RelayConnection] = []

    override func setUp() async throws {
        server = FakeAuthServer()
        relay = InProcessRelay(server: server)
    }

    override func tearDown() async throws {
        connections.forEach { $0.setActive(false) }
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
    }

    private func makeRegisteredDevice(name: String) async throws -> IntegrationDevice {
        let suiteName = "SessionIntegrationTests-\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let device = try IntegrationDevice(name: name, server: server,
                                           defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
        await device.register()
        return device
    }

    private func pairedDevices() async throws -> (IntegrationDevice, IntegrationDevice) {
        let ada = try await makeRegisteredDevice(name: "Ada")
        let bob = try await makeRegisteredDevice(name: "Bob")
        _ = try IntegrationDevice.pairFaceToFace(ada, bob)
        return (ada, bob)
    }

    /// In the foreground, connected.
    private func connect(_ device: IntegrationDevice) async throws -> RelayConnection {
        let connection = device.relayConnection(through: relay)
        connections.append(connection)
        connection.setActive(true)
        try await waitUntil { connection.state == .connected }
        return connection
    }

    private func conversation(on device: IntegrationDevice, with other: IntegrationDevice,
                              over connection: RelayConnection) throws -> ConversationViewModel {
        let account = try other.accountUUID
        let contact = try XCTUnwrap(device.contacts.contacts.first { $0.accountUUID == account })
        return ConversationViewModel(contact: contact, connection: connection, store: device.messages)
    }

    private func waitUntil(_ what: String = "condition", _ condition: () throws -> Bool) async throws {
        for _ in 0..<200 {
            if try condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for \(what)")
    }

    // MARK: Tests

    func test_pairedDevices_chatBothWays_throughTheRelay() async throws {
        let (ada, bob) = try await pairedDevices()
        let adaConnection = try await connect(ada), bobConnection = try await connect(bob)
        let adaChat = try conversation(on: ada, with: bob, over: adaConnection)
        let bobChat = try conversation(on: bob, with: ada, over: bobConnection)

        adaChat.appeared()   // opening the chat opens the session
        try await waitUntil("session open") { adaChat.status == .open }
        adaChat.draft = "Hello Bob"
        adaChat.send()
        try await waitUntil("Bob receives") { bobChat.messages.map(\.text) == ["Hello Bob"] }

        bobChat.appeared()
        bobChat.draft = "Hi Ada"
        bobChat.send()
        try await waitUntil("Ada receives") { adaChat.messages.count == 2 }

        XCTAssertEqual(adaChat.messages.map(\.text), ["Hello Bob", "Hi Ada"])
        XCTAssertEqual(adaChat.messages.map(\.status), [.sent, .received])
        XCTAssertEqual(bobChat.messages.map(\.status), [.received, .sent])
        XCTAssertEqual(bobChat.status, .open)
        XCTAssertEqual(adaChat.presence, .online)
        XCTAssertEqual(bobChat.presence, .online)
        XCTAssertEqual(server.issuedTokenCount, 2, "each device connects with its own session token")
    }

    func test_aMessageWrittenBeforeTheSessionOpens_goesOutWhenItOpens() async throws {
        let (ada, bob) = try await pairedDevices()
        let adaConnection = try await connect(ada)
        _ = try await connect(bob)
        let adaChat = try conversation(on: ada, with: bob, over: adaConnection)

        adaChat.draft = "First words"
        adaChat.send()   // no session yet: it waits for the handshake
        XCTAssertEqual(adaChat.messages.map(\.status), [.waiting])

        try await waitUntil("delivered") { bob.messages.messages(with: try ada.accountUUID).count == 1 }
        XCTAssertEqual(adaChat.messages.map(\.status), [.sent])
    }

    func test_aContactWhoIsNotConnected_isOffline_andTheMessageIsNotDelivered() async throws {
        let (ada, bob) = try await pairedDevices()
        let adaChat = try conversation(on: ada, with: bob, over: try await connect(ada))

        adaChat.appeared()
        adaChat.draft = "Anyone there?"
        adaChat.send()

        XCTAssertNil(adaChat.presence, "nothing known before the first try")
        try await waitUntil("offline") { adaChat.status == .offline }
        XCTAssertEqual(adaChat.presence, .offline)
        XCTAssertEqual(adaChat.messages.map(\.status), [.notDelivered])
    }

    func test_aContactWhoDoesNotHaveUs_staysSilent_andIsReportedUnanswered() async throws {
        let ada = try await makeRegisteredDevice(name: "Ada")
        let bob = try await makeRegisteredDevice(name: "Bob")
        // Only Ada reads Bob's code: Bob never stores Ada.
        _ = ada.pairing().scanned(try IntegrationDevice.code(on: bob.pairing()))
        XCTAssertTrue(bob.contacts.contacts.isEmpty)
        let adaChat = try conversation(on: ada, with: bob, over: try await connect(ada))
        _ = try await connect(bob)

        adaChat.draft = "It's Ada"
        adaChat.send()

        try await waitUntil("unanswered") { adaChat.status == .unanswered }
        XCTAssertEqual(adaChat.presence, .offline, "silent looks the same as away")
        XCTAssertEqual(adaChat.messages.map(\.status), [.notDelivered])
        XCTAssertTrue(bob.messages.messages(with: try ada.accountUUID).isEmpty, "a stranger's message is never stored")
    }

    func test_background_closesTheConnection_foreground_reconnectsWithAFreshToken() async throws {
        let (ada, bob) = try await pairedDevices()
        let adaConnection = try await connect(ada)

        adaConnection.setActive(false)
        XCTAssertEqual(adaConnection.state, .disconnected)
        XCTAssertFalse(relay.isConnected(try ada.accountUUID))

        adaConnection.setActive(true)
        try await waitUntil("reconnected") { adaConnection.state == .connected }
        XCTAssertEqual(server.issuedTokenCount, 2)
        _ = bob
    }

    func test_aDroppedConnection_isReopened_andTheOpenChatGetsANewSession() async throws {
        let (ada, bob) = try await pairedDevices()
        let adaConnection = try await connect(ada)
        _ = try await connect(bob)
        let adaChat = try conversation(on: ada, with: bob, over: adaConnection)
        adaChat.appeared()
        try await waitUntil("session open") { adaChat.status == .open }

        relay.drop(try ada.accountUUID)
        XCTAssertEqual(adaChat.status, .connecting)
        XCTAssertNil(adaChat.presence, "nothing known while this phone is not connected")

        try await waitUntil("session reopened") { adaChat.status == .open }
        adaChat.draft = "Still here"
        adaChat.send()
        try await waitUntil("delivered") { bob.messages.messages(with: try ada.accountUUID).map(\.text) == ["Still here"] }
    }

    func test_whatWasWaitingWhenTheConnectionDrops_isNotDelivered() async throws {
        let (ada, bob) = try await pairedDevices()
        let adaConnection = try await connect(ada)
        let adaChat = try conversation(on: ada, with: bob, over: adaConnection)
        _ = try await connect(bob)
        adaChat.draft = "Quick one"
        adaChat.send()
        XCTAssertEqual(adaChat.messages.map(\.status), [.waiting])

        // Before the handshake has even left.
        adaConnection.setActive(false)

        XCTAssertEqual(adaChat.messages.map(\.status), [.notDelivered])
    }

    func test_aRefusedCredential_backsOff_insteadOfRetryingAtOnce() async throws {
        let ada = try await makeRegisteredDevice(name: "Ada")
        // A claimed account, and this relay has no development flag.
        let connection = RelayConnection(
            identity: ada.identityProvider.loadForSessions,
            credential: { .developmentAccount($0.accountUUID) },
            makeTransport: relay.transport(for:),
            contacts: ada.contacts, messages: ada.messages,
            retryDelays: [10_000_000, 2_000_000_000])
        connections.append(connection)

        connection.setActive(true)
        try await waitUntil("refused twice") { relay.connectionAttempts >= 2 }
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(relay.connectionAttempts, 2, "a socket that opens and closes at once is a failure, not a success")
        XCTAssertNotEqual(connection.state, .connected)
    }
}
