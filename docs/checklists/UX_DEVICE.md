# Phase 4U UX overhaul: on-device checklist

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
