//
//  HarnessModel.swift
//  AppAttestTestApp
//
//  Drives AppAttestKit's real AttestationCoordinator against real
//  DCAppAttestService calls, with LocalFakeTransport standing in for the
//  not-yet-built server and IdentityKeyStore standing in for the eventual
//  RegistrationFeature layer (module doc §2's layering).
//
//  Deliberately reads NOTHING from AppAttestKit except its public surface —
//  AttestationCoordinator.currentState, never the internal storage types
//  directly. That boundary is the module's core guarantee (README.md: "the
//  one thing to look for" — the app cannot reach around the coordinator),
//  and a harness that used @testable to peek at it anyway would defeat the
//  point of building it this way.
//

import Foundation
import CryptoKit
import AppAttestKit

@Observable @MainActor
final class HarnessModel {

    var log: [String] = []
    var state: String = "unknown"

    /// Real generateKey() calls this harness has made on this device, ever.
    /// Apple exposes no remaining-budget API (confirmed against current
    /// docs), so this is a local heuristic, not authoritative — but it's the
    /// only visibility into "how much have I spent" available at all.
    var realAttemptCount: Int {
        UserDefaults.standard.integer(forKey: Self.attemptCountKey)
    }

    private static let attemptCountKey = "harness.realAttemptCount"
    private var coordinator: AttestationCoordinator?

    /// Step 0 — check support before anything else.
    func checkSupport() {
        append("Run on a real device to see isSupported == true.")
        append("On the Simulator, expect .unsupported from Attest below — that's correct, not a bug.")
    }

    /// Restore only — no network, no Apple calls. Reports exactly what's
    /// persisted, entirely through the coordinator's own public state.
    func restoreOnly() async {
        let coordinator = resolveCoordinator()
        await coordinator.restore()
        let current = await coordinator.currentState
        state = current.label
        append("restore() → \(current.label)")
    }

    /// Full registration flow. Consumes a real key generation the first time
    /// it runs from `.none` — use deliberately, not in a loop (the
    /// AttestationCoordinator rate-limit warning applies here for real).
    func runAttestation() async {
        let coordinator = resolveCoordinator()
        do {
            let identityKey = try IdentityKeyStore.loadOrCreate()
            let publicKey = identityKey.publicKey.rawRepresentation
            append("identity key ready (\(publicKey.prefix(4).map { String(format: "%02x", $0) }.joined())…)")

            let result = try await coordinator.ensureAttested { challenge in
                Data(SHA256.hash(data: challenge + publicKey))
            }
            state = result.label
            append("FINAL: \(result.label)")
        } catch let error as AttestationError {
            append("FAILED: \(error.diagnosticName)")
        } catch {
            append("FAILED: \(error)")
        }
    }

    /// Cheap and repeatable, unlike attestation — this is the call a real
    /// session handshake makes on every connect.
    func signAssertion() async {
        guard let coordinator else { append("run Attest first"); return }
        do {
            let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            let signature = try await coordinator.sign(Data(SHA256.hash(data: nonce)))
            append("assertion ok, \(signature.count) bytes")
            append("→ a real server must verify the counter is STRICTLY GREATER than stored")
        } catch let error as AttestationError {
            append("assertion failed: \(error.diagnosticName)")
        } catch {
            append("assertion failed: \(error)")
        }
    }

    /// Wipes AppAttestKit's own persisted state via its public debugReset()
    /// (DEBUG-only). Does NOT touch the identity key — appattestkit-module-
    /// design.md §8 says the identity key is meant to survive this. Use
    /// "Delete identity key" separately to simulate losing both.
    func resetModuleState() async {
        #if DEBUG
        guard let coordinator else { append("nothing to reset"); return }
        await coordinator.debugReset()
        state = "none"
        append("module state cleared — next Attest consumes a real key generation")
        #else
        append("debugReset is DEBUG-only")
        #endif
    }

    /// Simulates "identity key also lost" (module doc §8's fallback case),
    /// kept separate from resetModuleState() so the two paths — identity
    /// survives (the common, designed-for case) vs. identity also lost
    /// (full fresh start) — can be tested independently.
    func deleteIdentityKey() {
        IdentityKeyStore.delete()
        append("identity key deleted — next Attest generates a NEW identity, not just a new account")
    }

    private func resolveCoordinator() -> AttestationCoordinator {
        if let coordinator { return coordinator }
        let transport = LocalFakeTransport { [weak self] line in
            Task { @MainActor in self?.append(line) }
        }
        let observer = HarnessObserver(
            onTransition: { [weak self] state in
                Task { @MainActor in self?.recordTransition(state) }
            },
            onFailure: { [weak self] error, attempt in
                Task { @MainActor in self?.append("✗ \(error.diagnosticName) (attempt \(attempt))") }
            })
        let coordinator = AttestationCoordinator(transport: transport, observer: observer)
        self.coordinator = coordinator
        return coordinator
    }

    private func recordTransition(_ newState: AttestationState) {
        state = newState.label
        append("→ \(newState.label)")
        // Each .keyGenerated transition corresponds 1:1 with a real
        // generateKey() call — the only module-boundary-respecting signal
        // available for tracking actual budget consumption (see the doc
        // comment on realAttemptCount above).
        if case .keyGenerated = newState {
            let count = UserDefaults.standard.integer(forKey: Self.attemptCountKey)
            UserDefaults.standard.set(count + 1, forKey: Self.attemptCountKey)
        }
    }

    private func append(_ line: String) {
        log.insert("\(Date().formatted(date: .omitted, time: .standard))  \(line)", at: 0)
    }
}

/// Diagnostics only — never logs a keyId, which is a persistent device
/// identifier (architecture doc §10). AttestationObserver's methods are
/// synchronous by design (the coordinator calls them in-line from actor
/// context), so this hops to MainActor explicitly rather than assuming one —
/// exactly what the protocol's own doc comment warns to do.
struct HarnessObserver: AttestationObserver {
    let onTransition: @Sendable (AttestationState) -> Void
    let onFailure: @Sendable (AttestationError, Int) -> Void

    func didTransition(to state: AttestationState) { onTransition(state) }
    func didFail(_ error: AttestationError, attempt: Int) { onFailure(error, attempt) }
}
