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
- "Contact left": a closing connection's two-way correspondents get an
  unasked "peer unavailable" naming it (see "Presence").
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
| Relay | `RelayServer/`, 9 tests (delivery with sender id rewritten, peer unavailable, wrong size closes, no or wrong credentials refused, dev flag off refuses claimed accounts; since 2026-10-15 "contact left" sent after a two-way exchange and not after a one-way one). Runs in docker on 8081; logs connection counts only, never ids |
| End to end | `LiveRelayTests` (opt-in, `TEST_RUNNER_SESSIONKIT_LIVE_RELAY=ws://localhost:8081/relay`): two `SessionService`s open a session through the docker relay and exchange text; an offline contact is reported. Passed 2026-10-14 |
| `SessionTestApp` | Used by hand on 2026-10-15: contacts added by pasted code, both connected, session opened, messages sent both ways; "unanswered" (contact removed on one side) and "offline" (one side disconnected) also seen |
| SecureChat | Built 2026-10-15 (see "SecureChat" below). SecureChat tests pass on the Simulator, 7 of them session integration tests. **On phones, 2026-10-15** (SecureChat on the iPhone 16 Plus, `SessionTestApp` on the iPhone X, development accounts): paired face to face, messages both ways, offline, didn't answer, background and back; reported working by the user |

Running it: `docker compose up` in `AuthServer/` (the relay is part of it;
`.env` sets `RELAY_DEV_CLAIMED_ACCOUNTS=true`). Relay tests:
`./gradlew test` in `RelayServer/` with JDK 21.

## SecureChat (built 2026-10-15)

### Decisions (with the user, 2026-10-15)

| Question | Decision |
|---|---|
| Placeholder chat stack (`Chat`, `Guest`, `Message`, `ChatRepository`, `WebsocketClient` to the old echo mock) | Replaced. **A chat is a paired contact**, keyed by its account id. The old tables are dropped on first launch; `contacts` is kept |
| Message storage | **A, then B (both built 2026-10-15).** A = OS protection only (below). B = each message's text encrypted with a per-contact key in the Keychain, so deleting the key shreds the chat (§10 crypto-shredding). SQLCipher rejected: a dependency, and no per-contact deletion |
| Relay connection | Connected in the foreground, closed in the background (not on "inactive"), reopened after a drop with backoff 1, 2, 5, 10 s (10 s repeating). No separate network-change watcher: the backoff covers a network that comes back. The backoff only resets after a connection has lasted 10 s: the relay opens the socket before refusing a credential, so a refused one would otherwise retry every second, each time asking the Auth Server for a token |

### Pieces

