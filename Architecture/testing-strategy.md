# Testing strategy

Agreed with the user on 2026-10-14. Each main feature (Registration,
Pairing, Chat, …) is a Swift package under `Modules/`, tested on its own and
then together with the others inside SecureChat.

## Layers

| Layer | What runs for real | What is faked | When |
|---|---|---|---|
| Module tests (`xcodebuild test -scheme <Kit>` in `Modules/<Kit>`) | the module | everything around it | every change |
| SecureChat unit tests (`SecureChatTests`) | one app type at a time | its dependencies | every change |
| SecureChat integration tests (`SecureChatTests/Integration`) | every module and app type between the user and the outside world | Apple, the network, the Keychain | every change |
| Feature harnesses (`AppAttestTestApp`, `PairingTestApp`) | the feature on a phone; App Attest (development) only in `AppAttestTestApp` | whatever the harness chooses | when a feature's Apple or hardware behaviour changes |
| "SecureChat Real Registration" scheme | the whole app on a phone: development App Attest, the local Auth Server, real cameras | nothing | only when the user decides to |

## Rules

- **App Attest is tested in the harness.** Tests of SecureChat assume Apple
  works and stand in for it (`registration-status.md`, rule 1). The Real
  Registration scheme is the one opt-in exception, run by the user.
- **No build uses the production App Attest entitlement** until the user
  decides to publish on TestFlight. TestFlight and the App Store always use
  production, whatever the entitlement says, so every run before that is a
  build installed from Xcode.
- **Integration tests never touch shared state.** Every store is in memory
  or a throwaway `UserDefaults` suite, so they are safe on a phone too.
  (`RegistrationViewModelTests` still uses the real Keychain and skips
  itself outside the Simulator.)
- **Fakes stay in the test target** that uses them until a second target
  needs the same one; then they move to a shared package, never copied.

## Seams the integration tests use

| Seam | Where | Visible to shipping code? |
|---|---|---|
| `AttestServicing`, `AttestationKeyStore`, `AttestationCoordinator.init(testingService:store:transport:observer:)` | `AppAttestKit` | No: `@_spi(Testing)`, and the initializer is compiled in Debug only |
| `IdentityKeyStore.inMemory()` | `RegistrationKit` | No: `@_spi(Testing)`, Debug only |
| `IdentityKeyStore`/`RegisteredAccountStore` values, `RealAttestationTransport(session:)` | `RegistrationKit` | Yes, with `.live` / `.shared` defaults |
| `RegistrationViewModel(identity:account:)`, `LocalIdentityProvider(identityStore:accountStore:)` | SecureChat | Yes, with `.live` defaults |

## Fakes (`SecureChatTests/Integration/IntegrationFakes.swift`)

- `FakeAppleAttestService`: always supported; attests with an object whose
  aaguid is `appattestdevelop`.
- `InMemoryAttestationKeyStore`: AppAttestKit's Keychain state.
- `FakeAuthServer`: `/challenge` and `/register` behind a `URLProtocol`.
  Keeps the rules the app relies on (challenge issued for one identity key,
  used once, same key at `/register`, development attestations only); it
  does not verify Apple's signature.

## Not covered yet

- `DependencyManager`'s own wiring: the integration test assembles the
  pieces the same way, but not through it.
- The transport's error mapping (4xx/5xx, expired challenge) at the
  integration level.
- Sessions and chat: they get their own integration tests when built.
