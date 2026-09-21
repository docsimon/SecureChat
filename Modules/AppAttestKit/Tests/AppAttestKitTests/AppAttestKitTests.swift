//
//  AppAttestKitTests.swift
//  AppAttestKitTests
//
//  Orchestration tests for `AttestationCoordinator` — the module's actual
//  justification (module doc §1: "the strong reason [to extract this module]
//  is testability"). These tests verify the state machine and retry policy
//  entirely with mocks; they prove nothing about whether Apple's real API is
//  being called correctly (that needs the host-app integration target and a
//  device — module doc §9). What they DO prove is exactly the class of bug
//  that would otherwise strand a real user: wrong retry behaviour, a missed
//  resume-after-crash, or a race that burns two key generations at once.
//

import Foundation
import Testing
@testable import AppAttestKit

// MARK: - Shared fixtures
//
// One literal value per concept, reused everywhere, so a test failure's diff
// is easy to read (e.g. "expected key-1, got key-2" instead of opaque bytes).

private let testKeyId = "key-1"
private let testChallenge = Data([0xAA, 0xBB])
private let testAttestation = Data([0x01])
private let testAssertion = Data([0x02])
private let testAccountUUID = "account-uuid"

/// Builds a coordinator wired to fresh mocks, with sensible defaults for the
/// "everything succeeds first try" case. Each test overrides only the pieces
/// it cares about.
///
/// Policy defaults to `.immediate` (zero backoff) — without this, every test
/// that exercises a retry would sit through real exponential-backoff sleeps
/// and the suite would take minutes instead of seconds (module doc §4).
private func makeCoordinator(
    isSupported: Bool = true,
    generateKeyResults: [Result<String, Error>] = [.success(testKeyId)],
    attestKeyResults: [Result<Data, Error>] = [.success(testAttestation)],
    generateAssertionResults: [Result<Data, Error>] = [.success(testAssertion)],
    fetchChallengeResults: [Result<Data, Error>] = [.success(testChallenge)],
    submitResults: [Result<String, Error>] = [.success(testAccountUUID)],
    keyStore: InMemoryKeyStore = InMemoryKeyStore(),
    policy: AttestationCoordinator.Policy = .immediate
) -> (coordinator: AttestationCoordinator,
      service: MockAttestService,
      store: InMemoryKeyStore,
      transport: MockTransport,
      observer: MockObserver) {
    let service = MockAttestService(isSupported: isSupported,
                                     generateKeyResults: generateKeyResults,
                                     attestKeyResults: attestKeyResults,
                                     generateAssertionResults: generateAssertionResults)
    let transport = MockTransport(fetchChallengeResults: fetchChallengeResults,
                                   submitResults: submitResults)
    let observer = MockObserver()
    let coordinator = AttestationCoordinator(service: service, store: keyStore,
                                              transport: transport, observer: observer,
                                              policy: policy)
    return (coordinator, service, keyStore, transport, observer)
}

/// The app-supplied `binding` closure normally builds
/// `SHA256(challenge ‖ identityPublicKey)` (workflow doc step 6). The
/// coordinator never inspects its contents, so tests just pass it through
/// unchanged.
private let identityBinding: @Sendable (Data) throws -> Data = { $0 }

// MARK: - Happy path

@Suite("Full registration flow")
struct HappyPathTests {

    @Test("Attests successfully and persists the result")
    func happyPathAttestsAndPersists() async throws {
        let (coordinator, service, store, transport, observer) = makeCoordinator()

        let final = try await coordinator.ensureAttested(binding: identityBinding)

        #expect(final == .attested(keyId: testKeyId))
        #expect(await service.generateKeyCallCount == 1)
        #expect(await transport.fetchChallengeCallCount == 1)
        #expect(await transport.submittedRequests.count == 1)
        #expect(try store.loadKeyId() == testKeyId)
        #expect(try store.loadIsAttested() == true)
        // Step 12: the cached attestation blob exists only to survive a crash
        // between "attested" and "server confirmed" — once confirmed it must
        // be cleared, or a later relaunch would misread it as still pending.
        #expect(try store.loadAttestation() == nil)
    }

