//
//  AttestationCoordinator.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 30/08/2026.
//


import Foundation

/// The module's single entry point, and the only stateful thing in it.
///
/// Owns four responsibilities the seams deliberately do not:
///   1. The state machine — where in the flow we are, and what comes next
///   2. Serialization — actor + in-flight deduplication
///   3. Retry policy — backoff, attempt counting, the never-regenerate rule
///   4. Persistence ORDERING — the writes that make crash resumption work
///
/// Why an `actor` and not just `Sendable`: `ensureAttested()` is triggered from
/// app launch, foreground, AND connectivity change, which can overlap. Two
/// concurrent calls would mean two `generateKey()` calls, two orphaned keys, and
/// a device lifetime key budget burned for nothing. `Sendable` is a data-race
/// ANNOTATION, not mutual exclusion — it would not prevent this.
/// See module doc §4.
public actor AttestationCoordinator: AssertionSigning {

    enum Policy {
        static let maxAttempts = 5
        /// Persisted across launches. Bounds the ONE case where regenerating a
        /// key is legitimate, so a bug cannot loop and exhaust the device budget.
        static let maxKeyRegenerations = 3
        /// Nanoseconds, not `Duration` — `Duration` and `Task.sleep(for:)`
        /// are iOS 16+, and this package targets iOS 14.
        static func backoffNanos(attempt: Int) -> UInt64 {
            UInt64(min(pow(2.0, Double(attempt)), 60) * 1_000_000_000)
        }
    }

    private let service: AttestServicing
    private let store: AttestationKeyStore
    private let transport: AttestationTransport
    private let observer: AttestationObserver?

    private var state: AttestationState = .none
    private var inFlight: Task<AttestationState, Error>?

    // MARK: Initializers
    //
    // Two of them, because a `public init` cannot expose internal parameter
    // types — and `AttestServicing`/`AttestationKeyStore` are internal by design.

    /// Production. The app supplies only what is genuinely app-specific.
    /// Note it CANNOT inject a service or store — that is the point.
    public init(transport: AttestationTransport, observer: AttestationObserver? = nil) {
        self.init(service: AttestService(),
                  store: DefaultKeyStore(),
                  transport: transport,
                  observer: observer)
    }

    /// Tests. Internal — reachable via `@testable import AppAttestKit`.
    init(service: AttestServicing,
         store: AttestationKeyStore,
         transport: AttestationTransport,
         observer: AttestationObserver?) {
        self.service = service
        self.store = store
        self.transport = transport
        self.observer = observer
    }

    // MARK: Public API — this is the app's entire surface

    public var currentState: AttestationState { state }

    /// Idempotent. Safe to call on every launch, every foreground, and on
    /// connectivity change — concurrent calls collapse into one.
    ///
    /// - Parameter binding: the APP builds the clientDataHash from the challenge.
    ///   The module does NOT construct this — the composition
    ///   `SHA256(challenge ‖ identityPublicKey)` is an app-specific protocol
    ///   decision, and the module must not know identity keys exist.
    ///   A closure rather than a 6th protocol: no test needs a seam here (§11).
    @discardableResult
    public func ensureAttested(
        binding: @Sendable @escaping (Data) throws -> Data
    ) async throws -> AttestationState {
        // In-flight deduplication. Without this, overlapping triggers each start
        // their own attestation.
        if let existing = inFlight {
            return try await existing.value
        }
        let task = Task { try await run(binding: binding) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    /// Restores state from disk without contacting Apple or the network.
    /// Call on launch to decide which screen to show.
    public func restore() async {
        guard let keyId = (try? store.loadKeyId()) ?? nil else {
            transition(to: .none)
            return
        }
        // Order matters: check `attested` FIRST. A registered user must not be
        // sent back through the flow — attesting a one-shot key a second time
        // fails with .invalidKey, which would consume a key regeneration and,
        // repeated, lock the user out permanently.
        if (try? store.loadIsAttested()) == true {
            transition(to: .attested(keyId: keyId))
        } else if let cached = try? store.loadAttestation() {
            transition(to: .attestationPending(keyId: keyId,
                                               attestation: cached.object,
                                               challenge: cached.challenge))
        } else {
            transition(to: .keyGenerated(keyId: keyId))
        }
    }

    #if DEBUG
    /// Harness only. Wipes persisted state so a full attestation can be re-run.
    ///
    /// ⚠️ This does NOT give you unlimited test runs. Key generation is capped
    /// per device per App ID for the device's lifetime, so every reset-and-retry
    /// consumes part of a finite budget. Use the package's mock-based tests for
    /// iteration; use this sparingly to confirm real-API behaviour.
    ///
    /// Compile-time gated, NOT a runtime flag — a runtime bypass that ships is a
    /// bypass that gets found. See architecture doc §8.
    public func debugReset() {
        try? store.clear()
        transition(to: .none)
    }
    #endif

    // MARK: AssertionSigning
    //
    // The HOT PATH — runs on every authenticated request, forever.
    // Deliberately thin: no I/O, no retries, no observer calls, no state machine.
    // All the machinery above belongs to the one-time flow.

    public func sign(_ payload: Data) async throws -> Data {
        guard case .attested(let keyId) = state else {
            throw AttestationError.notAttested
        }
        do {
            return try await service.generateAssertion(keyId, clientDataHash: payload)
        } catch {
            throw AttestationError.from(error)
        }
    }

    // MARK: Flow

    private func run(binding: @Sendable @escaping (Data) throws -> Data) async throws -> AttestationState {
        if state.isAttested { return state }

        guard service.isSupported else {
            let error = AttestationError.unsupported
            observer?.didFail(error, attempt: 0)
            transition(to: .unsupported(error))
            return state
        }

        var attempt = 0
        while attempt < Policy.maxAttempts {
            do {
                return try await attemptRegistration(binding: binding)
            } catch let error as AttestationError where error.requiresNewKey {
                // The ONLY branch where a new key is legitimate. Bounded, and the
                // bound is persisted so a crash-loop cannot bypass it.
                let used = (try? store.loadRegenerationCount()) ?? 0
                guard used < Policy.maxKeyRegenerations else {
                    observer?.didFail(.exhausted, attempt: attempt)
                    throw AttestationError.exhausted
                }
                try? store.store(regenerationCount: used + 1)
                try? store.clear()
                transition(to: .none)
                attempt += 1
                observer?.didFail(error, attempt: attempt)

            } catch let error as AttestationError where error.isRetryable {
                // Retry with the SAME keyId. Never regenerate here.
                attempt += 1
                observer?.didFail(error, attempt: attempt)
                try await Task.sleep(nanoseconds: Policy.backoffNanos(attempt: attempt))

            } catch let error as AttestationError {
                observer?.didFail(error, attempt: attempt)
                throw error
            }
        }
        observer?.didFail(.exhausted, attempt: attempt)
        throw AttestationError.exhausted
    }

    private func attemptRegistration(binding: @Sendable @escaping (Data) throws -> Data) async throws -> AttestationState {
        // Resume path: a previous run already got an attestation from Apple but
        // never confirmed with the server. Skip Apple entirely — the key is
        // one-shot and cannot be attested again.
        if case .attestationPending(let keyId, let attestation, let challenge) = state {
            return try await submit(keyId: keyId, attestation: attestation, challenge: challenge)
        }

        // STEP 3 — load before generate, ALWAYS.
        let keyId: String
        if let existing = try store.loadKeyId() {
            keyId = existing
        } else {
            do { keyId = try await service.generateKey() }
            catch { throw AttestationError.from(error) }
            // STEP 4 — persist BEFORE attesting, so a crash cannot orphan the key.
            try store.store(keyId: keyId)
        }
        transition(to: .keyGenerated(keyId: keyId))

        // STEP 5 — challenge. ~15 min TTL, longer than session challenges,
        // because the attestation we cache below is bound to it.
        let challenge: Data
        do { challenge = try await transport.fetchChallenge() }
        catch { throw AttestationError.networkUnavailable }

        // STEP 6 — the APP builds the binding. This is the step that makes the
        // whole scheme work: the App Attest key signs over a hash CONTAINING the
        // identity public key, letting the server conclude that this identity key
        // came from a genuine app on real hardware. The module carries an opaque
        // hash and never learns what is in it.
        let clientDataHash = try binding(challenge)

        // STEP 7 — ONE-SHOT. After this succeeds the key is assertion-only.
        let attestation: Data
        do { attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash) }
        catch { throw AttestationError.from(error) }

        // STEP 8 — persist IMMEDIATELY, before any network call.
        try store.store(attestation: attestation, challenge: challenge)
        transition(to: .attestationPending(keyId: keyId,
                                           attestation: attestation,
                                           challenge: challenge))

        return try await submit(keyId: keyId, attestation: attestation, challenge: challenge)
    }

    private func submit(keyId: String, attestation: Data,
                        challenge: Data) async throws -> AttestationState {
        // STEP 9 — app-implemented transport.
        do {
            _ = try await transport.submitAttestation(
                AttestationSubmission(keyId: keyId, challenge: challenge,
                                      attestation: attestation))
        } catch let error as AttestationError {
            throw error
        } catch {
            throw AttestationError.networkUnavailable
        }

        // STEP 12 — clear the cache only AFTER the server confirms, and record
        // that registration completed so a relaunch skips the flow entirely.
        try? store.store(isAttested: true)
        try? store.clearAttestation()
        transition(to: .attested(keyId: keyId))
        return state
    }

    // MARK: Helpers

    private func transition(to newState: AttestationState) {
        state = newState
        observer?.didTransition(to: newState)
    }
}
