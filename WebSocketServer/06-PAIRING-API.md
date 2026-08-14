# Pairing Prototype — API Contract

Base URL: `http://localhost:8080`
Relay: `ws://localhost:8080/relay`

**Prototype only.** No authentication, no encryption, no rate limiting. Every endpoint trusts its input.

All UUIDs are **uppercase** in responses (matching Swift's `UUID.uuidString`). The server uppercases anything you send, so case-insensitive input is safe.

---

## Conventions

| | |
|---|---|
| Content type | `application/json` on both sides |
| Errors | `{ "error": "<code>" }` with a matching HTTP status |
| Phone format | Normalised to digits and `+` — `"+44 7700 900123"` and `"07700900123"` collapse to different values, so **be consistent in the client** |
| Timestamps | Unix milliseconds (JS `Date.now()`) |

### Objects

```jsonc
// User
{ "userID": "A1B2...", "phone": "+447700900001", "displayName": "Alice", "pushToken": "mock-token" }

// Invite
{ "inviteID": "...", "chatID": "...", "fromUserID": "...", "fromDisplayName": "Alice",
  "toUserID": "...", "status": "pending" | "accepted" | "declined", "createdAt": 1699999999999 }

// Chat
{ "chatID": "...", "memberIDs": ["...", "..."], "createdAt": 1699999999999 }
```

---

## Auth server

### `POST /register`

Idempotent on phone number — call it on every launch. An existing phone returns the existing user with `pushToken` refreshed; it does **not** create a duplicate or error.

```jsonc
// Request — all optional except phone
{ "phone": "+447700900001", "displayName": "Alice", "userID": "<client-generated>", "pushToken": "..." }

// 200 → User
{ "userID": "A1B2...", "phone": "+447700900001", "displayName": "Alice", "pushToken": "mock-token" }
```

Omit `userID` and the server generates one. `displayName` defaults to the phone number.

**400** `phone required`

---

### `GET /lookup?phone=<urlencoded>`

The contact-discovery step. A calls this with a number from the address book.

```jsonc
// 200
{ "userID": "C3D4...", "displayName": "Bob" }

// 404
{ "error": "not_registered" }
```

**The 404 is the branch that matters.** It's the common case in real usage, not an edge case, and it's where the SMS-invite fallback goes. Don't let the client treat it as a failure.

---

### `POST /invite`

A invites B. Sends a (logged) push to B and records a pending invite.

```jsonc
// Request
{ "fromUserID": "A1B2...", "toUserID": "C3D4...", "chatID": "<optional, client-generated>" }

// 200 → Invite
```

Omit `chatID` and the server generates one — but **generate it client-side**. It makes the call idempotent under retry: a dropped response followed by a retry with the same `chatID` won't produce two chats.

**404** `unknown user`

The logged push payload, which is what APNs would carry:

```jsonc
{ "type": "chat_invite", "inviteID": "...", "chatID": "...",
  "from": "Alice", "deeplink": "securechat://invite/<inviteID>" }
```

---

### `GET /invites?userID=<id>`

B polls this. Returns **pending only** — accepted and declined are filtered out.

```jsonc
// 200 → [Invite]
```

With real APNs the push carries `inviteID` and this becomes a fetch-by-id. Keep the polling path anyway as a fallback for missed notifications.

---

### `POST /invite/accept`

B accepts. Creates the chat if absent and adds both users. This is the moment membership exists.

```jsonc
// Request
{ "inviteID": "..." }

// 200 → Chat
{ "chatID": "...", "memberIDs": ["A1B2...", "C3D4..."], "createdAt": 1699999999999 }
```

**404** `unknown invite` · **409** `already accepted` / `already declined`

Handle the 409 — a double-tap on Accept, or a retry after a dropped response, will hit it. Treat it as success on the client and fetch the chat.

Pushes `{"type":"invite_accepted","chatID":"...","by":"Bob"}` to A.

---

### `POST /invite/decline`

```jsonc
// Request
{ "inviteID": "..." }

// 200 → Invite (status: "declined")
```

**404** `unknown invite`

---

### `GET /chats?userID=<id>`

Chat list for a user. `members` is a convenience join not present on the stored object.

```jsonc
// 200
[ { "chatID": "...", "memberIDs": ["...","..."], "createdAt": 169...,
    "members": [ { "userID": "...", "displayName": "Alice" },
                 { "userID": "...", "displayName": "Bob" } ] } ]
```

---

### Panel helpers

`GET /state` → everything, plus `connected: [userID]` for currently-open sockets.
`POST /reset` → wipes state, terminates all sockets. Body ignored.

---

## Relay

### `ws://localhost:8080/relay?as=<userID>&chat=<chatID>`

Both parameters required. Missing either closes with **4000** `missing_params`.

**The relay does not check membership.** It pairs whoever connects with the same `chatID` and forwards frames between them. Membership lives on the auth server, and in production lives in the clients' key agreement. Keeping the relay ignorant is deliberate — resist the urge to add a check.

**Behaviour**

- Every frame received is forwarded verbatim to all *other* sockets in the same `chatID`.
- Binary stays binary, text stays text.
- No parsing, no acks, no envelope. What you send is what your peer receives.
- A room exists only while a socket holds it open, then evaporates.
- Multiple sockets per user are allowed — useful for simulator plus device.

**Sending to nobody is silent.** Connect alone and messages go nowhere with no error. The console logs the peer count on join and forward count per message, which is the fastest way to spot a `chatID` mismatch.

---

## Flow

```
A: POST /register                    → userID_A
B: POST /register                    → userID_B

A: GET  /lookup?phone=<B's>          → userID_B          (404 → fallback path)
A: POST /invite {from,to,chatID}     → invite, push to B

B: GET  /invites?userID=<B>          → [invite]          (or via push deeplink)
B: POST /invite/accept {inviteID}    → chat, push to A

Both: ws /relay?as=<self>&chat=<chatID>
      → frames forwarded between them
```

---

## Client notes

**Poll `/chats` after accepting.** A's push tells it the invite was accepted, but A still needs to fetch the chat. There's no server-initiated chat delivery over the relay.

**Generate `chatID` client-side.** Retry safety, as above.

**Handle 409 on accept as success.** Fetch `/chats` and move on.

**Store `userID` locally after registration** and reuse it. Registration is idempotent, but only if you send the same phone.

**Nothing in the relay tells you who a message is from.** Frames are forwarded verbatim, so `guestID` (or whatever identifies the sender) must be inside your own message payload. That stays true in production, where the relay sees only ciphertext.
