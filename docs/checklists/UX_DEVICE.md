# Phase 4U on-device checklist (UX overhaul)

Device: iPhone 16 Pro / Pro Max, iOS 26 or later; Apple Watch for the watch rows. Install the build from the stage branch
(`bash scripts/xtool-dev.sh`, or TestFlight when available). Every row: tick, or note what you saw (a screenshot helps).
Settings used below: **Larger Text** (Settings › Accessibility › Display & Text Size › Larger Text, slider to the
right end = AX-XXXL), **Increase Contrast**, **Reduce Motion**, **Reduce Transparency**, **Dark Mode**, per-app
language (Settings › Apps › Tabula › Language), **24-Hour Time** (Settings › General › Date & Time).

Specs: `docs/specs/UX_OVERHAUL_PLAN.md` (decisions D1, D4, D12), `docs/ux-review/design_ui_ux_fix_OPUS.md`.

## U1 — design foundation

The debug screen `debug.design` (DEBUG builds: launch argument `-TabulaScreen debug.design`, or the CI screenshot
`debug.design@secondary`) shows the tokens, the NowMarker, the type scale and every app symbol on one page.

### U1.1 Ink tint and tokens (D1)
- [ ] Light mode: buttons, links, toggles that are on, selected tabs and selection checkmarks are **royal blue ink**
      (#2541B2), not the bright system blue. Same in sheets (editors, lesson detail).
- [ ] Dark mode: the ink is a soft periwinkle (#8EA2FF), readable on black and dark-grey cards.
- [ ] Increase Contrast on: the ink gets darker in light mode (#1A2F85) and lighter in dark mode; `debug.design` shows
      "Increase Contrast" in the Environment row and the new hex values.
- [ ] Widgets (Home Screen, all sizes) and the Lock Screen Live Activity use the ink for tinted elements.
- [ ] `debug.design` › Tokens: each swatch matches its name; the contrast figures read ≥ 4.5 for ink, correction and
      pencil on the card of the current appearance.

### U1.2 App symbols (M8, H5)
- [ ] `debug.design` › AppSymbol: "Missing symbols: 0", every row has a green check and a visible glyph. **If any row
      shows a red octagon, note its name**: the name is wrong on this iOS version.
- [ ] Today / Timetable list rows: the room uses the **map pin** (same as Exams), not a door.
- [ ] A lesson with only a room change shows the "arrow into a square" badge; only a time change the clock with "!";
      a substitute teacher the two people with a gear; cancelled a filled ×; an extra lesson a filled +.
      The ↻ arrows no longer appear on change badges (they stay for "Repeats" only).
- [ ] Next exam widget uses the graduation cap (was a clipboard).

### U1.3 Prominent buttons in dark mode (RISKS #86)
- [ ] Dark mode, onboarding: the **Next** / **Get Started** button label is black on the light ink and easy to read.
- [ ] Dark mode, Tasks: the selected filter chip has black text on ink; unselected chips have white (primary) text.
- [ ] Dark mode, every editor sheet (new exam, new task, lesson, subject): the toolbar **Save** (the
      `.confirmationAction` item, drawn by the system) is readable on its ink-tinted glass: note the label colour
      (white / black) and whether it is easy to read. Same for the disabled state.
- [ ] Dark mode: Exams empty state "Add Exam", Subjects empty state "Add Subject", the reminder permission sheet
      "Allow", the voice-note record button and the selected weekday chips in the task repeat editor have black
      labels on the light ink (the recording state: black on the light red).
- [ ] Note any other prominent button with white text on the light ink (validate.sh fails on new ones without
      `.onInkLabel()`; system-drawn buttons are outside that check).

### U1.4 12/24-hour clock (D4 / H1)
- [ ] Settings › Calendar & time › Time format shows **System** on a fresh install (onboarding does not change it).
- [ ] iOS 24-Hour Time **off**, app setting System: lesson editor, exam editor, bell editor and reminder-rule time
      pickers show AM/PM, and so does the app's text ("8:00 AM").
- [ ] iOS 24-Hour Time **on**, app setting System: all of the above show 24-hour times, pickers included.
- [ ] App setting **24-hour** with iOS set to 12-hour (US region): every time picker (lesson, exam, bell, reminder
      rule, onboarding first lesson) shows 24-hour values (no AM/PM column), matching the text. The reminder-rule screen no longer mixes "at 17:00" with
      "7:00 AM".
- [ ] App setting **12-hour** with a Slovak region: pickers show AM/PM.
- [ ] Changing the setting while an editor is closed, then opening the editor: the picker follows immediately.

### U1.5 Time pickers keep the region (RISKS #87)
The hour-cycle locale is applied to the time pickers only (not the whole app).
- [ ] Region with a custom iOS first weekday or date format (Settings › General › Language & Region): the lesson
      editor's time picker still uses the device's language and numbering; the rest of the app is unchanged.
- [ ] Serbian (Latin) device language: time picker labels are Latin, not Cyrillic.
- [ ] Japanese or Simplified Chinese: the NowMarker on `debug.design` reads 今 / 现在 and fits; time pickers follow
      the 12/24-hour setting.

### U1.6 Contrast fixes in shared components (C2)
- [ ] Settings › Appearance: the **Pro** marker next to Pro palettes is ink text in a light-ink capsule, clearly
      readable even though the row is disabled (was pale blue). Dark mode: readable too.
- [ ] Onboarding: option cards and the language card are **white on a light-grey page** (dark mode: dark-grey cards
      on black); the option description text is clearly readable; "Open language settings" is readable.
- [ ] Onboarding: the **Back** button has a visible thin outline in light and dark mode.
- [ ] Tasks: open checkboxes are **neutral grey rings** for every subject (no red/green/yellow rings); a checked task
      shows an ink disc with a tick. Yellow-subject tasks have a visible ring.
- [ ] Tasks filter chips: unselected chip text is black (white in dark mode); the Overdue chip only has a red icon.
- [ ] Timetable grid: empty slots have a thin solid grey outline with a small grey +, visible on white and black.

### U1.7 Standard close button (M7)
- [ ] Lesson detail, task detail, exam detail (opened as sheets, e.g. from Today or a notification): the leading button
      is the system **×** close button (no "Done" text); Edit stays on the trailing side. VoiceOver reads "Close".
- [ ] "Nothing to show" sheets (e.g. an editor opened without a timetable) also use the ×.

### U1.8 Labels not repeated (M1)
- [ ] Timetable settings › Rotation, Lesson editor › Applies, Task editor › Due, Reminder rule › Follow-up, Day change ›
      What changes, Appearance › Mode: the word appears **once** (as the section header), the control shows only its
      value / options. VoiceOver still announces the control with that name.
- [ ] Larger Text AX-XXXL: those rows do not leave an empty label area.

### U1.9 Title fields and validation (M5, M6)
- [ ] New exam / new task / new subject / new timetable: the first text field is a large, left-aligned field with a
      grey hint ("Exam title", "Task title", "Subject name", "Timetable name"); it looks like a field you can type in.
- [ ] Opening a new editor: **Save is disabled** and the grey hint ("Enter a title to save …" / "Enter a name.")
      shows directly under the empty title field, with an info icon. No red message is shown.
- [ ] Typing a title removes the hint and enables Save.
- [ ] Day change editor: "Enter at least one change." (Change a lesson) is grey with an info icon, never red, and
      Save is disabled until a change is entered.
- [ ] Errors (e.g. exam end before start, a lesson slot problem) appear in red only after you changed something.
- [ ] A complete form saves and closes as before.
- [ ] German and Slovak: the hint text and messages wrap, no truncation; AX-XXXL: the title field grows, the hint sits
      under it.

### U1.10 Times, rooms and type (M9, §9 type)
- [ ] Timetable list fallback (AX sizes) and other lesson rows: time and room are in the primary text colour (black /
      white), not grey; field icons are grey.
- [ ] Times on lesson tiles and rows use the rounded digits (SF Pro Rounded) and do not jiggle.
- [ ] Onboarding steppers show their value (e.g. "45 min") in rounded digits, readable grey.

### U1.11 Adaptive layout at large text (H13, F01)
- [ ] Larger Text AX-XXXL, onboarding profile step: each option shows its icon **above** the title, the title uses the
      full width (no "Elemen-tary" hyphenation), the checkmark stays visible. Slovak too.
- [ ] Larger Text AX-XXXL, timetable list rows: the subject badge sits above the subject name.
- [ ] Default text size: the same rows are side by side as before.
- [ ] `debug.design` › AdaptiveStack: "stacked yes" at AX sizes, "no" below; the icon never grows beyond ~40 pt.

### U1.12 NowMarker (signature element)
- [ ] `debug.design`: the small and regular **NOW** markers are black text on a yellow highlighter stroke with soft,
      slightly slanted ends, in light, dark and Increase Contrast; the word is never cut off at AX-XXXL.
- [ ] VoiceOver on the marker reads "Now" (not "N-O-W").
- [ ] Reduce Motion on: nothing changes (the marker never animates).
- [ ] (Watch, when the watch app adopts it) the marker renders the same.

### U1.13 Dates (L1)
- Screens adopt `contextualDate` in their own stages; nothing visible changes in U1. Linux tests cover the year
  boundary (`ContextualDateTests`).

### Not verifiable without a device
Actual resolved colours of the dynamic tokens (trait resolution in sheets, widgets and Live Activities), whether
`Button(role: .close)` renders the system ×, whether the time pickers honour the locale's hour-cycle keyword, whether a disabled row dims the ProBadge, the AX layouts, VoiceOver wording, and the SF
Symbol names that were not confirmed from an external list (`pencil.circle`, `exclamationmark.circle`, `circle`,
`list.bullet.indent`).

## State matrix (U2 to U7)

Each stage adds its own section; the orchestrator merges them. Run on the iPhone 16 Pro Max unless noted. For every
screen in a section also run the **state matrix** below. Record pass / fail / note per step.

**State matrix (every screen):** empty data · normal data (sample `secondary`) · long text (a 60-character subject
name, a long schedule name) · Dynamic Type default, xxxLarge and AX-XXXL · light and dark · Increase Contrast ·
Reduce Transparency / Reduce Motion · German (`de`) and Slovak (`sk`) lengths · Japanese / Chinese (CJK) · VoiceOver
(every control announces its purpose and state; reading order follows the layout) · targets at least 44 pt.

Launch routes: `-TabulaScreen <route> -TabulaSeed secondary` (DEBUG), or the Debug screen.

## U5b Editors

Routes: `editor.bell`, `editor.bell-period`, `editor.lesson`, `editor.lesson-new`, `editor.subject`, `editor.subjects`,
`editor.terms`, `editor.day-change`, `editor.timetable`, `editor.timetables`. The control matrix with expected results
is `docs/ux-review/EDITOR_CONTROL_AUDIT.md`; step numbers D-n match its Test column.

**Subject editor**
- [ ] D-1 New subject: type a name, Save → one subject appears in the list. Edit it, change nothing, Cancel → no
  dialog. Change something, Cancel → "Discard your changes?"; Keep Editing keeps the edit.
- [ ] D-2 No "Text contrast N : 1" line. Pick a very light colour → the low-contrast warning appears; a normal colour →
  no warning.
- [ ] D-3 New subject: no red "Enter a name" before typing; type and delete the name → it appears.
- [ ] D-4 "Palette" is a plain row (black label, grey value, chevron), not blue. It opens a list with a checkmark;
  choosing a pack returns and shows its swatches. On Free, Pro packs show a lock, cannot be chosen, footer explains.
- [ ] D-5 Icon: None / Emoji / Symbol; header reads "Icon". No "Symbol name" text field. A subject from older data with
  a symbol outside the suggestions still shows it selected in the grid.
- [ ] D-6 Turn every lesson detail off in Timetable Settings → the subject editor still offers default room, building,
  teacher and notes.
- [ ] D-7 Delete Subject shows the impact counts; confirm → gone.

**Subjects list**
- [ ] D-8 With one subject: no Edit button. With two or more: "Edit" (VoiceOver: "Reorder Subjects") shows drag
  handles; the sheet's Done is hidden until "Done" ends reordering. Swipe left → Delete. VoiceOver actions Move up /
  Move down announce the new position. Footer: only "New subjects are added at the end of the list."

**Lesson editor**
- [ ] D-10 Sample (A/B weeks): "Weeks" shows a segmented control "Every Week | Week A | Week B", no explanatory footer.
  A lesson stored for every week opens on Every Week; one stored for week B opens on Week B. Change, Save, reopen →
  same choice; the grid shows the lesson in the chosen weeks. At AX sizes the control becomes a list with a checkmark.
  With a 3-week cycle (Timetable Settings → Number of weeks 3): a checklist with "Every week" first and checked;
  tapping week 2 checks only week 2; unchecking it returns to Every week; checking all three returns to Every week.
  University sample (labels "Nepárny"/"Párny"): segments show the names alone, never "Week Párny".
- [ ] D-11 New lesson: type a room, tap New Subject, create a subject with a default teacher, Save → back in the lesson
  editor the new subject is selected, the typed room is still there, the teacher is filled. Repeat and Cancel the
  child → nothing changed in the lesson editor.
- [ ] D-12 No "Applies" section header above the "Applies" row.
- [ ] D-13 "More details" row: collapsed for a lesson without optional values, expanded for one with a room. Inside:
  room, building, teacher, type, notes; below, "What to bring". Turn every detail off in Timetable Settings → all
  fields are still offered. Hide Room, edit a lesson's room, show Room again → the new room is on the card.
- [ ] D-14 New lesson: no Delete Lesson button. Existing lesson: Delete Lesson with impact sheet.
- [ ] New lesson in a free-times timetable: no red error before the first edit; set end before start → red message.

**Bell schedule editor**
- [ ] D-15 Toolbar: Cancel, title "Bell Schedule", Save. No Edit buttons, no "•••". (C1)
- [ ] D-16 One row per period "1  08:00–08:45 ›" with a quiet "10 min break" line between rows; the long break shows
  "20 min break". Schedule picker lists "Bežný deň" and "Skrátené vyučovanie" (the sample's shortened schedule, used by
  a day change). No "Sort by Time".
- [ ] D-17 Pick the shortened schedule: "Used on" weekday chips (Monday first in sk), Delete Schedule disabled with
  "1 day change uses this schedule…". New Schedule copies the shown schedule as "Schedule 3"; tap Friday in "Used on",
  Save → Fridays use it (Timetable grid). Remove Friday, Save → the schedule still exists in the picker.
- [ ] D-18 Open a period used by lessons (`editor.bell-period`): "Used by N lessons", Delete Period disabled with the
  reason. Add Period, open it → Delete Period works and returns to the list. No lock icons anywhere.
- [ ] D-19 Regenerate from Lesson Length…: values match the schedule (first start, 45 min, breaks 10 / 20, count);
  change the length to 40 → preview updates; Replace Periods → list shows the new times; lessons stay in their
  periods after Save (grid). Count can't go below the last used period (footer explains).

**Terms & holidays**
- [ ] D-20 Title "Terms & Holidays". No red ⊖ in rows. Swipe left on an unused term → Delete. A term lessons use shows
  "Used by lessons, so it can't be deleted." and cannot be swiped. VoiceOver offers "Delete" only on deletable rows.
- [ ] D-21 Section "Holidays", button "Add Holiday"; swipe deletes a holiday. The timetable settings row reads
  "Terms & Holidays" (the Settings row is U5a's).

**Change for one day**
- [ ] D-22 Opened from a lesson: the date appears once (no full date line underneath). No red "Enter at least one
  change" before any edit. Kinds read "Use another day's timetable" and "Shortened lessons"; the kind list has no
  repeated "What changes" label.
- [ ] D-23 Change a lesson → Move to another time → choose period 7 → Save: the grid shows the lesson moved that day
  only. Lesson detail button reads "Cancel, Move or Substitute…".
- [ ] D-24 Shortened lessons → Edit Bell Schedules opens the bell editor, which lists the shortened schedule.
- [ ] D-25 A date with existing changes: each row has a labelled "Undo" button (no bare arrow, no footer); Undo
  removes that change at once.

**Timetable settings**
- [ ] D-26 First section: name and emoji only. "School days" chips in week order (sk: po ut st št pi so ne), selected
  = filled, unselected = outlined; at AX-XXXL they wrap into a grid with full names, no word-internal breaks. Turning
  all off → red "Choose at least one school day". No "Rotation" header over the Rotation row.
- [ ] D-27 Edit Bell Schedule / Terms & Holidays open as sheets from the Timetable tab, as pushed pages from Settings.
- [ ] D-28 Reset Timetable… at the bottom → impact sheet → lessons cleared, editor stays open. Without lessons it is
  disabled with a reason.

**Timetables manager**
- [ ] D-29 One timetable: no Edit, no Delete (swipe or menu), footer says why and that Reset is in its settings. Two:
  Edit reorders. Row tap → settings. Swipe left → Delete / Duplicate; swipe right → Show This Timetable; touch and
  hold → Show, Duplicate, Reset Timetable…, Delete Timetable…. "✓ Active" is grey text, not blue. No ⋯ button.

**Embedded mode (Settings, after U5a merges)**
- [ ] D-30 Settings → Timetable / Subjects / Bell schedule / Terms / Timetables push the editors: Back returns, no
  extra Cancel/Done. Edit a field → Back is replaced by Cancel (discard dialog); Save pops after saving. Swipe-back is
  not possible while edited. Subjects list and timetables manager apply changes at once and have no Done.

Not verifiable without a device: every visual and interaction step above (layout at AX sizes, chip wrapping, segmented
control truncation, swipe and context-menu behaviour, VoiceOver output, navigationDestination opening for the
`editor.bell-period` route, Back-button replacement in embedded mode).

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
