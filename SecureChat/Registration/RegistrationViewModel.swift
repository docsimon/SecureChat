//
//  RegistrationViewModel.swift
//  SecureChat
//
//  Drives device registration: App Attest (AppAttestKit) against the Auth
//  Server (RegistrationKit). Registration starts ONLY from the user's tap —
//  there is no automatic trigger, so a failed or refused attempt is never
//  retried behind the user's back and can never spend App Attest keys in a
//  loop (Architecture/attestation-error-state-table.md, "What the app does
//  with each outcome").
//

import Foundation
import AppAttestKit
import RegistrationKit

@MainActor @Observable
final class RegistrationViewModel {

    enum Phase: Equatable {
        /// Saved state not read yet.
        case loading
        case notRegistered
        case registering
        case registered
        /// App Attest is not available here (the Simulator, for one). Terminal.
        case unsupported
        /// The message is for the user; the cause is in the log.
        case failed(String)
    }

    private(set) var phase: Phase = .loading

    private let coordinator: AttestationCoordinator
    private let firstLaunchGate: FirstLaunchPurgeGate
    private let identity: IdentityKeyStore
    private let account: RegisteredAccountStore
    private var loadTask: Task<Void, Never>?

#if DEBUG
    /// Debug builds only. When true, `load()` reports "registered" without
    /// reading saved state, and nothing here ever reaches Apple or the Auth
    /// Server. App Attest is a limited resource and is tested in the
    /// AppAttestTestApp harness (Architecture/registration-status.md); the
    /// rest of the app is developed as if registration had succeeded.
    /// The Auth Server does NOT know this device. The "SecureChat Real
    /// Registration" scheme turns it off, when the user chooses to.
    @ObservationIgnored var assumesRegistered = false
#endif

    /// The stores are parameters for tests; the app uses the defaults.
    init(coordinator: AttestationCoordinator,
         firstLaunchGate: FirstLaunchPurgeGate = .standard(key: "registration.hasLaunchedBefore"),
         identity: IdentityKeyStore = .live,
         account: RegisteredAccountStore = .live) {
        self.coordinator = coordinator
        self.firstLaunchGate = firstLaunchGate
        self.identity = identity
        self.account = account
    }

    /// Call when the root view appears. Reads saved state only — never
    /// contacts Apple or the server. Safe to call more than once: later
    /// calls wait for the first.
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
#if DEBUG
        if assumesRegistered {
            SCLogger.logger.info(message: "Registration skipped: Debug build assumes this device is registered", category: .Registration)
            phase = .registered
            return
        }
#endif
        // BEFORE anything is shown: after a reinstall the Keychain still says
        // "registered" for a key Apple no longer recognises.
        await firstLaunchGate.runIfNeeded {
            if await Registration.purgeStaleInstallState(coordinator: coordinator,
                                                         identity: identity, account: account) {
                SCLogger.logger.info(message: "First launch: cleared registration left by a previous install", category: .Registration)
            }
        }
        do {
            try await coordinator.restore()
            phase = Self.phase(for: await coordinator.currentState)
        } catch {
            // Unreadable is NOT "not registered" — do not offer to register
            // over a registration that may well be there.
            log(error)
            phase = .failed(Self.message(for: error))
            loadTask = nil
        }
    }

    /// The user tapped Register (or Try again).
    func register() async {
        switch phase {
        case .registering, .registered, .unsupported:
            return
        case .loading:
            await load()
            guard phase == .notRegistered else { return }
        case .failed where loadTask == nil:
            // The saved state could not be read last time: read it again
            // before deciding there is anything to register.
            await load()
            guard phase == .notRegistered else { return }
        case .notRegistered, .failed:
            break
        }

        phase = .registering
        do {
            _ = try identity.loadOrCreate()
            let state = try await coordinator.ensureAttested(binding: Registration.clientDataHash)
            phase = Self.phase(for: state)
        } catch {
            log(error)
            phase = .failed(Self.message(for: error))
        }
    }

    // MARK: Mapping

    private static func phase(for state: AttestationState) -> Phase {
        switch state {
        case .attested:
            return .registered
        case .unsupported:
            return .unsupported
        case .none, .keyGenerated, .attestationPending:
            // Part-way through counts as not registered: the next tap
            // resumes from exactly where it stopped.
            return .notRegistered
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? AttestationError else {
            return "Registration couldn't be completed. Please try again."
        }
        switch error {
        case .networkUnavailable, .exhausted, .retryable:
            return "Couldn't reach the server. Check your connection and try again."
        case .storageFailed:
            return "Couldn't access secure storage. Unlock your device and try again."
        case .serverRejected, .keyInvalid, .challengeExpired:
            return "Registration was refused. Please try again later."
        case .unsupported:
            return "This device can't be verified."
        case .notAttested:
            return "Registration couldn't be completed. Please try again."
        }
    }

    private func log(_ error: Error) {
        // `diagnosticName` only — an AttestationError's associated text can
        // carry a server response body.
        let name = (error as? AttestationError)?.diagnosticName ?? String(describing: type(of: error))
        SCLogger.logger.error(message: "Registration failed: \(name)", category: .Registration)
    }
}

/// Sends AppAttestKit's progress to the app log. Never a keyId: `label` and
/// `diagnosticName` are the module's log-safe forms.
struct RegistrationLogObserver: AttestationObserver {
    func didTransition(to state: AttestationState) {
        SCLogger.logger.info(message: "Attestation state: \(state.label)", category: .Registration)
    }

    func didFail(_ error: AttestationError, attempt: Int) {
        SCLogger.logger.error(message: "Attestation attempt \(attempt) failed: \(error.diagnosticName)", category: .Registration)
    }
}
