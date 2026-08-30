# iOS private chat — architecture decisions

Context document for reuse across conversations. Captures decisions made, the reasoning behind them, and what is explicitly deferred or rejected.

Status: pre-launch, no live users. Last updated 2026-08-26.

---

## 1. Product shape

Privacy-focused iOS chat app. Core constraints, treated as fixed:

- **Manual pairing only** — BLE, NFC, or shared link. No discovery, no directory, no username search.
- **No server-side message storage.** Messages exist in transit and on the two devices, nowhere else.
- **Both parties must be online.** No offline delivery, no store-and-forward.
- **Local storage encrypted.**
- **Text only for now.** Media, voice, and video are explicitly out of scope for v1.
- Server retains nothing after a session ends — conversation routing state is deleted on disconnect.

The absence of discovery is the single most important property. It removes almost the entire spam and abuse surface that phone-number-based messengers have to defend against, because an attacker cannot reach a stranger without being physically handed a pairing.

### Scope — what this app does and does not promise

**In scope:**
- **Confidentiality.** Messages are readable only by the intended recipient. E2EE, no server-side plaintext, ever.
- **No storage beyond the endpoints.** Nothing persisted on the server; local storage encrypted.
- **No personal data collected.** No phone number, no email, no password. A compromised server yields opaque identifiers rather than a list of real phone numbers — this is the primary differentiator and the strongest claim available.

**Explicitly out of scope, now and in future:**
- **Anonymity and unlinkability.** The server can observe that two accounts are connected during an active session. It cannot learn who they are or what they say.

This scoping is deliberate. Expected user base is small (dozens, largely known personally). Metadata-layer defences — rendezvous IDs, cover traffic, sealed sender — belong to a different product with a different threat model and are not planned.

Note that the gap between this app and Signal/WhatsApp is *not* cryptographic — the primitives are the same. The gap is metadata handling. Narrower threat model, not weaker crypto.

**Positioning language:** lead with confidentiality and "no personal data required", both precisely true. Avoid "private" as the headline word — mainstream users hear it as including unlinkability. Avoid "military grade", which is marketing rather than a real tier.

---

## 2. Registration: App Attest + DeviceCheck

**Decision: App Attest. Phone + OTP and email + OTP both rejected.**

### Why the OTP options were rejected

Phone and email registration exist to provide discovery, recovery, and sybil resistance. This product deliberately has no discovery, so collecting a phone number or email would mean holding PII to power a feature that is never shipped.

That PII actively contradicts the product promise. A phone number is a cross-service join key indexed by data brokers and breach dumps, is tied to government ID at SIM registration in much of the world, is SIM-swappable, and enables user enumeration. Neither identifier adds anything to the E2EE guarantee.

Cost also favours attestation. SMS carries per-message fees, SMS-pumping fraud on any open signup endpoint, per-country deliverability quirks, and a vendor relationship. App Attest and DeviceCheck are free and first-party.

### The registration flow

Silent, on first launch. No user input at any point.

1. Generate identity keypair → Keychain, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
2. `DCAppAttestService.shared.generateKey()` → persist `keyId` to Keychain **immediately**, before attesting
3. `GET /challenge` → server returns 32 random bytes, stored with a short TTL
4. `attestKey(keyId, clientDataHash: SHA256(challenge ‖ identityPublicKey))`
5. `POST /register` with attestation object, challenge, identity public key
6. Server verifies; mints account UUID bound to `keyId` + identity public key
7. Client stores the UUID

Runs in roughly 300ms.

### Server-side verification steps

All of these are mandatory — skipping any one degrades the scheme to replayable garbage:

- Validate the X.509 chain in `attStmt.x5c` up to the Apple App Attest root CA
- Extract the nonce from the leaf certificate's custom Apple extension at OID `1.2.840.113635.100.8.2` and confirm it equals `SHA256(authData ‖ clientDataHash)`
- Confirm the `rpId` hash in `authData` equals `SHA256(teamId + "." + bundleId)`
- Confirm the counter is 0
- Confirm `keyId` equals `SHA256(publicKey)`

