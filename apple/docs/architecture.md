# Little Sister (Apple client) — Architecture

How the Swift codebase is built **today**. For the product (what and why) see
[`project.md`](project.md); for the rationale behind specific choices see
[`decisions.md`](decisions.md) and [`adr/`](adr/).

---

## 1. Technology stack

| Concern | Choice |
|---------|--------|
| Language | Swift, macOS 15 (Sequoia) minimum deployment |
| UI | SwiftUI for the *content* of the two windows (Settings, Debug Log), hosted in AppKit windows this app creates and orders front itself (ADR-0008); AppKit (`NSStatusItem`, `NSMenu`, `NSWindow`, `NSAlert`, `NSSound`) for the menu bar item, its menu, window presentation, and alerting — SwiftUI's `MenuBarExtra` was tried and dropped (ADR-0001) |
| State | `@Observable` (the `Observation` framework), not `ObservableObject`/Combine |
| Networking | `URLSession`, no third-party HTTP client |
| Persistence | `UserDefaults` for non-secret settings; macOS **Keychain** (`Security` framework) for the bearer token (ADR-0005) |
| Testing | Swift Testing (`@Test`/`@Suite`, `#expect`/`#require`), not XCTest |
| Dependencies | None — no Swift Package Manager packages; adding any requires an explicit OK |
| License | Inherits the repository's (MIT) |

Expected deployment: a single Mac, run from Xcode or as a local Apple Development-signed
build, querying one `little-sister` server instance (local or remote) over its
JSON API. Not distributed via the Mac App Store or notarized for wider
distribution — see [`project.md`](project.md) §5 (Non-goals).

---

## 2. Repository layout

```
apple/
├── README.md                 # entry doc — open in Xcode, build & test
├── LittleSister.xcodeproj/   # open this in Xcode
├── LittleSister/             # app sources (see §2.1)
├── LittleSisterTests/        # unit tests (Swift Testing)
├── LittleSisterUITests/      # UI test target scaffold, unused so far
├── docs/                     # this documentation set
│   └── api/                  # the JSON API contract this app targets (copied in, one-way)
├── memory/                   # the in-Xcode agent's own persistent memory (unrelated to the app itself)
└── .gitignore
```

This subtree is **self-contained**: open `LittleSister.xcodeproj` and build
without the rest of the surrounding repository. `docs/api/` is a one-way copy
of the server's contract (see [`project.md`](project.md) §1). An agent
connected only through Xcode's own tooling (its built-in Claude Agent, or an
external CLI agent via `xcrun mcpbridge`) is scoped to this `apple/` directory
and cannot see anything above it — which is exactly why this `docs/` set lives
here rather than being folded into the repository root's.

The project uses Xcode 16's **file-system-synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`): `LittleSister/`, `LittleSisterTests/`
and `LittleSisterUITests/` are each tracked as a whole folder, not file-by-file
in `project.pbxproj` — any file placed anywhere under one of those roots
becomes a build member automatically on the next build, no project-file
editing needed. The project itself sits directly in `apple/`, not
nested inside a same-named wrapper folder as Xcode's "New Project" flow would
normally produce.

### 2.1 `LittleSister/` — app sources

