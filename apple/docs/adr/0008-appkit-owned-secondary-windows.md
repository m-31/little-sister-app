# ADR-0008 — Settings and Debug Log are AppKit windows, not SwiftUI scenes

- **Status:** Accepted
- **Date:** 2026-08-01
- **Related:** [ADR-0001 — A managed NSStatusItem instead of MenuBarExtra](0001-status-item-over-menubarextra.md),
  [ADR-0004 — Settings commit on OK](0004-settings-apply-on-ok.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
The app hides its Dock icon (`LSUIElement = YES`), and SwiftUI's secondary
windows are awkward to bring forward from an accessory app. The original
design worked around that with an indirection:

1. The menu items "Settings…" and "View Debug Log…" posted a
   `NotificationCenter` message and did nothing else.
2. A 1×1 `Window("Hidden", id: "HiddenWindow")` scene hosted `HiddenWindowView`,
   whose `.onReceive` observers were the only subscribers.
3. On receipt it flipped the activation policy to `.regular`, activated the
   app, called `openSettings()` / `openWindow(id: "DebugLog")`, and searched
   `NSApp.windows` by title to force the result to the front.

After the app was added to Login Items and the machine restarted, both menu
items stopped working — silently, with no error in the app's own log, in
`os_log`, or on the console. "Open dashboard", which calls `NSWorkspace`
directly and involves no window, kept working, and polling continued
normally throughout.

The cause is step 2. An `LSUIElement` app started by launchd as a login item
never becomes the active application, and clicking its status-item menu does
not activate it either. SwiftUI therefore never presented the Hidden window,
`HiddenWindowView` was never instantiated, and **no observer existed** — so
the posts in step 1 reached nobody. Confirmed on the running instance: the
process had zero windows, and a single `open -a` (which activates the app)
made the window appear and both menu items start working again.

The indirection had made a process-lifetime concern — "can the user open
Settings?" — depend on whether a particular window happened to have been
presented, a condition the app neither controlled nor checked.

## Decision
Drop the SwiftUI scene and notification machinery for both windows.

- A new `@MainActor final class WindowPresenter`, owned by
  `StatusItemController`, builds each window on demand as a plain `NSWindow`
  wrapping the existing SwiftUI view in an `NSHostingController`, and orders
  it front itself (`setActivationPolicy(.regular)` → `activate` →
  `makeKeyAndOrderFront` → `orderFrontRegardless`).
- The menu actions call `WindowPresenter` directly. `HiddenWindowView`, the
  `Window("Hidden")` and `Window("Debug Log")` scenes, the `Settings` scene's
  real content, and all four `Notification.Name`s are deleted.
- `LittleSisterApp.body` keeps one empty `Settings { EmptyView() }` scene,
  solely because `App` requires a scene. `Settings` is the placeholder
  because, unlike `Window`, it never auto-presents at launch.
- `WindowPresenter` is the window delegate and returns the app to
  `.accessory` only when the **last** managed window closes.
- Every menu command, window presentation and activation-policy flip is
  recorded to the debug log under a new `menu` category.

## Rationale
- AppKit window ordering depends on neither scene presentation nor app
  activation, so the menu items behave identically whether the app was
  launched from Finder, from a login item, or restarted after a crash.
- The app was already AppKit-driven for its entire visible surface
  (ADR-0001); routing two windows back through SwiftUI's scene lifecycle was
  the only piece that wasn't, and it was the piece that broke.
- One indirection disappears entirely: a menu click now calls the code that
  opens the window, instead of posting a message and hoping something is
  listening. Failures become traceable rather than silent.
- Restoring `.accessory` on the last close, rather than on any close, fixes a
  latent bug in the old code: closing one of two open windows dropped the Dock
  icon while the other was still on screen.

## Consequences
- A closed window is rebuilt on the next open rather than reused. That is
  deliberate: it makes `SettingsView.onAppear` re-run, so the form reloads
  from truth every time, preserving ADR-0004's "Cancel discards" semantics
  for free.
- The Settings window is no longer a SwiftUI `Settings` scene, so it loses
  the system's automatic ⌘, binding — irrelevant here, since an `LSUIElement`
  app has no app menu to host that command.
- `WindowPresenter` is not covered by unit tests: it is `NSWindow`
  presentation and activation policy, verifiable only by launching the app in
  each launch mode. The verification that matters is a real login-item launch
  after a restart.

## Alternatives considered
- **Move the observers to an `NSApplicationDelegateAdaptor`.** Fixes message
  *delivery* — a delegate lives for the whole process — but `openSettings()`
  and `openWindow(id:)` would still be asking SwiftUI to present scenes in an
  app that is never active. Same failure, one layer down.
- **Keep the scenes and force the Hidden window open** (macOS 15's
  `.defaultLaunchBehavior(.presented)` / `.restorationBehavior(.disabled)`,
  or an explicit `openWindow(id: "HiddenWindow")` at launch). Cheapest patch,
  but it keeps a 1×1 window alive for the sole purpose of hosting an
  observer, and still leans on SwiftUI presenting a scene in a non-active
  app — the exact assumption that failed.
- **Drop the SwiftUI `App` shell for a plain `AppDelegate`.** Arguably the
  honest endpoint, since no scene does real work any more. Deferred: it is a
  larger, riskier change than the bug requires, and can be made later without
  touching anything decided here.
