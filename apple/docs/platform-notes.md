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
