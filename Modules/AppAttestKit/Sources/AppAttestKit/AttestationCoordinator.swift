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
/// Regeneration has no PERSISTED cap. Earlier revisions enforced a local,
/// Keychain-persisted regeneration limit as a defensive measure against an
/// undocumented Apple-side budget — reconsidered: Apple publishes no per-device
/// generateKey() count, the Secure Enclave has its own abuse defenses this
/// module has no business duplicating, and the cap's only measurable effect in
/// practice was false "exhausted" failures during ordinary reinstall-heavy
/// testing, with no production recovery path once hit. See account-keys-reference.md.
///
/// What IS bounded is a single `ensureAttested()` call: it replaces a dead
/// key at most once (see `run()`). Nothing is remembered afterwards, so this
/// cannot strand anyone — the next call simply starts again.
public actor AttestationCoordinator: AssertionSigning {

    /// Internal and injectable so tests can run with zero backoff. Not public:
    /// retry behaviour is module policy, and exposing it would invite the app to
    /// build a competing retry loop alongside this one.
    struct Policy: Sendable {
        var maxAttempts: Int = 5
        /// Exponential, capped at 60s, then randomised between half and the
        /// full value. Without the jitter every device that failed at the
        /// same moment (an Apple or server outage) would retry at the same
        /// moments too — the load pattern Apple's App Attest guidance warns
        /// against. `Duration` is iOS 16+, available now that the floor is 17.
        var backoff: @Sendable (Int) -> Duration = { attempt in
            .seconds(min(pow(2.0, Double(attempt)), 60) * Double.random(in: 0.5...1))
        }

        /// Deadline for a single `DCAppAttestService` call. Those calls have
        /// no timeout of their own: confirmed on a real device, `attestKey`
        /// started with no connectivity never returned — not after ten
        /// minutes, not when the network came back — and a registration
        /// waiting on it hung until the app was killed. Normal latency is a
        /// few seconds, so 30s is generous without being indefinite.
        var appleCallTimeout: Duration = .seconds(30)

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

    /// The challenge fetched for the key currently being attested, kept for
    /// the rest of ONE `ensureAttested()` call. Apple's guidance for a failed
    /// `attestKey` is to retry with the same key AND the same client data
    /// hash (it preserves the device's risk metric) — so a retry must not go
    /// back to the server for a new challenge. Dropped when the key is
    /// attested or discarded, and at the start of every call: the challenge
    /// has a server-side lifetime this module knows nothing about, and one
    /// call is short enough not to outlive it.
    private var heldChallenge: (keyId: String, challenge: Data)?

    // MARK: Initializers
    //
    // A production one that cannot be handed a service or store, and test
    // ones that can. `AttestServicing`/`AttestationKeyStore` are SPI, so the
    // app only sees them by opting in with `@_spi(Testing) import`.

    /// Production. The app supplies only what is genuinely app-specific.
    /// Note it CANNOT inject a service or store — that is the point. (The
    /// Debug-only SPI initializer below exists for tests, not for the app.)
    public init(transport: AttestationTransport, observer: AttestationObserver? = nil) {
        self.init(service: LiveAttestService(),
                  store: LiveKeyStore(),
                  transport: transport,
                  observer: observer,
                  policy: .default)
    }

#if DEBUG
    /// Tests of OTHER modules and of the app, which cannot use
    /// `@testable import AppAttestKit`: the real state machine with Apple and
    /// the Keychain replaced. Debug builds only, and behind
    /// `@_spi(Testing) import AppAttestKit`, so nothing that ships can reach
    /// it. Retries without waiting.
    @_spi(Testing)
    public init(testingService service: AttestServicing,
                store: AttestationKeyStore,
                transport: AttestationTransport,
                observer: AttestationObserver? = nil) {
        self.init(service: service, store: store, transport: transport,
                  observer: observer, policy: .immediate)
    }
#endif

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
    ///
    /// How a call ends, and what the app should do about it:
    ///   - returns `.attested` — done.
    ///   - returns `.unsupported` — this device cannot attest. Terminal.
    ///   - throws `.exhausted` — transient trouble outlasted the retries.
    ///     Call again on the next trigger; it resumes where it stopped.
    ///   - throws `.serverRejected` — the server said no. Do NOT call again
    ///     from an automatic trigger: against a server that consumes the
    ///     challenge on a rejected attempt, the following call discards the
    ///     key and attests a new one, so a server that rejects everything
    ///     would cost one key per two calls. Retry on the next cold launch
    ///     or an explicit user action.
    ///   - throws `.keyInvalid` / `.challengeExpired` — the key was replaced
    ///     once in this call and the replacement failed the same way. The
    ///     state is `.none`; treat it like `.serverRejected` above.
    ///   - throws `.storageFailed` — the Keychain refused a write. State is
    ///     whatever was last persisted; call again later.
    ///   - throws `CancellationError` — `acknowledgeKeyInvalidation()` ran.
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
    ///
    /// Throws `.storageFailed` when the persisted state cannot be READ —
    /// typically a launch while the device is still locked. That is not the
    /// same as "nothing persisted": the state is left as it was, and the app
    /// must not treat the user as unregistered. Call again once protected
    /// data is available.
    public func restore() async throws {
        transition(to: try persistedState())
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
        let service = self.service
        return try await callApple {
            try await service.generateAssertion(keyId, clientDataHash: payload)
        }
    }

    // MARK: Flow

    private func run(binding: @Sendable @escaping (Data) throws -> Data) async throws -> AttestationState {
        // Read the STORE, not just in-memory state. An app that calls
        // ensureAttested() without restore() first would otherwise skip
        // straight past whatever a previous run persisted and re-attest a
        // ONE-SHOT key — both for a fully registered key AND for one whose
        // attestation is cached but not yet confirmed by the server.
        if case .none = state {
            do {
                transition(to: try persistedState())
            } catch let error as AttestationError {
                observer?.didFail(error, attempt: 0)
                throw error
            }
        }
        if state.isAttested { return state }
        heldChallenge = nil

        guard service.isSupported else {
            let error = AttestationError.unsupported
            observer?.didFail(error, attempt: 0)
            transition(to: .unsupported(error))
            return state
        }

        var attempt = 0
        var replacedKey = false
        while attempt < policy.maxAttempts {
            // Set by cancelInFlight(). Checked before each attempt so a
            // cancelled call never starts another step.
            try Task.checkCancellation()
            do {
                return try await attemptRegistration(binding: binding)
            } catch let error as AttestationError where error.requiresNewKey {
                // The ONLY branch where a new key is legitimate. Shared logic
                // with acknowledgeKeyInvalidation() since both are "a key just
                // died, get ready to make a new one," differing only in *when*
                // that's discovered.
                regenerateKey()
                attempt += 1
                observer?.didFail(error, attempt: attempt)
                // ONE replacement per call. A brand-new key failing the same
                // way means the cause is not the key (a server that expires
                // every challenge, a device Apple refuses) — and without this
                // the loop would spend a real generateKey() on every remaining
                // attempt, back to back. The dead key is already cleared, so
                // the next call starts clean.
                if replacedKey { throw error }
                replacedKey = true

            } catch let error as AttestationError where error.isRetryable {
                // Retry with the SAME keyId. Never regenerate here.
                attempt += 1
                observer?.didFail(error, attempt: attempt)
                // No backoff after the final attempt — nothing follows it.
                if attempt < policy.maxAttempts {
                    try await Task.sleep(for: policy.backoff(attempt))
                }

            } catch AttestationError.unsupported {
                // `DCError.featureUnsupported` from a call, on a device whose
                // `isSupported` said yes. Same outcome as the guard above.
                observer?.didFail(.unsupported, attempt: attempt)
                transition(to: .unsupported(.unsupported))
                return state

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
        if let existing = try persisting({ try store.loadKeyId() }) {
            keyId = existing
        } else {
            let service = self.service
            keyId = try await callApple { try await service.generateKey() }
            // STEP 4 — persist BEFORE attesting, so a crash cannot orphan the key.
            try persisting { try store.store(keyId: keyId) }
        }
        transition(to: .keyGenerated(keyId: keyId))

        // STEP 5 — challenge. ~15 min TTL, longer than session challenges,
        // because the attestation we cache below is bound to it.
        // Fetched once per key per call: a retry after a failed attestKey
        // reuses it (see `heldChallenge`).
        let challenge: Data
        if let held = heldChallenge, held.keyId == keyId {
            challenge = held.challenge
        } else {
            do {
                challenge = try await transport.fetchChallenge()
            } catch let error as AttestationError {
                // Pass through unchanged. Coercing everything to .networkUnavailable
                // would turn a terminal .serverRejected into an infinite retry loop.
                throw error
            } catch {
                throw AttestationError.networkUnavailable
            }
            heldChallenge = (keyId, challenge)
        }

        // STEP 6 — the APP builds the binding. The module carries an opaque
        // hash and never learns what is in it (see `ensureAttested(binding:)`).
        let clientDataHash = try binding(challenge)

        // STEP 7 — ONE-SHOT. After this succeeds the key is assertion-only.
        let service = self.service
        let attestation: Data
        do {
            attestation = try await callApple {
                try await service.attestKey(keyId, clientDataHash: clientDataHash)
            }
        } catch AttestationError.serverRejected("invalidInput")
                    where clientDataHash.count == Self.sha256Length {
            // Apple rejected the INPUT, and the hash is a well-formed digest —
            // which leaves the keyId, one this module generated and stored
            // itself. Apple answers this way (not `.invalidKey`) for a key
            // orphaned by a reinstall; reported as-is it would be terminal,
            // and every later call would fail on the same key forever.
            throw AttestationError.keyInvalid
        }

        // STEP 8 — persist IMMEDIATELY, before any network call. If the write
        // fails, carry on from memory rather than throw: the cache only exists
        // to survive a crash, and throwing here would lose an attestation that
        // can never be obtained again for this key.
        do {
            try persisting { try store.store(attestation: attestation, challenge: challenge) }
        } catch let error as AttestationError {
            observer?.didFail(error, attempt: 0)
        }
        heldChallenge = nil
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
        try persisting { try store.store(isAttested: true) }
        try? store.clearAttestation()
        transition(to: .attested(keyId: keyId))
        return state
    }

    // MARK: Helpers

    /// `clientDataHash` is documented by Apple as a SHA256 digest.
    private static let sha256Length = 32

    /// Runs one store call, reporting a failure as `.storageFailed` so it
    /// goes through the same error handling — and reaches the observer —
    /// like every other failure, instead of escaping as a raw Keychain error.
    private func persisting<T>(_ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch {
            if let keychain = error as? KeychainError {
                throw AttestationError.storageFailed("keychain \(keychain.status)")
            }
            let ns = error as NSError
            throw AttestationError.storageFailed("\(ns.domain) \(ns.code)")
        }
    }

    /// Clears the dead key's record and transitions to `.none`, ready for a
    /// fresh `generateKey()` on the next attempt. Shared by the retry loop's
    /// `requiresNewKey` branch and `acknowledgeKeyInvalidation()`.
    private func regenerateKey() {
        heldChallenge = nil
        try? store.clear()
        transition(to: .none)
    }

    /// Runs one `DCAppAttestService` call under `Policy.appleCallTimeout`,
    /// mapping its errors to `AttestationError`.
    ///
    /// The call itself cannot be cancelled or timed out — so it runs in its
    /// own task and this method simply stops WAITING for it, on whichever
    /// comes first: its result, the deadline (`.retryable("timedOut")`), or
    /// cancellation of the caller (`CancellationError`). The last one is what
    /// lets `acknowledgeKeyInvalidation()` get past a flow that is stuck
    /// inside Apple's call instead of hanging behind it.
    ///
    /// A call abandoned this way may still complete later; its result is
    /// dropped. Confirmed on a real device that an abandoned `attestKey`
    /// does not consume the key — the next attempt attested it normally.
    private func callApple<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let (results, continuation) = AsyncThrowingStream<T, Error>.makeStream()
        let work = Task {
            do {
                continuation.yield(try await operation())
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timeout = policy.appleCallTimeout
        let deadline = Task {
            try await Task.sleep(for: timeout)
            continuation.finish(throwing: AttestationError.retryable("timedOut"))
        }
        defer {
            work.cancel()
            deadline.cancel()
        }
        do {
            for try await value in results { return value }
        } catch {
            throw AttestationError.from(error)
        }
        // The stream ended with neither a value nor an error: the task
        // waiting on it was cancelled.
        throw CancellationError()
    }

    /// What the persisted data alone says the state is. Shared by `restore()`
    /// and `run()` so a caller that skips `restore()` resumes identically.
    ///
    /// A read that FAILS throws `.storageFailed`; it is never taken to mean
    /// "not there". Guessing would be worst exactly where it is most likely:
    /// with the `keyId` readable but the "server confirmed" flag not, a
    /// registered key would look merely generated, be sent to `attestKey`
    /// a second time, fail as invalid, and be replaced — a new account for
    /// an existing user.
    private func persistedState() throws -> AttestationState {
        try persisting {
            guard let keyId = try store.loadKeyId() else { return .none }
            // Order matters: check `attested` FIRST. A registered user must
            // not be sent back through the flow — attesting a one-shot key a
            // second time fails with .invalidKey, triggering a needless
            // regeneration for a key that was never actually broken.
            if try store.loadIsAttested() {
                return .attested(keyId: keyId)
            }
            if let cached = try store.loadAttestation() {
                return .attestationPending(keyId: keyId,
                                           attestation: cached.object,
                                           challenge: cached.challenge)
            }
            return .keyGenerated(keyId: keyId)
        }
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