| File | Responsibility |
|------|-----------------|
| `LittleSisterApp.swift` | `@main` entry point; owns `MonitoringViewModel` and `StatusItemController`; declares the single placeholder scene the `App` protocol requires (§3) |
| `WindowPresenter.swift` | Creates, shows and closes the Settings and Debug Log windows as `NSWindow`s hosting the SwiftUI views, and owns the `.regular`/`.accessory` activation-policy flips (§5, ADR-0008) |
| `Models.swift` | `StatusCode`, `StatusResponse`, `StatusNode` — the decoded API shapes |
| `StatusAPIClient.swift` | builds the request, calls the API, maps HTTP/decoding failures to `APIError` |
| `DisplayState.swift` | maps a `StatusNode` to a `DisplayState`; the transition-to-notification decision function |
| `MonitoringViewModel.swift` | polling loop, applies new state, drives notifications/alarm/modal, owns the alarm repeat loop |
| `StatusItemController.swift` | owns the `NSStatusItem` and its `NSMenu`; icon coloring/blinking |
| `AppSettings.swift` | typed `UserDefaults` wrapper for all non-secret settings |
| `TokenStoring.swift` | `TokenStoring` protocol + `KeychainTokenStore`, the bearer token's only storage |
| `NotificationSending.swift` | `NotificationSending` protocol + `LiveNotificationSender` (banner via `UNUserNotificationCenter`, alarm audio via `NSSound`) |
| `SettingsView.swift` | the Settings window's SwiftUI form |
| `DebugLog.swift` / `DebugLogView.swift` | in-app ring-buffer log + its viewer window |
| `little-sister_voice.wav` | the bundled **default** alarm sound, a spoken voice message (plain resource, not in `Assets.xcassets` — ADR-0002) |
| `little-sister_alarm.wav` | the original bundled alarm sound, a short beep — kept as a selectable alternative, no longer the default |
| `Assets.xcassets` | app icon, accent color, `AlertIcon` (used by the modal dialog) |
| `ContentView.swift` | the default template view Xcode generates for a new SwiftUI app; **unused** — the app has no `WindowGroup`. Left in place, a candidate for deletion |

---

## 3. App lifecycle

There is no Dock icon (`LSUIElement = YES` in build settings) — this is a
pure menu-bar/accessory app. `LittleSisterApp.init()` builds one
`MonitoringViewModel` (reading the current `AppSettings`/Keychain token),
starts its polling loop, and constructs one `StatusItemController` bound to
it. Both live for the app's entire process lifetime; nothing recreates them.

**No SwiftUI scene is ever presented.** `body` declares a single empty
`Settings { EmptyView() }` purely because the `App` protocol requires at least
one scene; `Settings` is the placeholder because, unlike `Window`, it never
auto-presents at launch, and an `LSUIElement` app has no app menu to reach it
from. Everything the user sees is AppKit:

- the menu bar icon and its dropdown are `StatusItemController`'s own
  `NSStatusItem`/`NSMenu` (ADR-0001);
- the Settings and Debug Log windows are `NSWindow`s built on demand by
  `WindowPresenter`, each hosting the corresponding SwiftUI view in an
  `NSHostingController` (ADR-0008).

---

## 4. Domain model & state

### 4.1 `Models.swift`

```swift
enum StatusCode: String, Decodable {
    case ok = "OK", warn = "WARN", error = "ERROR"
    case maintenance = "MAINTENANCE", undefined = "UNDEFINED"
}

struct StatusResponse: Decodable {
    let schemaVersion: Int
    let generatedAt: Date
    let status: StatusNode
    // init(from:) rejects any schemaVersion != 1
}

struct StatusNode: Decodable {
    let path: String
    let name: String
    let ownCode: StatusCode
    let code: StatusCode          // the rolled-up code — this is what the app displays
    let reasons: [String]
    let timestamp: Date?          // null for multi-check containers (v1.2 contract)
    let frequencySeconds: Int?
    let maintenance: Bool
    let stale: Bool
    let children: [StatusNode]
}
```

`ownCode` is decoded but never read anywhere outside `Models.swift` — display
logic reads only `code`, the server's rolled-up status, matching the API
contract (`docs/api/`).

### 4.2 `DisplayState`

```swift
enum DisplayState: Equatable {
    case healthy
    case warning(isStale: Bool)
    case error
    case maintenance
    case undefined(reason: String)    // the server explicitly reported UNDEFINED
    case unavailable(reason: String)  // the client couldn't reach or parse the server at all
}
```

