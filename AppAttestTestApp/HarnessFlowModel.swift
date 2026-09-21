//
//  HarnessFlowModel.swift
//  AppAttestTestApp
//
//  Real version of the guided-sequence flow approved via the mock preview.
//  Drives AppAttestKit's real AttestationCoordinator against real
//  DCAppAttestService calls, under the development App Attest environment
//  (AppAttestTestApp.entitlements) — safe for repeated real-device testing,
//  since it doesn't count against the production per-device key budget
//  (confirmed this session — see account-keys-reference.md).
//
//  LocalFakeTransport still stands in for the not-yet-built Auth Server:
//  everything Apple-side here is real, everything server-side is fake.
//
//  Deliberately reads NOTHING from AppAttestKit except its public surface —
//  AttestationCoordinator.currentState — never LiveKeyStore/
//  AttestationKeyStore directly. That boundary is the module's core
//  guarantee (README.md: "the one thing to look for").
//

import Foundation
import CryptoKit
import AppAttestKit

@Observable @MainActor
final class HarnessFlowModel {
    enum ActiveStep { case none, identity, attest, sign }

    private(set) var identityGenerated = false
    private(set) var attested = false
    private(set) var activeStep: ActiveStep = .none
    private(set) var identityPublicKeyPrefix: String?

    /// Local heuristic only — Apple exposes no remaining-budget API
    /// (confirmed against current docs this session). Counts real
    /// generateKey() calls via the .keyGenerated transition, which fires
    /// exactly once per call.
    var realAttemptCount: Int {
        UserDefaults.standard.integer(forKey: Self.attemptCountKey)
    }
    private static let attemptCountKey = "harness.realAttemptCount"

    /// One entry per attempt. "Reset module state" and "Delete identity key"
    /// close out the current session and open a fresh one.
    var sessions: [HarnessSession] = [HarnessSession()]

    var stateLabel: String {
        if attested { return "attested" }
        if identityGenerated { return "identity ready (App Attest not yet requested)" }
        return "none"
    }

    private var coordinator: AttestationCoordinator?

    /// Call once when the view appears. Reflects whatever's already
    /// persisted — critical for the kill-and-relaunch smoke test
    /// (appattest-smoke-checklist.md item 4): without this, the UI would
    /// always show "not started" even after a real prior attestation.
    func restoreOnAppear() async {
        identityGenerated = IdentityKeyStore.exists()
        guard identityGenerated else { return }
        if let key = try? IdentityKeyStore.loadOrCreate() {
            identityPublicKeyPrefix = key.publicKey.rawRepresentation.prefix(4)
                .map { String(format: "%02x", $0) }.joined()
        }
        let coordinator = resolveCoordinator()
        await coordinator.restore()
        let state = await coordinator.currentState
        attested = state.isAttested
        // Structured, not just embedded in the summary text — HarnessSession
        // needs to reliably tell "restored into an already-attested state"
        // apart from "restored into something else," and matching against
        // free text would be fragile.
        log(.restored, summary: "found existing state on launch: \(state.label)",
            detail: [DetailField(label: "Restored as attested", value: state.isAttested ? "yes" : "no")])
    }

    func generateIdentity() async {
        guard activeStep == .none else { return }
        activeStep = .identity
        defer { activeStep = .none }
        do {
            let key = try IdentityKeyStore.loadOrCreate()
            let prefix = key.publicKey.rawRepresentation.prefix(4)
                .map { String(format: "%02x", $0) }.joined()
            identityGenerated = true
            identityPublicKeyPrefix = prefix
            log(.identityKeyGenerated, summary: "identity key ready (\(prefix)…)",
                detail: [DetailField(label: "Public key prefix", value: prefix)])
        } catch {
            log(.identityKeyGenerationFailed, summary: "\(error)", isError: true)
        }
    }

