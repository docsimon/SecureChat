# Real Auth Server — end-to-end device smoke checklist

Complements `appattest-smoke-checklist.md`, doesn't replace it. That file
explicitly scoped itself to `LocalFakeTransport` — "these checks validate
the client's integration with real `DCAppAttestService`, not server-side
verification correctness (that's separate, later work)." This is that later
work, now that `AuthServer/` exists. Where a scenario is already covered
well there (kill-and-relaunch restore, normal-launch-never-re-purges), this
file cross-references it instead of duplicating it.

Last updated 2026-09-29.

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
| B3 | Wi-Fi OFF but cellular ON (device has internet, but can't reach the Mac's LAN IP) | `attestKey()` may succeed (real internet to Apple), but `GET /challenge` or `POST /register` fails — these need the LAN, not general internet | This is a *different* failure point than B1 — confirms attestation-to-Apple and registration-to-your-server are genuinely independent network paths, not the same connectivity check |
| B4 | `docker compose stop auth-server` before tapping Attest, restart it ~5s later | Same as B2's recovery pattern — `.networkUnavailable`, retried, succeeds once the container's back up | Confirm the request that finally succeeds shows in the *restarted* container's logs, not stale output from before the stop |
| B5 | Kill Wi-Fi on the phone **immediately after** the CBOR attestation log entry appears (i.e., right after Apple responds, before `/register` completes) | Module persists `.attestationPending` to disk *before* attempting `/register` (module doc §7a) — force-quit the app now, restore Wi-Fi, relaunch | State should restore as `.attestationPending` and resume straight to `POST /register` on the next attempt — **no re-attestation with Apple**, since the key is one-shot. This is the single most important resumability case in this whole checklist. |
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

### D. Regeneration budget / key invalidation

| # | Provoke | Expected | Watch for |
|---|---|---|---|
| D1 | Force several genuine `.keyInvalid`/reinstall cycles in a row (see Suite 2) until `regenerationCount` hits 3 | `acknowledgeKeyInvalidation()` returns false, harness logs "regeneration budget exhausted" *visibly*, then (DEBUG only) auto-resets and retries | The failure must be a real, visible log entry — not silently reported as success (the bug fixed this session) |
| D2 | During D1, count how many *real* key generations actually happened vs. how many "App Attest Key Generated" log lines appeared | These should now match — retry-loop reflections of the same `keyId` (e.g. from B1/B4's retries) must not inflate the count | Regression check for the over-counting bug fixed this session (`lastCountedKeyId` guard in `HarnessFlowModel`) |

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
| R2 | Generated identity key only, never attested | Delete + reinstall | `hadIdentity=true, hadModuleState=false` → identity deleted, **`acknowledgeKeyInvalidation()` never called** (module state was already `.none`) | Confirms the module-state branch is correctly skipped when there's nothing there — no wasted regeneration-budget spend for a case that never touched the module at all |
| R3 | Full successful registration (`isAttested=true`) | Delete + reinstall | `restore()` finds `isAttested=true` → `.attested(keyId:)` (not `.keyGenerated` — no spurious "key generated" log) → purge clears it | Next Attest after this should register as a **new** account — confirm a *second*, different `account_uuid` row appears in Postgres, not a reuse of the old one (matches the "no re-attestation" design decision) |
| R4 | Attested with Apple, but `/register` never confirmed (killed mid-flow, or a genuine server rejection) | Delete + reinstall | Cached attestation *file* is gone (sandbox wiped) but `keyId` survives (Keychain) → `restore()` falls through to `.keyGenerated` (a real "orphaned key" reflection, not a new generation) → purge clears it | This is the exact scenario walked through live this session — confirms it's reliably reproducible and reliably recovered, not a one-off |
| R5 | Any state that leaves `regenerationCount` at 2 | Delete + reinstall (pushing a 3rd `acknowledgeKeyInvalidation()` call) | Hits `exhausted` for real this time — should trigger the debug-reset fallback automatically, with the visible warning log from D1 | Confirms the fallback works from a genuinely-earned exhaustion, not just the contrived path used to first discover the bug |
| R6 | Any attested/pending state | Delete + reinstall **while `docker compose` is stopped entirely** | Purge gate should complete normally — `restore()` and `acknowledgeKeyInvalidation()` are both purely local, no network involved | Confirms purge success doesn't depend on server availability; only a *subsequent* Attest attempt should be affected by the server being down |
| R7 | Repeat R3 or R4 three or more times back-to-back | Delete + reinstall each time | Each cycle's purge succeeds independently, `regenerationCount` climbs by exactly 1 each time until it caps at 3 | Regression check that nothing double-counts or under-counts the budget across multiple real cycles |

---

## After a pass

Worth a final check regardless of which cases were run: `SELECT
count(*) FROM accounts;` in Postgres should equal the number of times a
*genuinely new* registration succeeded (R3/R4's "new account" cases,
Suite 1's happy path) — not the number of test cycles overall, since most
Suite 2 scenarios are specifically about *not* re-registering when nothing
should have changed.
