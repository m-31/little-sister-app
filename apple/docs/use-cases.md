# Little Sister (Apple client) — Use Cases (the vision, in scenes)

> Concrete day-to-day scenes of this client in use. This is the **vision**,
> not a spec: domain terms are defined in [`project.md`](project.md), the
> current code is in [`architecture.md`](architecture.md).

>
> This is the client-side detail of the scene already imagined in the
> server-side product spec —
> [`docs/use-cases.md`](https://github.com/m-31/little-sister/blob/main/docs/use-cases.md) §7 ("A glance from the
> menu bar").

---

## 1. A glance from the menu bar

Sam rarely keeps a browser tab open. Instead, a small icon sits quietly in
the menu bar — a plain green checkmark, matching the surrounding chrome. Sam
never has to think about it; that's exactly the point. It's only there to be
looked at when it stops being green.

## 2. The alarm nobody can miss

It's 2am. `payments.gateway` goes `ERROR`. Sam is asleep, laptop closed on
the kitchen table, Focus mode on. The client's transition into `.error`
breaks straight through Focus: a notification banner, a sound loud enough to
wake someone in the next room, repeating every few seconds — not a single
polite chime easy to sleep through, an actual alarm. The menu bar icon, if
anyone glanced at the screen, would be a blinking red glyph, impossible to
mistake for "everything's fine." A modal dialog sits on screen too, with the
real failure reason already in it, so the first thing Sam reads on waking up
is *why*, not just *that*.

## 3. Acknowledging without dismissing

Sam clicks "Acknowledge" on the dialog — or, if the dialog was switched off
in Settings, the "Acknowledge Alarm" item in the menu. The sound stops
immediately. The icon keeps blinking. The menu still says `error`. Sam hasn't
told the app anything is fixed — only that a human has heard it and is now
looking. If `payments.gateway` is still `ERROR` an hour later, the icon is
still red, still waiting for an actual recovery, not a snoozed reminder.

## 4. Already broken at launch

The client's Mac restarts overnight for a routine update. On relaunch, the
very first poll finds the server already reporting `ERROR` — no comforting
"OK, then it went wrong" transition for the client to key off, just broken
from the first request. The app doesn't stay quiet because it never saw the
moment things changed; it treats "already broken at launch" exactly like any
other transition into `.error` — full alarm, full dialog, from the first
poll.

## 5. Choosing a sound that means business

Setting this client up the first time, Sam opens Settings → Alerts and hits
Preview a few times — the bundled default, then a couple of the fourteen
system sounds, landing on one that's unmistakably an alarm, not a
notification chime easy to tune out after a week. Later, Sam finds a
specific alert tone from another project and picks it via "Choose File…"
instead — no rebuild, no asset to hand anyone, just pointing the app at a
file already on disk.

## 6. The server that isn't there

Sam's laptop leaves the office network and the configured `little-sister`
server becomes unreachable — not `ERROR`, just gone. The icon shows a plain
"?", the menu explains why ("Reason: Network unavailable"), and — because
this isn't the server actually reporting a problem, just the client losing
contact with it — there's no alarm, no blinking icon, no modal dialog. A
quiet, honest "I don't know" instead of a false alarm.
