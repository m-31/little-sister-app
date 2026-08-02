# ADR-0009 — One timestamp vocabulary in the menu, in this Mac's timezone

> **2026-08-01:** The `Node observed:` label was renamed to `Observed:` — the server's own dashboard renders "Observed …", and ADR-0003 keeps this client speaking the server's vocabulary. The line now appears only when it carries signal, an extension of this ADR's own rule that omits `Server snapshot` when it would render identically to `Last request` (a permanently contentless line is the same redundancy). Three rules: a stamp → `Observed: <time>` (with `  (stale)` when stale); no stamp but `stale` → `Observed: —  (stale)` — the dash signals that no single check answers for this subtree and something below is overdue; no stamp and not stale → no line (a healthy multi-check root shows only `Server snapshot` and `Last request`). The server's ADR-0027 also widens the meaning of a stamp where present: a container's stamp, where it exists, is the run time of the single check below it.

- **Status:** Accepted
- **Date:** 2026-08-01
- **Related:** [ADR-0003 — DisplayState labels match the server's vocabulary](0003-displaystate-server-vocabulary.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
Three different instants are available to the menu, and they answer three
different questions:

| Instant | Source | Question it answers |
| --- | --- | --- |
| Node observed | `status.timestamp` | How old is the data the server is reporting? |
| Server snapshot | `generated_at` | When did the server build this response? |
| Last request | client `lastChecked` | Is this app still polling at all? |

The menu used to ration these per state: healthy showed all three, the
warning/error/maintenance branch showed only `status.timestamp` under the
label **"Updated:"**, and a client-side failure showed only its own
`lastChecked`, labeled "Last attempt:". So the same value carried two
different names depending on state, the most-seen state showed the vaguest
one, and no state but healthy let you tell "the server's data is old" apart
from "this app stopped polling" — the exact ambiguity that made a real
regression hard to diagnose (see [ADR-0008](0008-appkit-owned-secondary-windows.md)).

Two further problems compounded it. The timestamp rendered as `HH:mm:ss` with
no date, so a value from a previous day read as this morning — the case that
prompted this ADR was a `19:16:53` that turned out to be ten days old.
And when the server runs in another timezone, a reader comparing the menu
against the server's own dashboard has no way to know which zone either
number is in.

## Decision
- **One shared timestamp block, in every state, under one set of labels:**
  `Node observed`, `Server snapshot`, `Last request`. Only the reason line
  still varies by state, because a client-side failure has no response to read
  reasons from.
- **`Server snapshot` is omitted when it would render exactly like
  `Last request`.** `lastChecked` is stamped *before* the request is sent, so
  on a fast link the server builds its snapshot within the same second and the
  two lines read identically. The test is the rendered string, not an elapsed
  threshold — the line returns by itself as soon as the two clocks disagree.
- **Staleness comes from the server's `stale` flag**, appended as `(stale)` to
  the `Node observed` line — never from a client-side age threshold.
- **The date is shown whenever the instant is not today**, time alone
  otherwise.
- **`Last success:`** appears additionally while `.unavailable`, where the two
  server lines are frozen at the last response that did arrive.
- All rendering stays in **this Mac's timezone**, which requires no code: the
  API sends RFC 3339 with an explicit offset, `Date` is an absolute instant,
  and the menu's `DateFormatter`s set no `timeZone`, so they use
  `TimeZone.current`.

## Rationale
- A reader should not have to know which state the app is in to know what a
  timestamp means. One vocabulary costs three menu lines and removes an entire
  class of misreading.
- `stale` is defined by the contract as "not observed within ~2× its
  interval", so the server applies each check's own interval. Any threshold
  this client invented would be wrong for every check that doesn't match it.
- Showing the date only when it isn't today keeps the common case as short as
  before while making the dangerous case impossible to misread.
- `Last request` is the client's own clock, so it keeps advancing even when
  every server-derived value is frozen — which is precisely what distinguishes
  a stale server from a dead polling loop.

## Consequences
- The menu is up to two lines taller in the warning/error states, which are
  the states a user actually reads.
- `Updated:` and `Last attempt:` disappear as labels. Nothing consumes them
  programmatically, so there is no compatibility concern.
- Because `lastResponse` survives a failed poll, the two server lines describe
  the last response that arrived rather than the current moment while
  `.unavailable`. That is the intent, and `Last success:` states how long ago
  it was.

## Alternatives considered
- **Keep the per-state rationing, just rename `Updated:`.** Smallest change,
  but leaves the polling-versus-staleness ambiguity in place in exactly the
  states where it matters.
- **Append a relative age — "(15h ago)" — to every timestamp.** Very readable,
  but the threshold at which to show it is arbitrary, and it would duplicate
  what `stale` already says correctly.
- **Drop `Server snapshot` entirely.** It rarely differs from `Last request`,
  but when it does — clock skew between the two machines, a loaded server, or a
  federated branch answered from an older snapshot — that gap is the whole
  story. Hiding it only while it is provably redundant keeps the signal without
  the noise.
