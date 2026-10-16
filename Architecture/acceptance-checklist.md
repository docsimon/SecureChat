# Acceptance checklist

The app's final tests: run on two phones before a release (TestFlight or
App Store), after any change to pairing, sessions or the relay, and
whenever the automated tests cannot see what matters (cameras, vibration,
real networks). Every step here was seen working on phones on the date
given; a step that fails blocks the release.

Automated tests come first and must already pass (`testing-strategy.md`):
module tests, SecureChat unit and integration tests, relay tests, and the
SessionKit live relay tests against the relay being released
(`TEST_RUNNER_SESSIONKIT_LIVE_RELAY=ws://<relay>/relay`).

## Setup

- Phone A runs SecureChat. Phone B runs SecureChat, or `SessionTestApp`
  where it cannot (the iPhone X); B's steps say what to look at in each.
- Both reach the relay and the Auth Server under test. With development
  accounts (Debug builds) the relay needs `RELAY_DEV_CLAIMED_ACCOUNTS=true`;
  a release candidate is tested with registered devices and the flag off.

## Pairing (seen 2026-10-15)

1. Both on "Add contact" (harness: "Pair face to face"), screens facing,
   a hand's width apart: a short tap, then the long vibration on both;
   both say "Paired with …"; each lists the other once.
2. Close and pair the same two phones again: both complete quickly, no
   duplicate contact.
3. Pull apart right after the first tap: one says "Got …", the other
   "Looking…". Hold them together again without closing: both complete.

## Chat (seen 2026-10-15)

4. A opens B's chat: "Starting a secure session…", then "Secure session".
   Messages both ways arrive, in order.
5. B disconnects (harness: Disconnect; SecureChat: background). A sends:
   "B is offline…", the message "Not delivered".
6. B removes A (harness: Remove all). A sends: after about 10 s "B didn't
   answer", the message "Not delivered". B stores nothing from A.
7. A goes to the background and back: reconnects by itself within a few
   seconds; the open chat gets a new session.

## Presence and "contact left" (seen 2026-10-15)

8. A's dot for B is green while their session is open (chat list and chat
   title).
9. **Two-way exchange, then B leaves** (Disconnect, or background in
   SecureChat): within about a second A's dot turns red and A's chat says
   B is offline. A's next message, once B is back, arrives on a new session.
10. **One-way exchange: nobody is told.** B removes A (harness: Remove
    all). A sends (it goes unanswered). A goes to the background. B must
    NOT learn it: the harness log shows no "… is offline" for A. (The
    other direction, B leaving after A wrote unanswered, is covered by the
    live relay test "someone who only wrote to us is not told"; on a phone
    A's dot is already red from "didn't answer", so it cannot be seen.)

## Stored messages (seen 2026-10-16)

11. Quit SecureChat and open it again: every chat shows its messages,
    with their status.
12. First launch of a build with storage option B over an earlier one:
    messages written before are still there and readable.
13. Swipe a chat, "Delete messages", confirm: its messages are gone, after
    a relaunch too; the contact and the other chats stay; a new message to
    that contact works.

## Recording a run

Note the date, the builds, the phones and the relay under test at the end
of this file, with anything that differed.

- 2026-10-15: SecureChat on iPhone 16 Plus, `SessionTestApp` on iPhone X,
  docker relay on the Mac, development accounts. Steps 1–10 as described;
  reported working by the user.
- 2026-10-16: same phones and relay, SecureChat installed over the
  2026-10-15 build. Steps 11–13 as described; reported working by the user.
