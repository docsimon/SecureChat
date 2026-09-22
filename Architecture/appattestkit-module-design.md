# AppAttestKit — module design

Companion to `architecture-decisions.md`. Covers the extraction of registration logic into a reusable, testable module.

Status: design agreed. §8's blocker is resolved — no re-attestation, and identity survival is reversed for v1 (always wipe). Last updated 2026-09-21.

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

Keys stop working: Keychain cleared, device restored from backup, `DCError.invalidKey`. Two distinct discovery paths, handled differently — this distinction was missed in the first draft and only surfaced during real-device testing (see `appattest-smoke-checklist.md`):

- **Discovered mid-attestation** — `attestKey` itself throws `.keyInvalid` during an active `ensureAttested()` call. Handled entirely inside the retry loop: discard the `keyId`, generate a fresh one, re-attest, bounded by the regeneration cap (§6).
- **Discovered later, independently, via `sign()`** — the credential died after the app already believed it was attested (a reinstall is the common real-world cause). `sign()` deliberately never self-heals (§3: "keep this path thin — no state machine"), and `ensureAttested()`'s own persisted-flag check (it exists specifically so a healthy key isn't needlessly re-attested on every launch) would otherwise keep trusting the stale record forever. The app must explicitly call **`acknowledgeKeyInvalidation()`** on seeing `.keyInvalid` from `sign()` — this clears the persisted record and transitions to `.none`, drawing from the **same** regeneration cap as the mid-attestation path (one shared pool, not two, or the cap would be trivially bypassable).

Per §8's resolution below: re-attesting here always means a fresh `/register` producing a **new account** — never a rebind of the old one via a special re-attestation endpoint.

---

## 8. Resolved — no server-side re-attestation

**Decision: `.keyInvalid` always means a new account. No re-attestation path exists or is planned.** Full trade-off analysis in `account-keys-reference.md`; logged in `architecture-decisions.md` §12.

`/register` stays exactly as specced — idempotent on `keyId`, nothing more. There is no `/reattest` endpoint. The deciding constraint: the server discards `identityPublicKey` immediately after the nonce-binding check (workflow doc step 10) and never persists it — this is deliberate (architecture doc §10: it's the most graph-linkable value the server could hold). Any scheme that rebinds a new `keyId` to an existing account requires the server to retain `identityPublicKey` (or a derivative of it) indefinitely as a lookup index, which reverses that decision. Preserving it was judged more valuable than preserving an account across a rare App-Attest-only key failure.

**Client behaviour on `.keyInvalid`:** the regenerate-and-reattest path already implemented in `AttestationCoordinator` (§6/§7) needs no code change — discard `keyId`, generate a new one, reattest. What it produces is a **new account**, not a recovered one. The app layer must:
- run a completely fresh `/register`, minting a new `account_uuid`
- **also discard and regenerate the X25519 identity keypair** (revised — see below; an earlier version of this section kept it)
- surface to the user that every contact needs to be re-paired — there is no server-mediated way for a contact to learn the new `account_uuid`, since the product has no discovery/directory (architecture doc §1)

**Revised decision (v1 ships this way): wipe the identity key too, always, together with the module's own state.** The original reasoning for keeping it stands on its own merits — architecture doc §10's "pairings are the durable identifier, not the UUID" is still true, and a contact re-pairing with the same fingerprint really is a nicer experience than being treated as a stranger. But realizing that benefit requires app-layer work that doesn't exist yet (matching an incoming pairing's `identityPublicKey` against existing contacts and merging rather than duplicating — nothing in the current pairing spec does this), and shipping it doubles the invalidation state space into two paths to build, test, and keep correct (this is exactly where this session's real bugs lived — see the change log below). Given the goal of shipping v1 quickly, the cost wasn't worth the benefit yet. Concretely, the app now always pairs identity deletion with `acknowledgeKeyInvalidation()`/`debugReset()` — never one without the other.

This is a clean decision to reverse later — nothing here creates migration debt:
- The server is unaffected either way; it never persists `identityPublicKey` regardless of which policy the client runs.
- No contact-record schema changes; "match by `identityPublicKey`, update instead of insert" is a pure addition to the pairing-completion path whenever it's built.
- Existing users aren't harmed by a future switch — it only changes behavior for reinstalls that happen *after* the app updates to the new policy.

**Also newly true under this decision:** the "same identity key correlatable across two `/register` calls" privacy cost noted in the previous version of this section no longer applies at all — wiping the identity key removes that correlation surface entirely, for free.

**How the wipe is actually triggered: proactively at launch, not just reactively.** An earlier version of this decision only wiped reactively — inside `sign()`'s failure handler, the moment the app actually tried to use a dead credential. That has a real UX cost: right after a reinstall, the UI (or the real app's internal state) keeps showing "attested" until something happens to fail, which is exactly the kind of stale-looking state this whole section exists to avoid. The app now also detects the reinstall proactively, at launch, using the standard pattern already noted in architecture doc §8's failure-paths table: a `UserDefaults` flag, which is wiped along with the rest of the sandbox container on delete (unlike Keychain), so its absence means either a genuine first-ever install or a reinstall. On first detecting this, before showing any state, the app purges whatever Keychain state survived from a previous install.

⚠️ **This is the one piece of this decision where a bug is not just wrong but catastrophic.** If the "is this the first launch" check is ever inverted or otherwise wrong such that it fires on an *ordinary* launch instead of only the first one after install, it repeatedly spends the device's real, finite App Attest key-generation budget — exhausting it in days. Two things guard this specifically:
- The purge is conditional on something actually being there (`IdentityKeyStore.exists()` / `coordinator.currentState != .none`) — a genuine first-ever install must not be charged for a purge it didn't need.
- The `UserDefaults` flag is set *after* the purge completes, not before, so a crash mid-purge retries (idempotent, safe) on the next launch rather than silently marking itself done and leaking a stale credential forever.

The reactive `acknowledgeKeyInvalidation()` call from `sign()` remains in place as a safety net for invalidation that happens *without* a reinstall (e.g. a device restore, or Keychain cleared independently) — the launch-time check only catches the reinstall case.

**Open for v2 — manual contact merge, not automatic recognition.** Since the identity key changes on every reinstall now, there is no way for a contact's app to *automatically* recognize a returning identity — the cryptographic thread is gone by construction, not just unbuilt. A v2 feature could let the *user* manually declare "this new contact is the same person as this existing one" and merge the records (preserving nickname/history, retiring the orphaned old entry). This is fundamentally a socially-verified action, not a cryptographically-verified one — the app can never prove the claim, only let the user assert it. Tracked as an open question in `architecture-decisions.md` §11.

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

**Structural constraint:** App Attest entitlements belong to the **app target, not a package.** The package's own test suite can never exercise the real `DCAppAttestService`. Requires a host-app test target for integration (`AppAttestTestApp`), plus a manual on-device smoke checklist — see `appattest-smoke-checklist.md`.

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
| Server contract breaks on re-attestation | Resolved — re-attestation rejected, `.keyInvalid` mints a new account instead (§8) |
| No persistence seam — state machine untestable | Added `AttestationKeyStore` (§3) |
| Testing payoff overstated | Scoped honestly in §9 |
| Silent failures invisible in field | Added `AttestationObserver` (§3) |
| Layering vs. "don't over-abstract" tension | Each seam justified by a test; stated in §1 and §11 |