Use a maintained App Attest verification library. Do not hand-roll ASN.1 parsing — it is a well-known CVE farm (unbounded length fields, integer overflow in length arithmetic, non-canonical encodings).

Note the two binary formats involved: the attestation object wrapper is **CBOR** (RFC 8949); the certificates inside are **DER-encoded ASN.1** (X.690). Different formats, easy to confuse.

### Ongoing authentication

Attestation happens once per install. Every subsequent session uses an **assertion**: the client signs a request hash with the Secure Enclave key, the server verifies the ECDSA signature (~50–100µs) and checks the counter is monotonic, then issues a short-lived session token. Do not attest per message.

### Trade-offs accepted

- **No account recovery.** Lose the device, lose the identity. Since contacts are re-verified by physical pairing anyway, re-pairing after device loss is arguably correct behaviour rather than a defect.
- **Sybil resistance is good, not great.** Device farms still work — roughly comparable to burner SIMs, and irrelevant here given no discovery.
- **Excludes jailbroken devices** and is unavailable in the simulator.
- **iOS 14+, Apple-only.** Play Integrity API is the near-direct Android analogue if that platform arrives later.

### Reference point

Threema is the closest shipping precedent — random ID, no phone or email required.

---

## 3. DeviceCheck: evaluated, deferred

**Decision: wire the query into the registration path so the plumbing exists, but write no bits for now.**

### How it actually works

The two bits do **not** identify hardware. The developer never receives a device identifier.

1. App calls `DCDevice.current.generateToken()` → ephemeral opaque token
2. Server calls Apple's API (`query_two_bits` / `update_two_bits`), authenticated by an ES256-signed JWT
3. Apple resolves the token to its own internal identifier, scoped to the developer team, and returns `bit0`, `bit1`, `last_update_time`

Consequences:

- **Cannot correlate accounts.** No ID to join on, so "same device" is not determinable. Counting accounts per device is impossible.
- **Per-developer scoped.** Other apps get independent bits for the same device.
- `last_update_time` is month granularity (`YYYY-MM`) — deliberately coarse to prevent timing-based fingerprinting.
- **Survives app deletion, reinstall, and factory reset.** This is the unique property; App Attest's `keyId` does not survive reinstall.
- A never-seen device returns bit fields **absent**, not `0 0`. Treat absent and zero as identical or you will crash on first launch.

### Why it was deferred

The abuse it defends against barely exists here. With no discovery, sybil accounts have nobody to talk to. Harassment by an already-paired peer is correctly solved **client-side** by deleting the pairing and refusing that identity key — no server involvement, no bans.

Additional problems: bits persist across device resale with no signal, and this product has **no appeals channel by construction** (no email, no phone, no recovery), so a wrongly banned user is permanently locked out with no way to reach support.

A "has registered before" bit was considered and rejected — it cannot distinguish resale, factory reset, hand-me-down, or a legitimate reinstall, and cannot count.

### If bits are ever used

Four states, allocated as a graduated ladder. This encoding can never be migrated, so decide only once real abuse patterns are known:

| bit0 | bit1 | Meaning |
|---|---|---|
| 0 | 0 | Clean / unknown |
| 0 | 1 | Restricted — reduced rate limits |
| 1 | 0 | Temporary ban (age out via `last_update_time`) |
| 1 | 1 | Permanent ban |

Reserve permanent bans for behaviour you would testify about in court. Prefer temporary bans that expire.

**Token lifetime caveat:** DeviceCheck tokens are ephemeral and cannot be stored for later reuse. Query and update within the same request. To enforce a ban later, flag the account locally and write the bits on the device's next connect using a freshly minted token.

---

## 4. Cryptography

### Primitives

