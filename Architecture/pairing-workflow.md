# Pairing workflow — in-person QR, mutual scan

Rewritten 2026-10-12. The earlier design (BLE/NFC channel, Noise `XX`
handshake, SAS word comparison) is replaced; the reasons are in "Why the
earlier design was dropped" at the end. Companion to
`architecture-decisions.md` (§1 and §10) and `account-keys-reference.md`
(what the identity key is).

**v1 covers in-person pairing only**: two people, two phones, each scans the
other's screen. Pairing at a distance (sending a code or link through another
app) was discussed and deferred; see the closing notes.

**Ownership:** no server takes part at any step, and `AppAttestKit` is not
involved. The shared code is the `PairingKit` package (`Modules/PairingKit`),
compiled by both the real app and the `PairingTestApp` harness. Storing the
contact and the screens are app-owned.

---

## Overview

| # | Step | Owner | Code |
|---|---|---|---|
| 1 | Each phone shows its own code | App | `PairingPayload.encoded()`, `PairingQRCode.image(for:)` |
| 2 | Each phone scans the other's code | User, camera | `QRCodeScannerView` |
| 3 | The scanned code is checked | `PairingKit` | `Pairing.evaluate(...)` |
| 4 | The contact is stored | App | `PairedContact` |
| 5 | The first session confirms the pairing | App (not built) | Noise `KK` |

Steps 1–4 happen independently on each phone. There is no channel between
the two phones during pairing: the screen and the camera are the channel.

---

### Step 1 — Show the code

The code carries three things, none of them secret:

```
{ identityPublicKey, accountUUID, displayName }
```

- **`identityPublicKey`** — the X25519 identity key. This is the thing being
  verified: the other user's camera reads it straight off this screen.
- **`accountUUID`** — the routing address. There is no directory, so this is
  the only way a contact ever learns where to reach you.
- **`displayName`** — always present, at most 64 bytes of UTF-8. A label, not
  an identifier; the receiving side may rename the contact locally.

Wire form, version 1:

```
text   "SCPAIR:" + base64url(bytes), no padding
bytes  [version = 1][identityPublicKey 32][accountUUID 16][nameLength 1][name 1…64]
       [acknowledgement 8]   optional, see "Face to face" below
```

Without the acknowledgement the code is static: the same identity always
produces the same code (for the same name). It is about 160 characters.

### Step 2 — Scan

`QRCodeScannerView` is a bare camera preview that reports the text of any QR
code it sees. The app needs the camera permission
(`NSCameraUsageDescription`), the only permission pairing adds.

### Step 3 — Check the scanned code

`Pairing.evaluate` is a pure function of the scanned text, this device's own
identity, and the stored contacts.

| Scanned code | Result |
|---|---|
| Not ours (a URL, a Wi-Fi code) | refused, `notAPairingCode` |
| Ours, newer version | refused, `unsupportedVersion` |
| Damaged, wrong length, trailing bytes, name empty or not UTF-8 | refused, `malformed` |
| All-zero key | refused, `invalidIdentityKey` |
| Our own key or our own account id | refused, `ownCode` |
| Key and account id both unknown | **new contact** |
| Same key **and** same account id as a stored contact | **already paired**; nothing changes, not even the name |
| Known key with a different account id, or the reverse | refused, `conflictsWithExistingContact` |

The last row: under the v1 rules a reinstall replaces the identity key and
the account id together (`appattestkit-module-design.md` §8), so one changing
without the other is never a legitimate re-pairing.

The scanned name is cleaned before use (control characters and line breaks
removed, trimmed, cut to 64 bytes): it is text chosen by someone else that
ends up in our UI.

### Step 4 — Store the contact

```
{ identityPublicKey, accountUUID, displayName, pairedAt }
```

Stored by the app. A refused scan stores nothing.

### Step 5 — The first session confirms the pairing (not built)

Because both sides already hold each other's static key, the first chat
session can use Noise `KK` directly; the `XX` handshake is no longer needed
anywhere. That first successful `KK` session is also what proves the two
things a scan cannot (next section).

