# 03 — Crypto-Shredding

**This is the differentiating subsystem.** Most "disappearing messages" features delete database rows, which does not destroy data on flash storage. This document specifies destroying keys instead, and — just as importantly — states precisely how strong that guarantee is and where it stops.

---

## 1. Why deleting doesn't delete

An app on iOS has no ability to overwrite a specific physical location on flash. Five reasons, all of which apply simultaneously:

**The Flash Translation Layer.** The SSD controller maps logical block addresses to physical NAND pages and moves them freely. `write(lba, data)` writes to a *new* physical page and remaps; the old page keeps the old content until the controller reuses it. There is no `overwrite in place` primitive to reach for.

**Wear levelling.** The controller deliberately spreads writes across the device to equalise erase cycles, actively working against overwriting the same physical location.

**Over-provisioning.** Devices reserve 7–28% of capacity invisible to the filesystem. Stale copies live there, unreachable by any file API.

**TRIM is advisory.** It tells the controller a block is unused. When and whether it is physically erased is the controller's decision, not the OS's, and not the app's.

**SQLite makes copies.** WAL files, rollback journals, temp files, and `VACUUM` all write copies of page contents elsewhere. `DELETE FROM messages` can leave the plaintext in three other files.

The consequence: **on flash, "delete" means "unlink the reference." The bytes remain until the controller happens to reuse the block, which may be never.** A forensic tool reading raw NAND recovers them.

---

## 2. The precedent: Apple already does this

Crypto-shredding is not an exotic technique — it is how "Erase All Content and Settings" completes in seconds on a 1 TB device rather than in hours.

iOS Data Protection encrypts every file with a per-file key, which is wrapped by a class key, which is ultimately protected by keys held in **Effaceable Storage** — a small region built specifically to be reliably erased. Wiping the device destroys that key material; every byte of user data on the flash instantly becomes indistinguishable from noise.

Cite this precedent in your write-up. It is the strongest possible argument that the design is correct rather than clever: Apple faced the same physics and reached the same answer.

---

## 3. Key hierarchy

Two layers, each doing what it's good at.

```
┌─ SecureEnclave.P256.KeyAgreement.PrivateKey  (one per conversation)
│    private key material never leaves the SEP
│    encrypted blob stored in Keychain, ThisDeviceOnly + biometryCurrentSet
│
├─► sharedSecret = SEP_key ⋅ storedEphemeralPublicKey
│
├─► ConversationKey = HKDF(sharedSecret,
│                          salt: conversationSalt,   ← row inside SQLCipher DB
│                          info: "conv-v1")
│
└─► MessageKey_n   = HKDF(ConversationKey,
                          salt: messageNonce,        ← per-row random
                          info: "msg-v1")

Separately:
   DatabaseKey (256-bit random) → SQLCipher whole-file encryption
       wrapped by its own SEP key, protects schema, indexes, metadata
```

### Why two layers

**SQLCipher** encrypts the entire file — including indexes, table names, and free pages. Without it, an index on `conversation_id` leaks the shape of your social graph even if message bodies are encrypted.

**The envelope layer** provides *shredding granularity*. SQLCipher has one key for the whole database, so it cannot express "destroy this one conversation." The per-conversation key can.

Neither substitutes for the other. Reviewers ask about this; the answer is granularity, not paranoia.

---

## 4. Shredding a conversation

Ordered, and each step matters:

```
1. Zeroise ConversationKey and any derived MessageKeys in memory
2. Delete the SEP key blob from the Keychain
3. Overwrite then delete the conversationSalt row
4. DELETE the message rows
5. Checkpoint and truncate the WAL
6. Delete cached attachments, thumbnails, and search-index entries
7. Mark the DB for a sweep (§5)
```

Steps 1–3 are the security mechanism. Steps 4–6 are hygiene: they remove the easy paths and shrink the surface, but they are *not* what makes the data unrecoverable.

Enable `PRAGMA secure_delete = ON` so SQLite zeroes freed content within the file. It doesn't defeat the FTL, but it costs almost nothing and closes the trivial case.

---

## 5. The sweep — dealing with remnants

Deleting a Keychain item has the *same* flash problem: the Keychain is itself a database file, and the deleted blob may persist in unallocated space.

The answer is a periodic **rekey sweep**:

```
PRAGMA rekey = "x'<new 256-bit key>'"   -- rewrites every page under a new key
VACUUM                                  -- compacts, orphaning old pages
destroy the old DatabaseKey
```

Every page is physically rewritten to new locations under a key that no longer exists. Old remnants become ciphertext under a destroyed key. Run this opportunistically — on charge, on Wi-Fi, when idle — not on every burn.

This does not *guarantee* remnants are gone. It steadily converts them from "recoverable plaintext" into "ciphertext under a key that was destroyed."

