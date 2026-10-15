# Sessions — design

Started 2026-10-14. How two paired phones open an encrypted session through
the relay and exchange messages. Builds on `pairing-workflow.md` (who the
contacts are) and `architecture-decisions.md` §4–§6 (crypto, wire format,
relay).

## Decisions (with the user, 2026-10-14)

| Question | Decision |
|---|---|
| Relay stack | Kotlin/Ktor, a separate service next to the Auth Server, same docker-compose, same Redis |
| First slice | Noise `KK` handshake + encrypted, padded, fixed-size frames end to end. The Double Ratchet is slice 2, on top, without changing the frame format |
| Development access | The relay, started with an explicit development flag, accepts a client that claims an account id. Off by default. Simulators, Debug builds and the session harness use it; the Real Registration scheme uses a real session token |
| When a session starts | When a chat is opened. Each app holds one relay connection while in the foreground; opening a chat starts the handshake |

Also decided (by me, as implementation detail): Noise is written on
CryptoKit, not taken from a library (dependency count, §10), and checked
against the published test vector for `Noise_KK_25519_ChaChaPoly_SHA256`.

## Who can open a session

`KK` means each side must already hold the other's static key. A phone that
is not a stored contact cannot produce a first message the receiver can
decrypt, so **"accept sessions only from stored contacts" is enforced by the
protocol**, not only by a lookup. The receiver also looks the sender up by
account id first and drops unknown senders without answering, so a stranger
does not even learn that this device is online.

## Protocol

Noise `Noise_KK_25519_ChaChaPoly_SHA256`, prologue `SecureChat session v1`.

```
  -> s                      (known from pairing)
  <- s                      (known from pairing)
  ...
  -> e, es, ss              handshake 1 (initiator: whoever opened the chat)
  <- e, ee, se              handshake 2
  then transport messages, one CipherState per direction
```

Static keys are the identity keys (X25519) that pairing exchanged. Both
handshake payloads are empty.

- **Both open the chat at once:** two handshake-1 messages cross. The phone
  whose account id is lower (byte order) stays initiator; the other drops
  its own attempt and answers.
- **A new handshake 1 from a peer with an open session** replaces that
  session (the peer restarted). Known cost: whoever controls the relay can
  replay an old handshake 1 and break a running session. It cannot read or
  inject anything.
- **A message that fails to decrypt** ends the session. The next message
  from the user starts a new handshake.
- **The peer is not connected:** the relay answers "unavailable" and the
  chat shows the contact as offline. Nothing is queued (§1: both online).
- **The peer is connected but never answers** (they removed us, so they
  stay silent on purpose): after 10 s `SessionService` abandons the
  handshake and reports "unanswered"; the next attempt starts afresh.
  Without this the contact would stay stuck "starting" for good.

## Wire format

Every WebSocket frame, in both directions, is exactly **8,320 bytes**
(`architecture-decisions.md` §5). The relay drops any other size.

```
relay frame (8,320)
  [0]      version = 1
  [1]      kind: 1 deliver, 2 peer unavailable
  [2..17]  peer routing id (16 bytes). Client→relay: the destination.
           Relay→client: the relay overwrites it with the sender's id.
  [18..]   body, 8,302 bytes

body (deliver)
  [0]      type: 1 handshake 1, 2 handshake 2, 3 transport
  [1..2]   noise message length (big endian)
  [3..]    noise message, zero padded

transport plaintext (padded BEFORE encryption, 8,283 bytes)
  [0]      content type: 1 text (others reserved: receipt, control, media)
  [1..2]   content length (big endian)
  [3..]    content (UTF-8, at most 8,280 bytes), zero padded
```

