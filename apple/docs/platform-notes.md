# Little Sister (Apple client) — Platform Notes

> Swift / AppKit / SwiftUI / Xcode / macOS quirks discovered while building
> this app, written generically rather than as this app's own story — the
> point is portability: things worth not re-discovering the hard way on a
> future app. This is **not** where "why did we choose X" lives; that's
> [`decisions.md`](decisions.md) + [`adr/`](adr/). Where a quirk here led to
> an actual decision in this app, it's cross-linked to the ADR that has the
> full context.

---

## Xcode project structure

### Loose files inside `.xcassets` are silently ignored

`actool` (the asset-catalog compiler) only picks up files wrapped in a
proper catalog member (an `.imageset`/`.dataset`/etc. with its own
`Contents.json`). A file dropped directly inside `Assets.xcassets` with no
such wrapper builds without any error but never reaches the app bundle —
the resource is just silently absent at runtime. Plain resource files
(sounds, arbitrary data) belong as siblings of the source files, not inside
`.xcassets`.

### Xcode 16 file-system-synchronized groups

Xcode 16 replaced the traditional per-file `PBXFileReference` list with
folder-level `PBXFileSystemSynchronizedRootGroup` entries: whichever
folders are configured this way (blue-vs-yellow folder icons in Xcode, or
grep `project.pbxproj` for the string) automatically include every file
placed anywhere inside them — no `project.pbxproj` editing needed to
add/remove/move source files. As long as the reference is by relative name
(not an absolute path), such a folder can also be moved with a plain
`git mv` without touching the project file at all.

---

## AppKit / SwiftUI

### `NSAlert.alertStyle = .critical` auto-badges a custom `.icon`

Setting `.critical` makes AppKit overlay any custom `NSAlert.icon` with a
system caution-triangle badge automatically — there's no way to keep a
custom icon un-badged at that style. Use `.warning` if the custom icon
should render as-is.

### `NSAlert.addButton(withTitle:)` suppresses the implicit default button

Calling this at all — even once — replaces the automatic unlabeled "OK"
button; no need to separately suppress it.

### SwiftUI button sizing plateaus fast, and padding order matters

Three compounding gotchas, confirmed against Apple's own docs/sources:

- `ControlSize.extraLarge` is documented to resolve to `.large` on every
  platform except visionOS — so on macOS, `.controlSize(.large)` is already
  the ceiling; there's no bigger built-in step to reach for.
- `.bordered`/`.borderedProminent` on macOS **enforce their own fixed
  height**, regardless of padding added to the button — padding applied
  around a `.bordered`-styled button is silently absorbed, not rendered.
  ([reference](https://sarunw.com/posts/swiftui-button-size/))
- Padding placement relative to `.buttonStyle(...)` matters: padding applied
  **before** the style becomes part of the button's own content (so the
  background/border is drawn around it, growing the button); padding
  applied **after** just adds invisible space around an already-sized
  button.

Net effect: if a button needs to be genuinely, visibly larger than the
system default on macOS, don't reach for `.controlSize`/padding on top of
`.bordered`/`.borderedProminent` — write a small custom `ButtonStyle` that
owns its own padding/font/background/corner-radius entirely (see
`DialogButtonStyle` in `SettingsView.swift`).

### SwiftUI `Settings` scene / `@State` lifecycle

`onAppear` re-running unconditionally means a view can safely "reload from
truth" every time a window opens, discarding whatever was in its `@State`
before — useful for making a Cancel button (or any other non-committing
close) trivially correct: nothing needs to explicitly reset the buffered
fields, because the next `onAppear` will.

### `MenuBarExtra` forces monochrome/template icon rendering, no matter what

Confirmed via research, not a fixable SwiftUI quirk: `MenuBarExtra` enforces
template rendering on its status item image regardless of
`.renderingMode(.original)` or any tint applied in SwiftUI — this is Apple
pushing HIG-style, consistent (monochrome) menu bar icons, with no escape
hatch through the SwiftUI API surface. Getting an actually-colored menu bar
icon requires dropping down to a manually-managed `NSStatusItem` with a
plain `NSImage` that has `isTemplate = false` set explicitly — that flag is
what actually allows color through, but it's only reachable outside
`MenuBarExtra` entirely. Full story:
[`adr/0001-status-item-over-menubarextra.md`](adr/0001-status-item-over-menubarextra.md).

### A status item's `NSPopover` reads as a custom card, not a native menu

Showing SwiftUI content in an `NSPopover` when a status item is clicked
looks visually distinct from macOS's native menu bar dropdowns (rounded
card vs. thin native rows) — if a genuinely native-looking menu matters,
use `NSStatusItem.menu` directly and rebuild its dynamic content in
`NSMenuDelegate.menuNeedsUpdate(_:)` each time it opens, rather than hosting
a SwiftUI view in a popover.

