# Little Sister — macOS menu-bar status client

> The native client of the **little-sister** monitoring app. Target/bundle:
> `LittleSister`; display name: **Little Sister**.

A small native macOS menu-bar app that polls the monitoring application's read-only
JSON status API and alerts when the watched status tree (or a subtree) changes
materially. It is a compact indicator, not a copy of the web dashboard.

## Open in Xcode

```text
apple/LittleSister.xcodeproj
```

This folder is **self-contained** — Xcode needs only this subtree. The app depends only
on the JSON status API; its contract lives alongside in [`docs/api/`](docs/api/)
([`openapi.yaml`](docs/api/openapi.yaml) + usage notes in
[`README.md`](docs/api/README.md)).

## Build & test

Open the project and use Run / Test (⌘R / ⌘U), or `xcodebuild` from this directory.
Unit tests must never call a real backend — they mock `URLSession`.

Code signing is machine-local: copy [`Local.xcconfig.example`](Local.xcconfig.example)
to `Local.xcconfig` (git-ignored) and set your own `DEVELOPMENT_TEAM` — the project
file carries no team (see [`Base.xcconfig`](Base.xcconfig)).

## Configuration

At runtime the app keeps its base URL, optional subtree path and poll interval in
`UserDefaults`, and the **bearer token in the macOS Keychain** — never in git, source,
`UserDefaults`, `Info.plist`, or logs. Request a token from the application's
operator/admin.

## Distribution (DMG)

This is a personal/internal tool, not an App-Store or notarized release (see
[`docs/project.md`](docs/project.md) §5 — no notarization pipeline, no
auto-update). For occasional manual sharing, [`scripts/make_dmg.sh`](scripts/make_dmg.sh)
builds a Release version of the app and packages it into a disk image:

```sh
scripts/make_dmg.sh          # -> apple/dist/LittleSister-<version>.dmg
```

The project signs with the local development team only
(`CODE_SIGN_STYLE = Automatic`, not a Developer ID), so it isn't notarized.
Anyone opening the app on another Mac will hit Gatekeeper's "cannot be
opened" warning. As of macOS Sequoia, right-click → Open no longer bypasses
this; the recipient needs to attempt to launch it once, then go to
**System Settings → Privacy & Security → Open Anyway**.

## Documentation

See [`docs/`](docs/) for the full picture — [`docs/project.md`](docs/project.md)
(what it is) and [`docs/architecture.md`](docs/architecture.md) (how the code is
built). Design rationale is in [`docs/decisions.md`](docs/decisions.md) +
[`docs/adr/`](docs/adr/).

[`docs/platform-notes.md`](docs/platform-notes.md)
is a separate, portable reference of Swift/AppKit/Xcode/macOS quirks — not
this app's own decisions, which live in `decisions.md`/`adr/` instead. The
JSON API contract this app targets is copied in at
[`docs/api/openapi.yaml`](docs/api/openapi.yaml) (usage notes in
[`docs/api/README.md`](docs/api/README.md)).