- **X25519** for key agreement. 32-byte keys, no invalid-curve attacks by construction, easy constant-time implementation.
- **Ed25519** for signatures where needed. Same curve, different point representation.
- Identity key lives in the **Keychain**, not the Secure Enclave — the SE cannot hold X25519 keys and can only sign. The App Attest key is separate and does live in the SE.

### X3DH is not needed

X3DH exists to enable asynchronous session setup against an untrusted key server. This product requires both parties online and exchanges identity keys over a physically authenticated channel (BLE/NFC/link), so the MITM problem is solved by proximity rather than by prekey bundles and safety-number verification.

**Use the Noise Protocol Framework instead** — pattern `XX` for initial pairing, `KK` post-pairing when both static keys are already known. Far less code than X3DH for a formally analysed handshake.

### Double Ratchet: keep it

Two interlocking ratchets:

**Symmetric ratchet** (per message):
```
MK_n     = HMAC(CK_n, 0x01)   // message key
CK_(n+1) = HMAC(CK_n, 0x02)   // advance, then delete CK_n
```
One-way, so holding `CK_5` reveals nothing about `MK_1..4`. This is **forward secrecy** — provided old keys are actually deleted.

**DH ratchet** (per direction change): sender generates a fresh ephemeral keypair, sends the public half in the header, both feed the DH output into the root KDF producing a new chain. This is **post-compromise security** — an attacker who steals session state loses access after a DH step they did not observe.

Implementation hazards:

- **`MAX_SKIP` must be capped** (~1000). Out-of-order messages require deriving and caching skipped message keys; a header claiming counter 2,000,000 is a trivial DoS otherwise.
- **Key deletion is the entire security property.** SQLite WAL files, journals, and freelist pages retain deleted rows. Store ratchet state outside the main DB, or rely on crypto-shredding.

Alternative considered: fresh handshake per session, skipping the DH ratchet. Gives session-level forward secrecy for much less code but loses per-message granularity within long sessions. Full ratchet preferred.

---

## 5. Wire format

**Fixed-size frames. Single padding bucket — every frame on the wire is byte-identical in length, so message length leaks zero bits.**

Message cap: **2,000 grapheme clusters**, chosen for UX not cost. (An earlier 255-char cap was a cost decision, revised after establishing that text bandwidth is negligible. A tight cap is also counterproductive: users split long messages, producing more timed events and leaking more than a single padded frame would.)

| Component | Bytes |
|---|---|
| Plaintext, padded | 8,192 |
| Crypto + envelope overhead | ~128 |
| **Fixed frame total** | **8,320** |

Rules:

- Set WebSocket `ReadLimit` to exactly 8,320. Larger frames are dropped before allocation or parsing — this is the primary memory-exhaustion DoS guard.
- **Pad inside the encryption**, before AEAD, or an observer sees the true ciphertext length and padding accomplishes nothing.
- Plaintext layout: `[uint16 length][content][zero padding to 8192]`. Zeros are fine; random padding buys nothing since it is encrypted either way.
- **Client enforces the cap on grapheme clusters** (`String.count` in Swift — what the user perceives). **Server never counts characters**, only rejects frames of the wrong byte length.
- Beware ZWJ emoji sequences: one visible glyph can be 25+ bytes and several scalars.
- Include a **version byte** and a **type field** (text / control / receipt / future media) in the envelope. Two bytes now avoids a flag day when media is added.

Use a `sync.Pool` of preallocated frame buffers server-side — only in-flight messages need one, not every connection.

---

## 6. Infrastructure

### Auth server

Nearly free. Stateless, horizontally trivial, smallest available instance.

- `GET /challenge` — 32 random bytes into Redis, 60s TTL
- `POST /register` — full attestation verification, 1–5ms CPU, runs **once per install ever**
- `POST /session` — one ECDSA verify (~50–100µs) + counter check → short-lived session token

`POST /register` **must be idempotent**, keyed on `keyId`. If attestation succeeds but the response is lost, the client retries; return the existing account UUID rather than erroring.