### SF Symbols with multiple layers need one palette color *per layer*

A symbol like `"xmark.circle.fill"` renders as two layers (the circle, the
xmark) — `NSImage.SymbolConfiguration(paletteColors: [.systemRed])` only
supplies one color, so **both** layers render that same color and the
foreground shape visually disappears into the background one (e.g. an
"xmark in a circle" ends up looking like a plain solid dot). Supply one
color per layer, e.g. `paletteColors: [.white, .systemRed]` — and verify
which color lands on which layer by looking at the actual result, since SF
Symbols' color-to-layer mapping isn't always in the order you'd assume; be
ready to flip the array if it renders backwards.

### SF Symbols don't auto-match the size of neighboring status bar icons

Neither a plain nor a palette-colored `NSImage` built from an SF Symbol name
picks up a size that matches other icons already in the menu bar — both
render at the symbol's own default size unless a point size is set
explicitly via `NSImage.SymbolConfiguration(pointSize:weight:scale:)`.
There's no universal correct value; tune it visually against the actual
neighboring icons (a reasonable starting point: `pointSize: 16, weight:
.regular, scale: .medium`).

### `withObservationTracking` bridges `@Observable` state into non-SwiftUI code

The Observation framework (`@Observable`) only auto-updates SwiftUI views
that read the observed property inside their `body`. Driving a manually-
managed AppKit object (like a raw `NSStatusItem`) from the same observed
state needs an explicit `withObservationTracking` call to re-subscribe and
react each time the tracked property changes — SwiftUI's `body`-based
tracking doesn't extend to arbitrary imperative code for free.

### A login-launched `LSUIElement` app is never activated — so SwiftUI never presents its `Window` scenes

An accessory/menu-bar app (`LSUIElement = YES`) started by launchd as a login
item comes up **without ever becoming the active application**, and clicking
its status-item menu does not activate it either. SwiftUI defers presenting a
`Window` scene's window until the app is active, so in a login-launched
session that window is never created and its view is **never instantiated**.

That is quietly fatal for anything that lives in such a view — most of all a
`NotificationCenter` observer installed with `.onReceive`, which simply does
not exist, so posts to it reach nobody and fail with no error at any layer.
The same app launched from Finder activates, the window appears, and
everything works, which makes this look like an intermittent bug rather than a
launch-mode-dependent one.

Diagnosing it takes one command — an app in this state has *no windows at all*:

```
osascript -e 'tell application "System Events" to tell process "YourApp" \
    to get name of every window'
```

Two conclusions worth carrying to the next app: don't put process-lifetime
logic (observers, registrations, timers) in a SwiftUI view whose window may
never be presented; and if an accessory app must show a window from a status
menu, create it in AppKit (`NSWindow` + `NSHostingController` +
`orderFrontRegardless()`), which depends on neither scene presentation nor app
activation.

---

## Notifications & sound

### `UNNotificationSound(named:)`'s custom-sound path is unreliable on macOS

It requires the sound file to be copied into `~/Library/Sounds` at runtime
and is documented (via developer-forum reports) to silently fall back to
the default sound. `NSSound` has no such requirement — `NSSound(named:)`
searches the app bundle then `/Library/Sounds`/`~/Library/Sounds`, and
`NSSound(contentsOf:)` plays any file directly. Full story:
[`adr/0002-nssound-over-unnotificationsound.md`](adr/0002-nssound-over-unnotificationsound.md).

