# App Attest — manual on-device smoke checklist

`appattestkit-module-design.md` §9 calls for this: mock tests verify
orchestration, but nothing about whether Apple's API is actually being used
correctly. That's only checkable on a real device, using the
`AppAttestTestApp` harness. This is a checklist, not automation — run it by
hand after any change to `AttestationCoordinator`, `LiveAttestService`, or
`LiveKeyStore`.

Last updated 2026-09-21.

---

## Setup

- Real device only. `isSupported` is `false` on the Simulator by design —
  that's the one thing worth confirming there, nothing else.
- `AppAttestTestApp`'s entitlements are fixed to the **development** App
  Attest environment, so none of this touches the production per-device key
  budget (see `account-keys-reference.md` and the WebSearch findings folded
  into that session — development-environment attestations are tagged with
  `aaguid: appattestsandbox` and don't count against the production cap).
- Transport is `LocalFakeTransport` — no real server involved. These checks
  validate the client's integration with real `DCAppAttestService`, not
  server-side verification correctness (that's separate, later work).

## Checklist

1. **Support check.** The guided-sequence UI has no standalone Support
   button anymore — this check is folded into Attest's own outcome. On the
   Simulator specifically, tap Attest and confirm it ends in `.unsupported`,
   not a crash.

2. **Fresh attestation.** On a clean install, restore runs automatically on
   launch (`.task` on the root view) — confirm state shows `none`, then tap
   Attest. Confirm the log shows the full sequence — `.keyGenerated` →
   `.attestationPending` → `.attested` — and the final state is `.attested`.
   This is the only step that spends a real key generation.

3. **Assertion.** Tap Sign. Confirm it succeeds and reports a byte count.
   Repeat a few times — unlike attestation, this is cheap and should always
   succeed once attested.

4. **Kill-and-relaunch resumption.** Force-quit the app (not the in-app
   Reset), relaunch. Restore runs automatically — confirm state shows
   `attested`, the *same* state as before the kill, then tap Sign and confirm
   it succeeds (contrast with step 6: a plain kill doesn't touch the Secure
   Enclave credential, only an actual reinstall does). No new key generation,
   no re-attestation attempt. This is module doc §5's core guarantee: state
   reconstructible from persisted data alone. Note: session *history* is
   in-memory only and does not survive the kill — the fresh session this
   produces should show as "Attested (restored)," not "In progress."

5. **Module-state reset.** Tap "Reset module state." Confirm state returns to
   `.none` and a subsequent Attest performs a full fresh flow again
   (deliberately, since this spends another key generation — don't do this
   in a loop).

6. **The real end-to-end `.keyInvalid` test — proactive launch-time purge.**
   This is the one mocks can never cover, and the one that validates the
   current decision (`appattestkit-module-design.md` §8: v1 wipes the
   identity key together with module state, detected **proactively at
   launch**, not just reactively on a failed `sign()`) against actual device
   behaviour:
   - Complete steps 1–2 successfully, note the identity's public key prefix.
   - **Delete the app from the device via iOS itself** (not the in-app
     buttons) — this is what actually invalidates the App Attest key,
     confirmed against Apple's own documentation this session.
   - Reinstall from Xcode.
   - Launch. Expected (this changed from earlier in the session): the
     `FirstLaunchPurgeGate` fires **before any state is shown** — the log's
     first entry should read "first launch after install/reinstall — purged
     stale Keychain state," **not** "found existing state on launch:
     attested." The UI should show a genuinely clean slate immediately:
     Generate Identity Key enabled, everything else reset. You should
     *not* need to tap Sign to see anything clear itself this time — that
     reactive path (`acknowledgeKeyInvalidation()` from `sign()`'s failure
     handler) is now a secondary safety net for invalidation that happens
     *without* a reinstall, not the primary way this gets discovered.
   - Tap Generate Identity Key. Confirm the logged prefix differs from the
     one noted at the start.
   - Tap Attest. Confirm a full fresh registration completes — "real
     attempts" counter incremented by exactly 1.

7. **CRITICAL — repeated normal launches must never re-purge.** This is the
   single most important check in this document. If the first-launch gate
   is ever wrong in this direction — firing on an *ordinary* launch instead
   of only the first one after install — it repeatedly spends the device's
   real, finite key-generation budget until exhausted, in days, silently.
   Immediately after step 6 (so the flag is now set and the state is
   genuinely `attested`):
   - Force-quit and relaunch **3 or more times in a row**, without
     reinstalling in between.
   - After **every** relaunch, confirm: the log shows the ordinary "found
     existing state on launch: attested" restore path, **never** another
     "first launch... purged" entry; `identityGenerated`/`attested` both
     correctly read `true`; and — the actual bottom line — the **"real
     attempts" counter does not move**, on any of these relaunches.
   - This has automated coverage too, not just this manual check:
     `FirstLaunchPurgeGateTests` (`AppAttestTestAppTests.swift`) simulates
     10 consecutive launches in isolation and asserts the purge fires
     exactly once. Run it with
     `xcodebuild test -scheme AppAttestTestApp -only-testing:AppAttestTestAppTests`
     as a fast, repeatable check of the gating logic alongside this
     real-device one — the unit test proves the gate's own logic is sound;
     this manual step proves the real Keychain/`UserDefaults` integration
     actually behaves that way on a device. Use `-only-testing:` here
     deliberately: running the full scheme's test plan also pulls in the
     (unrelated, un-asserted) default UI test target, whose simulator/runner
     cold start can add well over a minute the first time.
   - Also confirm the "real attempts" counter itself survives the reinstall
     in step 6 — it's Keychain-backed specifically so it doesn't silently
     reset to near-zero every time this checklist's own reinstall steps run.

8. **Manual reset paths, tested in isolation.** The harness's two Danger
   Zone buttons don't correspond to distinct *real* recovery paths (v1 only
   has one — steps 6/7, above, triggered automatically) — they're
   diagnostic tools for exercising each underlying primitive on its own:
   - **"Reset module state"** alone: confirm it clears App Attest state but
     *keeps* the identity key (`identityGenerated` stays `true`) — useful
     for testing `AttestationCoordinator`'s own retry-from-`.none` behaviour
     in isolation, independent of the identity policy question.
   - **"Delete identity key"** alone (i.e. without a prior reinstall or Sign
     failure): confirm it clears both identity and module state together,
     same outcome as the automatic path, just triggered manually.

## Budget discipline

Steps 2 and 6 are the only ones that spend real `generateKey()` calls, and
only step 6 forces more than one (the reinstall plus the subsequent
re-attestation). Running the full checklist end to end costs roughly 2–3 real
key generations per pass. Step 7 is deliberately designed to cost **zero** —
that's the entire point of it, and if it ever doesn't, that's the bug. The
harness's "real attempts" counter is a local heuristic — Apple exposes no
remaining-budget API — so treat it as a running total to sanity-check
against, not an authoritative limit.
