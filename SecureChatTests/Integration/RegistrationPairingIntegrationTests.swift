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

    private var server: FakeAuthServer!
    private var suiteNames: [String] = []

    override func setUp() async throws {
        server = FakeAuthServer()
    }

    override func tearDown() async throws {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
    }

    private func makeDevice(name: String) throws -> IntegrationDevice {
        let suiteName = "RegistrationPairingIntegrationTests-\(UUID().uuidString)"
        suiteNames.append(suiteName)
        return try IntegrationDevice(name: name, server: server, defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    private func code(on viewModel: PairingViewModel) throws -> String {
        try IntegrationDevice.code(on: viewModel)
    }

    // MARK: Tests

    func test_registration_givesPairingTheServersAccountAndTheRegisteredKey() async throws {
        let ada = try makeDevice(name: "Ada")
        await ada.register()

        let me = try ada.identityProvider.load()

        XCTAssertEqual(me.accountUUID,
                       server.accountID(forIdentityKey: me.identityPublicKey).flatMap(UUID.init(uuidString:)),
                       "pairing must hand out the account id the server issued for this key")
        let shown = try PairingPayload(scanned: code(on: ada.pairing()))
        XCTAssertEqual(shown.identityPublicKey, me.identityPublicKey)
        XCTAssertEqual(shown.accountUUID, me.accountUUID)
    }

    func test_beforeRegistering_pairingIsUnavailable() async throws {
        let ada = try makeDevice(name: "Ada")
        await ada.registration.load()

        guard case .unavailable = ada.pairing().phase else {
            return XCTFail("an unregistered device must not show a pairing code")
        }
    }

    func test_twoRegisteredDevices_pairBothWays_withTheirRegisteredIdentities() async throws {
        let ada = try makeDevice(name: "Ada"), bob = try makeDevice(name: "Bob")
        await ada.register()
        await bob.register()
        let (adaPairing, bobPairing) = try IntegrationDevice.pairFaceToFace(ada, bob)

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
