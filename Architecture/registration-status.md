# Registration — status and hand-off

Written 2026-10-12, at the point where Registration is being closed and work
moves to pairing. This is the page to read first when picking Registration up
again. The per-error detail lives in `attestation-error-state-table.md`.

## Standing rules

1. **Apple's App Attest is tested in the `AppAttestTestApp` harness.** It is a
   limited resource. Any test of the real app (`SecureChat`) assumes Apple
   works and stands in for it. (Stated by the user on 2026-10-12.) The one
   exception is opt-in: the `SecureChat Real Registration` scheme runs the
   real flow (development App Attest + local Auth Server) on a phone, only
   when the user decides to (added 2026-10-14). No build uses the production
   entitlement until the user decides to publish on TestFlight.
2. **Development environment only.** No Debug build may use Apple's production
   App Attest. See "Development-environment safeguards" below.
3. **The harness runs the code that ships.** Anything both apps need lives in a
   package both compile, never copied into the harness.
4. **Each main feature gets its own harness app target.** Pairing has
   `PairingTestApp` (see `pairing-workflow.md`).
5. **Rare failures are ignored on purpose**, but written down (the error table's
   "Known and accepted" section).

## What exists

| Piece | Where | Role |
|---|---|---|
| `AppAttestKit` | `Modules/AppAttestKit` | The App Attest state machine. Owns the `keyId`, the cached attestation, retries. |
| `RegistrationKit` | `Modules/RegistrationKit` | Shared by harness and app: Auth Server transport (`RealAttestationTransport`), `SessionClient`, `IdentityKeyStore`, `RegisteredAccountStore`, `FirstLaunchPurgeGate`, `Registration.clientDataHash`, `Registration.purgeStaleInstallState`, `AttestationEnvironmentHint`. The two stores are values (`.live` in shipping code) so tests can pass in-memory ones. |
| Harness | `AppAttestTestApp` | Single-step testing on a phone: step control, fake transport, environment badge. |
| Real app | `SecureChat/Registration`, `View/RegistrationView.swift`, `View/RootView.swift` | `RegistrationViewModel` → Register button → chat list. Registration starts only from the user's tap. |
| Auth Server | `AuthServer` | `GET /challenge`, `POST /register`, `GET /session/nonce`, `POST /session`. Accepts a comma-separated list of bundle ids in `APPATTEST_BUNDLE_ID`. |

Removed from SecureChat on 2026-10-12: the old phone-number/OTP registration
flow (views, view models, `AuthService`, `RegistrationRepository`, its SQLite
table code). An install that predates this keeps an unused `registration`
table; there is no migration.

## What has been verified, and how

| What | Evidence |
|---|---|
| `AppAttestKit` rules | 33 unit tests pass. |
| Registration against Apple + local Auth Server, the ordinary failures (no network, server 5xx, app killed, `attestKey` hanging offline), reinstall purge | Observed on a phone with the harness on 2026-10-06/07 and 2026-10-12 — **before** the transport and purge moved into `RegistrationKit`. |
| Rows 0, 8a, 9, 10, 16, 20 of the error table (storage failures, one-replacement limit, `invalidInput` on `attestKey`, `featureUnsupported` from a call, reset during a hung Apple call) | Unit tests with mocks only. Never seen on a phone. |
| `RegistrationKit` | 11 unit tests (first-launch gate, environment check). The transport's error mapping has no automated test; its happy path runs in SecureChat's integration tests against a fake server. |
| Harness after the refactor | Unit tests pass; run on a phone on 2026-10-12 (Register, relaunch, session). |
| SecureChat registration screen | 7 unit tests pass; start screen and the Debug skip checked in the Simulator. The "registered" path runs in `RegistrationPairingIntegrationTests` with Apple and the server faked. **Run for real on the iPhone 16 Plus on 2026-10-14** with the Real Registration scheme: entitlement checked with the script before Register, `App Attest environment: development` logged, the Auth Server issued account `d832cf87…`, relaunch went straight to the chat list. |
| Auth Server bundle-id list | 4 unit tests pass; the harness registered against it on 2026-10-12, SecureChat on 2026-10-14. |

## Blockers before Registration is closed

**Registration was closed by the user on 2026-10-12.** Kept as a record.

1. **Done 2026-10-12 — `RegistrationViewModelTests` cannot run on a phone.**
   They write to and clear the real Keychain, which on a registered phone
   would wipe the registration and cost a new App Attest key. The whole class
   now skips itself outside the Simulator.
2. **Done 2026-10-12 — Debug builds of SecureChat skip registration** (rule 1).
   `RegistrationViewModel.assumesRegistered` (compiled in Debug only) makes
   `load()` report "registered" without reading saved state or contacting
   Apple or the server; `DependencyManager` turns it on for every Debug run.
   To run the real flow against the development server, launch with the
   argument `-RealRegistration YES`. Checked in the Simulator: the app opens
   on the chat list. What it does **not** solve: no identity key or account
   id is created and the Auth Server does not know the device, so anything
   pairing needs from the server needs a development-only path there too.
   Decide that as part of pairing.
