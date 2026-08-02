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

### ADR-0008 — Settings and Debug Log are AppKit windows, not SwiftUI scenes
**Q:** Why did "Settings…" and "View Debug Log…" do nothing — silently, with
no error — after the app was launched at login, while "Open dashboard" from
the same menu kept working?

**A:** Because both went through a SwiftUI scene that a login-launched
accessory app never presents. They now bypass SwiftUI's scene and window
machinery entirely: `WindowPresenter` builds an `NSWindow` around each
SwiftUI view and orders it front itself. This supersedes the `HiddenWindowView`
+ `NotificationCenter` workaround, which is deleted.

→ Full record: [`adr/0008-appkit-owned-secondary-windows.md`](adr/0008-appkit-owned-secondary-windows.md)

### ADR-0009 — One timestamp vocabulary in the menu, in this Mac's timezone
**Q:** What does the menu's "Updated:" line actually mean — the last poll, or
the server's own reading? And why could a ten-day-old value look like this
morning?

**A:** It was `status.timestamp`, shown only in some states and under a label
used nowhere else. Every state now shows the same three instants under the
same labels — `Node observed`, `Server snapshot`, `Last request` — with the
date included whenever the value isn't from today, and `(stale)` taken from
the server's own flag rather than a threshold invented here.

→ Full record: [`adr/0009-one-timestamp-vocabulary.md`](adr/0009-one-timestamp-vocabulary.md)

### ADR-0010 — A shortened, backing-off retry while polling is failing
**Q:** After a reboot the app sat at `unavailable` for about 90 seconds. Should
a failed poll really be followed by the same wait as a successful one?

**A:** No. While polls are failing the delay starts at 5s and doubles with each
consecutive failure, capped at the configured interval and reset by the first
success — so a transient outage recovers quickly while a server that is down
all night is polled no more often than before.

→ Full record: [`adr/0010-shorter-retry-while-failing.md`](adr/0010-shorter-retry-while-failing.md)

### ADR-0011 — Connectivity policy: a failure taxonomy, timeouts derived from the poll interval, and waiting-for-network as a reported state
**Q:** A poll can fail six materially different ways, but the app reported two
of them. Its 30-second timeout knew nothing about the poll interval, so a
5-second setting was quietly overruled. And while the session waited for a
network path, the app looked frozen rather than informed.

**A:** Map `URLError` to distinct reasons; derive one timeout budget from the
poll interval and split it between the total cap and the idle timeout; report
waiting-for-connectivity as a presentational flag that never reaches
`applyState`. `waitsForConnectivity` stays on — it already *is* the connectivity
monitor, so `NWPathMonitor` is not adopted. Transient failures keep ADR-0010's
backoff; a definite answer (`401`, `404`, bad schema version) waits
`max(pollInterval, 60)` instead.

→ Full record: [`adr/0011-connectivity-policy.md`](adr/0011-connectivity-policy.md)

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
