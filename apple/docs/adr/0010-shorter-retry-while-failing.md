# ADR-0010 — A shortened, backing-off retry while polling is failing

- **Status:** Accepted
- **Date:** 2026-08-01
- **Related:** [ADR-0004 — Settings commit on OK, applied live via fresh per-poll reads](0004-settings-apply-on-ok.md)
- **Register:** [`../decisions.md`](../decisions.md)

> **Update (2026-08-02):** the schedule below governs **transient** failures
> only. A definite answer from the server — `401`, `404`, an unsupported schema
> version — does not heal by being asked again sooner, so it waits
> `max(pollInterval, 60)` rather than entering the backoff at all; see
> [ADR-0011 §4](0011-connectivity-policy.md), which also explains why that is a
> floor and not a longer penalty. The backoff itself, its constants, and
> everything else recorded here are unchanged.

## Context
The polling loop waited the user's configured interval — 60 seconds by default
— after *every* poll, successful or not. Combined with a
`timeoutIntervalForResource` of 30 seconds, that made recovery from a cold boot
slow in a way that was easy to mistake for a broken app. A verified reboot
produced this:

```
16:48:33  App launched                     ← first poll starts
16:49:03  Poll failed: Request timed out   ← 30s later
16:49:45  Poll failed: Request timed out   ← a manual Refresh, another 30s
16:50:01  Poll: warn                       ← first success, 88s after launch
```

At boot the network path is not ready yet, so `waitsForConnectivity = true`
does what it was chosen to do — waits rather than failing instantly — and the
attempt consumes the full resource timeout. Waiting another full interval on
top of that meant the app sat at `unavailable` for around a minute and a half
after every restart, and emitted two notifications while doing so.

## Decision
While polls are failing, retry sooner than the configured interval:

- The delay starts at **5 seconds** and **doubles with each consecutive
  failure** — 5, 10, 20, 40 — **capped at the configured poll interval**.
- The first success resets the counter, returning immediately to the normal
  cadence.
- The schedule is `MonitoringViewModel.retryDelay(consecutiveFailures:pollInterval:)`,
  a pure static function, so it is unit-tested without running a loop.
- The loop logs `Retrying in Ns (N consecutive failures)` whenever the delay
  differs from the configured interval. It is decided and logged in the loop
  rather than inside `poll()`, so the number logged is the one actually waited
  — a manual refresh does not reschedule the loop.

## Rationale
- The common failure is transient: a boot, a sleep/wake, a Wi-Fi change. Those
  resolve in seconds, and a fixed 60-second penalty for them is pure latency.
- An unbounded fast retry would be worse than the problem. Capping at the
  configured interval means a server that is down all night is polled exactly
  as often as it was before this change, so nothing gets noisier in the case
  that lasts longest.
- Doubling rather than a flat short retry keeps the fast path fast without
  needing a second tunable: the schedule converges on the user's own setting,
  which is the only interval they ever expressed an opinion about.
- Capping also means a user who sets a 5-second interval is never *slowed down*
  by the retry floor.

## Consequences
- Recovery after a reboot roughly halves, but does **not** become instant: with
  each failed attempt still costing up to 30 seconds of resource timeout, that
  timeout — not the interval — is now the dominant term. Attempts begin at
  roughly 0s, 35s, 75s, 125s instead of 0s, 90s, 180s.
- Going further means attacking the timeout rather than the interval: watching
  the network path directly (`NWPathMonitor`) to poll the moment connectivity
  returns, which would also allow a shorter resource timeout. That is a new
  framework dependency and is deliberately **not** taken here.
- A failing server now produces a few extra debug-log lines early in the
  outage. They state the schedule explicitly, which is what makes this
  behavior diagnosable rather than mysterious.

## Alternatives considered
- **A flat short retry (10s) while failing.** Simpler, but polls a
  permanently-dead server six times as often as before, indefinitely, for no
  benefit after the first minute.
- **`NWPathMonitor` instead.** Solves the boot case exactly rather than
  approximately, and is the right answer eventually — but it adds the `Network`
  framework and another piece of state to own, for a case the backoff already
  improves substantially. Worth revisiting if boot latency still annoys.
- **Shortening `timeoutIntervalForResource`.** Tempting, since it now dominates.
  Rejected for now because the 30-second bound was chosen deliberately against
  `waitsForConnectivity = true`; shortening it trades cold-launch robustness for
  recovery speed, and that trade deserves its own decision rather than being
  folded into this one.
