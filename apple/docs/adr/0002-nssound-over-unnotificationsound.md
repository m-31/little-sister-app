# ADR-0002 — NSSound, not UNNotificationSound, for the alarm

- **Status:** Accepted
- **Date:** 2026-07-03
- **Related:** [ADR-0001 — NSStatusItem over MenuBarExtra](0001-status-item-over-menubarextra.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
An `.error` transition needed an actual alarm sound — configurable, audible,
and (once built) repeatable and user-choosable, including a custom file.
`UNNotificationSound`, the notification framework's own sound mechanism, was
the obvious first choice since the app already sends `UNUserNotificationCenter`
banners.

## Decision
Play the alarm entirely through AppKit's `NSSound`, bypassing
`UNNotificationSound`/`content.sound` completely. The banner notification's
`content.sound` is left unset.

## Rationale
- **`UNNotificationSound(named:)`'s custom-sound path is documented as
  unreliable on macOS** — it requires the sound file to be copied into
  `~/Library/Sounds` at runtime and can silently fall back to the default
  sound (confirmed via Apple Developer Forums reports, not just assumed).
  `NSSound` has no such requirement: `NSSound(named:)` searches the app
  bundle directly, then `/Library/Sounds` and `~/Library/Sounds`, and
  `NSSound(contentsOf:)` plays an arbitrary file from anywhere on disk.
- **Two separate causes of "no sound" were found and fixed along the way**,
  both specific to the notification-framework path, neither relevant once
  `NSSound` is used directly: (1) `UNUserNotificationCenter` silently
  suppresses notifications — including their sound — while the app is
  foregrounded, unless a delegate is set that explicitly opts in via
  `willPresent`; (2) macOS's own per-app "Play sound for notification" toggle
  in System Settings can be off independent of what the app requests in
  code. `NSSound` playback is a distinct, general-purpose audio API, not
  gated by either of these (a working assumption grounded in how the two
  APIs are documented, not something exhaustively stress-tested).
- Full control over **which** sound plays, and easy support for **repeating**
  it (`NSSound.play()` called again on a timer) and **choosing** one at
  runtime (system sounds by name, a bundled default, or an arbitrary file via
  `NSOpenPanel`) — none of which map cleanly onto `UNNotificationSound`.

## Consequences
- The alarm and the notification banner are now two independent
  subsystems — the banner can show with no sound, and the alarm can play
  with no banner, by design (each gated by its own settings toggle).
- `NotificationSending` carries two playback methods (`playAlarm(soundName:)`
  / `playAlarm(fileURL:)`) rather than one, and `LiveNotificationSender`
  still needs the `UNUserNotificationCenterDelegate` conformance anyway — for
  the **banner** to show at all while foregrounded, independent of sound.
- The app now depends on `NSSound`'s bundle-search behavior for its default
  and system-sound options; a future distribution/sandboxing change could in
  principle affect this and would need re-verifying.

## Alternatives considered
- **Fix the `UNNotificationSound` path properly** (copy the custom file into
  `~/Library/Sounds`, add the delegate, hope the OS toggle stays on). Rejected
  — still fragile per the documented unreliability, and doesn't support
  repeating or arbitrary custom files any more cleanly.
- **`AVAudioPlayer`** — a more modern, more capable audio API, but pulls in
  more surface area (session configuration, format support nuances) than a
  short alert sound needs; `NSSound` is the simpler fit for "play this short
  file/named sound."