    /// The one real atomic call — see the file header for why this can't be
    /// split any further than "identity, then attest."
    func attest() async {
        guard activeStep == .none else { return }
        activeStep = .attest
        defer { activeStep = .none }

        guard identityGenerated, let identityKey = try? IdentityKeyStore.loadOrCreate() else {
            let summary = identityGenerated
                ? "identity key unavailable despite being marked generated — try Delete Identity Key and Generate again"
                : "no identity key — generate one first"
            log(.attestationFailed, summary: summary, isError: true)
            return
        }
        let publicKey = identityKey.publicKey.rawRepresentation

        log(.attestationStarted, summary: "attestation flow started")

        let coordinator = resolveCoordinator()
        do {
            let result = try await coordinator.ensureAttested { challenge in
                Data(SHA256.hash(data: challenge + publicKey))
            }
            if result.isAttested {
                attested = true
            } else {
                log(.attestationFailed, summary: "ended in state: \(result.label)", isError: true)
            }
        } catch let error as AttestationError {
            log(.attestationFailed, summary: error.diagnosticName, isError: true)
        } catch {
            log(.attestationFailed, summary: "\(error)", isError: true)
        }
    }

    /// Cheap and repeatable, unlike attestation — purely local, no network
    /// at all (confirmed via web search this session).
    func sign() async {
        guard activeStep == .none else { return }
        guard let coordinator else {
            log(.signFailed, summary: "sign attempted before attesting", isError: true)
            return
        }
        activeStep = .sign
        defer { activeStep = .none }
        do {
            let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            let signature = try await coordinator.sign(Data(SHA256.hash(data: nonce)))
            log(.assertionSigned, summary: "assertion signed (\(signature.count) bytes)",
                detail: [DetailField(label: "Signature size", value: "\(signature.count) bytes")])
        } catch let error as AttestationError {
            log(.signFailed, summary: error.diagnosticName, isError: true)
            // Confirmed on real hardware (a delete+reinstall's orphaned keyId):
            // Apple's generateAssertion() surfaces this as DCError.invalidInput
            // → .serverRejected("invalidInput"), NOT .keyInvalid as originally
            // assumed — see the warning in AttestationError.swift this proved
            // right. Safe to treat as equivalent to .keyInvalid specifically
            // HERE: this call's clientDataHash is always a freshly-computed
            // SHA256 digest, never app-malformed, so an "invalidInput" rejection
            // at THIS call site can only mean the keyId itself is dead.
            if error == .keyInvalid || error == .serverRejected("invalidInput") {
                // v1 policy (appattestkit-module-design.md §8, revised): wipe
                // the identity key TOGETHER with module state, always — never
                // one without the other. The earlier version of this handler
                // only called acknowledgeKeyInvalidation(), which is exactly
                // the gap that method closes, but preserving identity here
                // would reintroduce the two-path complexity that decision
                // deliberately traded away for a faster v1 ship.
                IdentityKeyStore.delete()
                identityPublicKeyPrefix = nil
                let recovered = await coordinator.acknowledgeKeyInvalidation()
                identityGenerated = false
                attested = false
                log(.identityKeyDeleted, summary: recovered
                    ? "key invalidation acknowledged — identity and module state both cleared (v1 policy), next Generate/Attest starts fully fresh"
                    : "key invalidation acknowledged, but regeneration budget exhausted",
                    isError: !recovered)
                startNewSession()
            }
        } catch {
            log(.signFailed, summary: "\(error)", isError: true)
        }
    }

    /// Matches Option A (appattestkit-module-design.md §8): resetting module
    /// state does NOT touch the identity key.
    func resetModuleState() async {
        #if DEBUG
        if let coordinator {
            await coordinator.debugReset()
        }
        attested = false
        log(.moduleReset, summary: "module state cleared — identity key kept, matches Option A. Next Attest spends a real key generation.")
        startNewSession()
        #else
        log(.attestationFailed, summary: "debugReset is DEBUG-only", isError: true)
        #endif
    }

    func deleteIdentityKey() async {
        IdentityKeyStore.delete()
        identityGenerated = false
        attested = false
        identityPublicKeyPrefix = nil
        #if DEBUG
        // Without this, the coordinator's in-memory state can still say
        // .attested from before the delete — and AttestationCoordinator.run()
        // returns immediately on `state.isAttested`, without ever contacting
        // Apple again, for an identity that no longer matches it.
        if let coordinator {
            await coordinator.debugReset()
        }
        log(.identityKeyDeleted, summary: "identity key and module state cleared — next Attest starts fully fresh")
        #else
        log(.identityKeyDeleted, summary: "identity key deleted, but debugReset is DEBUG-only — module state may still read attested", isError: true)
        #endif
        startNewSession()
    }