Labels are **1:1 with the server's own vocabulary** (`ok`, `warn`, `error`,
`maintenance`, `undefined`, lowercase) — see ADR-0003 for why `unavailable` is
a separate case rather than reusing `undefined`. `isSameCase(as:)` treats
`.undefined`/`.unavailable` as equivalent for anti-spam purposes, and ignores
`isStale`/`reason` associated values — a stale flag flipping, or a
connection-failure reason changing, isn't a meaningful transition.

`displayState(for: StatusNode)` is the single mapping function; `code == .ok
&& stale` becomes `.warning(isStale: true)`, never a silently-fine `.healthy`.
`code == .warn` also carries `node.stale` into `isStale` — `.warning(isStale: true)` when
stale, `.warning(isStale: false)` otherwise.

`notification(from: DisplayState?, to: DisplayState) -> (title, body)?`
decides *whether* a transition is worth notifying about and what to say — a
pure function, the same one covered by `NotificationTests.swift`'s 35 tests.
It returns `nil` when `from` is `nil` (see §4.4 for how the app still alerts
on an already-broken startup) or when `from.isSameCase(as: to)`.

### 4.3 `StatusAPIClient`

Builds `GET /status` or `GET /status/<nodePath>` against a configured base
URL, with `Accept: application/json`, `Authorization: Bearer <token>`, and a
generated `X-Flow-Id`. Maps the response to `StatusResponse` or a typed
`APIError`, surfacing Problem JSON (RFC 9457) `detail`/`title` when present.
The network-layer cases are named rather than collapsed — `noConnection`,
`cannotResolveHost`, `cannotConnect`, `connectionLost`, `timeout`,
`blockedByAppTransportSecurity` (macOS refusing plain HTTP to a public host
name, which needs a remedy in the message rather than a code), and a
`networkError(code:)` fallback that carries any unnamed `URLError`'s code
(ADR-0011 §1); `unauthorized`, `notFound`, `serverError`, `invalidResponse`,
`unsupportedSchemaVersion`, and `contractMismatch` cover the cases where the
server answered. `contractMismatch` is the drift case: when the full decode
throws a `DecodingError`, `decodeResponse` probes the same bytes with a plain
`JSONDecoder` for `schema_version` alone — three outcomes: version 1 →
`contractMismatch(detail:)` naming the first failing coding path (e.g.
`status.own_code — type mismatch`); another version → `unsupportedSchemaVersion`
(normally unreachable, since `StatusResponse.init` rejects a foreign version
before any field decodes); probe fails → `invalidResponse`, unchanged.
`decodeResponse` is static and pure — testable without a network, like
`apiError(for:host:)`. The mapping is `StatusAPIClient.apiError(for:host:)` and
the user-facing wording `MonitoringViewModel.errorReason(from:)`, both static
and pure so the whole table is tested without a network. Each case also carries
its own `retryClass` — `transient` or `definite`, i.e. whether asking again
unprompted could produce a different answer — as a property beside the case list
rather than a table in the loop that consumes it (§4.4), since retry-ability is
a fact about the failure and not a policy of any one caller. Wording is the
opposite: that genuinely is the consumer's business, which is why it lives on
the view model. Dates decode via a
custom strategy accepting RFC 3339 timestamps both with and without
fractional seconds (the server emits both).

It also owns the session policy, so the composition root never builds a
`URLSessionConfiguration`. `makeSession(pollInterval:)` returns the
fresh-per-poll `URLSession` (a long-lived one can go on reusing a connection the
network already killed), enables `waitsForConnectivity` so a request made before
the path is ready waits rather than failing instantly, and derives **both** of
its timeouts from one budget: `min(30, pollInterval * 4 / 5)` seconds — over an
interval first clamped to `AppSettings.minimumPollInterval`, so the budget has
no lower bound of its own to keep aligned with the loop's — caps the whole
attempt (`timeoutIntervalForResource`, which is also what bounds that wait), and
half of it is the idle timeout (`timeoutIntervalForRequest`). The request copies
that idle timeout off the session rather than keeping `URLRequest`'s own 60-second
default, since which of the two would win is undocumented; the number still comes
from exactly one place, and a short poll interval is no longer overruled by a
constant that knows nothing about it (ADR-0011 §2).
`timeoutBudget(pollInterval:)` and `requestTimeout(pollInterval:)` are static
and pure, so the derivation is tested without a network.

