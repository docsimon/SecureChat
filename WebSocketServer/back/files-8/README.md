# Ephemeral Messenger — Documentation

**Product:** a confidentiality-focused iOS messenger. Messages exist only while both parties are present; nothing is stored on any server; local history is destroyed by key, on a timer the user controls.

**Explicitly not:** an anonymity tool. See `dev/02-THREAT-MODEL.md`.

---

## Development docs — the specification

Read in order. These define what gets built.

| Doc | Purpose |
|---|---|
| `dev/01-ARCHITECTURE.md` | System design, layers, wire protocol, module layout |
| `dev/02-THREAT-MODEL.md` | Who you defend against, and the non-goals. **The single highest-signal artifact in this project.** |
| `dev/03-CRYPTO-SHREDDING.md` | Deep dive on the differentiating feature |
| `dev/04-DECISIONS.md` | ADRs — every significant choice and what it cost |
| `dev/05-ROADMAP.md` | Build order, scope discipline, definition of done |

## Learning docs — the primers

Background for the libraries you haven't used. Read the relevant primer before starting the phase that needs it.

| Doc | Read before |
|---|---|
| `learning/ios-key-storage-primer.md` | Phase 1 — everything depends on it |
| `learning/sqlcipher-primer.md` | Phase 3 |
| `learning/libsignal-primer.md` | Phase 2 |

## Code

| File | Status |
|---|---|
| `relay-server.mjs` | Current. Signed-nonce auth, ephemeral rooms, opaque payloads. |
| `server.mjs` | **Superseded.** First-pass test harness, kept for reference only. |

## Superseded

`ARCHITECTURE.md` and `TOR-TRANSPORT.md` in the parent directory were written for an anonymity-scoped product and are **wrong for the current design**. `dev/01-ARCHITECTURE.md` replaces the first. The Tor doc is retained as background reading only — the decision to drop it is ADR-001.

---

## The short version

Three pillars, and what each one actually forces:

**Simplicity** → use audited libraries, not hand-rolled crypto. Cut anything that doesn't serve confidentiality. One platform, one product surface.

**Confidentiality** → E2E on the wire, encrypted at rest, nothing on the server, honest documentation of what leaks anyway.

**User first** → phone-number onboarding with no verification ceremony, a local outbox so the synchronous constraint doesn't punish anyone, and delivery states that never lie.

If a proposed feature doesn't serve one of those three, it's out of scope. Write it in `dev/05-ROADMAP.md` under "deliberately not building" and move on — that list is itself a hiring signal.