Transport ciphertext is always 8,283 + 16 bytes, so every transport frame is
the same length on the wire. The handshake messages are padded the same way
at the body level. The routing id is the contact's account UUID, produced in
one place (`RoutingID`) so a derived rendezvous id can replace it later
(§10's hedge).

## Relay

- `GET /relay` upgrades to a WebSocket. Authentication at connect:
  `Authorization: Bearer <session token>`, looked up in the Auth Server's
  Redis (`session:token:<token>` → account UUID).
- Development flag `RELAY_DEV_CLAIMED_ACCOUNTS=true`: also accepts
  `X-Dev-Account: <uuid>` without a token. Logged loudly at startup. Never
  set in production.
- Routing map in memory: account → connections. A frame for an account with
  no connection gets a "peer unavailable" frame back. Nothing is stored;
  the entry disappears with the connection.
- The token is checked at connect only; an open connection outlives the
  token's 15 minutes. Noted, not handled in slice 1.
- Rate limits (§9) are not in slice 1.

## Pieces

| Piece | Where | Role |
|---|---|---|
| `SessionKit` | `Modules/SessionKit` | Noise `KK`, frame codec, `SessionEngine` (one state per peer), `RelayClient` (WebSocket). Shared by the harness and the app |
| Relay | `RelayServer/` | Ktor service, port 8081, in `AuthServer/docker-compose.yml` |
| Harness | `SessionTestApp` | Two Simulators or phones open sessions through the relay, with development identities |
| App | `SecureChat` | Opening a chat with a contact opens a session |

## Status (2026-10-14)

| Piece | State |
|---|---|
| `SessionKit` | Noise `KK` matches the published test vector (handshake hash and transport). 18 unit tests: stranger refused without a reply, contact id without the key refused, simultaneous open, offline peer, silent peer abandoned, peer restart, tampering, every frame 8,320 bytes, too-long text, nothing queued for a non-contact. `RelayClient` and `SessionService` built |
| Relay | `RelayServer/`, 7 tests (delivery with sender id rewritten, peer unavailable, wrong size closes, no or wrong credentials refused, dev flag off refuses claimed accounts). Runs in docker on 8081; logs connection counts only, never ids |
| End to end | `LiveRelayTests` (opt-in, `TEST_RUNNER_SESSIONKIT_LIVE_RELAY=ws://localhost:8081/relay`): two `SessionService`s open a session through the docker relay and exchange text; an offline contact is reported. Passed 2026-10-14 |
| `SessionTestApp` | Used by hand on 2026-10-15: contacts added by pasted code, both connected, session opened, messages sent both ways; "unanswered" (contact removed on one side) and "offline" (one side disconnected) also seen |
| SecureChat | Not started |

Running it: `docker compose up` in `AuthServer/` (the relay is part of it;
`.env` sets `RELAY_DEV_CLAIMED_ACCOUNTS=true`). Relay tests:
`./gradlew test` in `RelayServer/` with JDK 21.

## Next: SecureChat (hand-off, 2026-10-15)

The agreed next step. Opening a chat with a paired contact opens a session
through the relay. What the code looks like today, and what is still to
decide:

**Facts about the current SecureChat code**

- The chat model is a placeholder from before registration: `Chat`,
  `Guest`, `Message` tables, `ChatRepository` and `WebsocketClient`
  connecting to `GlobalState.webSocketURL` = `ws://localhost:8080`, an old
  Node echo mock. Port 8080 is now the Auth Server. Contacts live apart, in
  the `contacts` table (`ContactRepository`); contacts are not linked to
  chats.
- `LocalIdentityProvider` returns only the PUBLIC key. Sessions need the
  private key: `IdentityKeyStore.live.loadExisting()` for a registered
  device, and `DebugLocalIdentity` already stores a private key in
  UserDefaults but does not hand it out yet.
- Credentials: registered devices get a token from
  `SessionClient(baseURL:signer:).openSession(accountUuid:)` (RegistrationKit;
  the `AttestationCoordinator` is the `AssertionSigning`: a local Secure
  Enclave signature, no Apple server call). Debug builds that skip
  registration use `.developmentAccount(<debug account UUID>)`, as the
  harness does. Token TTL is 15 min, checked at connect only.
- Relay URL: Debug = `ws://<AuthServerConfig LAN IP>:8081/relay`
  (Simulator could use localhost); Release has no address yet (same `#error`
  pattern as `AuthServerEnvironment`).
- `SessionService` takes a concrete `RelayClient`. SecureChat integration
  tests (two devices register → pair → open a session, all in process) need
  a transport seam in SessionKit (a small protocol the service talks to,
  with an in-process relay for tests).

**Decisions to put to the user first**

1. Replace the placeholder chat stack (tables, `ChatRepository`,
   `WebsocketClient`) with a contact-based chat, or adapt it.
2. Message storage: plain SQLite for now (encryption at rest is a known
   later item, §10) or encrypted from the start.
3. Relay connection policy: connect on foreground, disconnect on
   background, reconnect after a drop (suggested).

**Then build:** identity with private key → relay connection manager →
chat screen bound to a contact (session state: open / starting / offline /
did not answer) → integration tests → phone test with two devices (the
iPhone X runs `SessionTestApp`, since it cannot run SecureChat).

## Known limits (reviewed 2026-10-14)

- **No delivery confirmation.** A message handed to the relay may still be
  lost if the peer disconnects at that moment; the sender is not told.
  Receipts are a reserved content type.
- **No automatic reconnect.** `RelayClient` stays disconnected after a drop
  until `connect()` is called again. SecureChat needs to reconnect on
  foreground and on network change.
- **Whoever holds a `SessionService` must call `disconnect()`** before
  letting go: an open URLSession keeps its delegate alive.
- **The relay upgrades unauthenticated requests before refusing them.**
  Cheap, but rejecting before the upgrade would be tidier.
- **A slow receiver slows its senders**: the relay waits for the
  receiver's buffer. Irrelevant at this scale.

## Not in slice 1

Double Ratchet (slice 2), local message encryption at rest, rate limits,
token expiry on open connections, push, receipts, typing indicators.
