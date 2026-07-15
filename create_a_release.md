# Creating a release

How a release of this repository is produced, and what a release *is*. This is
the macOS client's process; it mirrors the little-sister library's, each
repository on its own version line.

## What `main` is

`main` carries **releases only**: one squash commit per version, tagged
`v<major.minor.patch>` (annotated; the tag message carries the release notes).
It is **generated** — a condensed file-tree snapshot of the private working
branch — never merged into or edited directly. Development history, working
notes, and the release tooling itself stay on the working branch; what ships is
the current state: the app source, its tests, and the documentation useful to
consumers.

Two properties are enforced by tooling at release time, not by convention:

- **Docs are classified.** Every Markdown file is deliberately marked
  ship / don't-ship; an unclassified one fails the release.
- **No private strings.** The entire released tree — code, tests, configs —
  is scanned against a denylist of private strings (real hostnames, private
  infrastructure, personal contact data). A hit fails the release.

## The pipeline

Two scripted steps per side, a human review in between — and a human pushes,
never a script.

**On the working branch:**

1. Bump `MARKETING_VERSION` by hand (set it in the Xcode target's General tab,
   or edit `apple/LittleSister.xcodeproj/project.pbxproj`) — the bump *is* the
   decision to release — and write consumer-facing notes under `## [Unreleased]`
   in [`CHANGELOG.md`](CHANGELOG.md). `MARKETING_VERSION` is the single source of
   the version.
2. **`release_prep.sh`** — validates, runs the gate (`xcodebuild test`, plus the
   release tooling's own self-tests), rolls `[Unreleased]` into a
   `## [<version>] - <date>` section, and commits. No tag yet: the version and
   CHANGELOG are single-sourced on the working branch; `main` only gates and
   tags.

**On the `main` worktree** (a dedicated worktree at `../little-sister-app-main`,
created on first run — the everyday checkout is never touched):

3. **`sync_main.sh`** — snapshots the working branch's *committed* tree onto
   `main` (a file sync, not a merge), condenses the docs (drops the
   working-branch-only files, strips their dev-only markup, validates), scans
   the tree for private strings, and stages the result. Nothing is committed
   until a human has **reviewed the staged diff**.
4. **`release_main.sh`** — runs `xcodebuild test` again on the condensed tree
   (a second net under the validation), commits `Release v<version>`, and
   creates the annotated tag with the CHANGELOG notes. Push after a final look:
   `git push github main --follow-tags`.

A failed validation is fixed on the working branch with ordinary commits, then
step 3 is re-run. Nothing on `main` is ever hand-edited, and `release_prep.sh`
runs once per version.

## Consuming releases

- Pin a **tag** (`v<x.y.z>`); `main` moves only at releases, one commit each.
- Release notes live in the tag message and in [`CHANGELOG.md`](CHANGELOG.md).
- This client versions **independently** of the little-sister library; when the
  JSON API contract matters, a release states the minimum library version it
  needs.
- Bugs and requests:
  [GitHub issues](https://github.com/m-31/little-sister-app/issues).

## Publishing the app binary (DMG)

A source tag isn't a download, so each release also ships a `.dmg` as a GitHub
**Release** asset on the same tag. This is optional and separate from the
pipeline above — do it after the tag is pushed.

1. Build and package: `apple/scripts/make_dmg.sh` produces
   `apple/dist/LittleSister-<version>.dmg` (a Release build, named from
   `MARKETING_VERSION`).
2. Attach it to the tag's GitHub Release — a human runs this, like the push:
   `gh release create v<version> apple/dist/LittleSister-<version>.dmg --title v<version> --notes-file <notes>`
   (or `gh release upload v<version> …` if the Release already exists).

The app is signed with an Apple Development identity, not a Developer ID, and is
not notarized — so on another Mac it trips Gatekeeper's "cannot be opened."
Recipients launch it once, then allow it under **System Settings → Privacy &
Security → Open Anyway**. Making it open cleanly (Developer ID + notarization)
is a separate, deferred decision.