| Piece | Role |
|---|---|
| `RelayConnection` (`SecureChat/Sessions`) | The one relay connection. A new `SessionService` per connection, with a fresh credential each time. Opening a chat opens a session with that contact, again after a reconnect. Keeps each contact's state (starting, open, offline, unanswered, ended) and writes every message to the `MessageStore` |
| `RelayCredentials` | Registered device: a token from `POST /session`, signed by the App Attest key (local Secure Enclave signature, no Apple call), fetched for every connection. Debug run that skipped registration: `.developmentAccount(debug account)` |
| `RelayEnvironment` | Debug: `ws://<AuthServerConfig host>:8081/relay`. Release: `#error` until a production relay exists |
| `SessionIdentity` (`LocalIdentity.swift`) | The identity private key and account id, for sessions only; pairing still gets just the public key |
| `MessageStore`, `StoredMessage` (`SecureChat/Chat`) | Messages per contact, in memory and in the `messages` table. Status: received, waiting (written before the session opened), sent (handed to the relay), not delivered |
| `ConversationViewModel`, `ConversationView` | The chat screen and its status line ("Connecting…", "Starting a secure session…", "Secure session", offline, didn't answer, session ended) |
| `DatabaseLocation` | Option A, below |
| SessionKit seam | `RelayTransport` protocol (`RelayClient` conforms), `SessionService(transport:…handshakeTimeout:)`, `onRelayStateChange` (called after `relayState` changes; `$relayState` publishes before, too early to open a session) |
| RegistrationKit seam | `SessionClient(…session:)`, for the fake Auth Server |

### Message storage (option A)

- The database is in `Application Support/Database/`, moved from Documents
  on first launch (pairings are kept).
- The directory is excluded from backup and has `NSFileProtectionComplete`;
  the files SQLite creates in it inherit that.
- Because the file is unreadable while the phone is locked,
  `DependencyManager` is built when the first window appears, not at launch:
  iOS may prewarm the process before the phone is unlocked.
- Not protected by A: messages on an unlocked phone; deleted messages
  recoverable from free pages and journals. That is B's job.

### Message storage (option B, 2026-10-15)

- **One key per contact** (`MessageKeyStore`): 256 bits, a Keychain item
  readable only while unlocked and never restored to another device
  (`WhenUnlockedThisDeviceOnly`), created with the first message.
- **Every message's text is sealed** before it reaches the database
  (`MessageSeal`: ChaChaPoly, authenticated with the message id and the
  contact's id, so a row moved to another message or chat does not open).
  The database holds only the sealed bytes; `MessageStore` callers did not
  change.
- **Deleting a chat** (swipe on the chat list, "Delete messages") deletes
  the key first, then the rows. Whatever copy is left on disk can no longer
  be read: crypto-shredding. The contact stays; the next message gets a new
  key.
- **Plain text from an earlier build** is sealed on first launch, the old
  table dropped and the file rewritten (VACUUM). `secure_delete` is on, so
  deleted rows are overwritten too.
- **Keys of contacts no longer on the phone** are deleted at launch (a
  reinstall deletes the database but not the Keychain).
- A row that cannot be opened (key gone, bytes changed) shows as "This
  message can't be read."

**Known limits.** Who, when and the status of each message are not sealed
(the contacts table holds who anyway). While the app runs, the messages
it shows are in memory in the clear. Deleting a contact is not built.

### Presence (2026-10-15)

A dot next to a contact's name, in the chat list and the chat's title
(`PresenceDot`). The relay has no presence, so it shows only what this
phone has learned on the current connection:

| Dot | When |
|---|---|
| green | a session with them is open |
| red | the last try found them offline, or they did not answer |
| none | nothing tried yet on this connection, a handshake still running, or this phone is not connected |

**"Contact left" (relay, 2026-10-15).** When a connection closes, the
relay sends the same "peer unavailable" frame, unasked and naming the
leaver, to every connection it routed frames **both ways** with during that
connection. The app needs no change: SessionKit already drops the session
on that frame, and the dot turns red. Rules:

- Two-way only. Someone who merely wrote to this phone (a stranger, a
  contact it removed and so ignores) learns nothing about it leaving.
- Also on "replaced" (the app reconnected): the sessions of the old
  connection are gone either way, so the other side should start afresh.
- The relay keeps, per open connection, the accounts it delivered frames
  to and from; the sets go with the connection (§1 still holds).

**Known limits.**
- Coming back is not announced: after "left", the dot stays red until this
  phone tries again (opening the chat, sending) or they open a session.
  Announcing arrivals would need the relay to know who wants to hear about
  whom, i.e. each phone's contact list. Not done.
- The chat list shows no dot for contacts whose chat has not been opened
  since the app came to the foreground (no probing).

### Phone test (done 2026-10-15)

The iPhone X cannot run SecureChat, so it runs `SessionTestApp`, which
since 2026-10-15 also pairs face to face ("Pair face to face": PairingKit's
`FaceToFacePairingView`, the same screen SecureChat shows). Copy and paste stays for
two Simulators.

- iPhone 16 Plus: SecureChat, the plain "SecureChat" scheme (Debug skips
  registration: debug identity, development account at the relay).
- iPhone X: `SessionTestApp`, connected to `ws://docs-MacBook-Pro-2.local:8081/relay`
  (the Mac's local name since 2026-10-15; it was the LAN IP, which DHCP changes).
- Both need the docker relay with `RELAY_DEV_CLAIMED_ACCOUNTS=true`.

## Next

1. Slice 2: Double Ratchet on the same frames.

## Known limits (reviewed 2026-10-14, SecureChat items 2026-10-15)

- **No delivery confirmation.** A message handed to the relay may still be
  lost if the peer disconnects at that moment; the sender is not told.
  Receipts are a reserved content type. In SecureChat such a message stays
  "sent", although the contact shows as offline.
- **No automatic reconnect in `RelayClient`.** It stays disconnected after
  a drop until `connect()` is called again; SecureChat's `RelayConnection`
  does that.
- **Whoever holds a `SessionService` must call `disconnect()`** before
  letting go: an open URLSession keeps its delegate alive.
- **The relay upgrades unauthenticated requests before refusing them.**
  Cheap, but rejecting before the upgrade would be tidier.
- **A slow receiver slows its senders**: the relay waits for the
  receiver's buffer. Irrelevant at this scale.

- **A device that keeps being refused retries every 10 s while in the
  foreground** (each time with a new token on a registered device). Nothing
  tells the user why; the chat says "Connecting…".
- **No unread marker** in the chat list; the row shows the last message.
- **No splitting:** a message longer than 8,280 UTF-8 bytes cannot be sent
  (the send button is disabled and says so).

## Not in slice 1

Double Ratchet (slice 2), local message encryption at rest, rate limits,
token expiry on open connections, push, receipts, typing indicators.
