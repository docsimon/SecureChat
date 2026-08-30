# AppAttestKit — module design

Companion to `architecture-decisions.md`. Covers the extraction of registration logic into a reusable, testable module.

Status: design agreed, not yet implemented. One blocker before starting (see §8). Last updated 2026-08-26.

---

## 1. Why extract it

**The justification is testability, not reuse.**

"Reuse in a future app" is a weak reason to modularise — designing for a consumer that doesn't exist produces abstractions shaped around imagined needs. The strong reason: the App Attest failure paths (§8 of the architecture doc) are painful to reproduce on device and impossible to exercise in CI unless the attestation logic sits behind a protocol boundary. That pays off in week one, on this app.

The design that delivers testability happens to be the same one that's portable later, so there's no trade-off to make.

**Every seam in this design must be justified by a test that needs it.** If a protocol is added that no test requires, that is the signal it has crossed into speculation.

---

## 2. Layering

The reuse boundary is narrower than "registration". Registration means *your* server's endpoints, *your* account model, *your* identity keys — none of that is portable. What's portable is **attestation**.

```
AppAttestKit          ← zero app knowledge. Reusable verbatim.
   ↑
RegistrationFeature   ← server contract, identity keys, view model. App-specific.
   ↑
App target            ← SwiftUI views, copy, branding. Never reusable.
```

`AppAttestKit` owns the App Attest key lifecycle, retry semantics, error taxonomy, and assertion signing. It knows nothing about challenges-from-your-server, identity keypairs, or account UUIDs.

**Dependency constraint:** imports `DeviceCheck`, `CryptoKit`, `Foundation`. Nothing else. This constraint is what keeps the boundary honest.

**No separate UI module.** UI carries copy, branding, navigation style, and design system — none of which survive a move to another app. A UI package would end up full of injected configuration and be harder to work with than writing two screens. What *is* portable is the flow's **view model** (the state machine driving which screen shows and what each tap does) — that lives in `RegistrationFeature` as an `@Observable`, with the SwiftUI views in the app target. App two rewrites ~200 lines of view code and reuses everything beneath.

---

## 3. Seams

Four protocols, each required by a test.

### AttestServicing

`DCAppAttestService` is a concrete class that cannot be subclassed or stubbed, and returns errors only on real hardware with the entitlement. This is the primary seam.

```swift
public protocol AttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}
```

Two implementations: live (wraps `DCAppAttestService`) and mock (configurable to fail in specific ways).

### AttestationKeyStore

Required because the module owns the "retry with the same keyId" rule, which means it owns keyId persistence. Keychain is as untestable as `DCAppAttestService`.

```swift
public protocol AttestationKeyStore: Sendable {
    func loadKeyId() throws -> String?
    func store(keyId: String) throws
    func clear() throws
}
```

Live wraps Keychain; tests use in-memory. **Without this seam the state machine cannot be tested at all**, which would undercut the entire justification for the module.

### AttestationTransport

The module never knows a URL. The app implements this against its own endpoints.

```swift
public protocol AttestationTransport: Sendable {
    func fetchChallenge() async throws -> Data
    func submitAttestation(_ request: AttestationRequest) async throws -> AttestationResult
}
```

### AttestationObserver

The failure paths are silent by nature. A module that swallows them into thrown errors makes field debugging harder, not easier.

```swift
public protocol AttestationObserver: Sendable {
    func didTransition(to state: AttestationState)
    func didFail(_ error: AttestationError, attempt: Int)
}
```

**Logging caution:** `keyId` is a persistent device identifier. Per §10 of the architecture doc, it must not reach a crash reporter.

---

## 4. Concurrency — actor with in-flight deduplication

**This is a correctness requirement, not a style choice.**

`ensureAttested()` is triggered from multiple places that can overlap: app launch, foreground, connectivity change. Two concurrent calls means two calls to `generateKey()`, two orphaned keys, and a device-level key generation limit burned for nothing.

`Sendable` does **not** solve this — it is a data-race annotation, not mutual exclusion. The coordinator must be an actor that deduplicates in-flight work:

```swift
public actor AttestationCoordinator {
    private var inFlight: Task<AttestationState, Error>?

    public func ensureAttested() async throws -> AttestationState {
        if let existing = inFlight { return try await existing.value }
        let task = Task { try await performAttestation() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
```

---

## 5. State machine

Must be reconstructible from persisted data alone, because the flow can crash between "key generated" and "attestation submitted".

```swift
public enum AttestationState: Sendable {
    case none
    case keyGenerated(keyId: String)      // persisted BEFORE attesting
    case attested(keyId: String)
    case unsupported(AttestationError)
}
```

Single entry point: `func ensureAttested() async throws -> AttestationState`. Inspects persisted state, resumes from wherever it left off. Idempotent, safe to call on every launch. Pairs with the server-side `/register` idempotency in §6 of the architecture doc.

---

## 6. Error handling

### The rule

> **Never regenerate a key on failure, except on `invalidKey`. Retry the same `keyId` with backoff.**

This is the single most important behaviour in the module. A naive retry loop calling `generateKey()` on each failure hits the per-device generation limit and **permanently locks the user out.**