`fetchStatus(onWaitingForConnectivity:)` takes one callback, defaulting to a
no-op so there is a single request path rather than one the app uses and one the
tests do. It is invoked when URLSession parks the request because the path is
not viable yet (§4.4, ADR-0011 §3), through a small private per-task delegate
passed to `session.data(for:delegate:)` — per-task because a session-level
delegate is retained until the session is invalidated, and this app builds one
session per poll. The callback arrives on the session's delegate queue and this
type hops for nobody: it is `@Sendable`, and the main-actor hop belongs to the
caller that owns main-actor state.

### 4.4 `MonitoringViewModel`

`@Observable @MainActor`. Owns `displayState`, `lastChecked`, `lastSucceeded`,
`lastResponse`, `isRefreshing`, `isAlarmActive`, `isWaitingForNetwork`, and
`previousDisplayState` (used only internally, to detect transitions).

`startPolling()` requests notification authorization once (non-blocking,
silent on denial) and starts a loop: poll immediately, then every
`currentPollInterval` seconds (default 60, minimum 5) — re-read from
`AppSettings` before each wait rather than captured at launch, because the
session's timeout budget (§4.3) is derived from the same setting on every poll
and the two must not disagree — never overlapping
(`isRefreshing` guards re-entry). Each poll builds a **fresh**
`StatusAPIClient` from the current `AppSettings`/Keychain values — there is no
cached client — so a settings change takes effect on the very next poll (or
immediately, via the Settings window's OK button, which also calls
`manualRefresh()`).

The loop does **not** wait the configured interval after a *failed* poll: the
delay starts at 5 seconds and doubles with each consecutive failure — 5, 10,
20, 40 — capped at the configured interval, and reset by the first success
(ADR-0010). A cold boot leaves the network path unready long enough for the
first attempt or two to time out, and a full interval on top of each timeout
kept the app at `unavailable` for about 90 seconds after every restart.

That backoff is for failures that might heal unaided. A failure the server
answered clearly — a rejected token, a missing node path, an unsupported schema
version, or a contract mismatch the server is consistent about — or one that
never left this Mac (an ATS refusal, §4.3) cannot change by being repeated, and repeating it is what costs something at the other end, so
it waits the configured interval floored at 60 seconds instead, whatever the
failure count (ADR-0011 §4). Recovery does not depend on waiting that out:
committing Settings calls `manualRefresh()`, so a corrected token is retried at
once. Which side a failure falls on is `APIError.retryClass` (§4.3), a property
of the failure rather than of this loop, switching without a `default` so a case
added later cannot compile until it picks one.

The schedule lives in
`MonitoringViewModel.retryDelay(consecutiveFailures:pollInterval:retryClass:)`,
a pure static function so it can be tested without running a loop; the loop
remembers the last failure's class, passes it in, and logs the delay and that
class whenever the delay differs from the configured interval.

