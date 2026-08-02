# Changelog

All notable changes to the Little Sister Apple client. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) and are independent
of the little-sister library's version line — when the JSON API contract
matters, an entry states the minimum library version required.

## [0.2.1] - 2026-08-02

### Fixed

- **A poll that expired its timeout waiting for a network path now says so.**
  When URLSession held the request because the network path was not yet viable
  and the whole-attempt budget expired before the path cleared, the failure
  read "Request timed out" — implying the server was reached and was slow. In
  truth the request never left this Mac. The Debug Log and menu now show "No
  usable network path (waited N s) — the request never left this Mac" instead,
  where N is the configured attempt budget. A "Refresh now" click while a poll
  is already running now also logs "Refresh ignored — a poll is already
  running" (or "… (waiting for a network path)" during a parked poll) rather
  than being silently discarded.

- **A contract drift within schema_version 1 now says what went wrong instead of looping forever.**
  When a JSON response parses but no longer matches the app's model, the menu now
  shows a specific message naming the first mismatch (e.g. `status.own_code — type
  mismatch`) and waits the poll interval before retrying, rather than entering the
  outage backoff and repeating every few seconds. A body that the server sent
  coherently is no longer treated the same as a truncated network response.
  `unsupportedSchemaVersion` wording is also sharpened to name both versions.

- **Null `timestamp` in the server response no longer causes every poll to fail.**
  The server's v1.2 contract makes `timestamp` nullable — the root of any
  multi-check deployment has no single observation time and sends `null`. The old
  client treated this as a decode error, entered the outage backoff, and looped
  "Poll failed: Invalid response" indefinitely (2026-07-30 incident). `timestamp`
  is now optional. The menu shows `Observed:` only where the server has a single
  answer; a stale node with no timestamp shows `Observed: — (stale)` instead; a
  non-stale node with no timestamp shows no `Observed:` line at all. Staleness now
  also reads correctly on the `warn` state — the label shows `warn (stale)` when
  the server reports `WARN` with `stale: true`, matching the server's own dashboard.

- **The distributed app was built with code-coverage instrumentation.** Release
  builds inherited Xcode's default `ENABLE_CODE_COVERAGE = YES`, which a
  scheme-driven build turns into real profiling instrumentation — so the shipped
  binary ran slower than it should and wrote profiling data on launch. Release
  builds now disable it, and the packaging script refuses to build a disk image
  from an instrumented binary rather than trusting that setting to stay correct.

- **"Settings…" and "View Debug Log…" did nothing when the app had been
  started at login.** An app launched this way is never activated, so the
  hidden helper window those two menu items depended on was never created and
  the commands were dropped without any error. Both windows are now opened
  directly and work in every launch mode.

- **Changing the poll interval no longer needs a restart.** It was the one
  setting that kept its old value until the app was relaunched: the polling
  loop read it once at launch and never again, so pressing OK appeared to
  work — the new value was saved and shown — while the app carried on at the
  old cadence. It now takes effect from the next poll, like every other
  setting.

### Added

- **The app says when it is waiting for a network connection.** macOS holds a
  request until there is a usable connection rather than failing it instantly —
  which is the right behavior, but until now it was indistinguishable from the
  app having quietly stopped: the status stayed on its last reading and "Last
  request" stopped advancing. The menu now shows "Waiting for network…" for as
  long as that is what is happening, and the Debug Log records it. Nothing else
  changes: a wait is not treated as a status change, so a connection that drops
  for two seconds and comes back produces no notifications.

- Debug log entries for menu commands and window activity, so a menu item
  that fails to do anything leaves a trace.

### Changed

- **A failed poll now says what actually went wrong.** Where every network
  problem used to read "Network unavailable", the menu now distinguishes having
  no network connection, a server name that cannot be resolved, a server that
  resolves but cannot be connected to, and a connection that dropped
  mid-request — so the reason line points at where to look. An unrecognized
  failure reports its system error code instead of being flattened.

- **A plain-HTTP address that macOS refuses now says so.** macOS blocks
  unencrypted HTTP to any public host name (an address like `nas:8000` or an IP
  is exempt, which is why this only appears once you enter a real domain). That
  used to surface as an opaque error number while the same address opened
  perfectly well in a browser; it now reads "Plain HTTP is blocked by macOS;
  use https://".

- **Recovery after a restart is faster.** A failed poll is no longer followed by
  the same wait as a successful one: while polling is failing the app retries
  after 5 seconds, then 10, 20, 40, up to your configured interval, returning to
  the normal cadence on the first success. A server that stays down is polled no
  more often than before.

- **A failure the server has answered clearly is no longer retried every few
  seconds.** The faster retry above is for problems that may pass on their own.
  A rejected token, a node path that does not exist, a status format this app is
  too old to read, or an address macOS refuses outright are none of those:
  asking again cannot change the answer, and repeatedly presenting a rejected
  token is exactly what an authentication log or a rate limit will notice. These
  now wait your configured interval, and at least a minute, before the app tries
  again unprompted — while pressing OK in Settings still retries immediately, so
  a corrected token or path takes effect at once. At the default 60-second
  interval nothing changes.

- **A short poll interval is now honored instead of being overruled.** Every
  poll used to be allowed up to 30 seconds no matter what interval you chose,
  and since the app waits *after* a poll finishes, a 5-second interval really
  meant one check every 35 seconds. How long a single poll may take is now
  derived from your interval — four fifths of it, never below 4 seconds and
  never above 30 — so a fast cadence behaves like one, and an unresponsive
  server is given up on before the next check is due. At the default 60-second
  interval nothing changes.
- **The menu's timestamps are consistent and unambiguous.** The old "Updated:"
  line named the server's own reading but appeared only in some states, and
  showed no date — so a ten-day-old value looked like this morning. Every
  state now shows the same three: **Node observed** (with `(stale)` when the
  server says so), **Server snapshot**, and **Last request**, the last being
  this app's own clock, so a stale server can be told apart from an app that
  has stopped polling (**Server snapshot** is hidden while it would just repeat
  **Last request**, and returns when the two clocks disagree). Dates appear whenever a value isn't from today, and all
  times are shown in your Mac's timezone whatever zone the server runs in.
- **The Debug Log window shows far more at a glance.** One line per entry
  instead of two, with a color-coded category badge; buttons to show or hide
  each category and a filter field to search the text; an entry count, a
  Clear button, and selectable rows so a single line can be copied on its
  own. The window remembers the size you give it.

## [0.2.0] - 2026-07-15

First release. A macOS menu-bar client for the
[little-sister](https://github.com/m-31/little-sister) status server:

- polls the read-only JSON status API (bearer token, kept in the macOS
  Keychain) and shows the overall status — or a chosen subtree — as a
  menu-bar icon;
- notifies on status transitions and repeats an **alarm** for unacknowledged
  errors: sound, blinking icon, modal dialog — each independently switchable,
  acknowledgment stops the sound only;
- Settings for base URL, subtree path, poll interval and alert behaviour,
  plus an in-app debug log.

Requires a little-sister server serving JSON API **contract 1.1.0** (envelope
`schema_version: 1`) — every little-sister release from its first (v0.2.0) on.
