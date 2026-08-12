# 05 — Roadmap

**Objective:** a small, complete, correct application plus documentation that demonstrates security judgement. Not a feature-complete messenger.

The failure mode to avoid: an ambitious app that is 70% done in five areas. Ship narrow and finished.

---

## Phase 1 — Onboarding and transport

*Goal: two devices can register and exchange plaintext frames.*

- [ ] Directory service: SMS OTP registration, phone-hash + identity key binding
- [ ] Registration lock PIN, delay window, notification to existing devices
- [ ] Contact discovery: peppered hashing, rate limits, no query logging
- [ ] Relay deployed (`relay-server.mjs` is already written and needs no changes)
- [ ] iOS: `RelayConnection` actor, signed-nonce auth, frame codec
- [ ] Secure Enclave identity key generation

**Done when:** a new user installs, registers, sees which contacts have the app, and connects — with no manual steps.

**Read first:** `learning/ios-key-storage-primer.md`

---

## Phase 2 — Real end-to-end encryption

*Goal: messages are encrypted end to end.*

- [ ] libsignal integrated, version pinned
- [ ] The five protocol stores, backed by SQLCipher, written atomically
- [ ] Prekey bundle exchange over the relay at session start (no prekey server)
- [ ] Local outbox with expiry
- [ ] Delivery states: queued / delivered / read / dropped, visually distinct
- [ ] Safety numbers in settings; loud interrupt on identity key change

**Done when:** two devices hold a conversation, the relay operator sees only ciphertext, and killing the app mid-session doesn't corrupt ratchet state.

**Read first:** `learning/libsignal-primer.md`

---

## Phase 3 — Storage and shredding

*Goal: the differentiator, done properly.*

- [ ] SQLCipher, raw-key mode, `SQLITE_HAS_CODEC=1`
- [ ] Key hierarchy: per-conversation SEP keys, derived conversation keys
- [ ] Envelope encryption on the message table
- [ ] Shred operation, full ordered sequence
- [ ] Timers: monotonic + wall clock, eager check on launch
- [ ] **Leak-path audit** — every row in `03-CRYPTO-SHREDDING.md` §6, signed off individually
- [ ] Verification suite — all seven tests in `03` §9
- [ ] Rekey sweep

**Done when:** the verification suite passes, including the memory-scan and kill-during-shred tests.

**Read first:** `learning/sqlcipher-primer.md`, then `03-CRYPTO-SHREDDING.md`

---

## Phase 4 — The documentation deliverable

*Goal: the artifact that does the hiring work.*

- [ ] `SECURITY.md` — guarantees, non-goals, honest limits, written for a skeptical reader
- [ ] Threat model finalised against what was actually built
- [ ] ADRs current, including anything that changed during the build
- [ ] Architecture diagram
- [ ] A written record of the security bugs you found in your own code and how you fixed them

That last item is worth more than it looks. Every real system has them; a candidate who documents their own findings demonstrates the security mindset better than one whose repo implies they wrote it perfectly first time.

---

## Deliberately not building

Keep this list in the README. It demonstrates scope discipline, which is rarer and more valuable than ambition — and it pre-empts the obvious interview question.

| Not building | Why |
|---|---|
| Group messaging | Membership consistency is a project of its own |
| Multi-device | Requires key sync; a subsystem, not a feature |
| Voice / video | Different protocol stack entirely (SRTP, ICE, TURN) |
| Attachments | Separate key management, thumbnail and cache leak paths |
| Android | One platform, done properly |
| Tor / anonymity | ADR-001 — different product |
| Key transparency | Correct, but post-v1. Named as the top open risk. |
| Private set intersection | Correct, but post-v1. Limitation documented. |
| Backup / recovery | Contradicts the shredding guarantee, by design |
| Duress mode | Post-v1 |

---

## Ordering notes

**Build against the relay from day one**, plaintext, before touching libsignal. Debugging an auth handshake and a ratchet simultaneously is a bad week, and every failure looks identical.

**Write the threat model in Phase 1, not Phase 4.** Drafting it early changes what you build; writing it at the end just describes what you happened to build. Revise it as things change — the revision history is itself evidence.

**The leak-path audit is not a checklist to rush.** It is the part of the project a security engineer will probe hardest, because it's where most real-world E2E apps actually fail.

**Test with two physical devices**, not two simulators. Simulator keychain and Secure Enclave behaviour differ from hardware in ways that will hide bugs — the Enclave is emulated in the simulator and does not enforce non-extractability.
