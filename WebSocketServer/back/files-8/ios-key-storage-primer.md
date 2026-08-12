# iOS Key Storage — Primer

*Read before Phase 1. Everything else depends on getting this right.*

---

## 1. The three places a key can live

| Location | Protection | Extractable? |
|---|---|---|
| App memory | None beyond process isolation | Yes, by anything reading the process |
| Keychain | Encrypted with SEP-derived class keys | Yes, while unlocked — it's designed to hand you the bytes |
| Secure Enclave | Private key never leaves the SEP | **No** |

The distinction that matters: **the Keychain gives you the key material; the Secure Enclave performs operations on your behalf and never reveals the key.** An attacker who dumps memory from a compromised app gets Keychain contents but cannot exfiltrate a reusable SEP key.

---

## 2. Secure Enclave — the constraint that shapes the design

**The Secure Enclave supports P-256 only.** Not Ed25519, not X25519, not RSA, and no symmetric keys.

CryptoKit exposes exactly two SEP types:

```swift
SecureEnclave.P256.Signing.PrivateKey       // ECDSA signatures
SecureEnclave.P256.KeyAgreement.PrivateKey  // ECDH
```

One key does one job — a signing key cannot do key agreement. If you need both, generate two.

This is why the architecture splits: libsignal mandates Curve25519, which the SEP cannot hold, so the SEP protects the **storage key hierarchy** rather than the protocol identity. Being precise about that distinction is worth doing, because a reviewer will ask.

### Persisting a SEP key

The private key never leaves the Enclave, but you get an opaque blob that only *that* Enclave can use:

```swift
let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
    accessControl: SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        [.privateKeyUsage, .biometryCurrentSet],
        nil)!
)
let blob = key.dataRepresentation   // store in Keychain; useless on any other device
```

**The simulator emulates the Secure Enclave in software and does not enforce non-extractability.** Test on hardware or you will not be testing what you think you are.

---

## 3. Keychain accessibility — the single most important constant

```swift
kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

Use this. Understand each half:

- **`WhenUnlocked`** — inaccessible while the device is locked. Correct for message keys: a seized locked device yields nothing.
- **`ThisDeviceOnly`** — never included in backups and never synced to iCloud or a new device. **This is what keeps your keys out of iCloud backup**, and it is not the default.

| Constant | Locked access | In backups |
|---|---|---|
| `WhenUnlocked` | No | Yes ⚠️ |
| `WhenUnlockedThisDeviceOnly` | No | **No** ✅ |
| `AfterFirstUnlock` | Yes, after one unlock | Yes ⚠️ |
| `AfterFirstUnlockThisDeviceOnly` | Yes, after one unlock | No |
| `Always*` | Always | Deprecated — don't |

`AfterFirstUnlock` is what you'd need for background processing, and it weakens the seizure story. Given ADR-003 (synchronous sessions, foreground operation), you don't need it. Choose `WhenUnlockedThisDeviceOnly` and let background access fail loudly.

### Access control flags

| Flag | Meaning |
|---|---|
| `.biometryCurrentSet` | Invalidated if the enrolled biometrics change — **use this** |
| `.biometryAny` | Survives adding a new fingerprint or face ⚠️ |
| `.userPresence` | Biometry or passcode |
| `.devicePasscode` | Passcode only |

`.biometryCurrentSet` is the meaningful one: if an attacker coerces the user into enrolling their own face, keys protected this way become unusable rather than accessible.

---

## 4. CryptoKit

```swift
import CryptoKit

let key = SymmetricKey(size: .bits256)      // zeroed on deallocation
let sealed = try ChaChaPoly.seal(plaintext, using: key)
let plain  = try ChaChaPoly.open(sealed, using: key)

let derived = HKDF<SHA256>.deriveKey(
    inputKeyMaterial: sharedSecret,
    salt: salt,
    info: Data("conv-v1".utf8),
    outputByteCount: 32
)
```

**`SymmetricKey` zeroes its memory on deallocation.** `Data` and `String` do not. Keep key material in `SymmetricKey`, never in `String`, and never build a key by string interpolation — copy-on-write means you cannot track or wipe the copies.

**ChaChaPoly vs AES.GCM:** both are fine. AES-GCM is hardware-accelerated on Apple silicon; ChaChaPoly is constant-time in software. Either is a defensible choice; pick one and be consistent.

**HKDF always needs distinct `info` strings per purpose.** Deriving two different keys from the same secret with the same `info` gives you the same key — a silent, serious bug. Domain-separate everything.

---

## 5. File Data Protection

Independent of the Keychain, and also required:

```swift
try FileManager.default.setAttributes(
    [.protectionKey: FileProtectionType.completeUnlessOpen],
    ofItemAtPath: dbPath
)

var url = URL(fileURLWithPath: dbPath)
var values = URLResourceValues()
values.isExcludedFromBackup = true
try url.setResourceValues(values)
```

| Class | Behaviour |
|---|---|
| `.complete` | Inaccessible while locked. Strongest. |
| `.completeUnlessOpen` | Can stay open across a lock. Right for a database. |
| `.completeUntilFirstUserAuthentication` | Default. Weakest useful option. |
| `.none` | Unencrypted ⚠️ |

**Apply this to `-wal` and `-shm` too.** Forgetting the sidecar files is a standard finding in security audits of iOS apps.

---

## 6. Mistakes to avoid

**Keys in `UserDefaults`.** It's a plist in the app container, entirely unprotected. This still happens in shipped apps.

**Hardcoded keys or salts.** Anything in the binary is extractable with `strings`. Not a secret.

**Omitting `ThisDeviceOnly`.** The most common real-world leak: keys correctly stored, then quietly backed up to iCloud.

**Assuming the simulator matches hardware.** Keychain and SEP semantics differ. Two physical devices, always.

**Not handling "key unavailable."** With `WhenUnlocked`, Keychain reads fail when locked. Fail explicitly and visibly rather than crashing or, worse, falling back to an unprotected path.

**`String` for anything sensitive.** Immutable, copy-on-write, unzeroable. `[UInt8]` you can wipe, or `SymmetricKey` which wipes itself.

**Reusing one key for everything.** Separate keys per purpose, derived with distinct HKDF `info` strings. It costs nothing and it bounds the blast radius of any single compromise.

---

## 7. Verify it works

```swift
#if DEBUG
// The Keychain will happily return data for a query you thought was
// biometry-gated if the access control was constructed wrong.
// Assert the failure case explicitly.
assert(readWithoutBiometry(tag) == nil, "Key is NOT biometry-protected")
#endif
```

The general principle, and it applies to this whole document: **test that the protected path fails when it should, not just that the happy path succeeds.** A key that seems to work may be entirely unprotected — the happy path looks identical either way.

---

## 8. What to read

- Apple Platform Security Guide — the Data Protection and Keychain chapters are the authoritative source and are genuinely well written
- CryptoKit documentation, particularly `SecureEnclave` and `HKDF`
- `03-CRYPTO-SHREDDING.md` §3 for how these pieces assemble into the key hierarchy
