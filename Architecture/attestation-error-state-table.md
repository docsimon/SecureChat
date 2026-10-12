# Attestation — error → state table

The spec the `AppAttestTestApp` harness checks against: for every failure at
every step of registration, which error `ensureAttested()` reports, which
state the module is left in, and what the next `ensureAttested()` call does.

For where Registration stands overall — what is verified, what blocks closing
it, what was deferred — see `registration-status.md`.

Derived from `AttestationCoordinator.swift` as of 2026-10-07. Rows marked
**mock-tested** are asserted in `AppAttestKitTests`; rows marked
**device-confirmed** were observed on a real device against the local Auth
Server during the 2026-10-06/07 harness pass. The timeout and the challenge
reuse on retry (row 7a) were added after that pass and device-confirmed on
2026-10-07; reset past a hung Apple call (row 20) is mock-tested only, as
are the rules added the same day for storage failures, the one-replacement
limit, `invalidInput` on `attestKey` and `featureUnsupported` (rows 0, 1a, 3,
8, 8a, 9, 10, 16).

How to read "Provoke": *Step control* is the harness section of that name
(`ControllableTransport.swift`). Set it before tapping **Register**.

## Rules that hold for every row

- One `ensureAttested()` call makes at most `maxAttempts` (5) attempts in
  total, whatever mix of errors it meets, then throws `.exhausted`. Backoff
  between attempts is at most 2, 4, 8, 16 s, each randomised between half
  and the full value; none after the last.
- A key is discarded on exactly two errors: `.keyInvalid` and
  `.challengeExpired`. Nothing else ever causes a `generateKey()`.
- One call replaces a dead key **at most once**. If the replacement fails the
  same way, it is discarded too and the error is thrown (row 8a).
- A failure of the module's own storage is `.storageFailed`: not retried
  within the call, nothing discarded, reported to the observer.
- State is rebuilt from disk whenever in-memory state is `.none`, so a
  relaunch, a fresh coordinator, or a skipped `restore()` all resume the same way.
- Saved state that cannot be **read** is `.storageFailed` — from `restore()`
  and from `ensureAttested()` alike — never "nothing saved". Apple and the
  server are not contacted and nothing is discarded (row 0). A cached
  attestation that reads but does not parse is treated as absent.
- The observer sees each state once, not once per retry.
- Every `DCAppAttestService` call has a 30 s deadline. Apple's calls have
  none of their own.
- Within one call, a key is always attested against the **same** challenge:
  it is fetched once and reused on every `attestKey` retry (Apple's guidance —
  same key, same client data hash). A new key, or a new call, fetches a new one.

## Registration

