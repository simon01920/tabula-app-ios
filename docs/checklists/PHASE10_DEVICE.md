# Phase 10 on-device checklist: polish, bug fixes and performance

Plan: `docs/specs/PHASE10_PLAN.md`. All Phase 10 code was written in a cloud container without a Swift toolchain; CI
compiled it on both build paths and ran the Linux tests, but **nothing below has been seen on a device**.

**Devices.** Run everything on the iPhone 16 Pro Max. Where a row says A13, use the slowest iPhone you can borrow
(iPhone 11 / SE 2nd or 3rd gen). Without one, use Display Zoom (Settings › Display & Brightness › Display Zoom ›
Larger Text) on the Pro Max for the 375 pt layout rows, and note "Pro Max only" for the speed rows.

**Each changed screen in:** light and dark, Dynamic Type XXL and AX3, Bold Text, Increase Contrast, German, Hungarian,
Japanese, VoiceOver.

Sections: A = app state and launch (WP1), B = widgets, Live Activities, watch (WP2), C = export, share and import (WP3),
D = core calendar and export formats (WP4), E = sync, backup and attachments (WP5), F = UI polish (WP6),
G = privacy manifest (WP7).

# A. App state, launch and reminders (WP1)
`PHASE10_DEVICE.md` at the gate. Best on the slowest available iPhone (A13 class) plus the iPhone 16 Pro Max.

## A1. Launch (P6, P7, P17)
- [ ] Cold launch, typical data: the mark swipes in once (0.3 s), then a 0.2 s cross-fade to Today. No one-frame flash.
- [ ] Reduce Motion on: static mark, then a cut (no fade) as soon as data is loaded; no 0.3 s wait.
- [ ] Open the app from a notification "Mark as Done" done while the app was not running, then open it from the Home
      Screen: Today appears directly (no mark, no fade) when the store was already loaded in the background.
- [ ] Instruments (Time Profiler / Hangs) on cold launch: the reminder re-plan runs ~1.5 s after the store loaded,
      not in the first frames. Reminders are still scheduled (Settings → Reminders → Test reminders shows pending).
- [ ] Timetable symbol legend tip still appears on a week with changes (TipKit still configured at launch).
- [ ] VoiceOver during launch reads "Loading…" once.

## A2. Single edit and tab re-render (P2, P11)
- [ ] Tick a task on Tasks, switch to Timetable: badges updated. Instruments SwiftUI template: ticking a task does not
      re-run the Timetable / Today / Exams bodies for formatter or resolver changes (only views reading the database).
- [ ] Change 12/24 h in Settings: every tab shows the new clock. Change the time zone setting: Today, Timetable, widgets
      follow.
- [ ] Timetable Grid / Week (time blocks) / Day / Tiles at normal size and Dynamic Type XXL: identical to Phase 9
      screenshots (strip dots, change markers, task/exam badges, Today marker, override week of the sample data).
- [ ] Timetable left open across a minute boundary: the now line moves, no visible hitch while scrolling.

## A3. Scene phase (P5)
- [ ] Pull down Notification Centre and back, Face ID unlock, call banner: no reminder re-plan (debug screen "Last run"
      time unchanged), no hitch.
- [ ] Same blip after 5+ minutes away: re-plan runs.
- [ ] Home Screen → back after 10 s: re-plan runs (real foreground, as before).
- [ ] Change the device time zone in Settings, return: times and reminders follow at once.
- [ ] Leave the app across midnight (or set the clock): Today shows the new day on return.
- [ ] Edit a task and swipe the app away from the app switcher within 1 s: the edit is there on relaunch.

## A4. Quiet hours (P14)
- [ ] Settings → Reminders → Quiet hours: spin the start time several times: the row follows every change; the debug
      screen shows one save / re-plan about 0.8 s after the last change, not one per wheel stop.
- [ ] Change the end time and leave the screen at once (back button): the value is kept on return.
- [ ] Change a time and go to the Home Screen at once: kept on relaunch.
- [ ] A kind's rule editor quiet hours behave the same (shared rows).
- [ ] Switching quiet hours on/off saves at once. VoiceOver reads the switch and both times; Dynamic Type XXL OK.

## A5. Mark as Done failure (B12)
- [ ] Force a read-only store (debug tools, newer-version file) and press "Mark as Done" on a reminder: a notification
      "Couldn't Mark as Done" / "Open Tabula to try again." appears with the item's title as subtitle; tapping it opens
      the item. German and Japanese strings fit; no truncation in the banner.
- [ ] Normal "Mark as Done": no notice; the item's other notifications are removed (unchanged).
- [ ] Delete the task in the app, then press "Mark as Done" on its old notification: no notice.

