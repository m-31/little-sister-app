# Little Sister (Apple client) — Product Specification

This is the product specification for the **macOS menu-bar client**: the
domain concepts, principles, and non-goals. It describes *what* the client
is, not how the code is built ([`architecture.md`](architecture.md)).
Significant design choices are recorded in [`decisions.md`](decisions.md).

The server-side product this client depends on has its own specification at
[`docs/project.md`](https://github.com/m-31/little-sister/blob/main/docs/project.md) — read that first if the
domain concepts below (status, code, roll-up) are unfamiliar. This document
only covers what's specific to the client.

---

## 1. What this client is

A small native macOS app that sits in the **menu bar** and answers one
question at a glance: *is the thing I'm watching OK?* It polls one configured
`little-sister` server's read-only JSON status API on an interval, shows the
server's rolled-up status as a colored menu bar icon, and — for the most
severe state — makes sure that state is genuinely hard to miss: a
Focus-breaking sound, a blinking icon, and a modal dialog, all
independently switchable off.

It is a **compact indicator and alert client**, not a reimplementation of the
web dashboard. There is no drill-down into history, no maintenance controls,
no admin actions — those already exist in the browser
([`docs/project.md`](https://github.com/m-31/little-sister/blob/main/docs/project.md) §3). The client's entire
reason to exist is to be present where the browser usually isn't: sitting
quietly in the corner of the screen, demanding attention only when something
is actually wrong.

This is exactly the "glance from the menu bar" scene the server-side product
spec already imagines
([`docs/use-cases.md`](https://github.com/m-31/little-sister/blob/main/docs/use-cases.md) §7) — this app is that
scene, built.

---

## 2. Domain concepts

### 2.1 DisplayState

The client's own presentation state, mapped from the server's `code` (never
`own_code` — the client always wants the rolled-up status, not one node's
private state):

| DisplayState | Server origin | Meaning |
|---|---|---|
| `.healthy` | `code == OK`, not stale | Green. Nothing to see. |
| `.warning(isStale:)` | `code == WARN`, or `OK` but stale | Degraded, or an `OK` the client can no longer trust as current. |
| `.error` | `code == ERROR` | The severe, actionable state — the one this whole app's alert-prominence machinery exists for. |
| `.maintenance` | `code == MAINTENANCE` | Intentionally offline; not an alert. |
| `.undefined(reason:)` | `code == UNDEFINED` | The server itself has no reliable status for the selected node. |
| `.unavailable(reason:)` | *(no server response)* | The client couldn't reach or parse the server at all — network failure, timeout, bad auth, decode failure. |

`.undefined` and `.unavailable` look the same to a user (a "?" icon, greyed
out) and are treated as the same case for alerting purposes — the
distinction exists only because the two situations have genuinely different
causes worth logging separately (server-side vs. client-side), not because a
user needs to tell them apart at a glance.

### 2.2 Meaningful transitions, not every poll

The client polls every 60 seconds by default, but only **notifies** on a
transition that actually changes the *case* of the display state — a stale
flag flipping, or the specific reason text changing while the state stays
`.error`, doesn't fire a new alert. This mirrors the server's own status
model, where what matters is the transition, not the individual observation.

### 2.3 Alert prominence

Not every `DisplayState` deserves the same volume. A transition into
`.error` — the only state that represents an actual, actionable failure —
gets escalating treatment the other states don't: it breaks through Focus,
it can play a repeating sound, it can pop a modal dialog, and until it's
acknowledged or resolved, the menu bar icon keeps blinking. Recovery,
maintenance, and "status unavailable" all still notify (so nothing is
silently missed), just quietly.

### 2.4 Acknowledgment vs. resolution

Acknowledging an alarm stops the *sound* — nothing else. The icon keeps
blinking, the menu still shows `.error`, and a fresh un-acknowledged alarm
starts on the next distinct error episode (recovery, then error again). This
is a deliberate, narrow scope: acknowledgment answers "I've heard this," not
"this is fixed" — only an actual state transition (the server reporting
something other than `ERROR`) clears the alert.

---

## 3. Product surfaces

- **Menu bar icon** — always visible, colored/blinking only during `.error`,
  otherwise a plain monochrome glyph matching the surrounding menu bar chrome.
- **Dropdown menu** — current state, target endpoint, timing (server
  snapshot / node observed / last request), the first reason when not
  healthy, and action items: Refresh now, Open dashboard (launches the
  browser dashboard for the same endpoint), View Debug Log…, Settings…, Quit.
  An "Acknowledge Alarm" item appears only while an alarm is actively
  repeating.
- **Settings window** — base URL, node path, poll interval, bearer token,
  and the Alerts section (sound on/off, alarm sound source and repeat, modal
  dialog on/off).
- **Debug Log window** — a scrollback of what the app has done, copyable as
  plain text, useful when something needs diagnosing without Xcode attached.
- **Notification banners, sound, and a modal dialog** — the alert-prominence
  layer (§2.3).

There is no dedicated history or events view in the client — that's the
web dashboard's job (`Open dashboard` gets you there).

---

## 4. Principles

Inherits the repository's engineering principles: boring over clever, small
reviewable diffs, phase discipline, a green test suite. Specific to this
client:

- **No new dependencies without an explicit OK** — the entire app is built on
  AppKit/SwiftUI/Foundation/UserNotifications/Security, no Swift Package
  Manager packages.
- **The server is the source of truth for status semantics.** This app
  never re-derives roll-up logic, aggregation, or severity ordering — it
  reads `code` and maps it to a display state one-to-one (§2.1). Any
  disagreement with the server's status belongs in the server's domain model,
  not worked around here.
- **The bearer token lives only in the Keychain** — never `UserDefaults`,
  `Info.plist`, source, git, or logs (see
  [`decisions.md`](decisions.md)).
- **Read-only.** Like the server's current JSON API
  ([`docs/project.md`](https://github.com/m-31/little-sister/blob/main/docs/project.md) §2.9), this client only
  reads. Write actions (acknowledging a *server-side* alert, setting
  maintenance from the menu bar) are a possible future direction, not a
  current one.

---

## 5. Non-goals

- **Not a dashboard replacement.** No history, no events log, no maintenance
  controls — the browser already does all of that well.
- **Not distributed or notarized for wide release.** This is a personal/
  internal tool, built and run from Xcode (or a local Apple Development-signed build) against
  a server the user already trusts. No App Store, no notarization pipeline,
  no auto-update mechanism.
- **Not multi-server.** One configured base URL / node path at a time — no
  switching between several `little-sister` instances from one app instance.
  (A user who watches multiple servers runs multiple copies, or waits for
  satellite federation to land server-side —
  [`docs/project.md`](https://github.com/m-31/little-sister/blob/main/docs/project.md) §2.9 — at which point one
  server, one client, still holds.)
- **Not a general alerting/paging platform.** No escalation policies, no
  on-call schedules, no snooze durations — acknowledgment is binary and
  scoped to the current error episode (§2.4). Anyone wanting Telegram/Slack/
  PagerDuty-style routing should look at the server-side notification
  direction instead — a planned little-sister capability, not part of this
  client.