| # | Where it fails | Error reported | State afterwards | Next `ensureAttested()` | Provoke |
|---|---|---|---|---|---|
| 0 | Saved state cannot be read (device locked at launch) | `.storageFailed`, thrown at once, also from `restore()` | unchanged in memory; everything stays on disk | Reads again; resumes normally once readable | Not injectable. **mock-tested** |
| 1 | `isSupported == false` | none thrown; returns `.unsupported` | `.unsupported` | Checks again, same result | Simulator. **mock-tested** |
| 1a | A call returns `DCError.featureUnsupported` although `isSupported` was true | none thrown; returns `.unsupported` | `.unsupported` in memory; the key, if any, stays on disk | Tries again from the persisted state | Not injectable. **mock-tested** |
| 2 | `generateKey()` fails | `.retryable`, retried; then `.exhausted` | `.none` | Starts from scratch | Not injectable |
| 3 | Reading or persisting `keyId` fails | `.storageFailed`, thrown at once | `.none`; a key just generated is orphaned | Generates another key | Not injectable |
| 4 | `/challenge` unreachable | `.networkUnavailable`, retried; then `.exhausted` | `.keyGenerated` | Reuses the same key, fetches a challenge | Step control: /challenge → *Fail: no connection*; or airplane mode. **mock-tested**, **device-confirmed** |
| 5 | `/challenge` returns 5xx | `.retryable`, retried; then `.exhausted` | `.keyGenerated` | Same as 4 | Step control: /challenge → *Fail: HTTP 500* |
| 6 | `/challenge` returns 4xx | `.serverRejected`, thrown at once | `.keyGenerated` | Same as 4 | Step control: /challenge → *Fail: HTTP 400*. **device-confirmed** |
| 7 | `attestKey` fails with an error (`serverUnavailable`, `unknownSystemFailure`) | `.retryable`, retried with the **same key and the same challenge**; then `.exhausted` | `.keyGenerated` | Reuses the same key, fetches a new challenge | Not reliably provokable — going offline produces row 7a instead. **mock-tested** |
| 7a | `attestKey` never returns (observed when started with no connectivity: no error after 10 min, and none when the network came back) | `.retryable("timedOut")` after 30 s, retried like row 7; then `.exhausted` (about 3 min in total if every attempt hangs) | `.keyGenerated`; the abandoned call does **not** consume the key | Reuses the same key — **device-confirmed** that it then attests normally | Step control: /challenge → *Pause after the response*; airplane mode **and Wi-Fi off**; Continue. **mock-tested**, **device-confirmed**: five timeouts, `exhausted`, then back online the same key attested with no new key generated |
| 8 | `attestKey` → `DCError.invalidKey` | `.keyInvalid`; key discarded, a new one generated in the same call, no backoff | `.none`, then onward with the new key | — | Not injectable. **mock-tested** |
| 8a | The replacement key from row 8 or 14 fails with `.keyInvalid` or `.challengeExpired` too | that error, thrown at once; the second key is discarded as well | `.none` | Starts from scratch (one new key) | Not injectable. **mock-tested** |
| 9 | `attestKey` → `DCError.invalidInput` | With a 32-byte hash: treated as row 8 (the keyId is the only other input). Otherwise `.serverRejected("invalidInput")`, thrown at once | as row 8; otherwise `.keyGenerated` | as row 8; otherwise tries the same key again — an app bug in `binding` | Not injectable. **mock-tested** |
| 10 | Persisting the attestation fails | `.storageFailed` to the observer only; the call **continues** from memory and submits | `.attestationPending` in memory, `.keyGenerated` on disk | If the process dies before the server confirms: re-attests a one-shot key, surfacing as row 8 | Not injectable. **mock-tested** |
| 11 | `/register` unreachable | `.networkUnavailable`, retried; then `.exhausted` | `.attestationPending` | Resubmits the cached attestation only — no `/challenge`, no Apple | Step control: /register → *Fail: no connection*; or *Pause before sending* and cut the network. **mock-tested** |
| 12 | `/register` returns 5xx | `.retryable`, retried; then `.exhausted` | `.attestationPending` | Same as 11 | Step control: /register → *Fail: HTTP 500*; or stop Postgres. **mock-tested**, **device-confirmed** (injected) |
| 13 | `/register` succeeded, response lost | `.networkUnavailable`, retried | `.attestationPending` until a retry gets through | Resubmits; server returns the **same** account (idempotent on `keyId`) | Step control: /register → *Send, then lose the response*. **device-confirmed**: five requests, one account row, same UUID on the retry |
| 14 | `/register`: challenge expired, unknown or already consumed | `.challengeExpired`; key discarded, new key, whole flow re-run in the same call | `.none`, then onward with the new key | — | Step control: /register → *Fail: challenge expired*; or wait out the 15 min TTL while paused. **mock-tested**, **device-confirmed** against the real server |
| 15 | `/register` returns any other 4xx (`identity_mismatch`, `attestation_invalid:…`) | `.serverRejected`, thrown at once | `.attestationPending`, cache kept | Against the real server: the rejected attempt already consumed the single-use challenge, so the resubmit gets row 14 and **recovers with a new key**. Only a rejection issued *before* the challenge is consumed repeats | Step control: /register → *Fail: HTTP 400* (repeats — injected, nothing reaches the server). **mock-tested**, **device-confirmed** both ways |
| 16 | Recording "server confirmed" fails | `.storageFailed`, thrown at once | `.attestationPending`, cache kept | Resubmits; same account comes back | Not injectable. **mock-tested** |
| 17 | Process killed before `attestKey` returns | — | `.keyGenerated` on relaunch | Reuses the key | Pause before /challenge, force-quit. **mock-tested**, **device-confirmed** |
| 18 | Process killed after `attestKey`, before the server confirms | — | `.attestationPending` on relaunch | Resubmits only | Pause before /register, force-quit. **mock-tested**, **device-confirmed** |
| 19 | Process killed after the server confirmed, before the client saw it | — | `.attestationPending` on relaunch | Resubmits; same account | Pause after /register, force-quit |
| 20 | `acknowledgeKeyInvalidation()` called mid-flow — including while the flow is stuck inside an Apple call | `CancellationError` to the `ensureAttested()` caller | `.none` | Starts from scratch | Danger zone → Reset module state while paused or retrying. **mock-tested**; **device-confirmed** for a paused flow |

## Assertion (`sign()`)

No retries and no state change inside the module — the app decides.

| # | Failure | Error | What the app does |
|---|---|---|---|
| 21 | Not registered yet | `.notAttested` | Run registration first. **mock-tested** |
| 22 | `DCError.invalidKey` | `.keyInvalid` | Wipe identity key + `acknowledgeKeyInvalidation()`, register again as a new account |
| 23 | `DCError.invalidInput` (confirmed on device for a key orphaned by reinstall) | `.serverRejected("invalidInput")` | Same as 22 |
| 24 | Any other Apple error, or no answer within 30 s (`.retryable("timedOut")`) | `.retryable` | Try again later; state untouched. **mock-tested** |
| 25 | `/session` rejects (`unknown_account`, `assertion_invalid`, `nonce_invalid_or_expired`) | `.serverRejected` from the app's own session client | Not decided — see below |

## What the app does with each outcome of `ensureAttested()`