---

## Face to face: both scans in one gesture

Tried on 2026-10-13 with an iPhone 16 Plus and an iPhone X (iOS 16.7, fixed-
focus front camera): held facing each other, each front camera read the other
screen at once. The X stands in for every phone before the iPhone 14, the
first with front autofocus.

Each phone shows its code and scans with the front camera at the same time.
Because both cameras keep watching, the code can say one more thing:

1. A reads B's code and stores the contact.
2. A's code gains an **acknowledgement**: the first 8 bytes of
   `SHA256(B's identityPublicKey)`. It means "I have yours".
3. B, still watching, reads A's code with the acknowledgement for B's own key
   (`Pairing.Evaluation.peerHasScannedUs`). B now knows A has its code.
4. The same happens in the other direction, so both phones can say "done"
   together.

The rules of one attempt are `FaceToFacePairing` in `PairingKit`: the view
shows `codeToShow`, feeds it every scanned text, and signals the event it
returns.

**Saved only on completion (decided with the user, 2026-10-15; replaces
"stored as soon as read").** A phone saves the contact only when it knows
both sides have each other's key: their code read, and their code saying
"I have yours". If that confirmation does not come within 5 s of reading
their code, the attempt is aborted and nothing is saved.

**The one case this cannot rule out.** Over a one-way channel there is
always a last code whose sender cannot know it was read. The phone that
completes first has saved the contact; if the other then times out, only
one side has it (its messages show "didn't answer"). Pairing again repairs
it: the first phone already has the contact, the other saves it, both
complete. To make this rare, the phone that completes keeps its code up for
3 s and vibrates only after 1 s, so nobody pulls away before the other phone
has read it. 1 s, 3 s and 5 s are starting values, to be tuned on phones
(the bench logs the gap between "read their code" and "paired both ways").

## Two screens (2026-10-15)

1. **Start:** what to do, how the last attempt ended (paired, didn't
   finish, nothing read, refused), and "Pair". It scrolls, so any text size
   works.
2. **Code:** only the QR code, as large as the screen allows, white, full
   brightness, no auto-lock. The front camera reads unseen; the rear one
   shows a small viewfinder to aim with. "Done" goes back. After 15 s
   without reading anything it goes back by itself, with the error buzz.

Feedback, since nobody sees their screen: a tap when their code is read,
the full vibration and a sound on completion, an error buzz for a refused
code, a timeout, or nothing read.

**On phones, 2026-10-15:** SecureChat (iPhone 16 Plus) and
`SessionTestApp` (iPhone X) paired with the two screens: saved on both
after completion. Pulling apart early: see below.

**Pulled apart after one read (seen on phones, 2026-10-15).** If only one
phone has read the other, that one times out after 5 s and says "didn't
finish"; the other has read nothing and nothing tells it the attempt is
over. It was left on its code for 60 s; now it stops after 15 s with the
error buzz and "the other phone's code wasn't read". Neither saves
anything. 15 s is counted from opening the code screen, so it also covers
bringing the phones together: a value to tune, like 1, 3 and 5 s.

Debug builds add a "Debug" button on both screens: this phone's code as
text, a field to use a code by hand (the Simulator has no camera; there the
timeouts are minutes, not seconds), the attempt's state, and each app's own
lines (account id; for the harnesses, relay or bench settings).

Nobody sees their own screen in this position, so the result must be felt or
heard. Confirmed on both phones on 2026-10-13: the full vibration
(`kSystemSoundID_Vibrate`) on completion. `UIFeedbackGenerator` haptics alone
could not be felt, cause not established.

**The acknowledgement is a convenience, not a proof.** It is a hash of a
public key and anyone can produce it. A false one only makes the liar's own
contact useless. The first session remains what confirms a pairing.

The rear camera stays available on the same screen as the fallback.

## What a scan does not prove

