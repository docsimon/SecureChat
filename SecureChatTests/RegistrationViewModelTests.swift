//
//  RegistrationViewModelTests.swift
//  SecureChatTests
//
//  What can be checked without a real device. App Attest itself only works
//  on hardware — the Simulator always reports "unsupported" — so the paths
//  through Apple and the Auth Server are covered by AppAttestKit's own tests
//  and by the AppAttestTestApp harness on a phone, not here.
//

import XCTest
import AppAttestKit
import RegistrationKit
@testable import SecureChat

@MainActor
final class RegistrationViewModelTests: XCTestCase {

    /// Counts calls; a registration that reached it on the Simulator would
    /// mean the "unsupported" guard was skipped.
    actor CountingTransport: AttestationTransport {
        private(set) var calls = 0
        func fetchChallenge() async throws -> Data { calls += 1; return Data(count: 32) }
        func submitAttestation(_ request: AttestationSubmission) async throws -> String {
            calls += 1
            return "uuid"
        }
    }

    private func makeViewModel(firstLaunch: Bool = false) -> (RegistrationViewModel, CountingTransport) {
        let transport = CountingTransport()
        let coordinator = AttestationCoordinator(transport: transport)
        let gate = FirstLaunchPurgeGate(hasRunBefore: { !firstLaunch }, markAsRun: {})
        return (RegistrationViewModel(coordinator: coordinator, firstLaunchGate: gate), transport)
    }

    /// These tests write to and clear the real Keychain. On a phone that
    /// would wipe an actual registration, and the next one costs a new App
    /// Attest key — so the whole class runs in the Simulator only.
    override func setUp() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator only: these tests clear the Keychain")
        #endif
    }

    override func tearDown() async throws {
        #if targetEnvironment(simulator)
        IdentityKeyStore.delete()
        #endif
    }

    func test_load_withNothingSaved_offersRegistration() async {
        let (viewModel, _) = makeViewModel()
        XCTAssertEqual(viewModel.phase, .loading)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .notRegistered)
    }

    func test_register_onSimulator_endsUnsupported_withoutContactingTheServer() async throws {
        let (viewModel, transport) = makeViewModel()
        await viewModel.load()

        await viewModel.register()

        XCTAssertEqual(viewModel.phase, .unsupported)
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func test_assumingRegistered_skipsEverything() async throws {
        _ = try IdentityKeyStore.loadOrCreate()
        let (viewModel, transport) = makeViewModel(firstLaunch: true)
        viewModel.assumesRegistered = true

        await viewModel.load()
        await viewModel.register()

        XCTAssertEqual(viewModel.phase, .registered)
        XCTAssertTrue(IdentityKeyStore.exists(), "the first-launch purge must not run")
        let calls = await transport.calls
        XCTAssertEqual(calls, 0)
    }

    func test_firstLaunch_clearsIdentityLeftByAPreviousInstall() async throws {
        _ = try IdentityKeyStore.loadOrCreate()
        XCTAssertTrue(IdentityKeyStore.exists())
        let (viewModel, _) = makeViewModel(firstLaunch: true)

        await viewModel.load()

        XCTAssertFalse(IdentityKeyStore.exists())
        XCTAssertEqual(viewModel.phase, .notRegistered)
    }

    func test_laterLaunch_keepsTheIdentity() async throws {
        _ = try IdentityKeyStore.loadOrCreate()
        let (viewModel, _) = makeViewModel(firstLaunch: false)

        await viewModel.load()

        XCTAssertTrue(IdentityKeyStore.exists())
    }

    func test_messages_neverExposeServerDetail() {
        let detail = "POST /register → HTTP 400: {\"error\":\"attestation_invalid\"}"
        for error in [AttestationError.serverRejected(detail), .retryable(detail), .storageFailed(detail)] {
            let message = RegistrationViewModel.message(for: error)
            XCTAssertFalse(message.contains("HTTP"), message)
            XCTAssertFalse(message.contains("attestation_invalid"), message)
        }
    }

    func test_messages_tellConnectionTroubleFromRefusal() {
        XCTAssertNotEqual(RegistrationViewModel.message(for: AttestationError.exhausted),
                          RegistrationViewModel.message(for: AttestationError.serverRejected("x")))
    }
}