The module keeps no memory between calls beyond its state, so how often to
call is the app's rule. In SecureChat as of 2026-10-12 registration starts
only from the user's tap (`RegistrationViewModel`), so there is no automatic
trigger at all and the rule below holds by construction. It becomes a rule to
enforce the day launch, foreground or connectivity triggers are added:

| Outcome | App |
|---|---|
| returns `.attested` | Proceed |
| returns `.unsupported` | Terminal for this device |
| `.exhausted`, `.storageFailed` | Call again on the next trigger (launch, foreground, connectivity). Resumes where it stopped; costs no key |
| `.serverRejected` (rows 6, 15), `.keyInvalid` / `.challengeExpired` (row 8a) | Do **not** call again from an automatic trigger. Retry on the next cold launch or an explicit user action. Against the real server each further pair of calls costs a key (row 15) |
| `CancellationError` | The app's own reset; nothing to do |

## Open — not addressed by a specific state yet

- **Row 15 / 8a.** The rule in the table above is a proposal. It bounds the
  cost of a server that rejects everything to one key per launch or user
  action, but nothing in the module enforces it.
- **Row 25.** Proposed, not implemented: `nonce_invalid_or_expired` — fetch a
  new nonce and retry once; `unknown_account` — same as row 22;
  `assertion_invalid` — retry once with a new nonce, then same as row 22.
- **Server receipt age.** The verification library rejects an attestation
  whose embedded receipt is older than a limit (5 min by default), as
  `attestation_invalid:InvalidReceipt`. Raised on 2026-10-07 to the challenge
  TTL + 1 min (`AppAttestVerification.kt`) so the challenge is the only clock;
  device-confirmed that a 7-minute-old attestation now registers.
- **A timed-out Apple call keeps running.** Its late result is dropped. If
  Apple attested the key in that abandoned call, the retry is expected to
  surface as row 8 (one extra key). Device-confirmed on 2026-10-07 that five
  abandoned offline calls did not consume the key. A call abandoned while
  *online* (Apple slow rather than unreachable) is still unobserved.
- **Row 9.** Whether Apple really answers `attestKey` with `invalidInput` for
  an orphaned key (as it does for `generateAssertion`, row 23) is unverified;
  the app's first-launch purge removes such keys before the module sees them.

## Priorities — what costs Apple attestations

Ranked by how often it can happen across all devices times what it costs.
Apple limits App Attest by rate across the whole app, not per device, so the
danger is many devices calling `attestKey` at once or repeatedly — not one
device having a bad day. Ordinary failures (no network, server 5xx, app
killed, `attestKey` hanging offline) already cost nothing: rows 4, 5, 7a,
11–13, 17–19, all device-confirmed.

1. **The server rejects attestations it should accept** (a server bug or bad
   deploy — this already happened once here, with the receipt age limit).
   Every device that is **registering while the bug is live** then gets row
   15: a new key and a new Apple attestation on every second call, for as
   long as `ensureAttested()` keeps being triggered. Devices already
   registered never call `attestKey` again and are not affected.
   **Not enforced by the module** — see the proposal above. A cool-down
   inside the coordinator was considered on 2026-10-12 and judged not worth
   it at the current scale: the exposure is limited to devices mid-registration,
   and the rule fits in the one place the app triggers registration.
2. **Apple is slow or rate-limiting** (`serverUnavailable`, row 7). One call
   makes up to 5 `attestKey` requests; every further trigger makes 5 more,
   with no pause between calls. Backoff *within* a call is randomised since
   2026-10-12 so devices do not retry in step. **No cool-down between calls
   yet.**
3. **An attestation outlives its challenge** (row 14): the network drops
   between `attestKey` and `/register` and stays down past the 15 min TTL.
   Costs one extra key and attestation. Inherent to the design — an
   attestation is bound to its challenge — and the window is seconds wide.
   Accepted.
4. **Reinstall.** One new key and one new account per reinstall, by the v1
   policy. Accepted.

Security checks made on 2026-10-12, no change needed: the Auth Server refuses
to start without `APPATTEST_ENVIRONMENT`, so a production deployment cannot
silently accept development attestations (`Config.kt`); `docker-compose.yml`
defaults it to `development` for local use only.

## Known and accepted — not being fixed

- **Row 3 — a freshly generated key is orphaned because its `keyId` could not
  be written.** The write happens immediately after `generateKey()`, to the
  Keychain with `WhenUnlockedThisDeviceOnly`. It fails only if the device is
  locked at that instant (a first registration running in the background, or
  the user locking the phone between the two calls — and iOS keeps protected
  data available briefly after locking), or if the Keychain itself is failing
  (sporadic `-34018`, full disk, corruption). Cost: one wasted key on a rare
  occasion. If a key already exists and the device is locked, nothing is lost:
  the read fails first and no key is generated. A fix exists (hold the
  `keyId` in memory and reuse it within the process) and was declined on
  2026-10-12 as not worth a second place for the key to live.
- **`binding` throwing.** The app's own error passes through unchanged and
  does not reach the observer.