3. **Done 2026-10-12 — the harness ran on the phone with the refactored
   code** (fresh install; Register, relaunch, open a session) and the user
   reported it went fine. Rows 0, 8a, 9, 10, 16 and 20 of the error table
   were not provoked and remain mock-tested only.
4. **Partly covered.** The hand-edited `project.pbxproj` opened in Xcode and
   built the harness for the phone. The SecureChat target's settings
   (`RegistrationKit` linked, `Debug-Info.plist` on Debug) were not looked at
   in the Xcode UI; they build from the command line.
5. **Done 2026-10-12 — committed** as `2d8c5d4` (one commit).

## Development-environment safeguards

- `SecureChat/SecureChat.entitlements` and the harness's entitlements set
  `com.apple.developer.devicecheck.appattest-environment` to `development`.
  One entitlements file for SecureChat, by decision; it must change before a
  production release. (Apple ignores the value for TestFlight, App Store and
  Enterprise builds, which always use production.)
- `./Scripts/check-appattest-environment.sh [scheme]` prints the entitlement
  the last **device** build was signed with. Default scheme is the harness;
  pass `SecureChat` or `"SecureChat Real Registration"` for the app. It needs
  a signed device build to exist. For SecureChat, run it while the Register
  screen is showing: nothing reaches Apple before the tap.
- The harness shows a badge read from Apple's own response
  (`appattestdevelop`). SecureChat Debug builds log the same check
  (`EnvironmentLoggingTransport`: "App Attest environment: development", or
  a ⚠️ error) when the Real Registration scheme runs the real flow.
- The Auth Server refuses to start without `APPATTEST_ENVIRONMENT`.
- SecureChat's Release configuration fails to compile on purpose
  (`AuthServerEnvironment.swift`, `#error`) until a production server address
  exists. This also blocks archiving and profiling.
- The LAN exception (`SecureChat/Debug-Info.plist`) applies to Debug only.

## Noted, not being done now

Module (`AppAttestKit`)
- `restore()` now throws and `AttestationError.storageFailed` is new: both
  are public API changes.
- `invalidInput` from `attestKey` is treated as a dead key. This is inferred
  from what `generateAssertion` does, not observed.
- At most one key replacement per `ensureAttested()` call. This partly
  reverses the earlier "no cap" decision (the persisted cap stays removed).
- The observer is told about a failed attestation-cache write with
  `attempt: 0`, which is a misuse of that parameter.
- No cool-down between `ensureAttested()` calls. Considered and declined; the
  app must not trigger registration automatically.
- A call to Apple abandoned by the timeout while *online* is unobserved.

Shared package (`RegistrationKit`)
- `RealAttestationTransport` saves the account id into `RegisteredAccountStore`
  as a side effect; the harness also saves it, so it is written twice.
- `SessionClient` still sends the placeholder body `"harness-session-ping"`
  and has no handling for a rejected `/session` (error table row 25, proposal
  only).
- `AuthServerConfig.localDevelopmentURL` (a LAN address) is compiled into the
  package in every configuration.

Real app (`SecureChat`)
- `RegistrationViewModel` takes the concrete `AttestationCoordinator`, so its
  success and failure paths cannot be unit-tested. Blocker 2 is the natural
  moment to put a protocol in between.
- "Registered" is decided by the module's attested state alone; a missing
  account id is not noticed.
- The retry-after-unreadable-state branch in `register()` is harder to read
  than it should be.
- No decision on what an unsupported device is offered.
- No production Auth Server address.

Auth Server
- With several bundle ids, a rejected attestation reports the first
  validator's reason, which may be "wrong app" rather than the real cause.
- The local `AuthServer/.env` (not in git) was edited to list both bundle ids.
- Enabling the App Attest capability for `com.wapdir.simone.SecureChat` in the
  Apple developer account is only needed once the real app attests for real.

Harness
- Running the whole `AppAttestTestApp` scheme's tests hangs; cause unknown.
  Use `-only-testing:AppAttestTestAppTests`.
- The "Custom" backend picker has a known bug.

Documentation
- `appattestkit-module-design.md`, `architecture-decisions.md`,
  `attestation-assertion-workflow.md`, both smoke checklists and `README.md`
  predate `RegistrationKit`, `storageFailed`, the throwing `restore()` and the
  one-replacement limit. Where they disagree with
  `attestation-error-state-table.md` or this page, these two are right.

## Working notes

- The packages are iOS-only: test with `xcodebuild` against an iOS Simulator,
  not `swift test`.
- App tests: `-only-testing:SecureChatTests`.
- Server tests: `./gradlew test` in `AuthServer/`.
