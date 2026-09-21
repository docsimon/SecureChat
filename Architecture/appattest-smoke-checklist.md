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

6. **The real end-to-end `.keyInvalid` test.** This is the one mocks can
   never cover, and the one that validates the current decision
   (`appattestkit-module-design.md` §8: v1 always wipes the identity key
   together with module state) against actual device behaviour, not just
   reasoning about it. It also exercises `acknowledgeKeyInvalidation()`
   (module doc §7) — a gap discovered *by running this exact test* before
   that method existed, when Sign correctly failed but nothing could recover
   from it short of a manual Reset:
   - Complete steps 1–2 successfully, note the identity's public key prefix.
   - **Delete the app from the device via iOS itself** (not the in-app
     buttons) — this is what actually invalidates the App Attest key,
     confirmed against Apple's own documentation this session.
   - Reinstall from Xcode.
   - Launch. Restore runs automatically. Expected: reports `attested` with
     the **old** `keyId` and the **old** identity prefix — both the identity
     key's Keychain item and `LiveKeyStore`'s state survive a plain app
     deletion; nothing has actually been cleared yet at this point.
   - Tap Sign. Expected: fails — confirmed on real hardware this reads as
     `serverRejected` (Apple's actual `DCError.invalidInput`, not
     `.invalidKey` as originally assumed — see the note on
     `AttestationError.from`), not a crash or a silent success. The harness's
     `sign()` handler treats `.keyInvalid` and `.serverRejected("invalidInput")`
     as equivalent here, and — per the v1 policy — now deletes the identity
     key **and** calls `acknowledgeKeyInvalidation()` together. Confirm the
     log shows both, `identityGenerated`/`attested` both flip back to `false`,
     and step 1 (Generate Identity Key) re-enables itself.
   - Tap Generate Identity Key. Confirm the logged prefix differs from the
     one noted at the start — a genuinely new identity, not the old one.
   - Tap Attest. Expected: a full fresh registration completes, tied to the
     new identity — confirm `generateKey` fires exactly once more (check the
     "real attempts" counter incremented by exactly 1).

7. **Manual reset paths, tested in isolation.** The harness's two Danger
   Zone buttons no longer map onto two different *real* recovery paths (v1
   only has one — step 6, above) — they're diagnostic tools for exercising
   each underlying primitive on its own:
   - **"Reset module state"** alone: confirm it clears App Attest state but
     *keeps* the identity key (`identityGenerated` stays `true`) — this is
     useful for testing `AttestationCoordinator`'s own retry-from-`.none`
     behaviour in isolation, independent of the identity policy question.
   - **"Delete identity key"** alone (i.e. without a prior Sign failure):
     confirm it clears both identity and module state together, same as the
     automatic path in step 6, just triggered manually.

## Budget discipline

Steps 2 and 6 are the only ones that spend real `generateKey()` calls, and
only step 6 forces more than one (the reinstall plus the subsequent
re-attestation). Running the full checklist end to end costs roughly 2–3 real
key generations per pass. The harness's "real attempts" counter is a local
heuristic — Apple exposes no remaining-budget API — so treat it as a running
total to sanity-check against, not an authoritative limit.