---

## 6. What else holds plaintext

Shredding the database is worthless if a copy sits somewhere else. Audit every one of these; each has leaked from an otherwise-correct app:

| Path | Mitigation |
|---|---|
| Notification payloads | Generic text only. Never message content. |
| App-switcher snapshot | Cover the window in `sceneWillResignActive` — `didEnterBackground` is too late |
| iCloud / iTunes backup | `ThisDeviceOnly` keychain items; `isExcludedFromBackup` on the DB and WAL |
| Keyboard learned words | `autocorrectionType = .no`, `spellCheckingType = .no`. Consider blocking third-party keyboards, which see every keystroke |
| Pasteboard | System-wide and Handoff-synced. Mark items `.localOnly` with expiry, or disable copy |
| Spotlight / Core Spotlight index | Do not index message content. At all. |
| Crash and analytics SDKs | Remove them, or guarantee no message data reaches them |
| Attachment caches, thumbnails | Same key hierarchy as messages; shred together |
| Memory | `SymmetricKey` zeroes on deallocation. Swift `String` does not, is copy-on-write, and cannot be reliably wiped — keep plaintext in `[UInt8]` and zero it explicitly |
| Screenshots | Cannot be prevented. `userDidTakeScreenshotNotification` at least lets you notify the peer |

---

## 7. The honest limits

**Write this section into `SECURITY.md` verbatim.** Claiming a guarantee you don't have is how a security product loses credibility; stating the limit precisely is how it earns trust.

Crypto-shredding raises recovery from *trivial with off-the-shelf forensic tools* to *requires all of the following simultaneously*:

- recovering a specific deleted encrypted blob from unallocated flash,
- on the original device, since the SEP key is device-bound and non-extractable,
- with the device unlocked and biometrics satisfied,
- plus recovering the deleted salt row from inside an encrypted database file,
- before a rekey sweep has rewritten the pages.

That is an enormous increase in cost. **It is not a mathematical guarantee of erasure**, and it should never be described as one.

Also unprotected, and worth stating plainly:
- Messages that have not yet expired, on an unlocked device.
- Anything the recipient copied, screenshotted, or photographed.
- Plaintext in memory while a conversation is open.
- A device compromised at the OS level.

---

## 8. Timer design

The details here are where naive implementations break.

**Clock rollback.** A user (or attacker) who sets the device clock backwards must not extend a message's life. Store both a wall-clock deadline and a monotonic reference (`ContinuousClock` / boot-relative time), and expire on **whichever fires first**.

**Background execution.** iOS suspends apps; timers do not fire reliably. Never depend on a scheduled task for deletion. Instead, **check and shred eagerly on every app launch and foreground** — before rendering any UI. A message whose deadline passed while the app was suspended must never be displayed.

**Timer starts.** Decide and document: on send, on delivery, or on read? "On read" is what users expect but requires a receipt from the peer, which they can withhold. Recommend: on delivery, with the peer's independent timer starting on their receipt.

**Per-conversation, not global.** The key hierarchy gives per-conversation timers for free. Use it.

**Failure mode.** If shredding fails — Keychain error, DB locked — it must be retried and surfaced, never silently swallowed. A burn that quietly failed is the worst outcome in the whole system, because the user has been told it succeeded.

---

## 9. Verification

Do not claim the property without testing it. These tests belong in the repo and are themselves a hiring signal:

1. **Ciphertext test.** Write known plaintext, close, `hexdump` the DB. The marker string must not appear. Extend to WAL, SHM, and journal files.
2. **Plain-SQLite test.** Open the file with unmodified SQLite. It must fail, not degrade.
3. **Post-shred test.** Shred a conversation, then attempt decryption with the hierarchy reconstructed as far as possible. It must fail.
4. **Keychain-absence test.** Assert the SEP blob is gone after shredding.
5. **Memory test.** After shredding, scan the process heap for the plaintext marker. Requires care with Swift's CoW semantics — this test is the one that catches real bugs.
6. **Clock-rollback test.** Set the deadline, move the clock back an hour, relaunch. Message must still be gone.
7. **Kill-during-shred test.** SIGKILL mid-shred, relaunch. The system must complete or safely retry — never leave a half-shredded conversation readable.

---

## 10. Implementation order

1. Key hierarchy and `KeyHierarchy` type, with tests, **before** any storage code
2. SQLCipher integration, raw-key mode (see `learning/sqlcipher-primer.md`)
3. Envelope encryption on the message table
4. Shred operation with the full ordered sequence in §4
5. Timers, with clock-rollback and launch-time eager checks
6. The leak-path audit in §6 — treat it as a checklist with sign-off
7. The verification suite in §9
8. Rekey sweep last — it's an optimisation over the guarantee, not part of it
