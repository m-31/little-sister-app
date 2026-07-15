# ADR-0004 — Settings commit on OK, applied live via fresh per-poll reads

- **Status:** Accepted
- **Date:** 2026-07-01
- **Related:** [ADR-0005 — Keychain-only token storage](0005-keychain-only-token-storage.md)
- **Register:** [`../decisions.md`](../decisions.md)

> **Update (2026-07-03):** the original decision let *any* window close —
> including the red traffic-light button, with no separate Cancel — commit
> the buffered edits. That surprised a user closing the window without
> intending to save, so a dedicated **Cancel** button was added, and the
> "closing without OK still commits" behavior was removed entirely: only OK
> commits now; Cancel and any other way of closing the window both discard.
> The rest of this ADR (buffer locally, commit only on an explicit action,
> read `AppSettings` fresh every poll tick) is unchanged.

## Context
`SettingsView` edits several values (base URL, node path, poll interval,
bearer token, alert toggles). Two questions needed settling: when do edits
actually take effect, and how does the polling loop pick up a change without
a restart?

## Decision
- `SettingsView` buffers every field in local `@State` and only writes to
  `AppSettings`/Keychain when the user presses **OK** — which also triggers
  an immediate `manualRefresh()` and closes the window. A **Cancel** button,
  and closing the window any other way (the red traffic-light button), both
  discard the buffered edits without writing anything.
- `MonitoringViewModel` never holds a fixed `StatusAPIClient` or token for its
  lifetime — **every poll tick** builds a fresh client from the
  current `AppSettings` values and a fresh Keychain read.

## Rationale
- Committing only on an explicit action (rather than live, per-keystroke)
  avoids sending half-typed base URLs or a token being edited mid-paste to
  a real request.
- Building a fresh client every poll means a settings change takes effect
  within one poll interval automatically, with **no notification/callback**
  needed between the Settings window and the polling loop — the simplest
  possible wiring, at the cost of a slightly more expensive per-poll setup
  (constructing a `URLRequest` and reading the Keychain each time), which is
  negligible at a 60-second-or-slower cadence.
- OK also calling `manualRefresh()` means the user sees the effect of their
  change immediately, rather than waiting up to a full poll interval.

## Consequences
- There is no live preview of settings changes while the window is open —
  by design; a user who wants to abort a change presses **Cancel** (or
  closes the window any other way), and none of the buffered edits reach
  `AppSettings`/Keychain.
- Every poll tick does a Keychain read, which happens on a background task
  off the UI-blocking path, so this is not user-visible latency.

## Alternatives considered
- **Apply on every keystroke.** Rejected — risks firing requests against
  invalid intermediate input (an incomplete URL, a token mid-edit).
- **A long-lived `StatusAPIClient` updated via a settings-changed
  callback/notification.** More typical MVC wiring, but adds a
  synchronization point (make sure the callback fires, make sure the client
  is rebuilt with the same values `AppSettings` now holds) for no real
  benefit over just reading fresh values each tick, given the app already
  polls on its own schedule regardless.
