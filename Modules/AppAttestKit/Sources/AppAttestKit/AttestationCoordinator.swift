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
/// concurrent calls would mean two `generateKey()` calls and two orphaned keys
/// for no reason. `Sendable` is a data-race ANNOTATION, not mutual exclusion —
/// it would not prevent this. See module doc §4.
///
/// Regeneration is NOT capped here. Earlier revisions enforced a local,
/// Keychain-persisted regeneration limit as a defensive measure against an
/// undocumented Apple-side budget — reconsidered: Apple publishes no per-device
/// generateKey() count, the Secure Enclave has its own abuse defenses this
/// module has no business duplicating, and the cap's only measurable effect in
/// practice was false "exhausted" failures during ordinary reinstall-heavy
/// testing, with no production recovery path once hit. See account-keys-reference.md.
public actor AttestationCoordinator: AssertionSigning {

    /// Internal and injectable so tests can run with zero backoff. Not public:
    /// retry behaviour is module policy, and exposing it would invite the app to
    /// build a competing retry loop alongside this one.
    struct Policy: Sendable {
        var maxAttempts: Int = 5
        /// Exponential, capped at 60s. `Duration` is iOS 16+, available now
        /// that the floor is 17.
        var backoff: @Sendable (Int) -> Duration = { attempt in
            .seconds(min(pow(2.0, Double(attempt)), 60))
        }

        static let `default` = Policy()
        /// Tests only — real sleeps would make the suite take minutes.
        static let immediate = Policy(backoff: { _ in .zero })
    }

    private let service: AttestServicing
    private let store: AttestationKeyStore
    private let transport: AttestationTransport
    private let observer: AttestationObserver?
    private let policy: Policy

    private var state: AttestationState = .none
    private var inFlight: Task<AttestationState, Error>?

    // MARK: Initializers
    //
    // Two of them, because a `public init` cannot expose internal parameter
    // types — and `AttestServicing`/`AttestationKeyStore` are internal by design.

    /// Production. The app supplies only what is genuinely app-specific.
    /// Note it CANNOT inject a service or store — that is the point.
    public init(transport: AttestationTransport, observer: AttestationObserver? = nil) {
        self.init(service: LiveAttestService(),
                  store: LiveKeyStore(),
                  transport: transport,
                  observer: observer,
                  policy: .default)
    }

    /// Tests. Internal — reachable via `@testable import AppAttestKit`.
    init(service: AttestServicing,
         store: AttestationKeyStore,
         transport: AttestationTransport,
         observer: AttestationObserver?,
         policy: Policy = .default) {
        self.service = service
        self.store = store
        self.transport = transport
        self.observer = observer
        self.policy = policy
    }

    // MARK: Public API — this is the app's entire surface

    public var currentState: AttestationState { state }

    /// Idempotent. Safe to call on every launch, every foreground, and on
    /// connectivity change — concurrent calls collapse into one.
    ///
    /// - Parameter binding: the APP builds the clientDataHash from the challenge.
    ///   The module does NOT construct this — the composition is an
    ///   app-specific protocol decision, and the module must not know
    ///   identity keys exist. Currently `SHA256(challenge)` alone (revised
    ///   from `SHA256(challenge ‖ identityPublicKey)` — the server-side
    ///   verification library fixes this formula with no override seam; the
    ///   identity binding now lives server-side instead, see
    ///   `account-keys-reference.md`). A closure rather than a 6th protocol:
    ///   no test needs a seam here (§11).
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
        // Only clear OUR task: `cancelInFlight()` may already have cleared it,
        // and a newer call may have installed its own since.
        defer { if inFlight == task { inFlight = nil } }
        return try await task.value
    }

    /// Restores state from disk without contacting Apple or the network.
    /// Call on launch to decide which screen to show.
    public func restore() async {
        transition(to: persistedState())
    }

    /// Call this — in production, not just tests — when the app observes
    /// `.keyInvalid` from `sign()`. That's the ONE way key invalidation can be
    /// discovered outside an active `ensureAttested()` call (a device restore,
    /// or Keychain cleared independently of a fresh install), and without this
    /// method there is no way back: `sign()` deliberately doesn't self-heal
    /// ("keep this path thin" — module doc §3), and `ensureAttested()`'s own
    /// persisted-state check (`run()`, below) would keep trusting the stale
    /// `isAttested` record forever, since it exists specifically to avoid
    /// re-attesting a key that's still fine.
    ///
    /// Also the way out of a registration the server has definitively
    /// rejected: `.serverRejected` from `ensureAttested()` leaves the state at
    /// `.attestationPending` (the module never discards a key on a server-side
    /// "no" by itself), and calling this is the app's explicit decision to
    /// give that key up and start over.
    ///
    /// Cancels and waits for any in-flight `ensureAttested()` first — without
    /// that, a call sitting in its retry backoff would wake up into the
    /// freshly-cleared state and run a whole new generate → attest → register
    /// behind the caller's back. The cancelled call throws `CancellationError`.
    ///
    /// ⚠️ Confirmed on real hardware: a keyId orphaned by an app reinstall does
    /// NOT surface from `sign()` as `.keyInvalid` — it surfaces as
    /// `.serverRejected("invalidInput")` (see the note on `AttestationError.from`).
    /// If your `clientDataHash` for `sign()` is always a freshly-computed,
    /// well-formed digest (true for the vast majority of callers — there's
    /// nothing app-supplied that could make it malformed), treat
    /// `.serverRejected("invalidInput")` from `sign()` as equivalent to
    /// `.keyInvalid` and call this method for both. This module can't make
    /// that assumption generically (a genuinely malformed hash elsewhere is a
    /// real bug worth surfacing, not silently papering over), so it's a
    /// judgment call for the caller, not encoded here.
    ///
    /// Not bounded by anything here — no local cap. Still only call this in
    /// direct response to a genuine key-invalidation signal from `sign()`,
    /// not speculatively: each call wipes state and spends a real
    /// `generateKey()` on the next attestation, so calling it needlessly is
    /// still wasteful even without an enforced cap.
    public func acknowledgeKeyInvalidation() async {
        await cancelInFlight()
        regenerateKey()
    }

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
        // Read the STORE, not just in-memory state. An app that calls
        // ensureAttested() without restore() first would otherwise skip
        // straight past whatever a previous run persisted and re-attest a
        // ONE-SHOT key — both for a fully registered key AND for one whose
        // attestation is cached but not yet confirmed by the server.
        if case .none = state { transition(to: persistedState()) }
        if state.isAttested { return state }

        guard service.isSupported else {
            let error = AttestationError.unsupported
            observer?.didFail(error, attempt: 0)
            transition(to: .unsupported(error))
            return state
        }

        var attempt = 0
        while attempt < policy.maxAttempts {
            // Set by cancelInFlight(). Checked before each attempt so a
            // cancelled call never starts another step.
            try Task.checkCancellation()
            do {
                return try await attemptRegistration(binding: binding)
            } catch let error as AttestationError where error.requiresNewKey {
                // The ONLY branch where a new key is legitimate — still bounded
                // by maxAttempts below (the while loop), just no separate,
                // longer-lived cap on top of it. Shared logic with
                // acknowledgeKeyInvalidation() since both are "a key just died,
                // get ready to make a new one," differing only in *when* that's
                // discovered.
                regenerateKey()
                attempt += 1
                observer?.didFail(error, attempt: attempt)

            } catch let error as AttestationError where error.isRetryable {
                // Retry with the SAME keyId. Never regenerate here.
                attempt += 1
                observer?.didFail(error, attempt: attempt)
                // No backoff after the final attempt — nothing follows it.
                if attempt < policy.maxAttempts {
                    try await Task.sleep(for: policy.backoff(attempt))
                }

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

        let pending = try await performAttestation(binding: binding)
        guard case .attestationPending(let keyId, let attestation, let challenge) = pending else {
            return pending
        }
        return try await submit(keyId: keyId, attestation: attestation, challenge: challenge)
    }

    /// STEPS 3–8: everything up to and including the Apple round trip and
    /// persisting `.attestationPending` — but NOT `submit()`.
    private func performAttestation(binding: @Sendable @escaping (Data) throws -> Data) async throws -> AttestationState {
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
        do {
            challenge = try await transport.fetchChallenge()
        } catch let error as AttestationError {
            // Pass through unchanged. Coercing everything to .networkUnavailable
            // would turn a terminal .serverRejected into an infinite retry loop.
            throw error
        } catch {
            throw AttestationError.networkUnavailable
        }

        // STEP 6 — the APP builds the binding. The module carries an opaque
        // hash and never learns what is in it (see `ensureAttested(binding:)`).
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
        return state
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

        // STEP 12 — record that registration completed so a relaunch skips
        // the flow entirely, THEN clear the cache. The flag write must not be
        // swallowed: if it failed and the cache were cleared anyway, a
        // relaunch would see "key generated, never attested", re-attest a
        // one-shot key, and end up registering a brand-new account. Throwing
        // here leaves `.attestationPending` intact, so the next call just
        // resubmits and the server's idempotency returns the same account.
        try store.store(isAttested: true)
        try? store.clearAttestation()
        transition(to: .attested(keyId: keyId))
        return state
    }

    // MARK: Helpers

    /// Clears the dead key's record and transitions to `.none`, ready for a
    /// fresh `generateKey()` on the next attempt. Shared by the retry loop's
    /// `requiresNewKey` branch and `acknowledgeKeyInvalidation()`.
    private func regenerateKey() {
        try? store.clear()
        transition(to: .none)
    }

    /// What the persisted data alone says the state is. Shared by `restore()`
    /// and `run()` so a caller that skips `restore()` resumes identically.
    private func persistedState() -> AttestationState {
        guard let keyId = (try? store.loadKeyId()) ?? nil else { return .none }
        // Order matters: check `attested` FIRST. A registered user must not be
        // sent back through the flow — attesting a one-shot key a second time
        // fails with .invalidKey, triggering a needless regeneration for a key
        // that was never actually broken.
        if (try? store.loadIsAttested()) == true {
            return .attested(keyId: keyId)
        }
        if let cached = try? store.loadAttestation() {
            return .attestationPending(keyId: keyId,
                                       attestation: cached.object,
                                       challenge: cached.challenge)
        }
        return .keyGenerated(keyId: keyId)
    }

    /// Cancels the in-flight `ensureAttested()`, if any, and waits for it to
    /// unwind. A step already past its last suspension point (e.g. inside
    /// `attestKey`) still completes; nothing new starts after it.
    private func cancelInFlight() async {
        while let task = inFlight {
            task.cancel()
            _ = try? await task.value
            if inFlight == task { inFlight = nil }
        }
    }

    /// No-op when the state is unchanged, so the observer sees each state
    /// once — not once per retry-loop re-entry.
    private func transition(to newState: AttestationState) {
        guard newState != state else { return }
        state = newState
        observer?.didTransition(to: newState)
    }
}
