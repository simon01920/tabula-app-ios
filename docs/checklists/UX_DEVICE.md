# Phase 4U: manual on-device checklist (UX overhaul)

One section per stage. Device: iPhone 16 Pro Max (and the Apple Watch where noted). Nothing here can be verified without a
device. For every screen also run these once per stage: default size, an intermediate Dynamic Type size, AX-XXXL, light,
dark, Increase Contrast, Reduce Transparency, Reduce Motion, Slovak, German (longest strings), Japanese (CJK), and VoiceOver
(swipe through; labels read sensibly).

## U5a: Settings IA and Reminders

Setup: install the build, finish onboarding with the "secondary" sample so subjects, a bell schedule and terms exist. Run the
numbered steps once with 1 timetable and once with 2 or more.

### Settings root (R3, H11)
1. Settings tab shows the groups Timetable, Notifications, General, then the Tabula Pro plan and About & Feedback. Every row has a
   coloured rounded icon tile with a white symbol. At AX-XXXL the tile stays 29 pt and the text wraps (values move below the title).
2. TIMETABLE: first row is the active timetable (name + emoji or tile; "Active" value only with 2+ timetables); Subjects shows a count;
   Bell schedule shows "N periods" (no value for a free-form timetable); Terms & holidays; "Manage timetables" is present only
   with 2+ timetables and is NOT blue text; "Add Another Timetable…" is the only blue row.
3. Tap each of the five editor rows: it PUSHES (slides in from the right), it does not show a sheet. UNVERIFIED RISK: the editors
   bring their own navigation bar (Cancel / Save or Done). Check there is exactly ONE bar, Cancel/Done/Save return to Settings, the
   edge-swipe back gesture works (note it if not), and no content hides under the status bar.
4. "Add Another Timetable…" opens a sheet (create flow); Cancel closes it; Save creates the timetable, makes it active, and the
   Manage row appears. With the free-tier timetable limit reached the row is disabled.
5. NOTIFICATIONS: Reminders shows "Off" or "N on"; Live Activities shows On / Off (Off without Pro or with both switches off).
6. GENERAL: School type is a menu picker with the up-down indicator and the current value; changing it changes nothing in existing
   timetables. Date & time shows System or 12-hour / 24-hour; Colors shows the current palette name; Language shows the language
   name (in that language) with an arrow and opens the iOS Settings app; the profile footer sits under the General group.
7. There is NO "Lessons are called" row (the wording follows School type). No section header repeats a row label.
8. Empty state: with no active timetable (debug seed "blank") the timetable rows are absent, only Add Another Timetable remains.

### Reminders (R4, H10)
1. Settings > Reminders is titled "Reminders" everywhere (root row, screen title).
2. One row per kind: `Homework  1 day before, 17:00 ›`, `Assignments  Off ›`. No switches in the list. Switching a kind on or off in
   its page changes only the trailing value; no rows appear or disappear. No "Times and delivery" rows.
3. Open a kind: first row "Remind me" switch. Off hides the rest. On shows When, Follow-up (no header repeating "Follow-up"),
   How it arrives, Quiet hours (no header). First time on with notifications "not asked": the pre-explainer sheet shows.
4. Delivery: Standard and Loud alarm only on a build without the Time Sensitive entitlement (all xtool builds). A rule that was saved
   as Time Sensitive shows Standard selected plus the footnote; the Reminders list row does not mention "Time Sensitive".
5. "Allow Time Sensitive" and its lead stepper are absent from the Reminders list in that build. (Paid-account build: unverified;
   they appear once iOS reports the setting.)
6. "Delivery check > Test reminders & troubleshoot" opens the Reminder Check. The attention row on top of the Reminders list appears
   ONLY while something is user-fixable: turn notifications off in iOS Settings and return (the row appears, icon + text, one
   orange warning colour), turn them back on (the row disappears).
7. Reminder Check: no printed "OK / Check / Info" words, VoiceOver reads the status word before each row; Focus has an "Open Settings"
   button that opens iOS Settings; "Technical details" is collapsed and holds "Scheduled: N (iOS limit: 64)", Silent mode and the
   limits; Low Power Mode on gives a warning; with everything fine the summary reads "Reminders should work".
8. Send Test Notification still arrives; the test alarm button appears only with the alarm permission.

### Colors (D3, M26)
1. There is no Light/Dark/System choice anywhere. Switch iOS between light and dark: Tabula follows at once. A device that had
   "Dark" stored by an older build now follows the system.
2. Color palette is an inline picker: name + swatch strip per row, check mark on the selected one. Ocean, Sunset and Pastel carry a
   neutral "Pro" capsule (with a padlock only while locked). Tapping a locked palette does nothing; the footer explains.
3. The preview tile follows the selection and stays readable on every palette in light and dark.
4. "Apply to All Subjects" is disabled when nothing would change. Otherwise a confirmation dialog names the palette and the number
   of subjects; confirming recolors the subjects (check the Timetable tab), and a status line + "Undo" appear; Undo restores the
   colors. Picking another palette hides the Undo line. Lesson tiles keep readable text on the new colors.

### Date & Time (M27, D4)
1. Week starts on and Time format are visible; "Advanced" is collapsed and holds the time zone (expanded when a fixed zone is already
   stored). Time format defaults to System: toggle iOS 24-Hour Time and check the sample row follows. The 12-hour / 24-hour
   override still works and survives a relaunch. (DatePickers follow the same setting only once U1's root locale lands.)
2. Fixed time zone: choosing it opens the searchable list; the explanation under the group matches the mode.

### About & Feedback (L4)
1. Version and Build rows; "Send Feedback" opens Mail with the subject "Tabula <version>" to the PLACEHOLDER address
   (feedback@tabula-app.invalid; replace before TestFlight); "Privacy Policy" opens Safari on the PLACEHOLDER URL; there is NO
   "Rate Tabula" row yet (it appears when `AppLinks.reviewURL` is set); privacy summary; Acknowledgements pushes a page.
2. No "built with Swift" text anywhere.
