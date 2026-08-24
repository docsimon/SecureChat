# Registration & OTP — API Contract

Additions to `06-PAIRING-API.md`. Registration is two steps: request, then verify.

---

## Types

| Wire type | Meaning | Swift |
|---|---|---|
| `String (UUID)` | Uppercase UUID, e.g. `"A1B2C3D4-..."` | `UUID` |
| `String (E.164-ish)` | Digits and a leading `+`; normalised server-side | `String` |
| `Int (epoch ms)` | Milliseconds since 1970 | `Date` via `.millisecondsSince1970` |
| `Int (ms)` | A duration, not a timestamp | `TimeInterval` after `/1000` |
| `String (enum)` | Fixed set of values | Swift `enum` with an `unknown` fallback |

**Timestamps are milliseconds, and nullable fields are `null`, not absent.** Set `dateDecodingStrategy = .millisecondsSince1970` and declare them `Date?`. Getting this wrong yields dates in the year 57,000 rather than a decode error, so it fails silently.

---

## The User object

Returned by `/register`, `/register/verify`, `/register/resend`, and `PUT /users/:id/phone`.

| Field | Type | Null? | Meaning |
|---|---|---|---|
| `userID` | `String (UUID)` | no | Client-generated or server-assigned. The handle for every later call. |
| `phone` | `String` | no | Normalised — may differ from what you sent |
| `displayName` | `String` | no | Defaults to the phone number |
| `status` | `String (enum)` | no | `pending_verification` \| `verified` |
| `phoneSentDate` | `Int (epoch ms)` | yes | Phone number submitted |
| `otpCodeSentDate` | `Int (epoch ms)` | yes | Code last issued — **also moves on resend** |
| `registeredAt` | `Int (epoch ms)` | yes | Successful verification. **The only proof of registration.** |

```swift
struct User: Decodable {
    let userID: UUID
    let phone: String
    let displayName: String
    let status: RegistrationStatus     // enum with .unknown fallback
    let phoneSentDate: Date?
    let otpCodeSentDate: Date?
    let registeredAt: Date?
}
```

Responses that issue a code add two more:

| Field | Type | Meaning |
|---|---|---|
| `otpExpiresAt` | `Int (epoch ms)` | When the current code dies |
| `attemptsRemaining` | `Int` | Wrong guesses left (always 3 on issue) |

### How the three dates move

| Action | `phoneSentDate` | `otpCodeSentDate` | `registeredAt` |
|---|---|---|---|
| `POST /register` | set | set | `null` |
| `POST /register/verify` ✓ | unchanged | unchanged | **set** |
| `POST /register/resend` | unchanged | **moved** | unchanged |
| `PUT .../phone` (changed) | **moved** | **moved** | back to `null` |
| `PUT .../phone` (same) | **moved** | **moved** | unchanged if verified |

Resend is the case where the two diverge — `phoneSentDate` answers *when did the user commit to this number*, `otpCodeSentDate` answers *how stale is the code they're waiting for*.

Both survive verification; they're stored independently of the live OTP, so consuming a code doesn't erase the record.

---

## State machine

```
    POST /register
         │
         ▼
  ┌──────────────────┐   POST /register/verify ✓   ┌──────────────┐
  │ pending_         │ ────────────────────────►   │ verified     │
  │ verification     │                             │ registeredAt │
  └──────────────────┘                             └──────────────┘
     │        ▲                                          │
     │        │  PUT /users/:id/phone (number changed)    │
     │        └──────────────────────────────────────────┘
     │
     └─► POST /register/resend  (new code, same state)
```

A user is **invisible to the rest of the system until verified.** `/lookup` returns 404 for pending users; `/invite` rejects them with 403.

---

## HTTP method rationale

| Endpoint | Method | Why |
|---|---|---|
| `/register` | `POST` | Creates a resource; each call issues a new code |
| `/register/verify` | `POST` | An **action** with side effects — consumes an attempt, transitions state. Not a resource replacement, so not `PUT`. |
| `/register/resend` | `POST` | Action, side effects, rate-limited |
| `/users/:id/phone` | `PUT` | Replaces a single value; **idempotent** — same number twice leaves the same state. `PATCH` implies partial update of a larger resource; `POST` implies creation. |

The `PUT` does have a side effect (issuing a code), which purists dislike. The alternative — `POST /users/:id/phone-change-requests` — is more ceremony than this needs.

---

## `POST /register`

