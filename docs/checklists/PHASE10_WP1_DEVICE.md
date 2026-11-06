# Phase 10 WP1 — app state & change fan-out: on-device checks

Code was written without a Swift toolchain; CI compiles it. Nothing here was seen on a device. Merge into
`PHASE10_DEVICE.md` at the gate. Best on the slowest available iPhone (A13 class) plus the iPhone 16 Pro Max.

## 1. Launch (P6, P7, P17)
- [ ] Cold launch, typical data: the mark swipes in once (0.3 s), then a 0.2 s cross-fade to Today. No one-frame flash.
- [ ] Reduce Motion on: static mark, then a cut (no fade) as soon as data is loaded; no 0.3 s wait.
- [ ] Open the app from a notification "Mark as Done" done while the app was not running, then open it from the Home
      Screen: Today appears directly (no mark, no fade) when the store was already loaded in the background.
- [ ] Instruments (Time Profiler / Hangs) on cold launch: the reminder re-plan runs ~1.5 s after the store loaded,
      not in the first frames. Reminders are still scheduled (Settings → Reminders → Test reminders shows pending).
- [ ] Timetable symbol legend tip still appears on a week with changes (TipKit still configured at launch).
- [ ] VoiceOver during launch reads "Loading…" once.

## 2. Single edit and tab re-render (P2, P11)
- [ ] Tick a task on Tasks, switch to Timetable: badges updated. Instruments SwiftUI template: ticking a task does not
      re-run the Timetable / Today / Exams bodies for formatter or resolver changes (only views reading the database).
- [ ] Change 12/24 h in Settings: every tab shows the new clock. Change the time zone setting: Today, Timetable, widgets
      follow.
- [ ] Timetable Grid / Week (time blocks) / Day / Tiles at normal size and Dynamic Type XXL: identical to Phase 9
      screenshots (strip dots, change markers, task/exam badges, Today marker, override week of the sample data).
- [ ] Timetable left open across a minute boundary: the now line moves, no visible hitch while scrolling.

## 3. Scene phase (P5)
- [ ] Pull down Notification Centre and back, Face ID unlock, call banner: no reminder re-plan (debug screen "Last run"
      time unchanged), no hitch.
- [ ] Same blip after 5+ minutes away: re-plan runs.
- [ ] Home Screen → back after 10 s: re-plan runs (real foreground, as before).
- [ ] Change the device time zone in Settings, return: times and reminders follow at once.
- [ ] Leave the app across midnight (or set the clock): Today shows the new day on return.
- [ ] Edit a task and swipe the app away from the app switcher within 1 s: the edit is there on relaunch.

## 4. Quiet hours (P14)
- [ ] Settings → Reminders → Quiet hours: spin the start time several times: the row follows every change; the debug
      screen shows one save / re-plan about 0.8 s after the last change, not one per wheel stop.
- [ ] Change the end time and leave the screen at once (back button): the value is kept on return.
- [ ] Change a time and go to the Home Screen at once: kept on relaunch.
- [ ] A kind's rule editor quiet hours behave the same (shared rows).
- [ ] Switching quiet hours on/off saves at once. VoiceOver reads the switch and both times; Dynamic Type XXL OK.

## 5. Mark as Done failure (B12)
- [ ] Force a read-only store (debug tools, newer-version file) and press "Mark as Done" on a reminder: a notification
      "Couldn't Mark as Done" / "Open Tabula to try again." appears with the item's title as subtitle; tapping it opens
      the item. German and Japanese strings fit; no truncation in the banner.
- [ ] Normal "Mark as Done": no notice; the item's other notifications are removed (unchanged).
- [ ] Delete the task in the app, then press "Mark as Done" on its old notification: no notice.

## 6. Off-screen tabs (P16, no code change)
- [ ] Instruments SwiftUI template with Timetable and Tasks visited, then sitting on Settings for 2 minutes: check
      whether Today / Timetable `TimelineView(.everyMinute)` bodies still run off screen. Record the result in
      docs/ENVIRONMENT.md; if they do, a follow-up gates the schedule on the selected tab.
