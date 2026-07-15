# ADR-0001 — A managed NSStatusItem instead of SwiftUI's MenuBarExtra

- **Status:** Accepted
- **Date:** 2026-07-02
- **Related:** [ADR-0002 — NSSound over UNNotificationSound](0002-nssound-over-unnotificationsound.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
The alert-prominence work ([`../architecture.md`](../architecture.md) §6)
needed the menu bar icon itself to turn a visible red and blink during
`.error` — not just show a different SF Symbol. The app originally used
SwiftUI's `MenuBarExtra(_:content:label:)`, the standard, low-effort way to
build a menu bar app.

## Decision
Drop `MenuBarExtra` and manage the menu bar item directly with AppKit:
`StatusItemController` owns an `NSStatusItem` and a real `NSMenu`, with
`button.image` set to a colored, non-template `NSImage` for `.error` and a
plain template image otherwise.

## Rationale
- **`MenuBarExtra` forces template rendering.** `Image(systemName:)` with
  `.renderingMode(.original)` and `.foregroundStyle(.red)` was tried first and
  confirmed, live, not to work — macOS still recolors the icon to match the
  menu bar chrome regardless of the modifier. This isn't a bug to work
  around; `MenuBarExtra` deliberately enforces HIG-style monochrome menu bar
  icons at the SwiftUI level, with no escape hatch. `NSImage.isTemplate =
  false` on a manually-managed `NSStatusItem` is the actual mechanism that
  controls this, and `MenuBarExtra` never exposes it.
- Once the icon needed AppKit anyway, hosting the existing menu content as a
  SwiftUI view (`NSPopover` + `NSHostingController`) was tried as a middle
  ground — it worked, but looked like a floating card (bordered buttons, form
  spacing) rather than a native dropdown, because `MenuBarExtra` was what had
  been supplying that native-menu styling all along. A real `NSMenu`
  (`statusItem.menu = menu`) gets genuine native appearance for free, with no
  manual click handling.
- No third-party dependency needed either way.

## Consequences
- The menu's dynamic content (state, timestamps, reasons) is rebuilt fresh
  via `NSMenuDelegate.menuNeedsUpdate(_:)` right before each open, rather than
  reactively re-rendering a SwiftUI view — a different mental model
  (imperative `NSMenuItem` construction) than the rest of the app, which is
  otherwise all SwiftUI/`@Observable`.
- `@Observable` state changes have to be bridged into this non-SwiftUI
  context manually, via `withObservationTracking(_:onChange:)`, re-subscribed
  inside its own callback each time — the standard pattern for observing
  outside a view body, but one more thing to get right than SwiftUI's
  automatic dependency tracking.
- `.error`'s SF Symbol (`xmark.circle.fill`) has two layers (circle + xmark);
  `NSImage.SymbolConfiguration(paletteColors:)` needs one color **per layer**
  — supplying only one flattens both to the same color, reading as a plain
  dot rather than a recognizable glyph at menu bar size. Non-obvious, easy to
  get wrong again if this code is ever touched.

## Alternatives considered
- **Keep `MenuBarExtra`, drop the colored icon.** Simplest, but directly
  defeats the alert-prominence goal — a monochrome icon during `.error`
  isn't meaningfully more visible than before.
- **`NSPopover` hosting the SwiftUI menu content.** Built first, shipped
  briefly, then replaced — see Rationale. Kept here as a documented dead end
  so it isn't retried.