### Why the taxonomy is deliberately coarse

An earlier draft proposed four discriminated cases including `transient(retryAfter:)` and `keyRateLimited`. Both were wrong:

- **`retryAfter` cannot be populated.** Apple provides no such value. Backoff is your own policy, not something the error carries.
- **`keyRateLimited` may not be distinguishable.** `DCError` surfaces a small set of codes — `invalidKey`, `invalidInput`, `serverUnavailable`, `featureUnsupported`, `unknownSystemFailure`. Rate limiting plausibly arrives as `serverUnavailable` or `unknownSystemFailure`, indistinguishable from a genuinely transient failure.

A four-way discrimination invited exactly the mistake it was meant to prevent. The coarse rule above is correct regardless of which code you receive.

### ⚠️ Verify before encoding

**The `DCError` code list above is from stale knowledge (mid-2025) and must be checked against current Apple documentation before being encoded.** This is the one place where being wrong strands users permanently.

### Suggested shape

```swift
public enum AttestationError: Error {
    case unsupported              // simulator, jailbroken → terminal, degrade
    case keyInvalid               // → discard keyId, regenerate, re-attest
    case retryable(underlying: Error)   // → same keyId, exponential backoff
    case networkUnavailable       // → defer, retry on connectivity change
    case serverRejected(reason: String) // → terminal, log
}
```

---

## 7. Key invalidation

Not covered in the first draft. Keys stop working: Keychain cleared, device restored from backup, `DCError.invalidKey`.

Client behaviour: discard the `keyId`, generate a fresh one, re-attest.

**This breaks the current server contract** — see §8.

---

## 8. ⚠️ BLOCKER — re-attestation server contract

**Resolve before writing the module.** It changes the interface the module talks to.

`/register` is currently idempotent **keyed on `keyId`** (architecture doc §6). A user whose key was invalidated returns with a **new keyId and the same identity public key**. Under the current contract that either creates a duplicate account or is rejected outright.

The server needs a defined re-attestation path: accept a new `keyId` bound to an existing identity key, **provided the client proves possession of that identity key by signing the challenge with it.**

Open sub-questions:
- Does the identity key persist across the events that invalidate an App Attest key? (Both live in Keychain, so probably yes — but a device restore may behave differently and needs verifying.)
- If the identity key is *also* lost, the user is a new user and must re-pair. Is that acceptable, and how is it surfaced?
- Rate limit re-attestation separately, since it is otherwise an account-takeover surface.

---

## 9. Testing — realistic scope

The mock tests verify **orchestration**, and nothing about whether Apple's API is being used correctly. That is still worth having — orchestration is where the user-stranding bugs live — but it is a narrower claim than "the §8 failure paths become unit tests."

**Testable with mocks:**
- State machine transitions and resumption after simulated crash
- Retry policy — that `generateKey()` is *not* called on retryable failures
- Concurrent `ensureAttested()` calls producing exactly one key generation
- Network failure → deferred state, retry on reconnect
- `isSupported == false` → correct terminal state

**Not testable with mocks:**
- Keychain surviving app deletion (filesystem behaviour)
- Real jailbroken-device behaviour
- Actual attestation acceptance (needs entitlement + hardware + live server)

**Structural constraint:** App Attest entitlements belong to the **app target, not a package.** The package's own test suite can never exercise the real `DCAppAttestService`. Requires a host-app test target for integration, plus a manual on-device smoke checklist.

---

## 10. Repository layout

Local package in the same repo — **not** a separate repository.

```
YourApp/
  YourApp.xcodeproj
  Packages/
    AppAttestKit/
      Package.swift
      Sources/AppAttestKit/
      Tests/AppAttestKitTests/
```

Referenced via `.package(path: "Packages/AppAttestKit")`. Gives the enforced boundary — the package literally cannot import the app — without versioning ceremony, cross-repo PRs, or a release process. Promote to its own repo only when a second app genuinely needs it; that is a mechanical `git subtree split`.

---

## 11. Things to resist

- **No configuration options for hypothetical needs.**
- **No generalisation beyond App Attest.** Do not build an `AttestationProvider` protocol anticipating Play Integrity. One platform, one use case. Generalise when a second case appears and shows where the real variation is.
- **No protocol without a test that needs it.**

---

## 12. Change log from first draft

Recorded so the reasoning is not re-derived.

| Issue | Resolution |
|---|---|
| Concurrent `ensureAttested()` race | Actor + in-flight task dedup (§4) |
| `transient(retryAfter:)` unpopulatable | Removed; backoff is local policy (§6) |
| `keyRateLimited` possibly indistinguishable | Collapsed to coarse rule; verify codes first (§6) |
| Key invalidation unhandled | Added §7; surfaced server contract gap |
| Server contract breaks on re-attestation | **Blocker, §8** |
| No persistence seam — state machine untestable | Added `AttestationKeyStore` (§3) |
| Testing payoff overstated | Scoped honestly in §9 |
| Silent failures invisible in field | Added `AttestationObserver` (§3) |
| Layering vs. "don't over-abstract" tension | Each seam justified by a test; stated in §1 and §11 |
