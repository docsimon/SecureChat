# 02 — Threat Model

> This is the document a security engineer will read first. It is the highest-signal artifact in the project, because an accurate statement of limitations demonstrates more than a long list of features. Write it before the code, and keep it honest as the code changes.

---

## 1. What is being protected

| Asset | Priority |
|---|---|
| Message content in transit | Critical |
| Message content at rest on device | Critical |
| Ability to destroy history irrecoverably | Critical — the differentiator |
| Contact list | High |
| Who talks to whom | Medium — **partially exposed, see §4** |
| When people talk | Low — **exposed, accepted** |
| Who uses the app at all | **Not protected** |

---

## 2. Adversaries in scope

### A1 — Passive network observer

*Reads traffic on the wire (ISP, café Wi-Fi, national backbone).*

Sees: TLS metadata, that a device contacts the relay, connection timing, approximate message sizes.
Cannot see: message content.

**Mitigation:** TLS in transit, E2E inside it, message padding to fixed buckets.

### A2 — Compromised or malicious relay operator

*Full control of the relay process.*

Sees: routing UUIDs, which pair is connected, session timing, IP addresses, message sizes.
Cannot see: content; cannot MITM sessions, because key agreement is authenticated by identity keys the relay does not hold.
Cannot retain: anything — the relay writes nothing to disk.

**Mitigation:** zero-knowledge relay design; ephemeral rooms; capacity 2; opaque payloads.
**Residual:** the pairing and timing are visible while a session is live. **Accepted.**

### A3 — Compromised directory operator

*Controls registration and discovery.*

**This is the strongest adversary in the model, and the honest weak point.** A malicious directory can serve an attacker-controlled identity key for a contact and MITM every session with that contact, silently.

**Mitigation:** safety numbers available in-app for users who choose to verify; alert loudly on identity key change.
**Not mitigated in v1:** key transparency. Until it exists, the directory must be trusted. **Document this as the top open risk.** Do not claim otherwise.

### A4 — Device seizure, after the fact

*Adversary obtains the device later, possibly unlocked.*

**Mitigation:** crypto-shredding of expired conversations; forward secrecy via Double Ratchet protects past sessions even if current keys leak; `WhenUnlockedThisDeviceOnly` keys are inaccessible on a locked device.
**Residual:** anything not yet expired is readable on an unlocked device. That is inherent — see `03-CRYPTO-SHREDDING.md` §7.

### A5 — Opportunistic local attacker

*Briefly borrows an unlocked phone.*

**Mitigation:** biometric gate on app open; no message content in notifications; screen obscured in the app switcher.

### A6 — SIM swap / number recycling

*Attacker takes control of the phone number.*

**Mitigation:** registration lock PIN, mandatory delay window, notification to existing devices.
Without this, everything else is bypassed by a carrier support call.

---

## 3. Explicit non-goals

State these as prominently as the guarantees. Overclaiming is the failure mode that discredits a security product.

**Anonymity.** The relay sees IP addresses and session timing; the directory holds a phone-number binding. Users are identifiable to the infrastructure and to anyone who compels it. **This is a confidentiality tool, not an anonymity tool.** Users who need anonymity should use Briar, Cwtch, or Ricochet Refresh — say so in the app.

**Metadata resistance.** Message timing, frequency, and approximate size are observable. Traffic-analysis defence would require constant-rate cover traffic, which is out of scope.

**Endpoint compromise.** Malware, a jailbroken device, or a hostile OS defeats everything. No protocol fixes a compromised endpoint.

**Coercion.** Rubber-hose cryptanalysis. There is no duress mode in v1.

**Screenshots and recipient behaviour.** The recipient can photograph the screen. Disappearing messages protect against later seizure, not against a determined recipient. Say this in onboarding — users routinely misunderstand it.

**Availability.** No DDoS resistance, no censorship circumvention, no domain fronting.

**Group messaging.** Out of scope. Groups introduce membership consistency problems that are a project of their own.

**Backup and recovery.** By design, there is none. A lost device is lost history. This is a deliberate consequence of the shredding guarantee and must be stated at onboarding, not discovered later.

---

## 4. Trust assumptions

We assume, and depend on:

- **Apple's Secure Enclave and Data Protection** behave as documented.
- **The directory operator is honest at registration time** — until key transparency exists. Top open risk.
- **libsignal is correctly implemented.** We do not audit it; we rely on the fact that others have.
- **The user's device is not already compromised** at install.
- **TLS and the CA system** function for the client-to-server hop.

Each of these is a real dependency. Listing them is not weakness — an unstated assumption is a vulnerability, a stated one is a design boundary.

---

## 5. Attack surface

| Surface | Exposure | Notes |
|---|---|---|
| Relay WebSocket | Public | Auth required within 10s, rate-limited, 128 KiB frame cap |
| Directory API | Public | Rate limits are the primary defence; enumeration is the risk |
| SMS OTP | Third party | Carrier and SMS gateway are outside our trust boundary |
| Push notifications | Apple | Apple learns contact timing; payloads carry no content |
| Local database | On-device | SQLCipher + envelope encryption |
| Keychain / Enclave | On-device | `ThisDeviceOnly`, biometric-gated |
| Pasteboard, screenshots, backups | On-device | See `03-CRYPTO-SHREDDING.md` §6 |

---

## 6. Known unresolved risks

Keep this list visible and current. Shrinking it over time is the project's progress metric.

| # | Risk | Severity | Plan |
|---|---|---|---|
| 1 | Directory can MITM by serving a false identity key | **High** | Key transparency, post-v1. Safety numbers available meanwhile. |
| 2 | Contact discovery is not private from the operator | Medium | Documented; PSI or enclave is post-v1 |
| 3 | Session timing visible to relay | Medium | Accepted — inherent to dropping Tor |
| 4 | Crypto-shredding is probabilistic, not a mathematical guarantee | Medium | See `03` §7 — layered, documented, swept |
| 5 | SMS OTP is phishable and SIM-swappable | Medium | Registration lock reduces impact |
| 6 | No duress or panic mode | Low | Post-v1 |

---

## 7. What "secure" means here, stated for users

The plain-language version, for onboarding and the App Store listing. If the marketing copy claims more than this paragraph, the marketing copy is wrong.

> Your messages are encrypted so that only you and the person you're talking to can read them — not us, not your network, not anyone who seizes our servers. We never store messages. On your phone, messages are encrypted and destroyed on the schedule you choose, in a way that makes them genuinely unrecoverable.
>
> We can see *that* you use the app and *when* you connect. We cannot see what you say. If you need to hide the fact that you are communicating at all, this app is not the right tool — try Briar or Cwtch.
