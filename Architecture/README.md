# Reference app — attestation & assertion

Illustrative source for `attestation-assertion-workflow.md`. Not a compiled Xcode
project; drop the files into a project with the App Attest entitlement.

```
Packages/AppAttestKit/          local SPM package
  Sources/AppAttestKit/
    AttestationState.swift      resumable state machine
    AttestationError.swift      coarse taxonomy + the cardinal rule
    Seams.swift                 5 protocols, 2 internal / 3 public
    LiveImplementations.swift   DCAppAttestService + Keychain wrappers
    AttestationCoordinator.swift THE module. actor, dedup, retry, ordering
  Tests/                        orchestration tests + mocks

App/
  Identity/IdentityKeyStore.swift    X25519 — APP-owned
  Registration/AuthTransport.swift   endpoints — APP-owned
  Registration/RegistrationViewModel.swift  flow state; builds clientDataHash
  Session/SessionClient.swift        assertion flow; stubbed chat
  Views/                             SwiftUI — never reusable
  ChatApp.swift                      entry point
```

## The one thing to look for

**The app never touches a `keyId`.** Search for it — it appears only inside the
package. `AttestServicing` and `AttestationKeyStore` are `internal`, so the app
*cannot* reach around the coordinator to call `attestKey` or write a key itself.

## Ownership at a glance

| Concern | Owner |
|---|---|
| X25519 identity key | App |
| `clientDataHash = SHA256(challenge ‖ IK_pub)` | App (closure) |
| Endpoints, wire format | App |
| Account UUID | App |
| *When* / *what* to sign | App |
| `keyId` lifecycle + persistence | Module |
| Attestation caching | Module |
| Retry policy | Module |
| `sign()` | Module |

## Known gaps

- **§8 blocker** — re-attestation after `.keyInvalid` clears state and starts
  over, which the server (idempotent on `keyId`) will reject or duplicate. The
  proof-of-possession path is not implemented because the contract is undecided.
- **Not compiled.** No Swift toolchain here. Treat as a design reference.
- **`DCError` mapping unverified** — see the warning in `AttestationError.swift`.
