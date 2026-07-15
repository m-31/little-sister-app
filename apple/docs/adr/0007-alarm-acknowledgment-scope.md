# ADR-0007 — Acknowledging the alarm stops sound only, no auto-timeout

- **Status:** Accepted
- **Date:** 2026-07-03
- **Related:** [ADR-0002 — NSSound over UNNotificationSound](0002-nssound-over-unnotificationsound.md)
- **Register:** [`../decisions.md`](../decisions.md)

## Context
Once the alarm sound could repeat indefinitely while `.error` persisted
([ADR-0002](0002-nssound-over-unnotificationsound.md)), it needed a way to
stop before the underlying error actually resolved — otherwise an
unattended, ongoing outage becomes an unattended, ongoing siren. Several
mechanisms were possible: acknowledging via the modal dialog, a menu item,
any interaction with the app at all, or an automatic timeout.

## Decision
Two explicit acknowledgment paths — the modal dialog's "Acknowledge" button,
and an "Acknowledge Alarm" menu item shown only while the alarm is actively
looping — both calling `MonitoringViewModel.acknowledgeAlarm()`, which stops
**only** the repeating sound. The banner notification, the blinking icon, and
the modal dialog's own visibility are untouched. There is no automatic
timeout/auto-stop.

## Rationale
- Requiring an **explicit** action (rather than "any interaction with the
  app counts") avoids silencing the alarm by accident — opening the menu to
  check something else, for instance, shouldn't be read as "I've handled
  this."
- Scoping acknowledgment to **sound only**, not the icon or dialog, keeps the
  passive signals (a blinking menu bar icon, a menu that still says `.error`)
  visible for as long as the problem is real — acknowledgment answers "I've
  heard the alarm," not "this is fixed."
- Two acknowledgment surfaces (dialog button, menu item) rather than one,
  because the modal dialog itself is optionally disabled
  (`AppSettings.modalAlertOnError`) — without the menu item, a user who
  wants sound but not the intrusive dialog would have no way to silence an
  alarm early at all.
- The existing anti-spam gate (the same one that decides whether a
  transition is worth notifying about at all) already prevents a fresh
  alarm from starting again for the same ongoing error, without any extra
  "was this acknowledged" bookkeeping — acknowledgment naturally holds until
  the error episode actually ends.
- No timeout was a deliberate, explicit scope decision, not an oversight:
  adding one trades a simple, predictable rule ("acknowledging is the only
  way to silence an alarm early") for a second, harder-to-reason-about rule
  ("...unless N minutes pass, in which case it stops on its own"). Left out
  for this pass; whether it's worth adding later stays an open question.

## Consequences
- An unattended Mac with an unresolved, un-acknowledged `.error` and nobody
  around will keep alarming indefinitely — a known, accepted limitation
  (`architecture.md` §10), not a bug.
- Acknowledgment state lives only in whether the loop task is currently
  running (`isAlarmActive`) — there's no separate "has this episode been
  acknowledged" flag to keep in sync, which is what makes the anti-spam
  interaction above work for free.

## Alternatives considered
- **Any interaction silences it** (opening the menu, clicking the icon).
  Rejected — too easy to trigger without meaning to.
- **Auto-stop after N repeats or minutes.** A reasonable safety net, but a
  genuinely separate design decision (a timeout, not an acknowledgment) —
  deliberately deferred rather than bundled in here.