### Relay server

Constraint is **memory and file descriptors, not CPU**. Holds a persistent WebSocket per online user plus an in-memory routing map. Forwarding is a map lookup and a write of opaque bytes — no parsing, no crypto, no disk.

| Stack | Per idle WS connection | 10k concurrent |
|---|---|---|
| Go (tuned buffers) | ~10–25 KB | 100–250 MB |
| Elixir / Phoenix | ~10–20 KB | 100–200 MB |
| Node.js | ~40–70 KB | 400–700 MB |

A single tuned Go or Elixir process handles 50k+ concurrent connections on an 8GB box. `ulimit` and ephemeral port exhaustion arrive before CPU limits — both are config fixes.

**Stay single-instance as long as possible.** One relay plus a hot standby carries tens of thousands of concurrent users. Scale by making the box bigger, not by adding boxes. Multi-instance requires Redis pub/sub or consistent hashing to route A's message to the instance holding B's connection — a real step up in complexity. When sharding becomes necessary, shard on the rendezvous identifier so both parties deterministically land on the same instance.

### Cost

| Stage | Setup | Hetzner | AWS / GCP |
|---|---|---|---|
| Dev + closed beta (<1k users) | 1 shared box, both services, local Redis | €5–8/mo | $30–60/mo |
| Launch (~10k MAU, 1–2k concurrent) | 2 small instances + LB | €20–30/mo | $150–300/mo |
| Growth (~100k MAU, 10–20k concurrent) | 2–3 mid instances, managed Redis | €70–120/mo | $500–900/mo |

Fixed costs: **Apple Developer Program $99/year** (mandatory for App Attest), domain ~£12/year, TLS free via Let's Encrypt.

**Provider choice is a 5–10× lever**, almost entirely egress pricing. Hetzner includes 20TB with a €5 box; AWS charges ~$0.09/GB plus ~$16/mo for an ALB. For a service whose entire job is moving bytes, that is the wrong billing model. Hetzner Falkenstein/Helsinki gives sub-30ms latency to UK users. Fly.io is a reasonable middle option if multi-region matters later.

At 2,000-char messages, 10k DAU × 50 messages/day is roughly 4GB/month of egress. Hetzner includes 20TB. **Text is effectively free.**

### P2P over Tor — rejected

Considered and dropped: initial circuit-building latency is unsuitable for chat, and battery consumption is unacceptable on mobile.

---

## 7. Onboarding UX

**There is no registration screen.** App Attest requires no user input, so the design problem is making the absence of friction feel deliberate rather than broken. Users arriving from WhatsApp expect to be asked for a number; silence reads as an error unless framed.

**Screen 1 — value proposition.** Lead with "No account needed." State the two things that will otherwise feel like bugs later: you cannot find people by searching, and you cannot message someone who is offline. Users must hear this before they hit it.

**Screen 2 — identity confirmation.** Show a visual fingerprint derived deterministically from the identity public key (identicon grid, and/or a word triple like `otter-canyon-4417` from a fixed wordlist). Solves "did anything happen?" and introduces the artifact that will later be used for pairing verification. Never user-editable.

**Display name** is optional, local-first, a label rather than an identifier, and overridable per-contact on the receiving side.

**Defer the recovery prompt.** On day one there is nothing to lose and no context for why it matters. Prompt after the first successful pairing or after a few days of use.

---

## 8. Failure paths — where the real work is

Registration is easy; these paths are silent, hard to reproduce, and will permanently strand users.

