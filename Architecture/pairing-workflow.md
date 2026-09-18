# Pairing workflow — BLE / NFC

Step-by-step, with explicit ownership at every step. Companion to
`architecture-decisions.md` (product/protocol, §1 and §10) and
`account-keys-reference.md` (what the identity key is and why it's the
thing exchanged here).

**Ownership rule:** this flow has no module and no server. `AppAttestKit`'s
boundary stops at registration/assertion (`appattestkit-module-design.md`
§2) and never touches pairing — everything below is app-owned.

v1 covers **BLE and NFC only**. A shared-link method was considered and
deferred — see the note at the end of this doc.

---

## Overview

| # | Step | Owner | Touches |
|---|---|---|---|
| 1 | Establish a raw bidirectional channel | App | BLE / NFC |
| 2 | Run Noise `XX` handshake | App | Identity keypair |
| 3 | Exchange `account_uuid` + display name | App | Local account state |
| 4 | Compute SAS locally, both sides | App | Both identity public keys |
| 5 | User confirms SAS match (hard gate) | User, via app UI | — |
| 6 | Persist the contact record | App | Local contact store |

No server involvement at any step — the main benefit of dropping
link-based pairing for v1, see the closing note.

---

### Step 1 — Establish a raw channel (App)

BLE or NFC connects the two devices directly. This step's only job is
producing a bidirectional byte stream — no cryptographic or identity
information is exchanged yet. Everything from step 2 onward is **identical
regardless of which transport established the channel**; one pairing
implementation runs on top of either.

### Step 2 — Noise `XX` handshake (App)

```
→ e
← e, ee, s, es
→ s, se
```

Both parties' X25519 identity static public keys are exchanged as an
inherent part of this pattern (architecture doc §4) — there is no separate
"send identity key" step. By the end of message 3, both sides hold the
peer's `identityPublicKey` and a shared, encrypted channel for everything
that follows.

No application data (`account_uuid`, display name) rides inside the
handshake's own payload fields. Reasoning: exactly which handshake
message's payload is authenticated by what, at that point in the pattern,
is a detail worth verifying against the Noise spec before relying on —
and this project consistently favours the boring, independently-verifiable
choice over shaving one round trip (X3DH rejected, hand-rolled ASN.1
rejected, ad hoc key reuse across primitives rejected elsewhere in these
docs). One extra message, for a one-time pairing event, costs nothing.

### Step 3 — Exchange `account_uuid` + display name (App)

First message on the now-encrypted channel, both directions:

```
{ accountUUID, displayName }
```

- **`accountUUID`** — required, always sent. This is the *only* way a
  contact ever learns your routing address — there is no discovery or
  directory (architecture doc §1) — so this exchange is the sole mechanism
  by which future messages can reach you at all.
- **`displayName`** — always sent, never optional. Defaults to the same
  word-triple already used for the identicon/SAS (architecture doc §7,
  e.g. `otter-canyon-4417`) if the user hasn't set a custom nickname. This
  costs no new generation logic, and keeps a useful property: since the
  identity key survives a `.keyInvalid` reset (`appattestkit-module-design.md`
  §8), the default name stays identical across that event too — one less
  thing that looks different to a contact re-pairing afterward. The
  receiving side may override it locally at any time — it's a label, not
  an identifier (architecture doc §7).

### Step 4 — Compute the SAS (App, both sides independently)

```
SAS = wordlist(HASH(sort(identityPubkeyA, identityPubkeyB)))
```

No network round trip — both devices already hold both public keys from
step 2. Sorting the two keys before hashing ensures both sides compute the
same input regardless of which device initiated.

⚠️ **The ordering matters for security, not just for correctness.** A SAS
derived naively, before both sides have committed to their contribution, is
vulnerable to an attacker adaptively searching for a colliding short string
— a few words is a small space (tens of bits, not hundreds). Protocols like
ZRTP close this with a commitment step: one side sends a hash of its
contribution before the other reveals theirs, so neither can choose a key
after seeing what value it would need to hit. **Verify this ordering
against a reference design (ZRTP) before implementing** — this is the same
category of risk as the `DCError` mapping and XEdDSA-reuse cautions
elsewhere in these docs: looks fine until tested against an active
attacker.

### Step 5 — User confirms the match (User, hard gate)

Both devices display the SAS. **The contact is not usable for messaging
until both users explicitly confirm the values match** — not a soft
"unverified" warning attached to an already-usable contact.

Reasoning: this happens once per contact, the friction cost of one
confirmation tap is low, and "unverified" badges are a well-worn UX failure
mode users learn to dismiss (mixed-content warnings, safety-number-change
notices people click past). Given confidentiality is the entire product
promise, enforcing it at the moment it's cheapest — both devices already
physically together — is worth the tap.

If the values don't match: abort pairing entirely, do not save a partial
contact record.

### Step 6 — Persist the contact record (App)

Only after step 5 confirms:

```
{ identityPublicKey, accountUUID, displayName, pairedAt }
```

---

## Why BLE/NFC-only removes a whole class of problem

Both transports require physical proximity to establish the channel at all
(step 1), and — critically — **step 1 has no server dependency**. A
shared-link method would have needed the relay server to broker a
rendezvous between two devices that aren't physically together (since
"both parties must be online" still applies regardless of transport,
architecture doc §1) — an ephemeral "connect these two sockets" primitive
on the relay, plus link-specific protections: single-use TTL, high
entropy, key material kept out of the URL path and in the fragment so it
never reaches server logs.

None of that is needed for v1. It's deferred, not discarded — if a
link-based method is added later, that mitigation list is the starting
point, and everything from step 2 onward in this doc is reused unchanged.
The whole point of decoupling "establish a channel" (step 1) from "what
runs over it" (steps 2–6) is that adding a transport later never touches
the protocol.

## Failure paths not yet designed

- Connection drops mid-handshake (BLE range, NFC tap too brief) — retry
  policy not yet specified.
- Duplicate pairing attempt with an already-paired identity key — behaviour
  not yet specified (overwrite the existing contact record? reject? merge?).