`isWaitingForNetwork` is the one piece of observable state that deliberately
does **not** go through `applyState(_:)`. It is raised by
`noteWaitingForNetwork(token:)` when §4.3's callback reports that URLSession is
holding the request for a viable path, and lowered when the request ends,
whichever way it ends; the menu shows a line while it is up (§5) and the Debug
Log gets one entry per poll that waits. When the whole-attempt budget expires
while the flag is still up — the parked request never left this Mac —
`poll()`'s `APIError` catch uses `pollFailureReason(from:waitingForNetwork:pollInterval:)`
(pure static, same pattern as `errorReason(from:)`) to compose `"No usable
network path (waited N s) — the request never left this Mac"` (where N is
§4.3's `timeoutBudget`), instead of the generic `"Request timed out"` which
would falsely imply the server was reached and was slow. A `manualRefresh()`
click while a poll is already in flight now also logs `"Refresh ignored — a
poll is already running"` (with `" (waiting for a network path)"` while the
flag is up) rather than discarding the click silently. Routing it into `.unavailable(reason:)`
instead would make every wait a state change, and notifications fire on case
changes — so a two-second hiccup would emit "Monitoring status unavailable"
followed by "available again" (ADR-0011 §3). The `token` is what keeps the flag
honest: the callback arrives on a background queue and its hop to the main actor
can outlive the request, so each poll takes a number from a monotonic sequence
and only the poll currently in flight can raise the flag — otherwise a late
callback could set a flag that nothing is left to clear.

`applyState(_:)` is where a decoded state (or a poll failure, mapped to
`.unavailable(reason:)`) becomes visible: it updates `displayState`, logs a
transition to `DebugLog` when the case changed, computes a `note` (§4.2's
`notification(from:to:)` — or, on the very first poll of the launch,
synthesizes a startup note instead, since `from` is `nil` and would otherwise
suppress all first-poll alerting even if the service is already broken), and
— when the destination is `.error` and `AppSettings.soundOnError` is
enabled — starts the alarm (§6). A modal dialog (§6) shows when
`AppSettings.modalAlertOnError` is enabled. The alarm stops automatically the
moment a later poll leaves `.error`, or early via `acknowledgeAlarm()` (§6).

---

## 5. Menu bar UI — `StatusItemController`

`@MainActor final class StatusItemController: NSObject, NSMenuDelegate` owns
a real `NSStatusItem` and `NSMenu` — not SwiftUI's `MenuBarExtra`, which
forces template/monochrome icon rendering regardless of any rendering
modifier (ADR-0001). `@Observable` changes are bridged into this non-SwiftUI
context via `withObservationTracking(_:onChange:)`, re-subscribed inside its
own `onChange` closure each time.

The menu's dynamic rows (state, target, timestamps, reasons, a conditional
"Waiting for network…" line while §4.4's flag is up, and a conditional
"Acknowledge Alarm" item) are rebuilt fresh via
`NSMenuDelegate.menuNeedsUpdate(_:)` right before each open — no continuous
observation needed for menu content, only for the icon. Static action rows
(Refresh now, Open dashboard, View Debug Log…, Settings…, Quit) are
`NSMenuItem`s with `target`/`action` selectors.

The menu shows up to three timestamps (ADR-0009). **Observed** (`status.timestamp`)
appears only where the server has a single answer — a leaf or a single-check
container. Three forms: a stamp → `Observed: <time>` (with `  (stale)` when the
server's `stale` flag is set); no stamp but stale → `Observed: —  (stale)` (no
single check answers for this subtree and something below is overdue); no stamp
and not stale → absent (a healthy multi-check root shows no `Observed:` line).
**Server snapshot** (`generated_at`) is omitted whenever it would render exactly
like **Last request**, which on a fast link is most of the time; it reappears by
itself when the two clocks disagree: a slow server, skew between the two machines,
or a federated branch answered from an older snapshot. **Last request** is this
app's clock when it *sent* its last poll — stamped before the request, so it
precedes the server's snapshot rather than following it. Keeping the client's own clock visible in every state is what lets a
stale server be told apart from a stalled polling loop; `Last success:` is
added while `.unavailable`, where the two server lines are frozen at the last
response that arrived. Instants render with a date whenever they are not from
today, and always in this Mac's timezone — the API sends RFC 3339 with an
offset, `Date` is absolute, and the menu's formatters set no `timeZone`.