```jsonc
// Request
{
  "phone":       "+447700900001",   // String, required
  "displayName": "Alice",           // String, optional → defaults to phone
  "userID":      "A1B2C3D4-...",    // String (UUID), optional → server generates
  "pushToken":   "mock-token"       // String, optional
}

// 200 → User + otpExpiresAt + attemptsRemaining
{
  "userID": "274BC092-3ED0-42BC-9F3E-59DFF7D85832",
  "phone": "+447700900001",
  "displayName": "Alice",
  "status": "pending_verification",
  "phoneSentDate": 1787569657146,
  "otpCodeSentDate": 1787569657147,
  "registeredAt": null,
  "otpExpiresAt": 1787569957147,
  "attemptsRemaining": 3
}
```

**400** `phone_required`

Idempotent on phone: re-registering a known number re-issues a code rather than duplicating the user. **The OTP is never in the response** — it goes to the console and the web panel.

---

## `POST /register/verify`

```jsonc
// Request
{ "userID": "274BC092-...", "code": "042317" }   // both String, required

// 200 → User
{ ..., "status": "verified", "registeredAt": 1787569657299 }
```

| Status | `error` | Extra | Client should |
|---|---|---|---|
| 401 | `invalid_code` | `attemptsRemaining: Int` | Show count, allow retry |
| 410 | `code_expired` | — | Offer resend |
| 429 | `too_many_attempts` | — | Code burned, force resend |
| 409 | `no_pending_verification` | — | Restart from `/register` |
| 404 | `unknown_user` | — | Restart from `/register` |

**Verifying an already-verified user returns 200**, not an error — a retry after a dropped response must not strand the client.

---

## `POST /register/resend`

```jsonc
// Request
{ "userID": "274BC092-..." }

// 200 → User + otpExpiresAt + attemptsRemaining
```

| Status | `error` | Extra |
|---|---|---|
| 429 | `resend_too_soon` | `retryAfterMs: Int` |
| 409 | `already_verified` | — |
| 404 | `unknown_user` | — |

Drive the countdown from `retryAfterMs`, not a hardcoded 30s — a local timer drifts across backgrounding.

---

## `PUT /users/:userID/phone`

The wrong-number recovery path. `userID` is a path component; URL-encode it.

```jsonc
// Request
{ "phone": "+447700900099" }   // String, required

// 200 → User + otpExpiresAt + attemptsRemaining
{ ..., "phone": "+447700900099", "status": "pending_verification", "registeredAt": null }
```

| Status | `error` |
|---|---|
| 409 | `phone_taken` — another **verified** user owns it |
| 400 | `phone_required` |
| 404 | `unknown_user` |

Submitting the *same* number re-issues without changing state — the "SMS never arrived, I retyped it identically" case.

---

## Errors

Every non-2xx carries a JSON body. `error` is a machine-readable code, never display text — the user-facing string is localized in the app.

```jsonc
{ "error": "invalid_code", "attemptsRemaining": 2 }
{ "error": "resend_too_soon", "retryAfterMs": 18420 }
{ "error": "phone_required" }
```

| Field | Type | Present |
|---|---|---|
| `error` | `String (enum)` | always |
| `attemptsRemaining` | `Int` | `invalid_code` only |
| `retryAfterMs` | `Int (ms)` | `resend_too_soon` only |

**The status code alone is not enough.** `429` means both `too_many_attempts` and `resend_too_soon`, which need different UI. Always decode the body.

Give the client enum an `unknown(String)` case so a new server code doesn't break an older build.

---

## Changed behaviour elsewhere

**`GET /lookup`** returns 404 for pending users. Only verified users are discoverable.

**`POST /invite`** returns **403** `sender_not_verified` or `recipient_not_verified`.

---

## Client notes

**Persist `userID` before verifying.** It's the handle for verify, resend, and phone change. Lose it and the user restarts registration.

**Persist the whole state across launches.** A user who registers, backgrounds the app waiting for the SMS, and returns must land back on the OTP screen — otherwise they burn another code.

**`registeredAt != nil` is the only registration check.** It and `status == "verified"` always agree; prefer the date since it's the value you store.

**Keep the phone-change route reachable from the OTP screen.** The whole point of `PUT /users/:id/phone` is the user who mistyped their number and will never receive a code. If the only exit is a correct OTP, they're stuck.

**Note `registeredAt` resets on a phone change.** It means "when the current number was verified", not "when this user joined". If you want a stable join date, add a separate `createdAt` — easy now, annoying to reconstruct later.

---

## Not built yet

- **Registration lock** — anyone can re-register any number and take it over. Production needs a PIN plus a delay window.
- **Rate limiting on `/register`** — numbers are enumerable by watching which ones re-register versus create.
- **Real OTP delivery** — console only.
- **Per-phone attempt limits** — burning one code and requesting another resets the counter.
