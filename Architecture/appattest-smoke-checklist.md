# App Attest — manual on-device smoke checklist

`appattestkit-module-design.md` §9 calls for this: mock tests verify
orchestration, but nothing about whether Apple's API is actually being used
correctly. That's only checkable on a real device, using the
`AppAttestTestApp` harness. This is a checklist, not automation — run it by
hand after any change to `AttestationCoordinator`, `LiveAttestService`, or
`LiveKeyStore`.

Last updated 2026-09-20.

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

1. **Support check.** Launch on device, tap Support. Confirm the app doesn't
   crash and logs a sane message. (On Simulator: confirm Attest below
   produces `.unsupported`, not a crash.)

2. **Fresh attestation.** Tap Restore first (should report `.none`), then
   Attest. Confirm the log shows the full sequence — `.keyGenerated` →
   `.attestationPending` → `.attested` — and the final state is `.attested`.
   This is the only step that spends a real key generation.

3. **Assertion.** Tap Sign. Confirm it succeeds and reports a byte count.
   Repeat a few times — unlike attestation, this is cheap and should always
   succeed once attested.

4. **Kill-and-relaunch resumption.** Force-quit the app (not the in-app
   Reset), relaunch, tap Restore. Confirm it reports `.attested` with the
   *same* state as before the kill — no new key generation, no re-attestation
   attempt. This is module doc §5's core guarantee: state reconstructible
   from persisted data alone.

5. **Module-state reset.** Tap "Reset module state." Confirm state returns to
   `.none` and a subsequent Attest performs a full fresh flow again
   (deliberately, since this spends another key generation — don't do this
   in a loop).

6. **The real end-to-end `.keyInvalid` test.** This is the one mocks can
   never cover, and the one that validates the Option A decision
   (`appattestkit-module-design.md` §8) against actual device behaviour, not
   just reasoning about it:
   - Complete step 2 successfully.
   - **Delete the app from the device via iOS itself** (not the in-app
     buttons) — this is what actually invalidates the App Attest key,
     confirmed against Apple's own documentation this session.
   - Reinstall from Xcode.
   - Launch, tap Restore. Expected: reports `.attested` with the **old**
     `keyId` — the identity key's Keychain item and `LiveKeyStore`'s state
     both survive a plain app deletion.
   - Tap Sign. Expected: fails with a real `AttestationError.keyInvalid`
     (mapped from Apple's actual `DCError.invalidKey`), not a crash or a
     silent success.
   - Tap Attest. Expected: the coordinator regenerates a key and completes a
     fresh registration — confirm `service` generateKey fires exactly once
     more (check the "real attempts" counter incremented by exactly 1).

7. **Identity-loss fallback.** Tap "Delete identity key," then Attest.
   Confirm a fresh identity keypair is generated (different public key
   prefix logged) alongside the fresh registration — this is the fallback
   path module doc §8 describes for when the identity key is *also* lost,
   distinct from step 6's "identity survives" path.

## Budget discipline

Steps 2 and 6 are the only ones that spend real `generateKey()` calls, and
only step 6 forces more than one (the reinstall plus the subsequent
re-attestation). Running the full checklist end to end costs roughly 2–3 real
key generations per pass. The harness's "real attempts" counter is a local
heuristic — Apple exposes no remaining-budget API — so treat it as a running
total to sanity-check against, not an authoritative limit.