    @Test("Observer sees the transitions in flow order")
    func observerRecordsTransitionsInOrder() async throws {
        let (coordinator, _, _, _, observer) = makeCoordinator()

        _ = try await coordinator.ensureAttested(binding: identityBinding)

        #expect(observer.transitions == [
            .keyGenerated(keyId: testKeyId),
            .attestationPending(keyId: testKeyId, attestation: testAttestation, challenge: testChallenge),
            .attested(keyId: testKeyId)
        ])
    }
}

// MARK: - Crash resumption
//
// Module doc §5: every state must be reconstructible from persisted data
// alone. These seed the store as if a previous run crashed mid-flow, then
// check `restore()` lands on the right state — and that continuing from
// there does the minimum necessary work, not a full re-run.

@Suite("Resumption after a simulated crash")
struct ResumptionTests {

    @Test("Resumes from keyGenerated without generating a new key")
    func resumesFromKeyGenerated() async throws {
        // Simulates a crash after step 4 (keyId persisted) but before step 7
        // (attestKey called).
        let store = InMemoryKeyStore(keyId: testKeyId)
        let (coordinator, service, _, _, _) = makeCoordinator(keyStore: store)

        await coordinator.restore()
        #expect(await coordinator.currentState == .keyGenerated(keyId: testKeyId))

        let final = try await coordinator.ensureAttested(binding: identityBinding)
        #expect(final == .attested(keyId: testKeyId))
        // The whole reason `restore()`/`loadKeyId()` exist: skip regenerating
        // and reuse the persisted key (workflow doc step 3, "load before generate").
        #expect(await service.generateKeyCallCount == 0)
    }

    @Test("Resumes from attestationPending without touching Apple's one-shot key again")
    func resumesFromAttestationPending() async throws {
        // Simulates a crash after step 8 (attestation cached) but before
        // step 12 (server confirmation processed).
        let store = InMemoryKeyStore(keyId: testKeyId,
                                      cachedAttestation: (testAttestation, testChallenge))
        let (coordinator, service, _, transport, _) = makeCoordinator(keyStore: store)

        await coordinator.restore()
        #expect(await coordinator.currentState ==
                .attestationPending(keyId: testKeyId, attestation: testAttestation, challenge: testChallenge))

        let final = try await coordinator.ensureAttested(binding: identityBinding)
        #expect(final == .attested(keyId: testKeyId))
        // Apple's key is one-shot: calling attestKey a second time would fail
        // with .keyInvalid and burn a regeneration for nothing. Resuming from
        // this state must skip Apple entirely and only retry the upload.
        #expect(await service.generateKeyCallCount == 0)
        #expect(await service.attestKeyCallCount == 0)
        #expect(await transport.submittedRequests.count == 1)
    }

    @Test("restore() checks attested before a stale cached attestation")
    func restoreChecksAttestedFirst() async throws {
        // A registered user whose cache was never cleared for some reason
        // must not be routed back through the pending-upload path — order
        // matters here (AttestationCoordinator.restore(), the comment on it).
        let store = InMemoryKeyStore(keyId: testKeyId, isAttested: true,
                                      cachedAttestation: (testAttestation, testChallenge))
        let (coordinator, _, _, _, _) = makeCoordinator(keyStore: store)

        await coordinator.restore()
        #expect(await coordinator.currentState == .attested(keyId: testKeyId))
    }
}

// MARK: - The cardinal rule: retry policy
//
// Module doc §6: "never regenerate a key on failure, except on invalidKey."
// This is the single most important behaviour in the module — get it wrong
// and a naive retry loop permanently locks users out by exhausting Apple's
// per-device key generation budget. Every test below asserts
// `generateKeyCallCount` explicitly, not just the end state, because a bug
// that regenerates unnecessarily would still reach `.attested` and look fine
// without that check.

@Suite("Retry policy")
struct RetryPolicyTests {

