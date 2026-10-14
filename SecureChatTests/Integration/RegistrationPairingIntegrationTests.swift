//
//  RegistrationPairingIntegrationTests.swift
//  SecureChatTests
//
//  Registration and pairing together, with only the outside world faked
//  (IntegrationFakes.swift): two devices register through the real
//  RegistrationViewModel, AttestationCoordinator and RealAttestationTransport,
//  then pair face to face with the identity key and account id registration
//  left behind.
//
//  Nothing here reaches Apple, the network or the Keychain: every store is
//  in memory, so it is safe on a phone as well as in the Simulator.
//

import XCTest
@_spi(Testing) import AppAttestKit
@_spi(Testing) import RegistrationKit
import PairingKit
@testable import SecureChat

@MainActor
final class RegistrationPairingIntegrationTests: XCTestCase {

    /// One phone: its own stores, wired together the way DependencyManager
    /// wires the real ones.
    private struct Device {
        let registration: RegistrationViewModel
        let identityProvider: LocalIdentityProvider
        let contacts: ContactRepository
        let profile: ProfileStore
    }

    private struct NotPairing: Error { let phase: String }

    private var server: FakeAuthServer!
    private var suiteNames: [String] = []

    override func setUp() async throws {
        server = FakeAuthServer()
    }

    override func tearDown() async throws {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
    }

    private func makeDevice(name: String) throws -> Device {
        let suiteName = "RegistrationPairingIntegrationTests-\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let identity = IdentityKeyStore.inMemory()
        let account = RegisteredAccountStore(defaults: defaults)

        let transport = EnvironmentLoggingTransport(base: RealAttestationTransport(
            baseURL: server.baseURL, identity: identity, account: account, session: server.session))
        let coordinator = AttestationCoordinator(testingService: FakeAppleAttestService(),
                                                 store: InMemoryAttestationKeyStore(),
                                                 transport: transport)
        let registration = RegistrationViewModel(
            coordinator: coordinator,
            firstLaunchGate: FirstLaunchPurgeGate(hasRunBefore: { false }, markAsRun: {}),
            identity: identity, account: account)

        let profile = ProfileStore(defaults: defaults)
        profile.displayName = name
        return Device(registration: registration,
                      identityProvider: LocalIdentityProvider(identityStore: identity, accountStore: account),
                      contacts: ContactRepository(db: try SQLiteDB(path: ":memory:")),
                      profile: profile)
    }

    private func register(_ device: Device) async {
        await device.registration.load()
        XCTAssertEqual(device.registration.phase, .notRegistered)
        await device.registration.register()
        XCTAssertEqual(device.registration.phase, .registered)
    }

    private func pairing(on device: Device) -> PairingViewModel {
        PairingViewModel(identity: device.identityProvider.load, contacts: device.contacts,
                         profile: device.profile, signal: { _ in })
    }

    private func code(on viewModel: PairingViewModel) throws -> String {
        guard case .pairing(let pairing) = viewModel.phase else {
            throw NotPairing(phase: "\(viewModel.phase)")
        }
        return try XCTUnwrap(pairing.codeToShow)
    }

    // MARK: Tests

    func test_registration_givesPairingTheServersAccountAndTheRegisteredKey() async throws {
        let ada = try makeDevice(name: "Ada")
        await register(ada)

        let me = try ada.identityProvider.load()

        XCTAssertEqual(me.accountUUID.uuidString,
                       server.accountID(forIdentityKey: me.identityPublicKey),
                       "pairing must hand out the account id the server issued for this key")
        let shown = try PairingPayload(scanned: code(on: pairing(on: ada)))
        XCTAssertEqual(shown.identityPublicKey, me.identityPublicKey)
        XCTAssertEqual(shown.accountUUID, me.accountUUID)
    }

    func test_beforeRegistering_pairingIsUnavailable() async throws {
        let ada = try makeDevice(name: "Ada")
        await ada.registration.load()

        guard case .unavailable = pairing(on: ada).phase else {
            return XCTFail("an unregistered device must not show a pairing code")
        }
    }

    func test_twoRegisteredDevices_pairBothWays_withTheirRegisteredIdentities() async throws {
        let ada = try makeDevice(name: "Ada"), bob = try makeDevice(name: "Bob")
        await register(ada)
        await register(bob)
        let adaPairing = pairing(on: ada), bobPairing = pairing(on: bob)

        // Face to face: each camera reads whatever the other screen shows now.
        bobPairing.scanned(try code(on: adaPairing))
        adaPairing.scanned(try code(on: bobPairing))   // Bob's code now says he has Ada's
        bobPairing.scanned(try code(on: adaPairing))   // Ada's code now says she has Bob's

        let adaIdentity = try ada.identityProvider.load(), bobIdentity = try bob.identityProvider.load()
        XCTAssertNotEqual(adaIdentity, bobIdentity)
        XCTAssertEqual(ada.contacts.contacts.map(\.identityPublicKey), [bobIdentity.identityPublicKey])
        XCTAssertEqual(ada.contacts.contacts.map(\.accountUUID), [bobIdentity.accountUUID])
        XCTAssertEqual(ada.contacts.contacts.map(\.displayName), ["Bob"])
        XCTAssertEqual(bob.contacts.contacts.map(\.identityPublicKey), [adaIdentity.identityPublicKey])
        XCTAssertEqual(bob.contacts.contacts.map(\.accountUUID), [adaIdentity.accountUUID])

        for viewModel in [adaPairing, bobPairing] {
            guard case .pairing(let pairing) = viewModel.phase, case .bothWays = pairing.progress else {
                return XCTFail("both phones should report paired both ways")
            }
        }
    }
}