The icon itself: a plain template `NSImage` for every state except `.error`,
which shows a non-template, colored, blinking icon (full-opacity ↔
~35%-opacity red, alternating on a ~600ms `Task` loop) — see ADR-0001 for why
a non-template image and two SF Symbol palette colors are both required to
render correctly.

This app hides its Dock icon (`LSUIElement`), so secondary windows (Settings,
Debug Log) don't come to front on their own. `WindowPresenter`
(`WindowPresenter.swift`) handles it: the menu action calls it directly, it
flips `NSApp.setActivationPolicy(.regular)`, activates the app, builds the
window and orders it front (`makeKeyAndOrderFront` plus `orderFrontRegardless`),
and restores `.accessory` once the **last** managed window closes. A window
that has been closed is rebuilt rather than reused, so `SettingsView.onAppear`
re-runs and the form reloads from truth on every open (ADR-0004).

Every menu action, window presentation and policy flip is recorded to the
debug log under the `menu` category (§8) — this path used to fail silently,
and now says so.

---

## 6. Alert prominence

A transition into `.error` (the most severe, actionable state) gets three
independently configurable layers beyond the plain notification banner from
§4.4 — all built without any third-party dependency:

- **Focus-breaking notification** — `content.interruptionLevel =
  .timeSensitive` breaks through Focus/Do Not Disturb. `LiveNotificationSender`
  conforms to `UNUserNotificationCenterDelegate` and implements `willPresent`
  returning `[.banner, .list]` — required for the banner to show at all while
  the app is in the foreground, independent of any OS-level notification
  setting.
- **Alarm sound**, via AppKit's `NSSound` rather than the notification
  framework's own sound support (ADR-0002) — three sources, chosen in
  Settings: one of two bundled sounds — a spoken voice message
  (`little-sister_voice.wav`, the default) or a short beep
  (`little-sister_alarm.wav`, kept as an alternative) — one of the fourteen
  macOS system sounds (`NSSound(named:)`), or an arbitrary file picked at
  runtime via `NSOpenPanel` (`NSSound(contentsOf:)`). Repeats for as long as
  `.error` persists (`AppSettings.repeatAlarmSound`, default on), independent
  of the poll interval — the gap between repeats is **duration-aware**
  (`NSSound.duration` + a short pause, floored at 5s), not a fixed interval,
  so a sound longer than the old fixed 5s gap doesn't overlap itself.
- **Modal dialog** — an `NSAlert` (`alertStyle = .warning`, the app's own
  logo as its icon, the real failure reason as its message) shown once per
  transition into `.error`, gated by `AppSettings.modalAlertOnError`. Its
  single button reads "Acknowledge" and stops the repeating alarm.

Either the dialog's button or an "Acknowledge Alarm" menu item (shown only
while the alarm is actively looping) can silence the alarm early — both call
`MonitoringViewModel.acknowledgeAlarm()`, which stops only the sound; the
banner, icon blink, and dialog are otherwise unaffected. Once acknowledged,
the alarm can't restart for the same ongoing error episode "for free" — the
same anti-spam gate from §4.2 already prevents a fresh `startAlarm()` call
until there's an actual transition into `.error` again.

Full rationale for each of the non-obvious choices here (`NSStatusItem` vs.
`MenuBarExtra`, `NSSound` vs. `UNNotificationSound`, no auto-stop timeout) is
in [`decisions.md`](decisions.md) / [`adr/`](adr/), not repeated here.

---

## 7. Settings & authentication

| Setting | Storage |
|---------|---------|
| Base URL, node path, poll interval | `UserDefaults` (`AppSettings`) |
| Bearer token | macOS **Keychain**, via `TokenStoring`/`KeychainTokenStore` — never `UserDefaults`, `Info.plist`, source, git, or logs (ADR-0005) |
| Sound/modal toggles, alarm sound choice, repeat toggle, custom sound path | `UserDefaults` (`AppSettings`) |