### `UNUserNotificationCenter` suppresses foregrounded notifications by default

Including their sound — unless a delegate is set that explicitly opts in
via `willPresent`. Easy to misdiagnose as "notifications aren't working"
rather than "notifications are being suppressed because the app is
frontmost."

### `NSSound.duration` is available immediately after construction

No need to wait for playback to start — useful for computing a
duration-aware repeat interval instead of a fixed guess.

### Xcode's "+ Capability" picker doesn't list Time Sensitive Notifications for macOS

The capability picker surfaces a distinct "Time Sensitive Notifications"
entry for iOS targets, but not for macOS ones — that's not something to
keep hunting for, it just isn't exposed there for Mac apps. More
importantly, it's rarely needed at all: the `.timeSensitive` interruption
level is honored by macOS in **local/development builds run from Xcode with
no entitlement whatsoever** — the entitlement only matters for
signed/distribution builds, and only then does it need to exist at all. If
it's ever genuinely needed (e.g. before distributing outside Xcode), the
manual path is: **File → New → File… → Property List**, rename its
extension to `.entitlements`, add the key
`com.apple.developer.usernotifications.time-sensitive` as Boolean `true`,
then point the target's **Code Signing Entitlements** build setting at that
file — not through the capability picker at all.

---

## Networking

### A long-lived `URLSession` can cache a dead connection