    // MARK: - Wiring

    private func resolveCoordinator() -> AttestationCoordinator {
        if let coordinator { return coordinator }
        let transport = LocalFakeTransport { [weak self] event in
            Task { @MainActor in self?.handleTransportEvent(event) }
        }
        let observer = HarnessObserver(
            onTransition: { [weak self] state in
                Task { @MainActor in self?.recordTransition(state) }
            },
            onFailure: { [weak self] error, attempt in
                Task { @MainActor in
                    self?.log(.attestationFailed, summary: "\(error.diagnosticName) (attempt \(attempt))", isError: true)
                }
            })
        let coordinator = AttestationCoordinator(transport: transport, observer: observer)
        self.coordinator = coordinator
        return coordinator
    }

    /// NEVER interpolate a state's associated keyId directly — `.label` is
    /// deliberately the safe, keyId-omitting summary (architecture doc §10).
    private func recordTransition(_ newState: AttestationState) {
        switch newState {
        case .none:
            break
        case .keyGenerated:
            log(.attestationStepKeyGenerated, summary: "App Attest key generated — no network involved")
            let count = UserDefaults.standard.integer(forKey: Self.attemptCountKey)
            UserDefaults.standard.set(count + 1, forKey: Self.attemptCountKey)
        case .attestationPending(_, let attestationData, _):
            log(.attestationStepAttested, summary: "CBOR attestation object received (\(attestationData.count) bytes)",
                detail: [
                    DetailField(label: "Format", value: "CBOR — {fmt, attStmt, authData}"),
                    DetailField(label: "Attestation object size", value: "\(attestationData.count) bytes"),
                    DetailField(label: "Environment", value: AttestationEnvironmentHint.describe(attestationData)),
                    // Full raw bytes, unmodified from what attestKey() returned.
                    // In-memory only (this history is never persisted), but this
                    // is the same category of sensitive data as keyId — the
                    // embedded cert contains the device's real App Attest
                    // public key. Never wire this field into anything that
                    // persists, syncs, or reaches a crash report.
                    DetailField(label: "Raw CBOR (hex)",
                                value: attestationData.map { String(format: "%02x", $0) }.joined())
                ])
        case .attested:
            // No log here — handleTransportEvent's .submitted case already
            // logs this same moment (with the actually useful detail, the
            // fake account UUID). This transition is just its downstream
            // result; logging both would duplicate one real event.
            break
        case .unsupported:
            log(.attestationFailed, summary: "unsupported — real device required (Simulator always reports this)", isError: true)
        }
    }

    private func handleTransportEvent(_ event: TransportEvent) {
        switch event {
        case .challengeFetched(let byteCount):
            log(.attestationStepChallenge, summary: "GET /challenge → \(byteCount) random bytes")
        case .submitted(let accountUUID):
            log(.attestationStepSubmitted, summary: "POST /register → Auth Server",
                detail: [DetailField(label: "Account UUID (fake)", value: accountUUID)])
        }
    }

    private func log(_ kind: HarnessEvent.Kind, summary: String, detail: [DetailField] = [], isError: Bool = false) {
        let event = HarnessEvent(kind: kind, timestamp: Date(), summary: summary, detail: detail, isError: isError)
        sessions[sessions.count - 1].events.append(event)
    }

    private func startNewSession() {
        sessions.append(HarnessSession())
    }
}

/// Diagnostics only — NEVER logs a keyId, which is a persistent device
/// identifier (architecture doc §10). AttestationObserver's methods are
/// synchronous by design (the coordinator calls them in-line from actor
/// context), so this hops to MainActor explicitly rather than assuming one.
struct HarnessObserver: AttestationObserver {
    let onTransition: @Sendable (AttestationState) -> Void
    let onFailure: @Sendable (AttestationError, Int) -> Void

    func didTransition(to state: AttestationState) { onTransition(state) }
    func didFail(_ error: AttestationError, attempt: Int) { onFailure(error, attempt) }
}
