# 08 — Registration Test Scenarios

Edge cases and unhappy paths for the registration and pairing flow. Most of these don't occur naturally in the mock environment — the OTP is always visible, the network never fails — so they have to be provoked deliberately.

Ordered by how likely each is to reach production unnoticed.

---

## 1 · Verify succeeded, response lost

**The most dangerous case in the flow.** The server verified the user and set `registeredAt`, but the response never arrived — dropped Wi-Fi, backgrounded mid-request, timeout.

**Provoke:** kill Wi-Fi immediately after tapping Verify. Or add a `sleep(10)` before the response in the verify handler and background the app.

**Expected:** retry with the same code returns **200** with `status: "verified"`, because the server treats already-verified as success. The client should land on the registered screen.

**Watch for:** a client that shows an error because the *first* attempt threw. The user is registered but the UI says otherwise, and they'll try to register again.

**Also test:** retry with a *different* (wrong) code after a successful-but-lost verify. Should still return 200 — the user is verified, the code is gone, and there's nothing left to check.

---

## 2 · Resend resets the attempt counter

Three wrong guesses burns the code (`429 too_many_attempts`). A resend issues a fresh code with `attemptsRemaining: 3`.

**Provoke:** three wrong codes, then resend.

**Expected:** UI shows 3 attempts again.

**Watch for:** a counter stuck at 0 because it's stored locally and never refreshed from the resend response. The user sees "no attempts remaining" while holding a perfectly good code.

**Related:** this is a real security gap, not just a UI bug. Unlimited resends means unlimited attempts. Noted in the API doc under "not built yet" — per-phone limits are the fix.

---

## 3 · Code expires while backgrounded

**Provoke:** register, background the app for longer than `OTP_TTL_MS` (5 min), return, submit the code.

**Expected:** **410** `code_expired`, and the UI offers resend.

**Watch for:**
- A countdown that kept running on a local timer and shows time remaining when the code is already dead.
- A countdown that froze at the value it had when backgrounded.

Drive it from `otpExpiresAt` recomputed against the current time on foreground, not from a `Timer` that assumes continuous execution.

---

## 4 · Null vs absent on the date fields

All three dates come back as JSON `null`, never omitted.

**Expected:** `Date?` properties decode cleanly to `nil`.

**Watch for:** non-optional properties, which throw `DecodingError.valueNotFound`. That's actually a useful early canary — it fails loudly rather than silently.

**The silent failure to check for is the date strategy.** With the default `.deferredToDate`, `1787569657146` decodes as seconds since 2001 and lands around the year 58,600. No error, no crash — just comparisons that quietly never behave. Confirm `.millisecondsSince1970` is set, and assert a decoded date is within a sane range in debug.

---

## 5 · Phone number already taken

**Provoke:** register and verify A with number X. Register B with a different number, then `PUT /users/B/phone` with X.

**Expected:** **409** `phone_taken`.

**Watch for:** this error has no obvious recovery. The user is stuck on a phone-entry screen with a number they believe is theirs — perhaps it *was* theirs, on an old device. Decide what to show: "this number is registered on another device" plus a support route, rather than a generic failure.

Note only **verified** users hold a claim. A pending registration doesn't block anyone.

---

## 6 · Phone re-registration takeover

**Provoke:** verify A with number X. Then `POST /register` with number X and a *different* `userID`.

**Expected (current):** succeeds. The record is taken over, `userID` is replaced, `registeredAt` clears.

This is deliberate — real apps allow reinstall and device change — but it means **anyone can take over any number** with no proof. Production needs a registration lock PIN plus a delay window and a notification to the existing device.

Test it now so the behaviour is understood, and keep it on the known-gaps list.

---

## 7 · Same number submitted again

**Provoke:** `PUT /users/:id/phone` with the number the user already has.

**Expected:** 200, a fresh code, `phoneSentDate` and `otpCodeSentDate` both move, `registeredAt` unchanged if already verified.

This is the "the SMS never arrived so I retyped it" path. It must not drop a verified user back to pending.

---

## 8 · Resend cooldown

**Provoke:** resend twice within 30 seconds.

**Expected:** **429** `resend_too_soon` with `retryAfterMs`.

**Watch for:** a hardcoded 30-second countdown instead of one driven by `retryAfterMs`. They diverge as soon as the request itself takes time, and a local timer drifts across backgrounding.

---

## 9 · Unknown user

**Provoke:** verify or resend with a `userID` that doesn't exist. Easiest via reset-the-server while the app holds stale state.

**Expected:** **404** `unknown_user`.

**Watch for:** the app sitting on an OTP screen for a user the server has never heard of. There must be a route back to the start — this is exactly what happens after you wipe `.pairing.json` during development, so you'll hit it often.

---

## 10 · State survives app termination

**Provoke:** register, force-quit the app, relaunch.

**Expected:** back on the OTP screen, same `userID`, countdown recomputed from `otpExpiresAt`.

**Watch for:** a relaunch that returns to the phone-entry screen. The user re-registers, burns a code, and — worse — may mistype a different number the second time.

---

## 11 · Invite gating on unverified users

**Provoke:** register A without verifying. Attempt `/lookup` for A's number, and attempt an invite from A.

**Expected:** `/lookup` → **404** `not_registered`. `/invite` → **403** `sender_not_verified` or `recipient_not_verified`.

A pending user is invisible system-wide. Confirm the client doesn't show them as an available contact.

---

## 12 · Double-tap and rapid retap

**Provoke:** tap Verify twice quickly. Tap Accept on an invite twice.

**Expected:** verify → second call returns 200 (already verified). Accept → **409** `already_accepted`, which the client should treat as success and fetch `/chats`.

**Watch for:** buttons that aren't disabled during the in-flight request, producing two OTP attempts from one user action — one of which counts against the limit.

---

## 13 · Malformed and hostile input

Quick sweep, mostly to confirm nothing crashes:

| Input | Expected |
|---|---|
| Empty phone | 400 `phone_required` |
| Phone with letters | Normalised to digits; may end up empty → 400 |
| Code with letters, or wrong length | 401 `invalid_code` |
| Empty request body | 400 or 404, never a 500 |
| Very long `displayName` | Accepted — check the UI truncates |

---

## Not covered by the mock

Flagged so they don't get mistaken for passing:

- **Wrong number entered, SMS goes to a stranger.** Unreproducible here since the code is always visible. The mitigation is UI: make the phone-change route reachable *from* the OTP screen.
- **SMS delayed by minutes.** Real carriers do this. The 5-minute TTL may be too short — worth revisiting once real delivery exists.
- **SIM swap.** See §6.
- **Enumeration.** No rate limiting on `/register` or `/lookup`, so the number space is walkable.

---

## Suggested order

1. §4 (date decoding) — a silent failure that corrupts everything downstream
2. §10 and §9 — you hit both constantly during development anyway
3. §1 — the one that leaves a registered user believing they aren't
4. §3, §2, §8 — the OTP screen's own state machine
5. §5, §6, §7 — phone-change paths
6. §11, §12, §13 — sweep
