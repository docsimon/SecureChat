# 04 — Architecture Decision Records

> ADRs are the cheapest way to demonstrate engineering judgement. A reviewer reading these learns more about how you think than they would from the code. Each records what was decided, what was rejected, and what it cost — including the decisions that reversed earlier ones.

---

## ADR-001 — Drop Tor; scope the product to confidentiality

**Status:** accepted — supersedes the earlier Tor transport design

**Context.** The design initially targeted anonymity: Tor transport, onion services, no phone numbers, manual pairing. That produced an unusable onboarding flow — 30 manual pairings, each with a verification ceremony — which conflicted directly with the user-experience pillar.

**Decision.** Build a *confidentiality* product. Phone-number onboarding, TLS transport, no Tor.

**Rationale.** Confidentiality and anonymity are different properties with different costs. Tor buys anonymity, which is now out of scope; it costs a 5–30 second bootstrap and 200–800 ms RTT, which directly damages the pillar we care about most. Carrying that cost without claiming the benefit is the worst of both.

**Consequences.**
- Relay learns IP addresses and session timing. Accepted, documented in `02-THREAT-MODEL.md` §2/A2.
- Onboarding becomes competitive with mainstream messengers.
- Users needing anonymity must be directed elsewhere, in-app.
- The Tor material is retained as background reading, clearly marked superseded.

**Rejected:** keeping Tor as an optional toggle. Two transports means two threat models, two sets of failure modes, and a settings switch most users cannot evaluate. Ship one, correctly.

---

## ADR-002 — Use libsignal rather than implementing the protocol

**Status:** accepted

**Decision.** Integrate libsignal for session establishment and message encryption.

**Rationale.** Hand-rolled cryptography is the single strongest negative signal in a security portfolio, regardless of quality. "I integrated the audited implementation" is the correct engineering answer and the one a hiring reviewer wants to hear. The time saved goes into the areas where original work *is* valuable: key lifecycle, secure deletion, iOS leak paths.

**Consequences.**
- **AGPL-3.0.** libsignal is licensed AGPL-3.0-only. For an open-source portfolio project this is fine and arguably desirable. It forecloses closed-source commercialisation — decide now if that matters.
- Signal states that use outside Signal is unsupported and the API may change without notice. Pin a version; expect to do integration work on upgrades.
- iOS integration is via CocoaPods with `use_frameworks!`; the Swift Package is intended for local development of libsignal itself, not consumption.
- Post-quantum key agreement (PQXDH) comes free.

**Rejected:** implementing Double Ratchet from the specification. Correct-looking and subtly broken is the default outcome, and it inverts the hiring signal.

**Noted, not rejected:** the Noise Protocol Framework is arguably the *better architectural fit* — Double Ratchet exists to handle asynchronous, out-of-order, long-lived sessions, and you have a synchronous live session, which is precisely Noise's design target. The blocker is implementation maturity on Swift, not the protocol. Being able to articulate this tradeoff in an interview is worth more than either choice. See `learning/libsignal-primer.md` §7.

---

## ADR-003 — Keep synchronous sessions; add a local outbox

**Status:** accepted

**Decision.** Messages are only deliverable when both parties are connected. Undeliverable messages queue **on the sender's device**.

**Rationale.** The synchronous constraint is what removes server-side storage, which is the product's core claim. But a UX that silently discards messages is unusable. A local outbox preserves the property — the server still stores nothing — while removing the sharp edge.

**Consequences.**
- Three distinct delivery states, always visually separate: queued, delivered, dropped.
- Outbox entries need a user-visible expiry.
- **If the queue ever moves server-side, the product's central claim is void.** Treat this as a hard invariant in code review.

---

## ADR-004 — Phone-number identity, with a directory

**Status:** accepted

**Decision.** Bind identity to a phone number via SMS OTP; run a directory for registration and contact discovery.

**Rationale.** Seamless onboarding requires discovery; discovery requires a directory. The trilemma — *no trusted directory · phone-number discovery · no verification ceremony* — allows any two. We choose the last two.

**Consequences.**
- A persistent server-side table binding phone numbers to keys exists and is seizable. This is the largest single concession in the design.
- **The directory can MITM** by serving a false identity key. Currently the top open risk (`02-THREAT-MODEL.md` §6).
- Registration lock is mandatory, not a nice-to-have.
- Discovery must be documented honestly — peppered hashing does not blind the operator.
- Discovery is separate from the relay and touched only when adding contacts.

**Deferred:** key transparency, which converts the directory from *trusted* to *auditable*. This is the right long-term answer and should be the first post-v1 security project.

---

## ADR-005 — Crypto-shredding rather than row deletion

**Status:** accepted

**Decision.** Destroy per-conversation keys; treat row deletion as hygiene.

**Rationale.** Flash storage makes overwrite-in-place unavailable to applications; deleted rows are recoverable. Apple's own "Erase All Content and Settings" uses the same technique for the same reason.

**Consequences.**
- Two encryption layers: SQLCipher whole-file, plus per-conversation envelopes for shred granularity.
- Per-conversation Secure Enclave keys.
- The guarantee is probabilistic, not absolute, and must be documented as such — see `03-CRYPTO-SHREDDING.md` §7.
- No backup or recovery is possible. Must be stated at onboarding.

---

## ADR-006 — No verification ceremony in the default flow

**Status:** accepted

**Decision.** Safety numbers exist in settings and can be compared voluntarily. Onboarding does not require them.

**Rationale.** Users click through security ceremonies without reading them, so a mandatory ceremony provides the *appearance* of verification while damaging onboarding. Better to make the default path fast and reserve interruption for events that genuinely warrant it.

**Consequences.**
- Trust-on-first-use against the directory, by default. Documented.
- **An identity key change must interrupt loudly** — that is the one event worth a user's attention.
- Verification quality depends on key transparency arriving later.

---

## ADR-007 — Single platform, single product surface

**Status:** accepted

**Decision.** iOS only. No group messaging, no multi-device, no voice, no video, no attachments in v1.

**Rationale.** A small, complete, correct application beats an ambitious half-finished one, decisively, for the stated goal. Each excluded feature carries a security design problem of its own — groups need membership consistency, multi-device needs key sync, attachments need separate key management and thumbnail leak paths.

**Consequences.** The "deliberately not building" list in `05-ROADMAP.md` is itself an artifact worth showing; it demonstrates scope discipline, which is rarer than ambition.

---

## ADR-008 — AI-assisted development, scoped and disclosed

**Status:** accepted

**Decision.** Use agentic tooling for scaffolding, tests, documentation, and refactoring. Do not use it to originate cryptographic design or key-handling code. Disclose this in the README.

**Rationale.** Agentic pipelines are a legitimate skill worth showcasing. But "I generated a cryptosystem with an agent" reads as a red flag to the exact audience being targeted. Separating the two — and saying which is which — demonstrates judgement about where the tooling is appropriate.

**Consequences.** Security-critical paths need human-reviewed provenance. Consider a `CODEOWNERS`-style annotation marking which modules were hand-written.