    @Test("A retryable attestKey failure retries the SAME keyId")
    func retryableFailureRetriesSameKey() async throws {
        let (coordinator, service, _, _, observer) = makeCoordinator(
            attestKeyResults: [
                .failure(AttestationError.retryable("serverUnavailable")),
                .failure(AttestationError.retryable("serverUnavailable")),
                .success(testAttestation)
            ]
        )

        let final = try await coordinator.ensureAttested(binding: identityBinding)

        #expect(final.isAttested)
        #expect(await service.generateKeyCallCount == 1)
        #expect(observer.failures.count == 2)
        #expect(observer.failures.allSatisfy { $0.error == .retryable("serverUnavailable") })
    }

    @Test("A generic network error on fetchChallenge is retried, not treated as terminal")
    func networkFailureOnChallengeRetries() async throws {
        let (coordinator, service, _, transport, observer) = makeCoordinator(
            fetchChallengeResults: [.failure(GenericNetworkError()), .success(testChallenge)]
        )

        let final = try await coordinator.ensureAttested(binding: identityBinding)

        #expect(final.isAttested)
        #expect(await service.generateKeyCallCount == 1)
        #expect(await transport.fetchChallengeCallCount == 2)
        #expect(observer.failures.first?.error == .networkUnavailable)
    }

    @Test("keyInvalid regenerates the key exactly once, and the count is persisted")
    func keyInvalidRegeneratesExactlyOnce() async throws {
        let store = InMemoryKeyStore()
        let (coordinator, service, _, _, _) = makeCoordinator(
            generateKeyResults: [.success("key-1"), .success("key-2")],
            attestKeyResults: [.failure(AttestationError.keyInvalid), .success(testAttestation)],
            keyStore: store
        )

        let final = try await coordinator.ensureAttested(binding: identityBinding)

        #expect(final == .attested(keyId: "key-2"))
        #expect(await service.generateKeyCallCount == 2)
        #expect(await service.issuedKeyIds == ["key-1", "key-2"])
        #expect(try store.loadRegenerationCount() == 1)
    }

    @Test("The regeneration cap is enforced and reported as .exhausted")
    func regenerationCapIsEnforced() async throws {
        let store = InMemoryKeyStore()
        let (coordinator, service, _, _, observer) = makeCoordinator(
            // Every single attestKey call fails with keyInvalid — a
            // pathological case a real device should never hit, but exactly
            // what the cap exists to survive.
            attestKeyResults: Array(repeating: .failure(AttestationError.keyInvalid), count: 10),
            keyStore: store
        )

        do {
            _ = try await coordinator.ensureAttested(binding: identityBinding)
            Issue.record("expected .exhausted to be thrown")
        } catch let error as AttestationError {
            #expect(error == .exhausted)
        }

        // Default policy caps regenerations at 3 (Policy.maxKeyRegenerations):
        // the original key + 3 regenerations = 4 generateKey calls, and the
        // 4th failure is the one that trips the cap rather than trying again.
        #expect(await service.generateKeyCallCount == 4)
        #expect(try store.loadRegenerationCount() == 3)
        #expect(observer.failures.last?.error == .exhausted)
    }

    @Test("isSupported == false is terminal — no key is ever generated")
    func unsupportedDeviceIsTerminal() async throws {
        let (coordinator, service, _, _, observer) = makeCoordinator(isSupported: false)

        let final = try await coordinator.ensureAttested(binding: identityBinding)

        #expect(final == .unsupported(.unsupported))
        #expect(await service.generateKeyCallCount == 0)
        #expect(observer.failures.first?.error == .unsupported)
    }
}

// MARK: - Concurrency
//
// Module doc §4: the coordinator is an actor specifically to deduplicate
// overlapping `ensureAttested()` calls (launch, foreground, connectivity
// change can all fire it at once). Without dedup, two concurrent calls would
// each call generateKey(), burning two key generations for one flow.

@Suite("Concurrent ensureAttested() calls")
struct ConcurrencyTests {

    @Test("Two overlapping calls collapse into a single key generation")
    func concurrentCallsDedupToOneKeyGeneration() async throws {
        let (coordinator, service, _, transport, _) = makeCoordinator()

        async let first = coordinator.ensureAttested(binding: identityBinding)
        async let second = coordinator.ensureAttested(binding: identityBinding)
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult == secondResult)
        #expect(await service.generateKeyCallCount == 1)
        #expect(await transport.submittedRequests.count == 1)
    }
}