1. **That they scanned you back.** A scans B, B never scans A: A holds a
   contact that B does not have. Face to face, the acknowledgement tells
   both phones when the pairing went both ways, but it is not stored and not
   a proof. With the rear camera, or if one side walks away early, the
   contact is "waiting for them to scan you" until the first session
   succeeds. The contact record has no status field yet.
2. **That they hold the private key.** Anyone can display a code built from
   someone else's public key. Such a contact simply never completes a
   session. Nothing is leaked, because nothing is sent to a contact outside
   a `KK` session.

## Rules the rest of the app must follow

- **Accept sessions only from stored contacts.** The code is static and can
  be photographed. A stranger who captures it learns the identity public key
  and the account id; they cannot impersonate the owner without the private
  key, and they must not be able to reach the owner either. This is the rule
  that makes a photographed code harmless, so it belongs to the session
  design.
- **Never treat `displayName` as identity.** Two contacts may carry the same
  name. The key is the identity.

## Why this is safe against a man in the middle

The old design needed the SAS because Bluetooth can be relayed: two victims
each complete a handshake with an attacker standing between them. Here there
is nothing to relay. Each user points a camera at the other user's screen,
and what is read is the full 32-byte key, not a short string derived from
it. An attacker would have to replace what is on the screen.

## Development and testing

- **`PairingTestApp`** (bundle id `com.wapdir.simone.PairingTestApp`) is the
  harness. It uses a throwaway identity (a random public key and a random
  account id in `UserDefaults`), never `RegistrationKit`, so it cannot reach
  App Attest or the Auth Server.
- **The Simulator has no camera.** The harness has "Copy code as text" and a
  paste field, so two Simulators, or a Simulator and a phone, can pair. A
  phone can also scan the code off a Simulator window on the Mac.
- **One pairing flow, in PairingKit** (since 2026-10-15):
  `FaceToFacePairingView` (the two screens above and the debug sheet),
  `PairingSignal` (vibration, sound, refusal wording) and `PairingTiming`. SecureChat,
  `PairingTestApp` and `SessionTestApp` all show it, so every iteration of
  how pairing looks and feels is tried on the bench and phones exactly as
  it ships. Hosts add only their own: which scans count and what is logged
  (`scan:`), and lines in the debug sheet (the bench's error-correction
  toggle).
- **Previews** (`FaceToFacePairingView+Previews.swift`, Debug only): both
  screens in every state (start: fresh, paired, timed out with a 54-byte
  name, nothing read, refused, camera denied, largest text, dark; code:
  looking, their code read, camera denied, no camera, largest text in
  dark). The camera window is a still. Open the file in Xcode with the
  canvas on to iterate without phones.
- The large-text problem of the one-screen version (title cut off, QR at
  half width) is what led to the two screens; the code screen keeps the QR
  at full width at the largest text size.
- **Face to face in the harness:** "Pair face to face (front camera)", on
  the shared screen (`FaceToFaceBenchView`). Read times are written to the
  harness log. Pairing both ways was
  confirmed on the two phones on 2026-10-13, with the attempt's rules still
  inside the harness view; they have since moved into `PairingKit`
  (`FaceToFacePairing`) and that version has not been run on phones.
- **`PairingKit` and the harness target are set to iOS 16** so the harness
  runs on the iPhone X. The other packages are iOS 17 and SecureChat 18.5;
  the production floor is not decided (iOS 17 suggested).
- **`PairingKit` tests:** `xcodebuild test -scheme PairingKit` in
  `Modules/PairingKit`, against an iOS Simulator (27 tests).
- **Debug builds of SecureChat skip registration**
  (`registration-status.md`, blocker 2), so they have no identity key and no
  account id. In that case pairing uses `DebugLocalIdentity`: a made-up key
  and account id in `UserDefaults`, Debug builds only, known to no server.
  The "SecureChat Real Registration" scheme (opt-in, phone, development
  App Attest) pairs with the registered identity.
