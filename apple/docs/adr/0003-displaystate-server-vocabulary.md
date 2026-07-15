# ADR-0003 — DisplayState labels match the server's vocabulary 1:1, and unavailable is its own case

- **Status:** Accepted
- **Date:** 2026-07-02
- **Related:** none
- **Register:** [`../decisions.md`](../decisions.md)

## Context
The original `DisplayState` used its own presentation words —
`healthy`/`warning`/`alert`/`maintenance`/`unknown` — chosen independently of
the server's own status vocabulary (`OK`/`WARN`/`ERROR`/`MAINTENANCE`/
`UNDEFINED`, [`docs/project.md`](https://github.com/m-31/little-sister/blob/main/docs/project.md) §2.2, and
the web dashboard's own lowercased rendering of the same). Two problems
surfaced once the app was actually in use: the client's words didn't match
what the web dashboard showed for the same underlying state, and one client
word (`unknown`) was being used for two genuinely different situations — the
server explicitly reporting `UNDEFINED`, and the client simply failing to
reach or parse the server at all.

## Decision
- `DisplayState.label` matches the server's own lowercased vocabulary
  exactly: `"ok"`, `"warn"` (`"warn (stale)"` when stale), `"error"`,
  `"maintenance"`, `"undefined"`.
- The no-server-response case is a **separate** `unavailable(reason:)` case,
  labeled `"unavailable"` — not folded into `undefined`, since the server
  never actually said "undefined" in that situation.
- `.undefined` and `.unavailable` are still treated as the **same case** for
  notification anti-spam purposes (`isSameCase(as:)`) — switching between
  "server says undefined" and "can't reach the server" isn't a meaningful
  transition to alert on, any more than a stale flag flipping is.

## Rationale
- A user reading both the web dashboard and the menu bar client for the same
  server should see the same word for the same state. Inventing client-only
  vocabulary (`alert` instead of `error`, `unknown` instead of `undefined`)
  adds a translation step with no benefit.
- Collapsing "server says undefined" and "client can't reach server" into one
  word actively hides useful information — they have different causes and
  different fixes (a check that hasn't reported yet, vs. a network/auth/
  decode problem on the client's own machine).
- Equating them for **notification** purposes (rather than display) is still
  correct: neither state tells the user anything actionable beyond "no
  reliable status available," so oscillating between the two shouldn't spam
  a notification each time.

## Consequences
- `DisplayState`'s six cases (`.healthy`, `.warning(isStale:)`, `.error`,
  `.maintenance`, `.undefined(reason:)`, `.unavailable(reason:)`) don't map
  one-to-one onto the server's five `StatusCode` values — there's one extra,
  client-only case with no server equivalent, which is deliberate.
- Any future server-side status vocabulary change (a new `StatusCode`, a
  rename) needs a matching client change to stay in sync — there's no
  indirection layer smoothing that over.

## Alternatives considered
- **Keep the original client-only vocabulary.** Simpler in isolation, but
  actively confusing across the two surfaces (dashboard vs. menu bar) a user
  is expected to cross-reference.
- **Fold `unavailable` into `undefined`.** Rejected — loses real diagnostic
  information for no display benefit, since the two already look identical
  to the user (a "?" icon) regardless.