A session can keep reusing a stale keep-alive TCP connection after the
underlying network changes (Wi-Fi drop/reconnect, sleep/wake, the remote
host's IP changing) — everything on that socket then fails until the
session is reset or recreated. This is per-process, so a browser or other
app is unaffected by whatever went stale in your app's session. Apple's own
guidance: [QA1941](https://developer.apple.com/library/archive/qa/qa1941/_index.html).
For a periodically-polling app, the simplest fix is building a genuinely
fresh `URLSession` per request rather than relying on `.shared` for the
whole process lifetime — negligible overhead at any polling cadence
measured in seconds or longer.

### A session's *very first* request fails instantly if made too early

Without `waitsForConnectivity = true`, a request made before the OS
considers the network path ready fails immediately rather than waiting —
and this only ever affects a session's first-ever request, so it's most
likely to bite exactly when an app polls right at cold launch. Set
`config.waitsForConnectivity = true` and bound how long it's allowed to
wait via `config.timeoutIntervalForResource` (its default is **7 days**,
not something you want silently in effect).

### The two `URLSessionConfiguration` timeouts measure different things

`timeoutIntervalForRequest` is an **idle** timeout: how long a task may go with
no new bytes arriving, restarted every time some do. Its default is 60 seconds.
`timeoutIntervalForResource` bounds the **whole attempt**, start to finish, and
its default is 7 days — so an app that sets only the first has, in effect, no
outer limit at all.

They stay distinct even for a response small enough that "progressing slowly"
and "stalled" look identical, because with `waitsForConnectivity = true` the
outer cap covers a period the idle timer never sees: while the session waits for
a usable network path there is no connection yet, so nothing can be idle. The
outer cap is therefore the only thing bounding that wait, and the conventional
layering — idle tighter, whole-attempt looser — is what behaves correctly.

Two adjacent details worth knowing:

- The connectivity wait applies to establishing the **initial** connection only.
  A path that drops mid-transfer fails the task (`NSURLErrorNetworkConnectionLost`,
  **-1005**) rather than waiting again.
- `URLRequest` carries its own `timeoutInterval` (default 60s) alongside the
  session's. Which one wins when both are set is not clearly documented; setting
  the value in exactly one place avoids the question, and the whole-attempt cap
  bounds the request either way.

For anything that polls on a schedule, the numbers are not independent of the
cadence: a loop that sleeps *after* a request returns has an effective period of
timeout + delay, so any timeout at or above the polling interval quietly
overrules the interval. A 30-second timeout under a 5-second interval yields one
poll every 35 seconds — seven times what was asked for.

### A freshly signed app's first poll can park in `taskIsWaitingForConnectivity` for tens of seconds on a healthy LAN

When a binary is rebuilt and re-signed (any Xcode build), its first poll can be
parked: the request to a LAN host triggers `taskIsWaitingForConnectivity`
immediately — even with Wi-Fi up and the server reachable — and sits in that
state until either the path clears or the whole-attempt budget expires (§ "The
two `URLSessionConfiguration` timeouts measure different things" above; the
resource budget is what bounds the park).

The following sequence was observed on 2026-07-30 at the first launch of a fresh
Xcode build on a healthy LAN (the failure line predates the wording change
recorded below — the same park now reads "No usable network path …"):

```
17:24:58  lifecycle: App launched
17:24:58  poll: Waiting for network…
17:25:28  poll: Poll failed: Request timed out        ← the 30 s resource budget
17:25:28  poll: Retrying in 5s (transient failure, 1 consecutive)
17:25:33  poll: Poll: warn                            ← the path had become viable
```

The "Waiting for network…" line is logged once per poll that waits, and the
recovering poll logged none — so whether the 5-second retry waited again at all
is not visible; only that the path was viable within five more seconds. When the
park recurs is not pinned down either: it appeared at the first launch of one
fresh build and did **not** appear after another rebuild the same day, so the
settled permission may be keyed to the bundle identity rather than to the exact
signature.

Two operator checks when this appears:

- **System Settings → Privacy & Security → Local Network** — the app should be
  listed with its toggle on. If absent, the evaluation never resolved; if present
  with the toggle off, turn it on and relaunch.
- The app target should carry `NSLocalNetworkUsageDescription` in its
  `Info.plist`. Without the key macOS has no text for the user-facing permission
  prompt, which would leave the evaluation to stall silently until the resource
  budget expires. For a target using `GENERATE_INFOPLIST_FILE = YES` the key is
  set via the build setting `INFOPLIST_KEY_NSLocalNetworkUsageDescription`; it
  can go in a shared `.xcconfig` and is harmless in test bundles that inherit
  it. Verify from resolved settings, not the file:
  `xcodebuild -showBuildSettings | grep INFOPLIST_KEY_NSLocalNetwork`.

This is intended behavior of the Local Network privacy framework, not a bug. The
prime suspect for the stall is macOS 15 re-evaluating the new code signature; a
secondary candidate is login-time Wi-Fi/path readiness. The two are
indistinguishable from the app's side, and the resource budget is what bounds
whichever one is responsible.

This client's decision not to route the wait through `applyState(_:)` is in
[`adr/0011-connectivity-policy.md`](adr/0011-connectivity-policy.md) §3; the
wording that replaces "Request timed out" when the park is what exhausted the
budget is in [`architecture.md`](architecture.md) §4.4.

### App Transport Security exempts unqualified host names, so plain HTTP "works" until it doesn't

ATS is on by default with no `Info.plist` configuration at all — including
under `GENERATE_INFOPLIST_FILE = YES`, where there is no plist in the repo to
notice its absence in. It blocks plain-HTTP requests, but Apple's documentation
is explicit that it "applies only to connections made to public host names":
**IP addresses, unqualified host names, and `.local` domains are exempt.**

The practical consequence is a false negative during development. `http://nas:8000`
or `http://192.168.1.10:8000` succeeds, so plain HTTP looks supported, and any
app that lets a user type a base URL inherits a failure that never appears in
testing: the first dotted public name — `http://monitor.example.com:8000` — is
refused before a packet leaves the machine, with
`NSURLErrorAppTransportSecurityRequiresSecureConnection` (**-1022**).

Two things follow for any app that surfaces network errors. Map -1022 to a
message naming the remedy rather than the fault — the same URL opens fine in
the user's browser, so nothing about the symptom points at the app's own
process refusing it. And never retry it on a backoff: ATS will not relent, and
only a changed URL can fix it.

### `waitsForConnectivity` is what a reachability pre-check is reaching for — but it reports nothing unless asked

The recurring instinct is to test reachability before sending a request. Apple's
guidance since the API was introduced (WWDC 2017, session 709) is the opposite,
and the reasoning is not stylistic: a reachability check tells you that a
request *might* succeed, and it is stale the moment it returns. Setting
`waitsForConnectivity = true` instead makes URLSession hold the task until the
path is actually viable and then send it — the same outcome a hand-rolled
`NWPathMonitor` retry loop is built to produce, without the debounce logic or a
second source of truth about connectivity. Alamofire's own reachability manager
warns in its source that it "should not be used to prevent a user from
initiating a network request", which is the same conclusion from a codebase that
never mentions the flag.

What the flag does not do is *say* that it is waiting. To an observer the app
simply stops: no error, no state change, nothing new in the UI until the wait
ends one way or the other. The only report is a delegate callback,
`URLSessionTaskDelegate.urlSession(_:taskIsWaitingForConnectivity:)`, and four
mechanics matter when wiring it up:

- **It is an *optional* `@objc` requirement.** A signature that drifts by a
  label still compiles, still conforms, and is simply never called. Nothing
  short of an actual unreachable network exercises it, so it cannot be covered
  by a test suite that runs on a working machine.
- **Prefer the per-task delegate**, `session.data(for:delegate:)` (macOS 12+).
  A delegate passed to `URLSession(configuration:delegate:delegateQueue:)` is
  retained until the session is explicitly invalidated — so an app that builds a
  session per request (see the dead-connection note above) would strand one
  delegate object per request. A per-task delegate is released when its task
  completes.
- **The callback arrives on the session's delegate queue**, not the main thread.
  Anything it touches has to hop — and the hop can outlive the request that
  caused it, so a flag raised from the callback needs to identify *which*
  request it belongs to, or it can be set just after the code that would have
  cleared it.
- **There is no "stopped waiting" callback.** The end of the wait is the end of
  the request, which is also the only moment at which anything can lower a flag
  the callback raised.

Two of those claims were checked against a running app rather than left to
documentation. On macOS 26.5 (2026-07-27), polling every 60 seconds — so a
30-second whole-attempt budget — with Wi-Fi switched off and then back on:

```
22:50:53  poll: Waiting for network…
22:51:23  poll: Poll failed: Request timed out
22:51:23  poll: Retrying in 5s (transient failure, 1 consecutive)
22:51:29  poll: Waiting for network…
22:51:32  poll: Poll: error
```

- **The whole-attempt timeout bounds the wait, to the second.** 22:50:53 →
  22:51:23 is exactly the 30-second budget, and the wait ends as an ordinary
  `.timedOut` rather than as anything wait-specific — the behavior developer
  reports describe and Apple does not document.
- **A parked request is resumed, not re-sent.** The answer at 22:51:32 belongs
  to the request that parked at 22:51:29: URLSession held that one open and sent
  it when the path returned three seconds later. Nothing scheduled a fresh
  attempt at that moment. This is the behavior that makes a
  reachability-check-plus-retry loop redundant, and only timestamps can show it
  — watching the UI cannot tell it apart from an ordinary retry landing.

The same log incidentally confirms the delegate wiring, which nothing else can:
`Waiting for network…` appearing at all means the optional `@objc` selector
matched and URLSession called it.

---

## Distribution / DMG

### Use `ditto`, not `cp -R`, to copy an `.app` bundle

`ditto` is Apple's own recommended tool for this — it preserves the
symlinks and extended metadata an app bundle's code signature depends on in
a way `cp -R` doesn't guarantee.

### Right-click → Open no longer bypasses Gatekeeper (macOS Sequoia+)

For a non-notarized app (signed with a development identity, not notarized), the old "hold-Control-and-click-Open"
bypass was removed. The user now has to attempt to launch the app once (it
gets blocked), then go to **System Settings → Privacy & Security → Open
Anyway**.

### A DMG's drag-to-install convention is an `Applications` symlink, not magic

Finder doesn't do anything special with a `.dmg` — the familiar
"drag the app onto Applications" experience just comes from the disk image
containing both the `.app` and a plain symlink to `/Applications` side by
side. `hdiutil create -volname "Name" -srcfolder <folder-with-both> -format
UDZO output.dmg` builds the image; `-srcfolder` accepts a relative path
(resolved against the current working directory), not just an absolute one.
