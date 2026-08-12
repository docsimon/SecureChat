# 01 — Architecture

**Scope:** confidentiality, not anonymity. Phone-number onboarding. No Tor. See `04-DECISIONS.md` for how we got here.

---

## 1. The product in one line

Messages exist only while both parties are present, are never stored on a server, and are destroyed locally by destroying their key.

Three properties, in order of how much they differentiate:

1. **Crypto-shredded local history** — most "disappearing messages" implementations delete rows, which does not destroy data on flash storage. This one destroys keys. See `03-CRYPTO-SHREDDING.md`.
2. **No server-side message storage, ever** — not queued, not buffered, not logged.
3. **Synchronous sessions** — a session is a live thing that ends when either party leaves.

---

## 2. Layers

```
┌─────────────────────────────────────────────────────────┐
│ UI            Delivered / queued / dropped are distinct │
│               and never conflated.                      │
├─────────────────────────────────────────────────────────┤
│ Persistence   SQLCipher (whole-file) + per-conversation │
│               envelope encryption (shred granularity)   │
├─────────────────────────────────────────────────────────┤
│ Session       libsignal — Double Ratchet, PQXDH         │
├─────────────────────────────────────────────────────────┤
│ Identity      Device keypair; phone number bound at     │
│               registration; keys in Secure Enclave      │
├─────────────────────────────────────────────────────────┤
│ Transport     WebSocket over TLS                        │
├─────────────────────────────────────────────────────────┤
│ Servers       Directory (registration + discovery)      │
│               Relay (opaque forwarding, RAM only)       │
└─────────────────────────────────────────────────────────┘
```

**The two servers are separate systems and must stay separate.** The directory is touched when adding a contact and never again. The relay never sees an identity beyond a routing UUID, never sees plaintext, never persists. Neither should be able to reconstruct what the other knows.

---

## 3. Identity

### 3.1 Registration

```
phone number → SMS OTP → directory binds phone_hash → identity public key
                       → client sets a registration-lock PIN
                       → client publishes routing UUID
```

**Registration lock is not optional.** Phone numbers get SIM-swapped, and carriers recycle numbers to new people. Require a PIN to re-register a number, enforce a delay window, and notify existing devices. Without this, anyone who social-engineers a carrier owns the account.

### 3.2 Key material

| Key | Where | Algorithm | Why |
|---|---|---|---|
| Identity signing | Secure Enclave | P-256 | Non-extractable — the Enclave holds no other curve |
| libsignal identity | Keychain, `ThisDeviceOnly` | Curve25519 | Required by the protocol; software-only |
| Ratchet / session | Memory, persisted in SQLCipher | Curve25519 | Ephemeral by design; must be destroyable |
| Conversation content | Derived, see `03` | AES-256 | Shredding granularity |

Note the split: libsignal mandates Curve25519, which the Secure Enclave cannot hold. So the Enclave protects the *storage key hierarchy*, not the protocol identity. Be precise about this in `SECURITY.md` — a reviewer will ask, and "the Enclave protects data at rest, not the protocol identity" is the correct answer.

### 3.3 One device, one identity

A second device is a different identity. Multi-device requires key sync, which is a subsystem, not a feature. Out of scope — say so explicitly rather than leaving it ambiguous.

---

## 4. Contact discovery

Hashed-phone-number lookup with a server-side pepper and aggressive rate limits.

**Be honest in the docs about what this does and doesn't do.** Naive hashing of phone numbers is security theatre: the global number space is roughly 10¹², so an exhaustive table is cheap. A server-side pepper blocks *outsiders* who obtain the database. It does not blind the *operator*, who holds the pepper.

The genuinely private options — cryptographic PSI, or SGX enclaves as Signal uses — are out of scope for v1. Document the limitation plainly. A reviewer who sees "we use hashing, therefore private" will discount everything else you wrote; one who sees an accurate description of a known-imperfect mechanism will trust the rest.

Mitigations that are in scope and cheap:
- Rate-limit lookups per account, hard.
- Never log queries. State this as policy and enforce it in code review.
- Let users opt out of discoverability entirely.

---

## 5. Session layer

**libsignal.** Double Ratchet, PQXDH, X3DH — audited, and the correct engineering answer. See `learning/libsignal-primer.md` for the API and for the AGPL and Noise considerations.

One adaptation to your design: normally the server stores prekey bundles so an absent recipient can still be messaged. **You don't need that.** Both parties are online, so bundles are exchanged live over the relay at session start. Delete the prekey server from the design — one less system, one less thing holding key material.

---

## 6. Transport — wire protocol

Unchanged from `relay-server.mjs`. WebSocket, JSON control frames, base64 opaque payloads, `t` for frame type.

### Handshake

