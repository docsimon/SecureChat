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
```

The code is static: the same identity always produces the same code (for the
same name). It is about 160 characters.

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

## What a scan does not prove

1. **That they scanned you back.** A scans B, B never scans A: A holds a
   contact that B does not have. Until the first session succeeds the contact
   is "waiting for them to scan you". How this is shown is a UX decision; the
   contact record has no status field yet.
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
- **Face-to-face prototype (2026-10-12, untested on phones).** The harness
  has "Pair face to face (front camera)": it shows this device's code and
  scans with the front camera at once, so two phones held facing each other
  read each other in one gesture. Success is a vibration and a sound; the
  time to read is written to the harness log. The open question is whether
  front cameras, fixed-focus on older phones, read the code reliably at
  15–30 cm. If they do, the next step is an "I have yours" marker added to
  the code after a successful read, which would let both phones know the
  pairing is mutual.
- **`PairingKit` tests:** `xcodebuild test -scheme PairingKit` in
  `Modules/PairingKit`, against an iOS Simulator (17 tests).
- **Debug builds of SecureChat skip registration**
  (`registration-status.md`, blocker 2), so they have no identity key and no
  account id to put in a code. Integrating pairing into SecureChat needs a
  Debug-only local identity. No server path is needed for it, since pairing
  never contacts a server.

## Not done yet

- **The pairing screen in SecureChat** and its UX (how showing and scanning
  are arranged so the two scans feel like one action). `PairingKit` is not
  linked into the SecureChat target yet.
- **Contact storage in SecureChat.** The existing `guests` table has no
  column for a key or an account id.
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
