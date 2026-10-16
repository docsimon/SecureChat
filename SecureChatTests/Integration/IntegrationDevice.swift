//
//  IntegrationDevice.swift
//  SecureChatTests
//
//  One phone in the integration tests: its own stores, wired together the
//  way DependencyManager wires the real ones, with only the outside world
//  faked (IntegrationFakes.swift). Every store is in memory or a throwaway
//  UserDefaults suite.
//

import XCTest
@_spi(Testing) import AppAttestKit
@_spi(Testing) import RegistrationKit
import PairingKit
import SessionKit
@testable import SecureChat

@MainActor
final class IntegrationDevice {

    struct NotPairing: Error { let phase: String }

    let registration: RegistrationViewModel
    let identityProvider: LocalIdentityProvider
    let contacts: ContactRepository
    let messages: MessageStore
    let profile: ProfileStore
    private let coordinator: AttestationCoordinator
    private let server: FakeAuthServer

    /// - Parameter defaults: a throwaway suite; the caller removes it.
    init(name: String, server: FakeAuthServer, defaults: UserDefaults) throws {
        self.server = server
        let identity = IdentityKeyStore.inMemory()
        let account = RegisteredAccountStore(defaults: defaults)
        let transport = EnvironmentLoggingTransport(base: RealAttestationTransport(
            baseURL: server.baseURL, identity: identity, account: account, session: server.session))
        coordinator = AttestationCoordinator(testingService: FakeAppleAttestService(),
                                             store: InMemoryAttestationKeyStore(),
                                             transport: transport)
        registration = RegistrationViewModel(
            coordinator: coordinator,
            firstLaunchGate: FirstLaunchPurgeGate(hasRunBefore: { false }, markAsRun: {}),
            identity: identity, account: account)
        identityProvider = LocalIdentityProvider(identityStore: identity, accountStore: account)
        let db = try SQLiteDB(path: ":memory:")
        contacts = ContactRepository(db: db)
        messages = MessageStore(db: db, keys: .inMemory(), keepKeysFor: [])
        profile = ProfileStore(defaults: defaults)
        profile.displayName = name
    }

    var accountUUID: UUID {
        get throws { try identityProvider.load().accountUUID }
    }

    func register() async {
        await registration.load()
        XCTAssertEqual(registration.phase, .notRegistered)
        await registration.register()
        XCTAssertEqual(registration.phase, .registered)
    }

    func pairing() -> PairingViewModel {
        PairingViewModel(identity: identityProvider.load, contacts: contacts, profile: profile)
    }

    static func code(on viewModel: PairingViewModel) throws -> String {
        guard case .pairing(let pairing) = viewModel.phase else {
            throw NotPairing(phase: "\(viewModel.phase)")
        }
        return try XCTUnwrap(pairing.codeToShow)
    }

    /// Face to face: each camera reads whatever the other screen shows now.
    static func pairFaceToFace(_ first: IntegrationDevice, _ second: IntegrationDevice) throws
        -> (PairingViewModel, PairingViewModel) {
        let firstPairing = first.pairing(), secondPairing = second.pairing()
        _ = secondPairing.scanned(try code(on: firstPairing))
        _ = firstPairing.scanned(try code(on: secondPairing))   // second's code now says it has first's
        _ = secondPairing.scanned(try code(on: firstPairing))   // first's code now says it has second's
        return (firstPairing, secondPairing)
    }

    /// The relay connection, as DependencyManager builds it for a registered
    /// device: a session token from the (fake) Auth Server, signed by the
    /// App Attest key.
    func relayConnection(through relay: InProcessRelay,
                         handshakeTimeout: UInt64 = 300_000_000,
                         retryDelays: [UInt64] = [10_000_000]) -> RelayConnection {
        let credentials = RelayCredentials(
            sessionClient: SessionClient(baseURL: server.baseURL, signer: coordinator, session: server.session))
        return RelayConnection(identity: identityProvider.loadForSessions,
                               credential: credentials.credential(for:),
                               makeTransport: relay.transport(for:),
                               contacts: contacts,
                               messages: messages,
                               handshakeTimeout: handshakeTimeout,
                               retryDelays: retryDelays)
    }
}
