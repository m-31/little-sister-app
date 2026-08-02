# ADR-0011 — Connectivity policy: a failure taxonomy, timeouts derived from the poll interval, and waiting-for-network as a reported state

> **2026-08-02 (§3):** §3's reported wait (the `isWaitingForNetwork` flag and the "Waiting for network…" log line) now also shapes the failure's wording. When the whole-attempt budget expires while the flag is up — the parked request never left this Mac — `poll()` composes `"No usable network path (waited N s) — the request never left this Mac"` (where N is `StatusAPIClient.timeoutBudget(pollInterval:)`) instead of the generic `"Request timed out"`, which implies the server was reached and was slow. The composed reason flows through the existing "Poll failed: …" log line and `.unavailable(reason:)`. A `manualRefresh()` click while a poll is already running now also logs `"Refresh ignored — a poll is already running"` (with `" (waiting for a network path)"` appended while the flag is up) rather than returning silently.

> **2026-08-02 (§4):** The error taxonomy (§4) gains a new `definite` case: `contractMismatch(detail:)`. When a full decode throws a `DecodingError` against a body that does parse as JSON, `decodeResponse` probes the same bytes with a plain decoder for `schema_version` alone. Three outcomes: version 1 → `contractMismatch(detail:)` carrying the first failing coding path (e.g. `status.own_code — type mismatch`); a different version → `unsupportedSchemaVersion` (normally unreachable, since `StatusResponse.init` rejects a foreign version before any field decodes); probe fails → `invalidResponse`, unchanged. `contractMismatch` is definite: the server answered coherently and consistently, and only an app or server update changes the outcome. The distinction matters because a body that parses as JSON and carries the envelope is not a truncated body — a contract drift is not the same failure as a flaky link, and the outage backoff is exactly the wrong response to it.

