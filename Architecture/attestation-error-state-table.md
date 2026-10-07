# Attestation — error → state table

The spec the `AppAttestTestApp` harness checks against: for every failure at
every step of registration, which error `ensureAttested()` reports, which
state the module is left in, and what the next `ensureAttested()` call does.

Derived from `AttestationCoordinator.swift` as of 2026-10-06. Rows marked
**mock-tested** are asserted in `AppAttestKitTests`. Nothing here has been
confirmed on a device since the 2026-10-06 changes — that is what the harness
pass is for.

How to read "Provoke": *Step control* is the harness section of that name
(`ControllableTransport.swift`). Set it before tapping **Register**.

## Rules that hold for every row

- One `ensureAttested()` call makes at most `maxAttempts` (5) attempts in
  total, whatever mix of errors it meets, then throws `.exhausted`. Backoff
  between attempts is 2, 4, 8, 16 s; none after the last.
- A key is discarded on exactly two errors: `.keyInvalid` and
  `.challengeExpired`. Nothing else ever causes a `generateKey()`.
- State is rebuilt from disk whenever in-memory state is `.none`, so a
  relaunch, a fresh coordinator, or a skipped `restore()` all resume the same way.
- The observer sees each state once, not once per retry.

## Registration

| # | Where it fails | Error reported | State afterwards | Next `ensureAttested()` | Provoke |
|---|---|---|---|---|---|
| 1 | `isSupported == false` | none thrown; returns `.unsupported` | `.unsupported` | Checks again, same result | Simulator. **mock-tested** |
| 2 | `generateKey()` fails | `.retryable`, retried; then `.exhausted` | `.none` | Starts from scratch | Not injectable |
| 3 | Persisting `keyId` fails | raw Keychain error (not an `AttestationError`) | `.none`; the key just generated is orphaned | Generates another key | Not injectable |
| 4 | `/challenge` unreachable | `.networkUnavailable`, retried; then `.exhausted` | `.keyGenerated` | Reuses the same key, fetches a challenge | Step control: /challenge → *Fail: no connection*; or airplane mode. **mock-tested** |
| 5 | `/challenge` returns 5xx | `.retryable`, retried; then `.exhausted` | `.keyGenerated` | Same as 4 | Step control: /challenge → *Fail: HTTP 500* |
| 6 | `/challenge` returns 4xx | `.serverRejected`, thrown at once | `.keyGenerated` | Same as 4 | Step control: /challenge → *Fail: HTTP 400* |
| 7 | `attestKey` transient failure (Apple unreachable, `serverUnavailable`, `unknownSystemFailure`) | `.retryable`, retried with the **same key** and a **new challenge** each time; then `.exhausted` | `.keyGenerated` | Reuses the same key | Step control: /challenge → *Pause after the response*; enable airplane mode; Continue. **mock-tested** |
| 8 | `attestKey` → `DCError.invalidKey` | `.keyInvalid`; key discarded, a new one generated in the same call, no backoff | `.none`, then onward with the new key | — | Not injectable. **mock-tested** |
| 9 | `attestKey` → `DCError.invalidInput` | `.serverRejected("invalidInput")`, thrown at once | `.keyGenerated` | Tries the same key again | Not injectable |
| 10 | Persisting the attestation fails | raw file error | `.keyGenerated`; the attestation is lost | Re-attests a one-shot key; expected to surface as row 8 | Not injectable |
| 11 | `/register` unreachable | `.networkUnavailable`, retried; then `.exhausted` | `.attestationPending` | Resubmits the cached attestation only — no `/challenge`, no Apple | Step control: /register → *Fail: no connection*; or *Pause before sending* and cut the network. **mock-tested** |
| 12 | `/register` returns 5xx | `.retryable`, retried; then `.exhausted` | `.attestationPending` | Same as 11 | Step control: /register → *Fail: HTTP 500*; or stop Postgres. **mock-tested** |
| 13 | `/register` succeeded, response lost | `.networkUnavailable`, retried | `.attestationPending` until a retry gets through | Resubmits; server returns the **same** account (idempotent on `keyId`) | Step control: /register → *Send, then lose the response* |
| 14 | `/register`: challenge expired or unknown | `.challengeExpired`; key discarded, new key, whole flow re-run in the same call | `.none`, then onward with the new key | — | Step control: /register → *Fail: challenge expired*; or wait out the 15 min TTL / `DEL` the Redis key while paused. **mock-tested** |
| 15 | `/register` returns any other 4xx (`identity_mismatch`, `attestation_invalid:…`) | `.serverRejected`, thrown at once | `.attestationPending`, cache kept | Resubmits once, gets the same answer | Step control: /register → *Fail: HTTP 400*. **mock-tested** |
| 16 | Recording "server confirmed" fails | raw Keychain error | `.attestationPending`, cache kept | Resubmits; same account comes back | Not injectable. **mock-tested** |
| 17 | Process killed before `attestKey` returns | — | `.keyGenerated` on relaunch | Reuses the key | Pause before /challenge, force-quit. **mock-tested** |
| 18 | Process killed after `attestKey`, before the server confirms | — | `.attestationPending` on relaunch | Resubmits only | Pause before /register, force-quit. **mock-tested** |
| 19 | Process killed after the server confirmed, before the client saw it | — | `.attestationPending` on relaunch | Resubmits; same account | Pause after /register, force-quit |
| 20 | `acknowledgeKeyInvalidation()` called mid-flow | `CancellationError` to the `ensureAttested()` caller | `.none` | Starts from scratch | Danger zone → Reset module state while paused or retrying. **mock-tested** |

## Assertion (`sign()`)

No retries and no state change inside the module — the app decides.

| # | Failure | Error | What the app does |
|---|---|---|---|
| 21 | Not registered yet | `.notAttested` | Run registration first. **mock-tested** |
| 22 | `DCError.invalidKey` | `.keyInvalid` | Wipe identity key + `acknowledgeKeyInvalidation()`, register again as a new account |
| 23 | `DCError.invalidInput` (confirmed on device for a key orphaned by reinstall) | `.serverRejected("invalidInput")` | Same as 22 |
| 24 | Any other Apple error | `.retryable` | Try again later; state untouched |
| 25 | `/session` rejects (`unknown_account`, `assertion_invalid`, `nonce_invalid_or_expired`) | `.serverRejected` from the app's own session client | Not decided — see below |

## Open — not addressed by a specific state yet

- **Row 15.** A definitive server "no" leaves a pending attestation that will
  be rejected again on every call. The module deliberately does not discard
  the key by itself (a misconfigured server would otherwise burn a key per
  launch); the only way out is the app calling `acknowledgeKeyInvalidation()`.
  When the app should do that — immediately, after N rejections, never for
  `attestation_invalid` — is not decided.
- **Rows 3, 10, 16.** Storage failures escape as raw errors rather than an
  `AttestationError` case, and never reach the observer.
- **Row 8.** A second `.keyInvalid` on a brand-new key regenerates again, up
  to 5 keys in one call with no backoff.
- **Row 9.** If Apple answers `attestKey` with `invalidInput` for an orphaned
  key (as it does for `generateAssertion`, row 23), that key is retried
  forever. Only the app's first-launch purge prevents it today. Worth one
  device check.
- **`DCError.featureUnsupported` from a call** (as opposed to
  `isSupported == false`) throws `.unsupported` but leaves the state at
  `.keyGenerated`, not `.unsupported`.
- **Row 25.** Nothing maps a `/session` rejection to a recovery.