- **No network on first launch.** Do not block behind a spinner. Generate the identity keypair locally, let the user in, mark the account unregistered, retry on foreground and connectivity change. Surface the state on the "add contact" screen, not at launch.
- **`DCAppAttestService.isSupported == false`.** Simulator, jailbroken, some enterprise configs. Decide the policy explicitly. Gate any bypass behind `#if DEBUG` at **compile time** — a runtime flag will be found.
- **`attestKey` fails.** Apple runs a server-side risk assessment that can transiently reject legitimate devices. Retry with exponential backoff **using the same `keyId`**. Key generation is rate-limited per device; regenerating on every failure will lock the user out.
- **Response lost after success.** Handled by `POST /register` idempotency (above).
- **Keychain survives app deletion.** Reinstalling does not clear the identity key unless explicitly deleted. Common pattern: a flag in `UserDefaults` (which *is* cleared) triggers a Keychain purge on first launch if absent. Decide deliberately.

---

## 9. Rate limiting

Endpoints split into two zones with different economics.

**Pre-attestation** is the only anonymous surface and is expensive to serve (cert validation, ASN.1 parsing). Keyed on IP, which is a poor key — CGNAT puts thousands behind one address; **always bucket IPv6 at the /64, never the /128**.

**Post-attestation** the `keyId` is an excellent key: stable per install, unforgeable, cheap to verify. Push enforcement past this boundary wherever possible.

| Limit | Key | Starting budget |
|---|---|---|
| Challenge requests | IP / IPv6 /64 | 10/min, burst 20 |
| Full attestation verify | IP / /64 | 5/hour |
| Attestation verify | global circuit breaker | trip at ~3× baseline |
| WebSocket connects | keyId | 20/hour, burst 5 |
| Concurrent connections | keyId | 3 |
| Relayed bytes | keyId | 50 MB/hour |
| Pairing links issued | keyId | 10/day |

Token buckets in Redis (or GCRA). Fixed windows punish legitimate reconnection storms after a network flap.

More important than the numbers:

- **Cheap rejection first.** IP bucket check, body size cap, and challenge-freshness check must all run before touching a certificate parser. Consider a hashcash-style client puzzle in front of attestation under load.
- **Global circuit breaker.** Per-key limits do not stop a distributed flood where every key is individually under budget.

---

## 10. Known risks — acknowledged, deliberately deferred

Deferred on the reasoning that attack risk is low pre-scale. Noted here so they are not forgotten.

### Metadata — accepted, out of scope

**Resolved: static account UUID routing. Rendezvous IDs rejected as out of scope.**

The trade-off assessed: rendezvous IDs would rotate the routing identifier hourly, making sessions unlinkable to the server. But the failure mode is real and severe — clock skew between devices silently breaks messaging with no obvious diagnosis — while the risk it mitigates requires a live adversary with server access who then possesses only an anonymous graph with no content and no identities.

A concrete failure that breaks the core function outweighs a speculative leak of information the product never promised to protect. Confidentiality is the guarantee; unlinkability is not.

Two premises worth recording accurately, since they were initially overstated in the app's favour and should not be relied on:

- The UUID is **not meaningfully resettable**. A reinstall issues a new UUID, but the user must then re-pair with every contact, so the server sees a new UUID immediately connecting to the same peer set — a trivial re-link. Pairings are the durable identifier, not the UUID.
- Anonymised graphs are **not anonymous**. Structural matching against any auxiliary graph de-anonymises a large fraction of nodes. This is well established. It does not change the decision at this scale, but the mitigation should not be described as stronger than it is.

**The hedge, implemented:** these cost nothing now and keep the door open.
- Frame carries **16 opaque bytes**, not a typed UUID field
- Server routes by **subscription** (`id → [connections]`), not by address lookup
- Client produces the routing ID from a **single function**

With these, swapping in a derived rendezvous ID later is a client-side change plus a rollout window, not a frame format break.

**Still worth doing regardless:** load balancer, reverse proxy, TLS terminator, WAF, and hosting provider each log IP + timestamp + duration on their own schedules, outside app control. Audit these before making any no-logging claim.

### Pairing channel

Proximity is not authentication. BLE relay attacks are practical; a shared link sent over WhatsApp is a bearer token on a channel you do not control.