| Dir | Frame |
|---|---|
| S→C | `{"t":"challenge","v":1,"nonce":"<b64>"}` |
| C→S | `{"t":"auth","alg":"P-256","pk":"<b64>","sig":"<b64>"}` |
| S→C | `{"t":"ready","userId":"<uuid>","capacity":2}` |

Signature covers `"securechat-relay-auth-v1|" + nonce`. Domain-separated so a captured signature cannot be replayed into another context; nonce is single-use and per-connection.

### Session

| Dir | Frame |
|---|---|
| C→S | `{"t":"open","room":"<uuid>"}` |
| S→C | `{"t":"room","room":..,"peers":[..]}` |
| S→C | `{"t":"peer-join" \| "peer-leave","room":..,"userId":..}` |
| C→S | `{"t":"msg","room":..,"payload":"<opaque>","ref":"<local id>"}` |
| S→C | `{"t":"msg","room":..,"from":..,"payload":"<verbatim>"}` |
| S→C | `{"t":"ack","ref":..,"delivered":0\|1}` |

### Relay invariants

1. Nothing touches disk.
2. Rooms are refcounted by live sockets; last peer out deletes the room.
3. `payload` is length-checked and forwarded verbatim. Never parsed. The relay has no schema for message contents and must never acquire one, not even for debugging.
4. No unauthenticated identity claims.
5. Capacity 2. A third connection is refused — a relay that silently admits an extra peer is an eavesdropper.

The relay's peer list is a routing hint, not the truth. Real membership is whoever the session layer has agreed keys with.

---

## 7. Delivery semantics and the outbox

This is where the synchronous constraint meets "user first."

Three states, always visually distinct:

| State | Meaning | UI |
|---|---|---|
| **Queued** | Peer offline; held in the local outbox | Clock icon, muted |
| **Delivered** | Handed to a peer socket (`delivered: 1`) | Single check |
| **Read** | Application-level ACK inside the ciphertext | Double check |
| **Dropped** | `delivered: 0` and the outbox rejected it | **Red, explicit, actionable** |

**The outbox lives on the sender's device. Never on the server.** If that queue ever moves server-side you have rebuilt the mailbox and lost the entire design.

`delivered` counts peer sockets the frame was handed to. It is a lower bound on failure, not proof of success — true receipt is the application ACK. Silent failure in a security tool is how people leak things: a user who believes a message arrived will act on that belief. Never render an unacknowledged message identically to a delivered one.

### Reconnection

A dropped socket ends the session. Ratchet state persists (libsignal handles this), but the *session* is over and the UI should say so rather than papering over it with a spinner.

---

## 8. Module layout

```
Identity/
  RegistrationService     phone binding, OTP, registration lock
  IdentityStore           SEP keygen, signing, libsignal identity
  SafetyNumbers           fingerprint display (settings only, not onboarding)
Discovery/
  ContactMatcher          hashed lookup, local contact cache
Session/
  SignalSessionManager    libsignal stores, bundle exchange, encrypt/decrypt
  Outbox                  local queue, retry policy, expiry
Transport/
  RelayConnection         actor; WebSocket, auth handshake, frame codec
  ConnectionState         one enum, single source of truth for the UI
Storage/
  KeyHierarchy            SEP-wrapped keys, derivation  → see 03
  ConversationStore       SQLCipher + per-conversation envelope
  ShredScheduler          burn timers, key destruction, sweep → see 03
UI/
```

### Concurrency notes

- `RelayConnection` is an `actor`. Its state machine has real interleaving hazards — an `open` racing a `peer-leave` racing a socket close is exactly the shape that sends messages into a dead room.
- **Re-check state after every `await`** in that state machine. Actor reentrancy means the peer may have left while you were suspended.
- Ratchet advancement must be synchronous and non-reentrant. A suspension point mid-ratchet lets two sends derive the same message key — a catastrophic, silent failure.
- libsignal store writes must be atomic with the send/receive they belong to. A crash between "ratchet advanced" and "state persisted" leaves an undecryptable session.
- Cancellation must propagate to key destruction. A cancelled session that leaves keys in memory has silently lost forward secrecy.

---

## 9. What the servers know

Worth keeping current, because it is the table a reviewer will look for.

| | Directory | Relay |
|---|---|---|
| Phone number hash | Yes, persistent | No |
| Identity public key | Yes, persistent | No |
| Routing UUID | Yes | Yes, per connection |
| Who contacts whom | Lookups only, unlogged | Pairing, in RAM, transient |
| When they talk | No | **Yes** — this is the main residual leak |
| Message content | No | No |
| Message length | No | Yes |
| IP addresses | Yes | Yes |

The relay learning session timing and IPs is the honest cost of dropping Tor. It is documented in `02-THREAT-MODEL.md` as an accepted risk, not hidden.