// MARK: - Assertion signing (the hot path)
//
// Deliberately thin per module doc §3/workflow doc Part 2: no retries, no
// observer calls, no state machine — just "are we attested, and if so, sign."

@Suite("sign()")
struct SigningTests {

    @Test("Throws .notAttested before registration completes")
    func signBeforeAttestationThrows() async throws {
        let (coordinator, _, _, _, _) = makeCoordinator()

        do {
            _ = try await coordinator.sign(Data([0xFF]))
            Issue.record("expected .notAttested to be thrown")
        } catch let error as AttestationError {
            #expect(error == .notAttested)
        }
    }

    @Test("Signs once attested")
    func signAfterAttestationSucceeds() async throws {
        let (coordinator, service, _, _, _) = makeCoordinator()
        _ = try await coordinator.ensureAttested(binding: identityBinding)

        let assertion = try await coordinator.sign(Data([0xFF]))

        #expect(assertion == testAssertion)
        #expect(await service.generateAssertionCallCount == 1)
    }
}

// MARK: - Key invalidation acknowledged after the fact
//
// sign() deliberately never self-heals (it's the thin hot path — no I/O, no
// state machine). That means a `.keyInvalid` it surfaces is the ONE way the
// app can discover invalidation outside an active ensureAttested() call, and
// without a way to act on it, ensureAttested()'s own persisted-flag check
// (which exists specifically to avoid re-attesting a key that's still fine)
// would keep trusting the stale record forever. acknowledgeKeyInvalidation()
// closes that gap — these tests are what justify it existing at all.

@Suite("acknowledgeKeyInvalidation()")
struct KeyInvalidationAcknowledgementTests {

    @Test("Resets state so the next ensureAttested() call re-attests with a new key")
    func resetsAndAllowsReattestation() async throws {
        let (coordinator, service, store, _, _) = makeCoordinator(
            generateKeyResults: [.success("key-1"), .success("key-2")]
        )
        _ = try await coordinator.ensureAttested(binding: identityBinding)
        #expect(await coordinator.currentState == .attested(keyId: "key-1"))

        // Simulates: the app called sign(), got .keyInvalid back, and is
        // telling the coordinator about it.
        let recovered = await coordinator.acknowledgeKeyInvalidation()

        #expect(recovered)
        #expect(await coordinator.currentState == .none)
        #expect(try store.loadIsAttested() == false)
        #expect(try store.loadKeyId() == nil)

        let final = try await coordinator.ensureAttested(binding: identityBinding)
        #expect(final == .attested(keyId: "key-2"))
        #expect(await service.generateKeyCallCount == 2)
    }

    @Test("Shares the regeneration budget with the retry loop's own keyInvalid handling")
    func sharesRegenerationBudgetWithRetryLoop() async throws {
        let store = InMemoryKeyStore()
        // The first attestKey() call fails mid-flow, spending 1 of 3 via the
        // retry loop's own handling; the rest succeed.
        let (coordinator, _, _, _, _) = makeCoordinator(
            generateKeyResults: [.success("key-1"), .success("key-2")],
            attestKeyResults: [.failure(AttestationError.keyInvalid), .success(testAttestation)],
            keyStore: store
        )
        _ = try await coordinator.ensureAttested(binding: identityBinding)
        #expect(try store.loadRegenerationCount() == 1)

        // If these two paths tracked separate budgets, this would incorrectly
        // allow 3 MORE regenerations on top of the 1 already spent, instead
        // of sharing one capped pool of 3 total.
        #expect(await coordinator.acknowledgeKeyInvalidation())
        #expect(try store.loadRegenerationCount() == 2)
        #expect(await coordinator.acknowledgeKeyInvalidation())
        #expect(try store.loadRegenerationCount() == 3)
        #expect(await coordinator.acknowledgeKeyInvalidation() == false)
        #expect(try store.loadRegenerationCount() == 3)
    }
}