- **Registration feeding pairing** is covered by
  `SecureChatTests/Integration/RegistrationPairingIntegrationTests.swift`:
  two devices register through the real code (Apple and the Auth Server
  faked), then pair with the key and account id registration stored. See
  `testing-strategy.md`.
- **SecureChat in the Simulator** has a paste field on the pairing screen
  (Debug + Simulator only), for a code copied from the harness.

## In SecureChat (2026-10-13)

| Piece | Where |
|---|---|
| Entry point | Person icon, top left of the chat list → "Add contact" sheet |
| Screen | `View/PairingView.swift`: asks for a name once, then PairingKit's `FaceToFacePairingView` (rear camera as fallback) |
| View model | `Pairing/PairingViewModel.swift`, wrapping `FaceToFacePairing`; `scanned` returns the event to signal, or nil when the contact could not be saved (at completion, when saving happens) |
| Who we are | `Pairing/LocalIdentity.swift`: `IdentityKeyStore` + `RegisteredAccountStore`, or the Debug stand-in |
| Display name | `ProfileStore` (`UserDefaults`), asked for on first use |
| Storage | `contacts` table (key is the primary key, account id unique), `ContactRepository` |
| Result | A "Contacts" section in the chat list |

Verified: 8 unit tests (`SecureChatTests/PairingTests.swift`) and 3
integration tests (`SecureChatTests/Integration`). **On phones, 2026-10-14:**
SecureChat on the iPhone 16 Plus, registered for real (development App
Attest, account `d832cf87…`), paired face to face with `PairingTestApp` on
the iPhone X; the harness's contact carried account `D832CF87…`, so the code
SecureChat showed used the registered identity, not the Debug stand-in.
The first run on a phone also exposed a crash unrelated to pairing: the
database path was built without a separator and pointed outside
`Documents`, which a phone refuses (fixed in `SQLiteConstants.swift`).

## Not done yet

- **Contacts are not linked to chats.** A paired contact is listed and
  nothing more; the `guests`/`chats` tables do not know about it. That link
  belongs with sessions.
- **Changing your display name**, and renaming or removing a contact.
- **The "waiting for them to scan you" state**, and what ends it.
- **Default display name.** The docs propose the identicon word-triple
  (`otter-canyon-4417`, `architecture-decisions.md` §7); no wordlist exists
  yet. The harness uses "Harness 1234".
- **Removing a contact / blocking** (`architecture-decisions.md` §12, abuse
  handling).
- **Manual contact merge (v2)**, unchanged from before: a contact who
  reinstalls arrives with a new key and a new account id and is a stranger
  to this flow. Any merge is a user-asserted claim, never something pairing
  can detect.

## Why the earlier design was dropped

- **NFC is not available.** Core NFC only reads tags; an iPhone cannot act
  as one for another iPhone without Apple's gated card-emulation APIs
  (commercial agreement, payment-oriented).
- **BLE needed everything else**: CoreBluetooth, a Noise `XX` handshake, and
  a SAS comparison.
- **The SAS as specified was breakable.** `HASH(sort(keyA, keyB))` over
  long-lived keys lets a relay attacker try keys offline until the short
  strings collide. The fix (commit-reveal with fresh random values) was
  understood but adds three messages and more to test.
- **Mutual scan needs none of it**, and verifies the whole key instead of a
  short string. It is also what Threema does in person.

## Deferred: pairing at a distance

Discussed on 2026-10-12, not designed. Recorded so it does not have to be
rediscovered:

- One scan (or one link) is possible if the relay carries the reply: the
  code adds a single-use secret, and the other side completes a
  pre-shared-key Noise handshake (`IKpsk2`-style) through the relay.
- A code sent through email or another chat app is a bearer token: whoever
  uses it first is paired. It cannot be bound to a person, because their key
  is not known yet. Single use, expiry and an approval prompt limit this but
  do not close it.
- Security then rests on the channel the code travelled through, so a word
  comparison over a second channel (a call) comes back, with commit-reveal.
- The app cannot tell an in-person scan from a forwarded screenshot.
- It makes the relay a requirement for pairing.