**Mitigation: short authentication string.** After the handshake, derive a few words or emoji from both identity keys and have both users compare them. Defeats MITM even against a fully compromised server. This is what makes "the server cannot lie about identities" true rather than aspirational.

For links: single-use, minutes-long TTL, high entropy. Any key material goes in the **URL fragment** so it never reaches server logs.

### Local storage

- Keychain: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the suffix is what stops a restored iCloud backup being decryptable elsewhere
- Exclude the DB from backup (`isExcludedFromBackup`), set `NSFileProtectionComplete`
- **Deletion is not deletion** — WAL files, journals, freelist pages, flash wear-levelling. Use crypto-shredding: per-conversation keys, delete the key, ciphertext becomes noise
- Blur the app-switcher snapshot on `sceneWillResignActive`
- Block third-party keyboards via `application(_:shouldAllowExtensionPointIdentifier:)`
- Mind the pasteboard — Universal Clipboard syncs to the user's other devices

### Other

- **Crash reporters will leak plaintext.** Sentry/Crashlytics capture memory, breadcrumbs, sometimes locals. Either run none, or symbolication-only with aggressive scrubbing.
- **Every SPM dependency is supply-chain surface.** Keep the count near zero.
- **Push notifications** tell Apple that a device received something at an instant — a metadata channel outside your control. Given both parties must be online, consider whether push is needed at all. Never put plaintext or sender identity in the payload.
- **Traffic analysis:** typing indicators and read receipts leak timing structure. Opt-out at minimum.
- **App Attest's limit:** proves a genuine unmodified app *at attestation time*. Does not prevent later runtime instrumentation, and says nothing about what a legitimate user does — screenshots by the person you are talking to are unpreventable.

### Threat model, as it currently stands

Worth publishing in this form — specific and honest beats "we don't log anything", which users discount:

> The server cannot read messages. It observes routing identifiers and IP addresses for the duration of an active session, retains nothing after disconnect, and cannot decrypt content. It cannot defend against an adversary with live access to server memory or the network path.

A server compromise yields: future metadata, IP correlation, and the ability to MITM *new* pairings if pairing material passes through the server. It does not yield message content or past sessions. SAS verification closes the MITM gap.

---

## 11. Open questions

1. **Server language/stack** — determines which App Attest verification library to use; quality varies significantly between ecosystems.
2. **Final message cap** — 2,000 graphemes proposed, not confirmed.
3. **Recovery mechanism** — user-held recovery phrase vs. iCloud Keychain sync vs. none. Deferred, but affects the Keychain accessibility flag chosen at implementation time.
4. **Push notifications** — needed at all, given the both-online constraint?

*Resolved: routing identifier (static UUID, see §10).*

---

## 12. Decisions log

| Decision | Outcome |
|---|---|
| Registration method | App Attest. Phone OTP and email OTP rejected. |
| DeviceCheck | Query wired in, no bits written. Revisit only if real abuse appears. |
| Key agreement | X25519 + Noise (`XX` pairing, `KK` thereafter). X3DH rejected as unnecessary. |
| Per-message crypto | Double Ratchet, `MAX_SKIP` capped |
| Wire format | Fixed 8,320-byte frames, padded inside encryption, version byte + type field |
| Message cap | 2,000 grapheme clusters (UX-driven, not cost-driven) |
| Routing identifier | Static account UUID in 16 opaque bytes. Rendezvous IDs rejected — clock-skew failure outweighs a metadata risk outside the app's scope. |
| Scope | Confidentiality yes, anonymity/unlinkability explicitly no |
| Transport | Auth server + relay server. P2P over Tor rejected (latency, battery). |
| Hosting | Hetzner strongly preferred over AWS/GCP on egress pricing |
| Scaling | Single relay instance as long as possible |
| Media | Out of scope for v1; version byte reserves the upgrade path |
| Abuse handling | Client-side unpair/block is the primary remedy, not server bans |
