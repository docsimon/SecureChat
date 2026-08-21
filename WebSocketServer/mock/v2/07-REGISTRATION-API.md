# Registration & OTP — API Contract

Additions to `06-PAIRING-API.md`. Registration is now two steps: request, then verify.

---

## State machine

```
    POST /register
         │
         ▼
  ┌──────────────────┐   POST /register/verify  ✓   ┌────────────┐
  │ pending_         │ ─────────────────────────►   │ verified   │
  │ verification     │                              │ registeredAt set
  └──────────────────┘                              └────────────┘
     │        ▲                                          │
     │        │ PUT /users/:id/phone (number changed)     │
     │        └──────────────────────────────────────────┘
     │
     └─► POST /register/resend  (new code, same state)
```

A user is **invisible to the rest of the system until verified.** `/lookup` returns 404 for pending users, and `/invite` rejects them with 403. That's deliberate: an unverified phone number is an unproven claim.

---

## HTTP method rationale

| Endpoint | Method | Why |
|---|---|---|
| `/register` | `POST` | Creates a resource; not idempotent in effect (issues a new code each call) |
| `/register/verify` | `POST` | An **action** with side effects — consumes an attempt, transitions state. Not a resource replacement, so not `PUT`. |
| `/register/resend` | `POST` | Action, side effects, rate-limited |
| `/users/:id/phone` | `PUT` | Replaces a single value; **idempotent** — same number twice leaves the same state. `PATCH` would imply partial update of a larger resource; `POST` would imply creation. |

The `PUT` does have a side effect (issuing a new OTP), which purists dislike. The alternative — `POST /users/:id/phone-change-requests` — is more ceremony than this needs, and the idempotency argument wins.

---

## `POST /register`

Step 1. Stores details, issues an OTP, returns a **pending** user.

```jsonc
// Request
{ "phone": "+447700900001", "displayName": "Alice",
  "userID": "<optional, client-generated>", "pushToken": "mock-token" }

// 200
{ "userID": "A1B2...", "phone": "+447700900001", "displayName": "Alice",
  "status": "pending_verification", "registeredAt": null,
  "otpExpiresAt": 1699999999999, "attemptsRemaining": 3 }
```

**400** `phone_required`

Idempotent on phone: re-registering a known number re-issues a code rather than duplicating the user. Real apps allow this (reinstall, new device); production would gate it behind a registration-lock PIN.

**The OTP is never in the response.** It's printed to the server console and shown in the web panel.

---

## `POST /register/verify`

Step 2. On success `registeredAt` is set — that's the value the client stores as its registration date.

```jsonc
// Request
{ "userID": "A1B2...", "code": "042317" }

// 200
{ "userID": "A1B2...", "phone": "+447700900001", "displayName": "Alice",
  "status": "verified", "registeredAt": 1699999999999 }
```

| Status | Error | Client should |
|---|---|---|
| 401 | `invalid_code` (+ `attemptsRemaining`) | Show remaining attempts, let them retry |
| 410 | `code_expired` | Offer resend |
| 429 | `too_many_attempts` | Code is burned — force resend |
| 409 | `no_pending_verification` | Restart from `/register` |
| 404 | `unknown_user` | Restart from `/register` |

**Verifying an already-verified user returns 200**, not an error. A retry after a dropped response should succeed, not strand the client.

---

## `POST /register/resend`

```jsonc
// Request
{ "userID": "A1B2..." }

// 200 — same shape as /register
```

| Status | Error |
|---|---|
| 429 | `resend_too_soon` (+ `retryAfterMs`) — 30s cooldown |
| 409 | `already_verified` |
| 404 | `unknown_user` |

Use `retryAfterMs` to drive the countdown on the resend button rather than hardcoding 30s client-side.

---

## `PUT /users/:userID/phone`

The wrong-number recovery path. Changing the number drops the user back to `pending_verification`, clears `registeredAt`, and issues a fresh OTP.

```jsonc
// Request
{ "phone": "+447700900099" }

// 200
{ "userID": "A1B2...", "phone": "+447700900099",
  "status": "pending_verification", "registeredAt": null,
  "otpExpiresAt": 1699999999999, "attemptsRemaining": 3 }
```

| Status | Error |
|---|---|
| 409 | `phone_taken` — another **verified** user owns it |
| 400 | `phone_required` |
| 404 | `unknown_user` |

Submitting the *same* number re-issues the code without changing state — which is what you want when the SMS never arrived and the user retypes it identically.

---

## Changed behaviour

**`GET /lookup`** now returns 404 for pending users. Only verified users are discoverable.

**`POST /invite`** returns **403** `sender_not_verified` or `recipient_not_verified`.

---

## Client notes

**Persist `userID` before verifying.** It's the handle for verify, resend, and phone change. Lose it and the user has to restart registration.

**Drive the resend countdown from `otpExpiresAt` and `retryAfterMs`**, not a local timer. Server time is the truth, and a client-side timer drifts across backgrounding.

**Keep the phone-change route reachable from the OTP screen.** The whole reason for `PUT /users/:id/phone` is the user who mistyped their number and will never receive a code — if the only exit from that screen is a correct OTP, they're stuck.

**Treat 200-on-already-verified as success**, and don't re-prompt.

---

## Not built yet

Deliberately absent, listed so they don't get forgotten:

- **Registration lock** — anyone can re-register any number and take it over. Production needs a PIN plus a delay window.
- **Rate limiting on `/register`** — an attacker can enumerate numbers by watching which ones re-register versus create.
- **OTP delivery** — console only. Real SMS is a third party outside the trust boundary.
- **Attempt limits per phone** rather than per code — burning one code and requesting another resets the counter.
