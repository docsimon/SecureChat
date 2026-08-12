# libsignal — Primer

*Read before Phase 2.*

---

## 1. What it is

libsignal is Signal's cryptographic core: a Rust implementation with bindings for Swift, Java, and TypeScript. <cite index="11-1">It is used by the Signal client apps on Android, iOS and Desktop as well as server-side, and the products of the repository are the Java, Swift and TypeScript libraries wrapping the underlying Rust implementations.</cite>

For our purposes the relevant part is the Signal Protocol: X3DH/PQXDH key agreement plus the Double Ratchet. The repo also contains `zkgroup`, `usernames`, `attest`, and `device-transfer`, none of which you need.

---

## 2. Two caveats to settle before writing code

**License: AGPL-3.0-only.** <cite index="9-1">libsignal is licensed under the GNU Affero General Public License v3.0, is specifically designed for use within Signal's applications and services, and the API is subject to change without notice, as are the JNI, C, and Node bridge layers.</cite>

For an open-source portfolio project this is fine — arguably a positive, since it signals you read licenses. It does foreclose closed-source commercialisation. Decide now, because ripping it out later is expensive.

**Unsupported for third parties.** <cite index="11-1">Use outside of Signal is unsupported.</cite> Practically: pin a version, expect breakage on upgrade, and don't expect help with integration issues.

---

## 3. iOS integration

Counterintuitively, **CocoaPods is the supported path, not SPM.** <cite index="2-1">The Swift binding is set up as a CocoaPod for integration into the Signal iOS client, and as a Swift Package for local development.</cite> The Swift Package exists for developing libsignal itself.

<cite index="2-1">The pod requires `use_frameworks!` in your Podfile — LibSignalClient is a Swift pod and cannot be compiled as a plain library — and you add `LibSignalClient` as a dependency along with the prebuild checksum for the latest release, found in the project's GitHub Releases.</cite>

```ruby
use_frameworks!
ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = '<from the GitHub release>'
pod 'LibSignalClient', git: 'https://github.com/signalapp/libsignal.git', tag: 'v<version>'
```

Two knock-on effects worth knowing up front: `use_frameworks!` forces *all* your pods to build as dynamic frameworks, and without the checksum the pod builds the Rust library locally, which needs a Rust toolchain and takes a while.

---

## 4. The mental model

Four concepts. Everything else is detail.

**Identity key** — long-term, per install. Represents "you" to peers.

**Prekeys** — one-time keypairs published in advance so someone can start a session with you while you're offline. Signed prekeys are rotated periodically; Kyber prekeys provide the post-quantum half of PQXDH.

**Session** — the ratchet state for one conversation with one device. Stateful, mutable, and **the thing that breaks if you persist it carelessly**.

**Stores** — five protocols you implement, backed by your own database. libsignal holds no state itself; it calls into your stores for everything.

| Store | Holds |
|---|---|
| `IdentityKeyStore` | Your identity key, peers' identity keys, trust decisions |
| `PreKeyStore` | One-time prekeys |
| `SignedPreKeyStore` | Signed prekeys |
| `KyberPreKeyStore` | Post-quantum prekeys |
| `SessionStore` | Ratchet state per `ProtocolAddress` |

`ProtocolAddress` is `(name, deviceId)`. Since we're one-device-per-identity, `deviceId` is always 1.

---

## 5. The flow

```
INSTALL
  IdentityKeyPair.generate()
  generate registration ID
  generate prekeys, signed prekey, Kyber prekey
  persist all of it in your stores

SESSION START  (adapted — see below)
  receive peer's PreKeyBundle
  processPreKeyBundle(bundle, for: address, sessionStore:, identityStore:, ...)
  → session established, ratchet initialised

SEND
  signalEncrypt(message, for: address, sessionStore:, identityStore:, ...)
  → CiphertextMessage; .messageType is .preKey for the first, .whisper after
  → put the serialized bytes in the relay's `payload` field

RECEIVE
  .preKey  → signalDecryptPreKey(...)
  .whisper → signalDecrypt(...)
```

### The adaptation to our design

Normally the server stores prekey bundles so an absent recipient can still receive messages. **We don't need that.** Both parties are online by construction, so bundles are exchanged live over the relay at session start — as the first two opaque payloads, before any message traffic.

This deletes an entire server component. Worth calling out explicitly in the write-up: it's a case where the product constraint simplified the security architecture rather than complicating it.

---

## 6. Pitfalls

**Session state must be persisted atomically with the operation that changed it.** Every encrypt and decrypt mutates the ratchet. A crash between "ratchet advanced in memory" and "state written to disk" produces a session that can no longer decrypt anything — silently. Wrap store writes and the crypto operation in one transaction.

**Never let two concurrent sends touch the same session.** Two sends deriving the same message key is a catastrophic, silent failure. Serialise per-conversation. Note that an `actor` alone is *not* sufficient if you `await` mid-ratchet — reentrancy lets a second call in. Keep ratchet advancement synchronous.

**Identity key changes need an explicit policy.** When a peer's identity key changes, libsignal asks your `IdentityKeyStore` whether to trust it. Accepting silently means a MITM is undetectable. Given ADR-006, this is one of the few events that *should* interrupt the user loudly.

**Prekey exhaustion.** One-time prekeys are consumed. Track the count and replenish. Less pressing in our design since bundles are exchanged live, but don't assume it's free.

**Errors are `SignalError`.** Decryption failures are normal operational events (duplicate message, out-of-order, unknown session), not crashes. Handle each explicitly.

---

## 7. The alternative worth knowing about

**The Noise Protocol Framework is arguably a better architectural fit than Double Ratchet for what you're building.**

Double Ratchet exists to solve a specific problem: asynchronous, out-of-order, long-lived sessions where the peer may be offline for weeks. That machinery — skipped message keys, chain management, prekeys — is there to handle absence.

You have a synchronous live session with both parties present. That is precisely Noise's design target. `Noise_XX` gives mutual authentication and forward secrecy in a three-message handshake, with far less state. It's what WireGuard uses.

**Why the recommendation is still libsignal:** implementation maturity on Swift. Noise's Swift ecosystem is thin, and an unaudited Noise implementation is worse than an audited Double Ratchet, regardless of architectural elegance.

**Why you should know this anyway:** being able to say *"Double Ratchet is over-engineered for a synchronous session — Noise is the better fit architecturally, but I chose libsignal because implementation maturity outweighs elegance for crypto"* is exactly the kind of reasoning that distinguishes candidates. Put it in ADR-002 and be ready to discuss it.

---

## 8. What to read

- `swift/README.md` in the libsignal repo — build and integration
- `swift/Sources/LibSignalClient/` — the API surface; the source is the documentation
- The Signal Protocol specifications (X3DH, Double Ratchet, PQXDH) on signal.org/docs
- Signal-iOS itself, for how the stores are implemented in practice against a real database

Verify the current version and API against the repo before starting — this library changes without notice and anything written down about it goes stale quickly.