`SettingsView` buffers edits in local `@State` and only commits — writing to
`AppSettings`/Keychain — when the user presses **OK** (which also triggers an
immediate refresh and closes the window). **Cancel**, or closing the window
any other way, discards the buffered edits instead. See ADR-0004 for why
committing is deliberately not "apply as you type."

`http://localhost:8000` is the default base URL — the server doesn't yet
serve HTTPS. What that means for the client once the server side moves to
TLS is an open question.

---

## 8. Debug log

`DebugLog.shared` (`@MainActor @Observable`) is a fixed-capacity ring buffer
(200 entries, oldest dropped) of terse, one-line entries — app launch, every
poll's outcome, display-state transitions, each notification sent, committed
settings (never the bearer token), and every menu command, window
presentation and activation-policy flip (category `menu`, §5). Each entry is also mirrored to
`os.Logger`, so the same events show up in Console.app / `log show` even if
the in-app viewer is never opened. `DebugLogView`, reachable via "View Debug Log…" in the menu, lists entries
newest-first, one row each: a time column, a color-coded category badge, and
the message. Only the message column wraps, so however long an entry is (a
committed-settings line runs to a few hundred characters) the time and
category columns stay aligned down the whole list.

Above the list, one toggle button per category plus a substring filter narrow
what's shown; below it, an entry count, **Clear**, and a copy button whose
label states what it will actually copy — **Copy All**, or **Copy Filtered**
while a filter is active, so a filtered view never puts hidden entries on the
clipboard unannounced. Row text is selectable, so one line can be copied
without the rest.

The filtering is `DebugLog.visibleEntries(from:hiding:matching:)` — a pure
static function deliberately kept out of the view so it can be unit-tested
without a window. The window's frame is autosaved under `DebugLogWindow`,
because `WindowPresenter` rebuilds the window on every open (§5) and would
otherwise forget the size the user gave it.

---

## 9. Tests

Swift Testing, `LittleSisterTests/`:

- `LittleSisterTests.swift` — API decoding: schema version acceptance/
  rejection, nested children, null `frequency_seconds`, all `StatusCode`
  values, timestamps with and without fractional seconds, unknown-field
  tolerance.
- `DisplayStateTests.swift` — `displayState(for:)` mapping for every
  `StatusCode` × `stale` combination.
- `APIClientTests.swift` — HTTP behavior: headers sent, `401`/`404` mapping,
  Problem JSON detail extraction (valid and malformed), invalid-JSON handling,
  `URLError` mapping, node-path URL construction.
- `NotificationTests.swift` — the pure `notification(from:to:)` function
  across every named and generic transition, plus an integration suite
  driving a real `MonitoringViewModel` + a `NotificationSpy` through actual
  polls (startup notification, repeat-suppression, `isAlert` gating).
- `SettingsTests.swift` — `AppSettings`' typed `UserDefaults` wrapper
  (defaults, round-tripping, node-path normalization).
- `DebugLogTests.swift` — ring-buffer capacity and clipboard formatting.

Unit tests never call a real backend — `StatusAPIClient` is driven through a
mocked `URLProtocol`. `LittleSisterUITests/` exists as Xcode's default
scaffold (created automatically alongside the unit test target) but is
unused.

---

## 10. Known limitations

- `NSSound` playback for the alarm is assumed — not exhaustively verified —
  to be unaffected by macOS's per-app "Play sound for notification" toggle,
  since it's a separate audio API from notification-delivered sound — an
  open point to verify.
- No timeout/auto-stop backstop on the repeating alarm — acknowledging is the
  only way to silence one early, by design (ADR-0007), but this means an
  unattended Mac with an unresolved error and nobody around to acknowledge
  will alarm indefinitely.
- `ContentView.swift` is dead code (§2.1).
- Custom alarm sound formats beyond AIFF/WAV/CAF/M4A (e.g. MP3) are
  documented as supported by `NSSound` but not stress-tested against every
  format in this app specifically.