- **Status:** Accepted
- **Date:** 2026-07-27
- **Related:** [ADR-0010 — A shortened, backing-off retry while polling is failing](0010-shorter-retry-while-failing.md),
  [ADR-0003 — DisplayState labels match the server's vocabulary](0003-displaystate-server-vocabulary.md),
  [ADR-0009 — One timestamp vocabulary in the menu](0009-one-timestamp-vocabulary.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
This app is a poller against a status server on another host, so network
failure is a normal operating condition rather than an exception. Its current
network behavior is the sum of three separately-reasonable decisions that were
never considered together:

- a **fresh `URLSession` per poll**, so a stale keep-alive connection can't
  outlive a network change;
- **`waitsForConnectivity = true`** with **`timeoutIntervalForResource = 30`**,
  so a request made before the OS considers the path ready waits instead of
  failing instantly;
- **`URLRequest.timeoutInterval = 30`** set separately in the request builder.

Each is defensible alone. Together they produce three problems.

### 1. Six situations, two strings
A poll can fail in materially different ways, each of which points somewhere
different:

| Situation | How it fails | Where to look |
| --- | --- | --- |
| No local path at all | no connectivity | this Mac — interface, sleep/wake, Wi-Fi |
| Path up, name won't resolve | DNS failure | the resolver; LAN names are the first thing to break after a network change |
| Name resolves, host unreachable | fast if refused, slow if filtered or unrouted | routing, VPN, subnet |
| Host up, nothing listening | connection refused, immediately | the service, not the network |
| Service slow | eventually answers | server load |
| Service accepts, then hangs | only a timeout ends it | the server |

`errorReason(from:)` collapses all of these into `.timedOut` →
"Request timed out" and *everything else* → "Network unavailable".
`URLError` already distinguishes them; the information is being discarded at
the last step before it would have been useful.

### 2. The timeout ignores the poll interval
`timeoutIntervalForResource` is hardcoded at 30 seconds while the poll interval
is user-configurable from 5 seconds up. The polling loop is sequential — it
sleeps *after* a poll returns — so the effective period while the server is
unreachable is `timeout + delay`. Expressed as a multiple of what the user
asked for:

| Interval set | Effective period when failing | Multiple |
| --- | --- | --- |
| 60s | 30 + 60 (or 30 + 5 with ADR-0010) | 1.5× / 0.6× |
| 5s | 30 + 5 | **7×** |

A user who asks for a 5-second cadence and gets one poll every 35 seconds has
had their setting quietly overruled by a constant that knows nothing about it.
The constant is not wrong for a 60-second interval; it is wrong as a constant.

### 3. Waiting for connectivity is invisible
`waitsForConnectivity = true` means URLSession holds the request until the path
becomes satisfied, then sends it. For those seconds the app knows perfectly
well that it has no connectivity — but nothing surfaces it: the menu keeps
showing the previous status and a `Last request` that stops advancing, which
reads as a frozen app rather than an informed one.

Worth stating plainly, because it settles a question that keeps coming up:
**`waitsForConnectivity` already is the connectivity monitor.** URLSession
resumes the request itself the moment the path is viable — the same behavior a
hand-rolled `NWPathMonitor` would provide, without the debounce logic or the
extra state. What is missing is not the mechanism but the reporting. This is
Apple's own position, not an inference: the documentation calls waiting
"preferable to testing for reachability", and the session that introduced the
API argues that a reachability check "only tells you that you *might* be able
to reach the server, not that you will" — the check is stale the moment it
returns.

One documented limit applies: **the session waits only when establishing the
*initial* connection.** If connectivity drops mid-transfer the task fails
rather than waiting again. That would matter for an app holding a long
download open; it barely matters here, because this client builds a fresh
`URLSession` and therefore a fresh connection for every poll — so every poll
*is* an initial connection. A mid-transfer drop surfaces as
`.networkConnectionLost`, which the taxonomy in §1 names and the ADR-0010
backoff retries.

## Decision

### 1. Map `URLError` to distinct reasons
Replace the two-string mapping with one that preserves what the system already
knows:

| `URLError` code | Reason |
| --- | --- |
| `.notConnectedToInternet` | No network connection |
| `.dnsLookupFailed`, `.cannotFindHost` | Cannot resolve *host* |
| `.cannotConnectToHost` | Cannot connect to *host* |
| `.networkConnectionLost` | Connection lost |
| `.timedOut` | Request timed out |
| `.appTransportSecurityRequiresSecureConnection` | Plain HTTP is blocked by macOS; use `https://` |
| `.badServerResponse` | *(folds into `.invalidResponse`)* |
| anything else | Network error (*code*) — never silently flattened |

The host name is presentational and safe to show; the bearer token appears in
no reason string, no log line, and no error path, as always.

An earlier draft of this table rendered `.cannotConnectToHost` as "*host*
refused the connection". That over-claims: the code covers a refusal, but
equally a filtered port, an unrouted subnet, or a host that is down — cases
`URLError` does not distinguish. For a monitoring client a confidently wrong
pointer is the more expensive error, because it sends someone to inspect a
service that is fine while the real fault is the route. "Cannot connect to
*host*" is always true and still separates the service/route layer from DNS
("Cannot resolve *host*") and from the local path ("No network connection"),
which is the distinction the taxonomy exists to draw.

**App Transport Security is in this table, and it is the row that matters most.**
The project sets no `NSAppTransportSecurity` keys — `GENERATE_INFOPLIST_FILE = YES`
with nothing configured — so stock ATS applies, and stock ATS blocks plain HTTP
to any *public host name*. Today's `http://nas1:8000` works only because
`nas1` is unqualified and therefore exempt, alongside IP addresses and
`.local` names. Nothing in this repository said so until now.

That exemption is invisible until the moment Settings is used for the thing
Settings is for. Type `http://monitor.example.com:8000` and the request is
refused before a packet leaves the machine, with
`NSURLErrorAppTransportSecurityRequiresSecureConnection` (-1022). Rendered as
"Network error (-1022)" it is the most confusing failure in the set: the same
URL opens fine in the user's browser, so nothing about the symptom suggests
this Mac is the thing refusing. It is the one reason string that has to name
the remedy rather than describe the fault.

It also fixes its own place in §4: an ATS refusal is **definite**. No retry
schedule will ever make ATS relent, so it belongs at the 60-second floor rather
than entering the backoff at 5 seconds.

`.badServerResponse` (-1011) is likewise not a network fault — something
answered, but not parseable as HTTP — so it folds into the `.invalidResponse`
case the enum already had, instead of the numeric fallback.

**TLS failures are deliberately not in this table.** `.secureConnectionFailed`,
`.serverCertificateUntrusted` and `.serverCertificateHasBadDate` fall to the
fallback row and read "Network error (*code*)". That costs nothing while the
server is plain HTTP, and naming them now would be building ahead of a
request — but it is exactly where a clear message would earn its keep, since
an untrusted self-signed certificate is a configuration problem the user can
act on. Tracked as part of the HTTPS move rather than done here.

### 2. Derive both timeouts from the poll interval
One number, computed in one place, from the only cadence the user ever
expressed an opinion about:

```
budget = min(30, max(AppSettings.minimumPollInterval, pollInterval) * 4 / 5)
```

— four fifths of the interval, capped at 30 so a very long interval doesn't
license a very long hang. The input is clamped to **the setting's own
minimum**, which is the only floor in the expression.

That clamp is doing real work, and an earlier draft of this ADR got it wrong.
It wrote the floor as a literal `4`, which is numerically identical for every
input — but it made `budget < pollInterval` a relationship between two
independent constants that merely happened to line up (4 below the loop's
minimum of 5), in a codebase where that minimum was itself written out in two
other places. Deriving from a clamped interval instead makes the property
arithmetic: below the cap the budget is four fifths of an interval, and an
interval that reaches the cap must exceed 37 seconds to have got there. The
"4 seconds" a fast configuration sees is now a consequence — four fifths of
the smallest interval anyone can pick — not a number anyone maintains.

The bounds of the setting therefore live on `AppSettings` beside
`defaultPollInterval`, and the Settings stepper, the loop's clamp and this
derivation all read them from there. Transport *policy* still has no business
on a `UserDefaults` wrapper (§"Where it lives"); the *bounds of a setting* are
exactly its owner's business.

The two session timeouts mean different things, and get **different** values
derived from that one budget:

- **`timeoutIntervalForResource = budget`** — the hard cap on the whole
  attempt, *including* any wait for connectivity. This is the one that has to
  stay under the poll interval.
- **`timeoutIntervalForRequest = budget / 2`** — the idle timeout, which only
  begins to matter once a connection is established. Keeping it tighter than
  the outer cap leaves the full budget available for waiting on a path, while a
  server that accepts the connection and then goes silent is abandoned in half
  the time. No floor: the budget's own smallest value is 4, so this cannot fall
  below 2, and writing that 2 down would recreate in miniature the
  two-constants-lining-up problem the clamp above just removed.

An earlier draft of this ADR gave both settings the same value, reasoning that
a single small JSON body has no phase where "progressing slowly" differs from
"stalled". That was wrong in a way worth recording: with
`waitsForConnectivity`, the outer cap covers a period — waiting for a path —
during which the idle timer is not running at all. The two are therefore
measuring different things even for a single small body, and the conventional
layering (idle tighter, total looser) is the one that behaves correctly here.

The derivation is a pure function, tested without a network.

**Where it lives.** Both statics go on `StatusAPIClient`: a pure
`timeoutBudget(pollInterval:)` and a `makeSession(pollInterval:)` that applies
it. The transport type owns transport policy, `LittleSisterApp`'s
`clientProvider` closure stops constructing a `URLSessionConfiguration`
altogether. `buildRequest()` keeps no timeout constant of its own: it reads
`session.configuration.timeoutIntervalForRequest` back off the session that
will run the request, so the number still has exactly one source *and* the
outcome no longer depends on whether a `URLRequest`'s own 60-second default
takes precedence over a session's — which is not clearly documented. Left
bare, the idle timeout could silently have been 60 seconds under a 30-second
cap, with nothing anywhere to say so. That file already hosts a
pure, tested policy static in `apiError(for:host:)` (§1), so this is the
established home for what the client knows about talking to the server rather
than a new one.

**Prerequisite: the poll interval has to be live first.** It is currently the
one setting that does not apply until relaunch —
`MonitoringViewModel.pollInterval` is a `let` captured at init, `startPolling()`
is called exactly once from `LittleSisterApp.init()`, and committing Settings
calls `manualRefresh()`, which polls once but never re-anchors the loop.
Everything else is re-read per tick by the `clientProvider` closure exactly as
ADR-0004 intended; the interval simply missed that pattern.

That matters here because the closure reads `AppSettings()` fresh on every
poll. Deriving the budget there while the loop still runs on a value captured
at launch would leave the timeout tracking the *new* interval and the cadence
the *old* one — worse than today, where the two are at least stale together.
So the interval becomes an injected `intervalProvider: () -> Int` alongside
`clientProvider` — `{ AppSettings().pollInterval }` in the app, a fixed value
in tests — restoring the "every tick reads current settings" property ADR-0004
claims for every field. `retryDelay(consecutiveFailures:pollInterval:)` already
takes the interval as a parameter, so it needs no change.

### 3. Report waiting-for-connectivity, without disturbing state
Implement `URLSessionTaskDelegate.urlSession(_:taskIsWaitingForConnectivity:)`,
passed per-task via `session.data(for:delegate:)` so session construction is
untouched. It records a debug-log entry and sets an observable
`isWaitingForNetwork` flag that the menu can show.

Verified end to end on a running app — Wi-Fi off, then on — rather than only
from documentation: the callback fires, the whole-attempt budget bounds the wait
to the second, and a parked request is resumed rather than re-sent. The log and
what each line establishes are in
[`../platform-notes.md`](../platform-notes.md).

**It must not go through `applyState(_:)`.** Routing it into
`.unavailable(reason:)` would make every transient wait a state change, and the
notification machinery fires on case changes — so a healthy → waiting → healthy
blip would emit "Monitoring status unavailable" followed by "available again"
for a network hiccup that resolved itself in two seconds. The flag is
presentational only: it changes what the menu says, never what the app decides
has happened.

### 4. Network failures keep the backoff; a definite answer does not
Per-reason retry rules for *network* failures ("DNS failures retry faster,
refusals slower") are **not** adopted: they multiply the state space, and no
evidence suggests ADR-0010's uniform schedule is wrong for any of them.

That reasoning does not extend to a server that answered clearly. A `401` or a
`404` is a correct, definite reply — neither heals by being asked again five
seconds later — yet both currently increment the same counter as a dropped
packet, and so earn the *fast* end of the backoff. Retrying a rejected token
several times a minute is also the one failure whose repetition costs something
at the other end: rate limits, lockouts, and a log full of failed
authentications. Mature practice differentiates here; NetNewsWire honors
`Retry-After` on `429` per host and skips a URL for roughly two days after any
other `4xx` (see References).

So `APIError` is split in two:

| Class | Cases | Delay |
| --- | --- | --- |
| **Transient** — may heal unaided | `.noConnection`, `.cannotResolveHost`, `.cannotConnect`, `.connectionLost`, `.timeout`, `.networkError`, `.serverError`, `.invalidResponse` | ADR-0010's backoff, unchanged |
| **Definite** — will not heal unaided | `.unauthorized`, `.notFound`, `.unsupportedSchemaVersion`, `.blockedByAppTransportSecurity` | `max(pollInterval, 60)` |

`.blockedByAppTransportSecurity` is the clearest definite case of all: the
request never reached the network, and retrying cannot change the outcome until
the base URL itself changes — which, per ADR-0004, triggers a `manualRefresh()`
the instant the user commits Settings. In implementation terms the branch point
is the unconditional `consecutiveFailures += 1` in `poll()`'s `APIError` catch;
that single line is what this decision splits.

`.serverError` stays transient because a 5xx is the server *failing*, not
answering. `.invalidResponse` stays transient because a body truncated by a
flaky link is indistinguishable from one the server malformed.

The delay for a definite answer is the configured interval, floored at **60
seconds**. The floor is what stops the hammering: at the default interval it
changes nothing at all, while at a 5-second interval it cuts useless
authentication attempts by a factor of twelve.

It is a floor rather than a long fixed penalty on purpose — recovery must not
depend on waiting it out, and it doesn't: committing Settings calls
`manualRefresh()`, so a corrected token or node path is retried the instant the
user presses OK (ADR-0004). The floor governs only how often the app asks
*unprompted*, and keeping it short bounds how stale the loop's own schedule can
be after a fix to at most a minute — which is why this is not, say, five
minutes.

## Consequences
- The reason line in the menu becomes actionable — "Cannot resolve nas1"
  points at DNS, "Cannot connect to nas1" points past DNS at the service or
  the route. Today both read "Network unavailable".
- A short poll interval starts behaving like one. A long interval is unchanged:
  at 60 seconds the budget stays 30, exactly as today.
- The app stops looking frozen while URLSession waits for a path, and the debug
  log permanently separates "no local path" from "server not answering". Those
  are otherwise hard to tell apart, since a resource-timeout expiry during a
  connectivity wait appears to surface as an ordinary timeout — behavior that
  is consistent with what developer reports describe but that Apple does not
  document explicitly. `taskIsWaitingForConnectivity` firing is a positive
  signal and needs no such inference, which is an argument for §3 independent
  of the reporting benefit.
- `isRefreshing` remains as a guard against a manual refresh racing the loop.
  It is not load-bearing for the loop itself, which is sequential.
- The fresh-`URLSession`-per-poll decision is untouched and still required.

## Alternatives considered
- **`NWPathMonitor`.** Rejected: `waitsForConnectivity` already resumes the
  request when the path becomes viable, so the monitor would duplicate an
  existing mechanism while adding debouncing, a second source of truth about
  connectivity, and an interaction with the in-flight-poll guard. Its one real
  advantage — reacting to connectivity returning *between* polls rather than
  during one — is worth at most the few seconds until the next retry fires,
  and ADR-0010 already puts that first retry 5 seconds after a failure. Worth
  revisiting only if `taskIsWaitingForConnectivity` shows waits the budget
  can't absorb.

  The premise held when it was finally observed: a request parked by the flag is
  resumed the moment the path returns, three seconds in the measured case, with
  nothing scheduling it — which is precisely the job the monitor would have been
  hired for (see [`../platform-notes.md`](../platform-notes.md)).

  In fairness this is not unanimous: current writing on the subject recommends
  `waitsForConnectivity` as the foundation *and* `NWPathMonitor` as a secondary
  trigger to retry once a connection is restored — precisely the combination
  declined here. That advice is aimed at apps whose failed request is a
  user-visible dead end awaiting a manual retry. This app already retries on
  its own schedule, so the monitor would only move the next attempt earlier by
  the remainder of a 5-second backoff. The reasoning, not the conclusion, is
  what should be re-examined if that backoff ever lengthens.
- **`waitsForConnectivity = false`, fail fast, let the retry loop handle it.**
  Coherent, and appealing now that a backoff exists — and it is what
  NetNewsWire actually does: no connectivity wait, a tight 15-second idle
  timeout, and reliance on the next refresh. Still rejected here, but on
  narrower grounds than before: a feed reader fans out across many hosts where
  one stalled wait would hold up a batch, while this client makes exactly one
  request at a time to one known host, so waiting costs nothing that the
  budget in §2 doesn't already bound. It also reintroduces the cold-launch
  failure the flag was turned on to fix. If §3's reporting shows waits that
  the budget can't absorb, this is the alternative to revisit first.
- **Keep fixed timeouts, just lower them.** Picks a different arbitrary
  constant. The problem is not the value at a 60-second interval; it is that
  the value is unrelated to the interval at all.
- **Per-reason retry schedules.** See §4.

## References
The timeout semantics and the reachability guidance above were checked against
sources outside this project rather than assumed. Because the primary sources
are old — the API dates from 2017 — they were also re-checked against current
ones before this ADR was written:

- No networking session appears in the **WWDC 2026** guides consulted, and no
  source describes `URLSession`, `waitsForConnectivity` or either timeout as
  deprecated or superseded. Absence from one curated guide is weak evidence,
  but it is the evidence available.
- A [February 2026 URLSession guide](https://oneuptime.com/blog/post/2026-02-02-swift-urlsession-networking/view)
  still configures `waitsForConnectivity = true` and treats `URLSession` as the
  current, dependency-free default. It sets `timeoutIntervalForRequest` tighter
  than `timeoutIntervalForResource` — the layering §2 adopts.
- [SwiftLee, 2022](https://www.avanderlee.com/swift/urlsessionconfiguration/)
  independently arrives at a 30-second request timeout as "large enough for a
  regular request to finish", which is where this app's current constant came
  from. That is generic advice for a request-driven app; a poller can do better
  by deriving from its own interval, which is what §2 does.

Actively-maintained source was also surveyed, on the principle that shipping
code beats an article. It did **not** validate §2, and the result is recorded
here rather than quietly dropped:

- [Alamofire](https://github.com/Alamofire/Alamofire) sets no timeouts in its
  default configuration, and Apple's own
  [swift-openapi-urlsession](https://github.com/apple/swift-openapi-urlsession)
  sets none either — both leave the policy to the application. Consistent with
  §2's premise (a library has no cadence to derive from, so it declines to
  invent one), but not evidence for the derivation itself.
- Alamofire's `NetworkReachabilityManager` warns *in its own source* that
  reachability "should not be used to prevent a user from initiating a network
  request, as it's possible that an initial request may be required to
  establish reachability" — independent of Apple's guidance, since it never
  mentions `waitsForConnectivity`.
- The closest analogue found — a macOS menu-bar app polling a status endpoint
  every 60 seconds — uses `URLSession.shared` with every default: a 60-second
  request timeout, a **7-day** resource timeout, no waiting for connectivity,
  all network failures collapsed into one error case, and a timer that fires on
  the interval regardless of outcome. Its request timeout therefore equals its
  poll interval exactly: one poll may consume the entire period. That is the
  failure mode §2 exists to prevent, arrived at by configuring nothing.

- **[NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire)'s
  `DownloadSession`** is the closest mature analogue: a Swift feed poller,
  actively maintained (its concurrency has been migrated to Swift 6), fetching
  many URLs on a refresh cycle. Its session configuration is deliberate and
  informative on three counts:
  - `timeoutIntervalForRequest = 15.0` — a quarter of the 60-second default,
    and far below any plausible refresh cadence. Real precedent for §2's
    *direction*: a poller should tighten the idle timeout well below the
    system default. It does not derive the value from its interval.
  - `timeoutIntervalForResource` is **not** set, left at its 7-day default —
    and consistently, `waitsForConnectivity` is **not** enabled either. With
    no connectivity wait to bound, the idle timeout does all the work, and
    the outer cap has nothing to cap. The two choices go together.
  - Failure handling is emphatically **not** reason-agnostic: a `429` has its
    `Retry-After` parsed and honored per host (defaulting to 10 minutes when
    absent), and any other `4xx` puts that URL in a skip cache for ~53 hours.

**Still, no project was found that derives its timeouts from its polling
interval.** §2's *direction* now has precedent; its derivation does not. Its
constants remain judgment and should be revisited if experience contradicts
them.

The 2017-era sources, still the authoritative statement of intent:

- [Advances in Networking, Part 2 (WWDC 2017, session 709)](https://asciiwwdc.com/2017/sessions/709)
  — introduces `waitsForConnectivity`, recommends it in place of reachability
  checks, and names `taskIsWaitingForConnectivity` as the way to observe the
  waiting state.
- [URLSessionConfiguration Quick Guide](https://useyourloaf.com/blog/urlsessionconfiguration-quick-guide/)
  — `timeoutIntervalForRequest` is the idle timeout ("the timer resets each
  time new data arrives", default 60s); `timeoutIntervalForResource` bounds the
  whole request (default 7 days) and is what limits the connectivity wait.
- [URLSession Waiting For Connectivity](https://useyourloaf.com/blog/urlsession-waiting-for-connectivity/)
  — the wait applies to the initial connection only.
- [Should you use network connectivity checks in Swift?](https://www.donnywals.com/should-you-use-network-connectivity-checks-in-swift/)
  — why a pre-flight connectivity check is stale by the time the request runs.

Two details were **not** confirmed from any authoritative source and should be
settled at the compiler rather than in prose: whether `URLRequest.timeoutInterval`
takes precedence over the session's `timeoutIntervalForRequest` (moot under §2,
which removes the per-request value so only one setting remains), and the exact
availability annotation for the per-task `data(for:delegate:)` overload used by
§3.
