# Real Auth Server — end-to-end device smoke checklist

Complements `appattest-smoke-checklist.md`, doesn't replace it. That file
explicitly scoped itself to `LocalFakeTransport` — "these checks validate
the client's integration with real `DCAppAttestService`, not server-side
verification correctness (that's separate, later work)." This is that later
work, now that `AuthServer/` exists. Where a scenario is already covered
well there (kill-and-relaunch restore, normal-launch-never-re-purges), this
file cross-references it instead of duplicating it.

Last updated 2026-10-06.

---

## Setup

- Real device, same Wi-Fi network as the Mac. `AppAttestTestApp` on the
  development App Attest environment — doesn't touch the production budget.
- `docker compose up -d` in `AuthServer/`, and keep `docker compose logs -f
  auth-server` open in a terminal throughout — most of what distinguishes
  "expected" from "actually broken" below is only visible there.
- Know your Mac's current LAN IP (`ipconfig getifaddr en0`) and confirm it
  matches `AuthServerConfig.baseURL`. DHCP reassigns this; a stale IP here
  produces the same symptom as a real network failure, so rule it out first.
- Useful mid-test inspection, from `AuthServer/`:
  `docker compose exec postgres psql -U authserver -d authserver` and
  `docker compose exec redis redis-cli` (see "Running the Auth Server"
  doc for query examples).

## Fixed since this checklist was first written

`RealAttestationTransport.performRequest` originally mapped **any** non-2xx
HTTP response — a 400 *and* a 500 alike — to `AttestationError.serverRejected`
(terminal, never retried). Found while writing this checklist, fixed the same
session: 5xx (our own server having a transient problem, e.g. a Postgres
hiccup) now maps to `AttestationError.retryable` instead, so it gets retried
with backoff like a network failure rather than given up on immediately.
Verified server-side (a real `500` while Postgres was stopped, recovered
cleanly once restarted) — B6/B7 below now test the client's retry behavior
against this fix on a real device, not just document the gap.

Two more fixed during real-device testing of B3:

- **Duplicate "App Attest key generated" log entries.** `attemptRegistration()`
  re-enters on every retry and re-transitions to the same `.keyGenerated(keyId)`
  even though no new `generateKey()` runs. The harness's `realAttemptCount`
  already guarded against over-counting this, but the log line didn't. Now
  deduplicated per distinct `keyId` within one attempt (`HarnessFlowModel.recordTransition`).
- **keyId in the log.** The `keyGenerated` log entry now carries the real keyId in
  its detail field, so sameness across retries/steps is checkable by eye. This is
  a deliberate exception to the harness's usual "never log keyId" rule — safe
  only because History is in-memory and never persisted, synced, or crash-reported
  (same reasoning as the raw CBOR hex already logged there). Don't extend it.

## Test-harness change: step control instead of a split flow

The harness has one flow button, **Register (ensureAttested)**, which calls
the same `ensureAttested()` the real app will ship. An earlier revision split
it into "Attest (Apple)" / "Register (Auth Server)" using a DEBUG-only
`attestOnly()` in the module — removed, because it tested a code path (single
attempt, no retry loop) that production never runs.

Control over individual steps now comes from **Step control**
(`ControllableTransport.swift`), which wraps the app-owned transport:

- Per endpoint (`GET /challenge`, `POST /register`): pass through, pause
  before sending, pause after the response, or fail with a chosen error.
- While paused, an orange **Paused … — Continue** row appears. Force-quit,
  cut the network or stop Docker before tapping it.
- Settings are sticky until changed and reset to pass-through on relaunch.
  *Fail: challenge expired* is the exception: it fires once, so the
  regenerated key is not expired again.
- "Reset module state" and "Delete identity key" now call the module's
  production `acknowledgeKeyInvalidation()` (there is no `debugReset()` any
  more) and work while a flow is paused or retrying — that is how to abort one.
- The banner shows the coordinator's real state, live.

The expected outcome of every case is in `attestation-error-state-table.md`;
the row numbers below refer to it. Wherever the tables in this file say
"Attest", read "Register".

Apple-side failures cannot be injected. To make `attestKey` fail for real:
/challenge → *Pause after the response*, enable airplane mode, Continue.

---

## Suite 1 — First install through registration

Assumes a device already past the purge gate (clean, or already purged) —
see Suite 2 for reinstall-specific scenarios. Re-run "Delete identity key"
from Danger Zone between test cases here to get a clean slate without a
full reinstall (spends no extra real key generation by itself — see
`appattest-smoke-checklist.md` §8 for what that button does and doesn't do).

### A. Happy path

1. Generate Identity → Attest → Sign, all succeeding. Confirm in
   `docker compose logs`: `GET /challenge` → `POST /register`, both 200.
   Confirm the account row in Postgres (`account_uuid`, `counter = 0`).
2. Repeat Sign a few times. Confirm `GET /session/nonce` → `POST /session`,
   both 200, and `counter` in Postgres increments each time.

### B. Network conditions

| # | Provoke | Expected | Watch for |
|---|---|---|---|
| B1 | Airplane mode ON, then tap Attest | `GET /challenge` never reaches the server (nothing in docker logs) → `.networkUnavailable`, retried with backoff, eventually `exhausted` if airplane mode stays on through all retries | The harness's `requestFailed` event shows `statusCode: nil` ("server never reached") — confirms this is a real connectivity failure, not a masked rejection |
| B2 | Airplane mode ON, wait ~10s, turn OFF mid-retry-backoff | Coordinator's retry loop picks up the recovered connection on its next scheduled attempt and succeeds | No manual retry needed — this is the resilience the backoff design exists for |
| B3 | Wi-Fi OFF but cellular ON (device has internet, but can't reach the Mac's LAN IP) | `fetchChallenge()` runs BEFORE `attestKey()` (`AttestationCoordinator.attemptRegistration`) and needs the LAN — so for a *fresh* flow this fails at `GET /challenge`, before Apple is ever contacted. Confirmed on a real device: exhausted after 5 attempts with no "CBOR attestation object received" log entry, meaning `attestKey()` never ran. | Check the history for `.attestationStepAttested` ("CBOR attestation object received") to tell these apart — present means `attestKey()` genuinely succeeded; absent means it failed earlier, at `/challenge`. This case doesn't actually exercise "Apple reachable, LAN not" the way it sounds — F1 is the one that does |
| B4 | `docker compose stop auth-server` before tapping Attest, restart it ~5s later | Same as B2's recovery pattern — `.networkUnavailable`, retried, succeeds once the container's back up | Confirm the request that finally succeeds shows in the *restarted* container's logs, not stale output from before the stop |
| B5 | **Superseded by section F below.** The original plan timed a Wi-Fi cut against the CBOR log line — a race a few hundred ms wide, not reliable by hand. Use Step control instead. | — | See F1–F4 |
| B6 | `docker compose stop postgres` (leave `auth-server` and `redis` running), then tap Attest | `auth-server` can't reach its DB → real `500` from `/register` → now classified `.retryable`, not terminal | Confirmed server-side already: a real `500 {"error":"internal_error"}` while Postgres is stopped. This case is about confirming the *client* retries it rather than giving up immediately. |
| B7 | Same as B6, but restart `postgres` while the app is mid-retry-backoff | Should recover automatically, matching B2/B4 — the retry succeeds once Postgres is healthy again | If this doesn't self-recover, that's a real regression against the fix made this session |

### C. Server-side rejections (the server responds, and says no)

These are harder to provoke deliberately without touching code — most are
now closed by the identity-mismatch fix and correct-by-construction client
behavior. Included so the *symptom* is documented if one ever resurfaces.

| Server error code | What it means | How you'd know |
|---|---|---|
| `identity_mismatch` | The `identityPublicKey` bound to the challenge at `/challenge` time doesn't match what `/register` submitted. Root-caused and fixed this session (a `+` in the base64 key getting corrupted via unescaped query-string encoding) — if this reappears, it's a regression, not expected. | `requestFailed` event shows `statusCode: 400`, detail contains `identity_mismatch` |
| `challenge_invalid_or_expired` | Challenge was never issued, already consumed, or outlived its 15-minute TTL. Hard to provoke normally (15 min is a long wait); can be simulated by manually deleting the Redis key (`DEL challenge:register:<value>`) between fetching it and submitting | Same as above, detail contains this code |
| `attestation_invalid:<ExceptionClassName>` | The attestation object itself failed verification (bad chain, wrong rpIdHash, non-zero counter, wrong environment). Should not happen from a genuine device in the correct App Attest environment — if it does, check `APPATTEST_ENVIRONMENT`/`APPATTEST_TEAM_ID`/`APPATTEST_BUNDLE_ID` in `AuthServer/.env` match the real entitlement | Server logs show the specific exception class server-side even though the client only sees the generic message |

### D. Key regeneration (no local cap)

`Policy.maxKeyRegenerations` and its `regenerationCount` bookkeeping were
removed — see `appattestkit-module-design.md` §8a. There is no device-lifetime
budget to track and no `exhausted`/debug-reset fallback to exercise anymore;
`acknowledgeKeyInvalidation()` now just regenerates, every time, with no cap.

| # | Provoke | Expected | Watch for |
|---|---|---|---|
| D1 | Force several genuine `.keyInvalid`/reinstall cycles in a row (see Suite 2) | Each cycle regenerates cleanly via `acknowledgeKeyInvalidation()` — no `exhausted`, no debug-reset fallback, no decisional branching on a call count anywhere in the path | Confirms the removal didn't leave any stray dependency on a counter that no longer exists |
| D2 | During D1, count how many *real* key generations actually happened vs. how many "App Attest Key Generated" log lines appeared | These should match — retry-loop reflections of the same `keyId` (e.g. from B1/B4's retries) must not inflate the count | Regression check for the over-counting bug fixed this session (`lastCountedKeyId` guard in `HarnessFlowModel`) — unrelated to the cap removal, still worth checking here |

### F. Interruption and resumption (Step control)

Setup for every case: clean module state (Delete identity key, then Generate
Identity Key), Wi-Fi on, `docker compose logs -f auth-server` open, and the
"real attempts" counter noted before starting.

What every case is checking, in order of importance:

1. **Exactly one real `generateKey()` and one real `attestKey()` across the
   whole case** unless the row says a new key is expected. Real attempts goes up by 1.
2. **The CBOR is reused, not re-minted.** On resume, the docker logs show
   `POST /register` only — no `GET /challenge` — and the history shows no second
   "CBOR attestation object received" entry.
3. **The banner state after each call matches the table row.**

| # | Step control | Then | Expected (table row) |
|---|---|---|---|
| F1 | /register → Pause before sending | Register → wait for the pause → Wi-Fi off → Continue | Retries with `networkUnavailable`, then `exhausted` after ~30 s. State `attestationPending`. Nothing in docker logs (row 11) |
| F1b | as F1 | Turn Wi-Fi back on during the backoff | The same call recovers and registers. Docker: `/register` 200, no `/challenge` (row 11) |
| F2 | /register → Pause before sending | Register → pause → `docker compose stop auth-server` → Continue | As F1; failure is `networkUnavailable`, not `serverRejected` (row 11) |
| F2b | as F2 | `docker compose start auth-server`, during backoff or then tap Register again | Registers. `/register` only (row 11) |
| F3 | /register → Fail: HTTP 500 | Register; mid-backoff set /register → Pass through | Retries, then succeeds on the next attempt (row 12) |
| F4 | /register → Pause before sending | Register → pause → **force-quit** → relaunch → Register | History: "found existing state on launch: attestationPending". Register submits the cached CBOR; no new key, no new CBOR (row 18) |
| F5 | /challenge → Pause before sending | Register → pause → force-quit → relaunch → Register | Relaunch shows "found existing state on launch: keyGenerated" — real attempts unchanged by the relaunch, +1 for the whole case (row 17) |
| F6 | /register → Pause after the response | Register → pause → force-quit → relaunch → Register | Postgres has the account already; client relaunches as `attestationPending`; resubmit returns the **same** `account_uuid`, still one row (row 19) |
| F7 | /register → Send, then lose the response | Register; mid-backoff set /register → Pass through | Same account UUID on the retry, one row in Postgres (row 13) |
| F8 | /register → Fail: challenge expired (fires once, then resets itself to Pass through) | Register | Old key discarded, **new** key and CBOR, registers. Real attempts +2 (row 14). Real-server variant: pause before /register, `DEL` the challenge key in Redis, Continue |
| F9 | /register → Fail: HTTP 400 (rejected) | Register, then Register again | Each tap: one rejection, no retry, state stays `attestationPending`, no new key (row 15). Clear with Reset module state |
| F10 | /challenge → Pause after the response | Register → pause → airplane mode → Continue; later airplane mode off | `attestKey` fails for real → `retryable`, same key; recovers when the network is back (row 7) |
| F11 | /register → Pause before sending | Register → pause → Danger zone → Reset module state | "ensureAttested() cancelled by a reset", state `none`, nothing sent to `/register`, no new key generated behind your back (row 20) |
| F12 | all Pass through | Register, then Sign Assertion | Happy path: `POST /session` 200 |

### E. Concurrency

| # | Provoke | Expected | Watch for |
|---|---|---|---|
| E1 | Rapidly tap Attest multiple times before the first call returns | In-flight task deduplication (module doc) collapses these into one attempt | Only one `GET /challenge` in the server logs per genuine attempt, not one per tap |
| E2 | Background the app mid-attest (before `/register` completes), then foreground it | Should behave like a slower version of B5 — no double-attestation on return | Confirm via docker logs that only one `/register` attempt happened, not a duplicate |

---

## Suite 2 — Delete / reinstall scenarios

Keychain survives app deletion; the sandbox container (including the
cached-attestation file) does not. Every scenario here is really about that
asymmetry. Cross-reference `appattest-smoke-checklist.md` §4 and §7 for the
non-reinstall cases (kill-and-relaunch restore, and the critical "normal
launches must never re-purge" regression check) — not repeated here.

| # | Prior state before delete | Provoke | Expected purge-gate behavior | Watch for |
|---|---|---|---|---|
| R1 | Never generated anything (truly clean) | Delete + reinstall | `hasIdentity=false, hadModuleState=false` → logs "first launch — Keychain already clean, nothing to purge", no session closed | No spurious purge session appears when there's genuinely nothing to purge |
| R2 | Generated identity key only, never attested | Delete + reinstall | `hadIdentity=true, hadModuleState=false` → identity deleted, **`acknowledgeKeyInvalidation()` never called** (module state was already `.none`) | Confirms the module-state branch is correctly skipped when there's nothing there — no needless regeneration for a case that never touched the module at all |
| R3 | Full successful registration (`isAttested=true`) | Delete + reinstall | `restore()` finds `isAttested=true` → `.attested(keyId:)` (not `.keyGenerated` — no spurious "key generated" log) → purge clears it | Next Attest after this should register as a **new** account — confirm a *second*, different `account_uuid` row appears in Postgres, not a reuse of the old one (matches the "no re-attestation" design decision) |
| R4 | Attested with Apple, but `/register` never confirmed (killed mid-flow, or a genuine server rejection) | Delete + reinstall | Cached attestation *file* is gone (sandbox wiped) but `keyId` survives (Keychain) → `restore()` falls through to `.keyGenerated` (a real "orphaned key" reflection, not a new generation) → purge clears it | This is the exact scenario walked through live this session — confirms it's reliably reproducible and reliably recovered, not a one-off |
| R5 | Repeat R4 (orphaned-key reflection) five or more times back-to-back, as fast as reinstalling allows | Delete + reinstall each time | Each cycle regenerates cleanly — no local cap, no `exhausted`, no debug-reset fallback (that mechanism no longer exists, see `appattestkit-module-design.md` §8a) | Watch for Apple's *own* side effects now that nothing local throttles this: a rate-limit `DCError`, or a visibly slower `attestKey()` round-trip — either would be the Secure Enclave's own defense surfacing, not a bug in this code |
| R6 | Any attested/pending state | Delete + reinstall **while `docker compose` is stopped entirely** | Purge gate should complete normally — `restore()` and `acknowledgeKeyInvalidation()` are both purely local, no network involved | Confirms purge success doesn't depend on server availability; only a *subsequent* Attest attempt should be affected by the server being down |
| R7 | Repeat R3 or R4 three or more times back-to-back | Delete + reinstall each time | Each cycle's purge succeeds independently, every cycle regenerates with no cap | Regression check that the purge gate itself doesn't double-fire or skip across multiple real cycles — see R5 for what to actually watch for under heavy repetition |

---

## After a pass

Worth a final check regardless of which cases were run: `SELECT
count(*) FROM accounts;` in Postgres should equal the number of times a
*genuinely new* registration succeeded (R3/R4's "new account" cases,
Suite 1's happy path) — not the number of test cycles overall, since most
Suite 2 scenarios are specifically about *not* re-registering when nothing
should have changed.