## A6. Off-screen tabs (P16, no code change)
- [ ] Instruments SwiftUI template with Timetable and Tasks visited, then sitting on Settings for 2 minutes: check
      whether Today / Timetable `TimelineView(.everyMinute)` bodies still run off screen. Record the result in
      docs/ENVIRONMENT.md; if they do, a follow-up gates the schedule on the selected tab.

# B. Widgets, Live Activities and watch (WP2)
- [ ] B1 Edit a lesson: the Home Screen widget and a running Live Activity show the change once (no double reload; widget reload count in the debug screen goes up by 1).
- [ ] B2 Cold launch with no edits: the widget is not rewritten or reloaded (debug screen: last write time unchanged).
- [ ] B3 Now & Next widget in Japanese: the detail line uses "・"; in German and Slovak " · " as before.
- [ ] B4 Widget content at a lesson boundary and across midnight: correct (timeline planner refactor, C3).
- [ ] B5 Large Homework widget with 3 timetables: content as in Phase 4 (snapshot budget refactor; RISKS #83).
- [ ] B6 Watch (paid / TestFlight build only): snapshot arrives after an iPhone edit; complications refresh; offline, Low Power Mode and a time-zone change still refresh.

# C. Export, share and import (WP3)
Max. Run each screen in: light and dark mode, Dynamic Type XXL, German, Japanese or Simplified Chinese, VoiceOver.
Nothing here was compiled or run in the container that wrote it.

## Export: image (P1/B13)
- [ ] Image, Grid, Custom range of 6+ weeks: the share sheet opens, the progress indicator keeps spinning while it renders (no frozen UI), and the app is not killed. In Xcode's memory gauge (if a Mac is available), the peak stays below ≈ 150 MB.
- [ ] The 6-page PNG opens in Photos/Files: about 1684 px wide (scale 1.99), text sharp when zoomed. A 1-page PNG is 2526 px wide (scale 3), as before.

## Export: Week view fits the page (B1, decision P10-4)
- [ ] PDF, Week, a timetable with an 8-hour day (e.g. 08:00–16:00): the whole day is on the page, last lesson and last hour label visible above the bottom edge. Before the fix it was cut off.
- [ ] Same with a short day (08:00–12:00): blocks keep their normal on-screen height (not stretched).
- [ ] A very long day (07:00–22:00): fits with smaller blocks; short lessons still show their names.
- [ ] PDF, Day (portrait): a 10-hour day fits on one page.
- [ ] PDF, Grid: unchanged from Phase 8 (regression check: header, all periods, nothing shifted).

## Export: cancel and clean-up (B2, B14, C5)
- [ ] PDF of a full term (Range: Current term): tap Cancel mid-render. The sheet closes at once, no share sheet pops up afterwards, the app stays responsive.
- [ ] Same, but tap a reminder notification mid-render (deep link): the sheet closes, no share sheet appears later.
- [ ] Fast double tap on Export: one file, one share sheet.
- [ ] Excel and Calendar for a 366-day custom range: the spinner animates smoothly while the file is built; the share sheet opens.
- [ ] Share sheet: Save to Files, then check the file opens. Repeat and close the share sheet with a swipe instead. Both times, the next Export works (no leftover state).

## Week time-block view width (U9)
- [ ] 375 pt phone (SE / 13 mini) or Display Zoom on the Pro Max: Week view with 7 days and two overlapping lessons shows the period grid instead of thin blocks. With 5 days and no overlap it still shows blocks.
- [ ] Pro Max, 7 days with one overlap: blocks (27 pt lanes), names readable.
- [ ] Rotate to landscape and back: the view switches between blocks and grid without a glitch.

## Share Timetable sheet (P8/U12, B9)
- [ ] Open the sheet: the QR code appears after a brief spinner; VoiceOver reads "QR code for the timetable …".
- [ ] Scroll the sheet up and down quickly: no stutter (the QR code is not redrawn).
- [ ] A timetable too big for an inline link: a code appears. Toggle "Include open tasks and exams" on, then off: the first code comes back without a second "Preparing" upload (same code shown).
- [ ] Airplane mode: the upload error shows, Try Again uploads again.

## Share import preview (B4)
- [ ] Open a share link, tap "Add as New Timetable" twice quickly: exactly one new timetable.
- [ ] Replace, confirm, then tap the buttons again while it closes: one replacement, one backup copy, no error alert.

## Photo / file import (P9, P10, U11)
- [ ] Choose Photo with a 48 MP ProRAW / HEIC photo: processing starts without a long freeze; the app is not killed.
- [ ] Choose File, a 20 MB PDF from iCloud Drive: a spinner covers the choices while it opens; Cancel stops it.
- [ ] Multi-page PDF (10+ pages): the page grid appears at once; previews fill in as you scroll (spinners first).
- [ ] Password-protected PDF: alert "This PDF is password-protected…" (German and Japanese: text fits).
- [ ] A damaged or empty PDF: the "Can’t Import This" alert, or the "Can’t Show the Pages" screen with "Choose Another File", which returns to the choices.
- [ ] VoiceOver on the page grid: each page reads "Page N, button".

# D. Calendar and export formats (WP4)
- [ ] D1 Export Excel (.xlsx), open in Numbers and Excel: dates are real dates (sortable, formatted yyyy-mm-dd), times are real times (hh:mm); no repair prompt.
- [ ] D2 A subject starting with "=" or "+" exports as text in Excel (no formula).
- [ ] D3 Calendar (.ics) for a fixed-zone timetable imported into Calendar: times correct across a DST change.
- [ ] D4 Timetable screens across the last Sunday of March / October (device clock or a past week): lessons at the right times (fast DST path, C4).
- [ ] D5 Import from photo: the aSc example still parses exactly (shared regexes, C6).

# E. Sync, backup and attachments (WP5)
- [ ] E1 (paid build) Two devices: edit on one, the other updates; with a large timetable (many tasks), one edit uploads one record (CloudKit Console / debug log).
- [ ] E2 (paid build) First launch after updating from the Phase 9 build: no mass re-upload.
- [ ] E3 (paid build) Large fetch (new device signing in): all data arrives, nothing duplicated; a second launch does not fetch it again.
- [ ] E4 Restore a backup: "Restored" appears only after the save. With a full disk, "Restored Data Not Saved" appears instead.
- [ ] E5 Backup export fails (e.g. Files full): "Try Again" row works.
- [ ] E6 Make 7+ backups of the same kind: only the newest 5 stay in Files › Tabula › Backups; the one just made is always there.
- [ ] E7 Add a large file to a task and tap Cancel while it copies: Tabula asks first; Discard leaves no file behind (Files › On My iPhone › Tabula).
- [ ] E8 Quick Look an attachment while another copy finishes: the new attachment is still in the task.
- [ ] E9 Relaunch with no edits: `tabula.json` modification time unchanged (Files or the debug screen).

# F. UI polish (WP6)
- [ ] F1 At AX3: segmented pickers (Exams filter, subject symbol, timetable density, onboarding week, import review) become menus; labels readable.
- [ ] F2 Weekday chips at 375 pt width (Display Zoom) and XXL: two rows of 4, each at least 44 pt; one row on the Pro Max at default size.
- [ ] F3 VoiceOver on the subject symbol grid reads names ("Book", "Flask"…) in the app language.
- [ ] F4 Delete every timetable (or a fresh install that skips onboarding): Today and Timetable show the explanation and "Add Timetable", which opens the new-timetable sheet.
- [ ] F5 Japanese: exam location and attachment details use "、", not ", ".
- [ ] F6 AX5: the Settings row emoji and the subject symbol cells are not clipped.
- [ ] F7 Settings › About › Privacy text mentions the 30-day share-code copy; fits in all languages.
- [ ] F8 Day Change editor: Undo on an existing change asks first; Cancel keeps it.
- [ ] F9 Voice note: Record again after a take asks "Replace this recording?"; Cancel keeps the take.
- [ ] F10 Week start set to Sunday in Settings while the region starts on Monday: date pickers in editors start on Sunday.
- [ ] F11 Play voice note A to its end and tap note B at once: B keeps playing.

# H. QA fix pass
- [ ] H1 Replace-restore once, then restore 5 more times: the first "pre-restore" copy is still in Automatic copies (kept for 30 days).
- [ ] H2 Change 24-Hour Time or the Region format while Tabula is in the background, return: every time and date follows at once.
- [ ] H3 Launch Tabula and go to the Home Screen within 1.5 s: reminders are still planned (debug screen, last run reason "launch").
- [ ] H4 Read-only store (debug tools), "Mark as Done" on a reminder: the "Couldn't Mark as Done" notice appears.
- [ ] H5 Import review at AX5: the "Show" label is visible above the menu; VoiceOver reads it once.
- [ ] H6 Settings › Backup footer at XXL in German: the retention sentence fits.

# G. Privacy manifest (WP7)
- [ ] G1 First TestFlight upload after Phase 10: no ITMS-91053 "Missing API declaration" email.

# I. Bug fix pass (2026-11, `wip/bugfix-2026-11`)
- [ ] I1 Split class: two lessons in Tuesday period 3 (two language groups). Days × periods grid: both tiles share the day row (stacked, half height each), both readable and tappable; periods × days (Settings › Grid layout): side by side in the day column. VoiceOver reaches both, the first lane first. Repeat at XXL, German, dark mode and compact density (the half-height tile is tight: note if the name is unreadable).
- [ ] I2 Cancel a lesson for a day, open the cancelled tile › Change for This Day: "Change a lesson" with "Choose a lesson" (nothing preselected, Save disabled); the cancellation is listed under existing changes with Undo. Change another lesson's room and save: the cancelled tile stays cancelled. A normal tile still preselects itself.
