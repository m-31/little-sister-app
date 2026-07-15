# Little Sister (Apple client) — Decisions

> One self-contained digest per decision — the question it settled, the
> answer, and a link to the full Architecture Decision Record in
> [`adr/`](adr/) for the context, alternatives, and date. Reading this page is
> enough to know **what** we decided and **why**; the ADR holds the history.
>
> A decision is in force unless its heading is marked **superseded**.

---

### ADR-0001 — A managed NSStatusItem instead of SwiftUI's MenuBarExtra
**Q:** How does the menu bar icon turn a genuine, visible red and blink
during `.error`, when `MenuBarExtra` forces monochrome template rendering
with no escape hatch?

**A:** Bypass `MenuBarExtra` entirely. `StatusItemController` owns a raw
`NSStatusItem` with a real `NSMenu` (not a hosted SwiftUI popover, which
doesn't pick up native dropdown styling); a non-template `NSImage`
(`isTemplate = false`) is what actually allows color through.

→ Full record: [`adr/0001-status-item-over-menubarextra.md`](adr/0001-status-item-over-menubarextra.md)

### ADR-0002 — NSSound, not UNNotificationSound, for the alarm
**Q:** How does the alarm sound get played reliably, support repeating, and
let the user choose or supply their own sound — given `UNNotificationSound`'s
custom-file path is documented as unreliable on macOS?

**A:** Play it through AppKit's **`NSSound`** entirely, separate from the
notification framework. `content.sound` is left unset on the banner; the
alarm is a fully independent playback path, unaffected by foreground
notification suppression or (per its documented scope) the OS-level
per-app sound toggle.

→ Full record: [`adr/0002-nssound-over-unnotificationsound.md`](adr/0002-nssound-over-unnotificationsound.md)

### ADR-0003 — DisplayState labels match the server's vocabulary 1:1
**Q:** Should the client use its own presentation words for status, and
should "the server said UNDEFINED" and "the client couldn't reach the
server at all" share one word?

**A:** No and no. `DisplayState.label` matches the server's own lowercased
vocabulary exactly (`ok`, `warn`, `error`, `maintenance`, `undefined`), and
the no-response case is its own `unavailable` case — labeled differently
from `undefined` since the server never said that — though the two are still
treated as equivalent for notification anti-spam purposes.

→ Full record: [`adr/0003-displaystate-server-vocabulary.md`](adr/0003-displaystate-server-vocabulary.md)

### ADR-0004 — Settings commit on OK, applied live via fresh per-poll reads
**Q:** When do Settings edits take effect, and how does the polling loop
pick up a change without restarting the app?

**A:** Edits are buffered locally and only written to `AppSettings`/Keychain
when **OK** is pressed — **Cancel**, or closing the window any other way,
both discard the buffered edits instead. The polling loop never caches a
client — **every poll tick** builds a fresh `StatusAPIClient` from current
settings, so a change
takes effect within one poll interval with no callback wiring needed.

→ Full record: [`adr/0004-settings-apply-on-ok.md`](adr/0004-settings-apply-on-ok.md)

### ADR-0005 — Bearer token in Keychain only, never UserDefaults
**Q:** Where does the one real secret this app holds — the API bearer
token — live?

**A:** The macOS **Keychain**, exclusively, behind a small `TokenStoring`
protocol (real implementation: `KeychainTokenStore`,
`kSecAttrAccessibleAfterFirstUnlock` so background polling can read it while
the screen is locked). Never `UserDefaults`, `Info.plist`, source, git, or
logs — including the Debug Log.

→ Full record: [`adr/0005-keychain-only-token-storage.md`](adr/0005-keychain-only-token-storage.md)

### ADR-0007 — Acknowledging the alarm stops sound only, no auto-timeout
**Q:** Once the alarm could repeat indefinitely, how does a user stop it
before the underlying error actually resolves?

**A:** Two explicit acknowledgment paths — the modal dialog's "Acknowledge"
button, and an "Acknowledge Alarm" menu item for when the dialog is
disabled — both stopping **only** the sound; the icon blink and dialog
visibility are untouched. No automatic timeout: acknowledging is the only
way to silence an alarm early, by deliberate design.

→ Full record: [`adr/0007-alarm-acknowledgment-scope.md`](adr/0007-alarm-acknowledgment-scope.md)

### Releases — the library's generated-`main` pattern (no ADR)
**Q:** How does this repository publish releases?

**A:** Exactly like little-sister: `main` is a generated, condensed snapshot of
the private working branch — one squash commit per version, an annotated tag
with the CHANGELOG notes, doc classification, release-markup stripping and a
private-strings scan enforced by tooling at the repository root, with a human
review before anything is committed. Versioning is **independent** of the
library (`MARKETING_VERSION` is the source); the gate is `xcodebuild … test`.
Full decision:
[little-sister ADR-0022](https://github.com/m-31/little-sister/blob/main/docs/adr/0022-generated-release-branch.md).
Recorded here, no ADR.

### Code signing & the distributed DMG (no ADR)
**Q:** How is the app signed, and what would a cleanly-opening `.dmg` need?

**A:** Automatic signing with a machine-local `DEVELOPMENT_TEAM`, kept in a
git-ignored `Local.xcconfig` that `Base.xcconfig` includes and the project's
Debug/Release configurations reference as their base. A Release build resolves
`CODE_SIGN_IDENTITY` to **Apple Development** with hardened runtime on — signed
for the developer, but on another Mac it still meets Gatekeeper's "cannot be
opened", because that is neither a **Developer ID Application** signature nor
notarized. For the current developer audience that is a deliberate stopgap
(recipients use **Open Anyway**). Opening cleanly is a separate, deferred step:
a Developer ID certificate plus notarization — notarization itself is free but
needs the paid Apple Developer Program, and hardened runtime being on already
covers one of its prerequisites.
