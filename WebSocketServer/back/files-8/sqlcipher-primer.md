# SQLCipher — Primer

*Read before Phase 3.*

---

## 1. What it is

<cite index="22-1">SQLCipher is a standalone fork of the SQLite database library that adds 256-bit AES encryption of database files and other security features.</cite> It is a drop-in replacement: your SQL is unchanged, and pages are encrypted and decrypted transparently on I/O.

The important property for us: it encrypts the **entire file** — schema, indexes, free pages, everything. An unencrypted index on `conversation_id` would leak the shape of the user's social graph even if message bodies were encrypted separately. SQLCipher closes that.

---

## 2. SQLCipher 4 defaults

<cite index="27-1">Version 4 raised the default page size to 4096 bytes, increased default PBKDF2 iterations to 256,000, and switched the default KDF and HMAC algorithms to PBKDF2-HMAC-SHA512 and HMAC-SHA512 respectively.</cite>

| Parameter | Default |
|---|---|
| Cipher | AES-256-CBC |
| Page size | 4096 bytes |
| KDF | PBKDF2-HMAC-SHA512, 256,000 iterations |
| Page authentication | HMAC-SHA512 |
| Salt | 16 bytes, stored in the file header |

Each page gets its own random IV and its own HMAC, so tampering with any page is detectable.

**Version compatibility bites.** SQLCipher 4 will not open databases created by 3.x without explicit compatibility pragmas or `PRAGMA cipher_migrate`. Pin your version and record it.

---

## 3. Licensing

<cite index="18-1">SQLCipher.swift is distributed under a BSD-style license requiring attribution and reproduction of the license in applications and documentation, and is the official Swift Package for SQLCipher maintained by Zetetic, LLC.</cite>

Community Edition is free with attribution. Commercial editions exist, and <cite index="20-1">when using Commercial or Enterprise packages you must call `PRAGMA cipher_license` with a valid license code — failure to do so results in an `SQLITE_AUTH(23)` error.</cite> Community Edition needs no such call; if you see `SQLITE_AUTH(23)`, you've picked up a commercial build by accident.

Much friendlier than libsignal's AGPL. No copyleft obligation on your app.

---

## 4. Integration

**Official:** <cite index="22-1">add `https://github.com/sqlcipher/SQLCipher.swift` via File > Add Packages, then set `SQLITE_HAS_CODEC=1` in Preprocessor Macros for both Debug and Release.</cite>

**The `SQLITE_HAS_CODEC` flag is not optional and its failure mode is dangerous:** without it the library silently behaves as plain SQLite and writes an unencrypted database. Add a startup assertion (§7) rather than trusting the build setting.

Alternatives: `skiptools/swift-sqlcipher` bundles SQLite plus SQLCipher with a Swift query interface; GRDB has a SQLCipher configuration if you want its ergonomics.

---

## 5. Raw key mode — use this

<cite index="20-1">An application can tell SQLCipher to use a specific binary key in blob notation, and SQLCipher requires exactly 256 bits of key material:</cite>

```sql
PRAGMA key = "x'2DD29CA851E7B56E4697B0E1F08507293D761A05CE4D1B628663F411A8086D99'";
```

Exactly 64 hex characters. This **skips the KDF entirely**.

That is what you want. Our database key comes from the Secure Enclave-backed hierarchy — it is already 256 bits of uniform random. Running 256,000 rounds of PBKDF2 over a random key adds startup latency and buys nothing; PBKDF2 exists to stretch *low-entropy passphrases*. Using passphrase mode here would be a small but telling mistake, and precisely the kind a reviewer notices.

You may also supply a 32-hex-character salt appended to the key (96 hex total) to control the header salt explicitly.

---

## 6. Opening a database, in order

Order matters — the key must be set before any other operation on the connection.

```swift
sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
exec("PRAGMA key = \"x'\(hexKey)'\"")     // FIRST. Always.
exec("PRAGMA cipher_memory_security = ON") // zeroes internal buffers; costs performance
exec("PRAGMA secure_delete = ON")          // zero freed pages within the file
exec("SELECT count(*) FROM sqlite_master") // ← this is what actually verifies the key
```

**A wrong key does not fail at `PRAGMA key`.** It fails on the first read, with `SQLITE_NOTADB`. Always perform a verification read immediately, or you'll get confusing errors much later.

Other pragmas worth knowing:

| Pragma | Use |
|---|---|
| `rekey` | Re-encrypts every page with a new key — the basis of the shred sweep in `03` §5 |
| `cipher_memory_security` | Zeroes internal allocations; measure the cost before enabling in release |
| `cipher_plaintext_header_size` | Leaves the first N bytes unencrypted so tools can identify the file. Requires storing the salt separately. Only if you need it. |
| `cipher_migrate` | Upgrading databases from older SQLCipher versions |

---

## 7. iOS gotchas

**The WAL and SHM files.** `-wal` and `-shm` sit alongside the database and are also encrypted, but they need the same file-protection class and the same backup exclusion. Forgetting them is a classic leak.

**File protection.** Use `.completeUnlessOpen` on the database and its sidecars, and `isExcludedFromBackup = true`. With `.complete`, a background wake with the device locked cannot open the database at all — decide which you want and handle the failure explicitly rather than crashing.

**Never hold the key in a `String`.** Swift strings are immutable, copy-on-write, and cannot be reliably zeroed. Build the hex key in a `[UInt8]`, pass it, then zero the buffer. Yes, SQLCipher copies it internally — `cipher_memory_security` covers that side; your side is still your responsibility.

**Verify encryption at startup, in debug:**

```swift
// A SQLCipher database has no readable header. Plain SQLite files begin
// with the ASCII string "SQLite format 3". If you can read it, you are
// writing plaintext.
assert(!fileBeginsWithSQLiteMagic(path), "Database is NOT encrypted")
```

This assertion catches the `SQLITE_HAS_CODEC` failure mode, which is otherwise invisible until someone dumps the file.

**`VACUUM` rewrites the whole database.** Useful for the sweep, expensive on large databases, and it needs free space equal to the database size.

---

## 8. How it fits the shredding design

SQLCipher is the **outer** layer. It has one key for the whole file, so it cannot express "destroy this one conversation" — rekeying to shred one conversation would destroy every conversation.

Shred granularity comes from the **inner** envelope layer: per-conversation keys encrypting message bodies before they reach SQLite.

| Layer | Protects | Key |
|---|---|---|
| SQLCipher | Schema, indexes, metadata, free pages | One `DatabaseKey` |
| Envelope | Message bodies | Per-conversation |

Both are necessary. Neither replaces the other. `03-CRYPTO-SHREDDING.md` §3 has the full hierarchy.

---

## 9. What to read

- zetetic.net/sqlcipher/documentation — the pragma reference, which is the real manual
- The design page on how page encryption and HMAC work — worth understanding before you rely on it
- `03-CRYPTO-SHREDDING.md` §5 for how `rekey` and `VACUUM` combine into the sweep
