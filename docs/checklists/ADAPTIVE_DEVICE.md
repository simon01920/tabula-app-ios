# Adaptive layout: on-device checklist (iPad, iPhone Duo, existing iPhones)

Spec: `docs/specs/ADAPTIVE_LAYOUT.md`. Build from `wip/adaptive-layout` (TestFlight or Xcode; the xtool path installs
on iPhone only). CI simulator screenshots exist for most rows, but they are simulation: nothing here is verified on a
device yet. Every row: tick, or note what you saw (a screenshot helps).
Settings: Larger Text (AX-XXXL = slider at the right end), Dark Mode, Reduce Motion, VoiceOver, per-app language
(German for long strings, Japanese for CJK).

## A. Existing iPhone (iPhone 16 Pro Max): nothing changed
- [ ] A1 Portrait: Today, Timetable (all views), Tasks, Exams, Settings look and behave as in the previous build: Tasks
      opens the detail as a sheet, Exams pushes the detail, a lesson opens as a sheet.
- [ ] A2 Landscape (Pro Max is regular width in landscape): still the phone layout, no list-beside-detail, no inspector.
- [ ] A3 Timetable toolbar: the View Options button now shows a slider symbol instead of "⋯"; its menu is unchanged.
- [ ] A4 An exam in the future: its detail's "More" button shows an archive box symbol; "Move to History" still works.
- [ ] A5 Tab bar at the bottom as before (sidebar-adaptable style must not change iPhone).

## B. iPad (11-inch and 13-inch, portrait and landscape)
- [ ] B1 The app installs and launches on iPad, fills the screen in all four orientations (also upside down).
- [ ] B2 Tab bar at the top; its sidebar button turns it into a sidebar and back; all five tabs reachable both ways.
- [ ] B3 Tasks: the list on the left, "Select a Task" on the right; tapping a task shows it on the right, the row stays
      highlighted; Edit opens the editor sheet; deleting the task clears the right side.
- [ ] B4 Exams: same with "Select an Exam"; the big next-exam card also opens on the right; History segment works.
- [ ] B5 Timetable (13-inch any orientation, 11-inch landscape): tapping a lesson opens its detail in a column on the
      right, the grid stays visible and usable; Close hides it. 11-inch portrait: the detail is a sheet as on iPhone.
- [ ] B6 From the lesson column: Edit, Change for This Day, Add Homework and a task row each open their sheet.
- [ ] B7 Today and Settings: rows sit in one centred column (about the width of a book page), not stretched across the
      screen; pushed Settings pages too. At AX-XXXL text the column uses the full width again.
- [ ] B8 Editors and forms are sheets of moderate width; no row stretches across 13 inches.
- [ ] B9 Hardware keyboard on forms: Tab moves between fields, Return does not drop data; the on-screen keyboard does not
      cover the field being edited (task editor notes, exam editor topics, lesson editor room).

## C. iPad resizing while editing (Split View, Stage Manager, windowed apps)
- [ ] C1 Tasks, wide: select a task, Edit, change the title (do not save). Resize the window to narrow (one-third /
      compact) and back to wide. The editor stays open with the change; Save keeps it.
- [ ] C2 Tasks, narrow: open a task (sheet), Edit, type, widen the window. Editor still open, change kept; after closing,
      the same task is selected in the right column.
- [ ] C3 Tasks, wide with a task selected and no editor: narrow the window. The task comes back as the detail sheet.
- [ ] C4 Exams: open an exam, Edit, type, resize narrow ↔ wide. Editor stays with the change; the exam stays open
      (pushed when narrow, on the right when wide).
- [ ] C5 Timetable: open a lesson (column), Edit lesson, type, narrow the window. Editor stays with the change; after
      Save/Cancel the lesson is shown as a sheet. Back to wide: the lesson moves to the column.
- [ ] C6 The selected tab, the shown week/day of the timetable and the Tasks filter survive every resize.
- [ ] C7 Slide Over / the narrowest window: everything is the phone layout, nothing clipped.

## D. iPhone Duo
- [ ] D1 Outer display (closed): tab bar and toolbars on the side (placed by the system); nothing under the camera;
      Today, Timetable (grid, week, day, tiles), Tasks, Exams, Settings show no clipped labels, no overlapping controls,
      no horizontal scrolling; quick add and editors fit.
- [ ] D2 Inner display, portrait: horizontal bars; Tasks and Exams show list beside detail if the width class is regular
      (record which you see).
- [ ] D3 Inner display, landscape: bars on the side; list beside detail; Timetable lesson column if it fits.
- [ ] D4 Fold while editing: open a task editor on the inner display, type, close the device to the outer display and
      open it again. The editor stays with the change.
- [ ] D5 Partial fold (book pose): sheets, alerts and menus move clear of the fold; the split columns are not cut by it.
- [ ] D6 Toolbar items on the side: every icon has a label in its long-press / overflow menu; the system overflow (⋯)
      holds overflowed items, our menus use other symbols.
- [ ] D7 Two apps side by side on the inner display: our bars sit on our outer edge, content not covered.

## E. Every new layout: text, appearance, languages, VoiceOver
- [ ] E1 AX-XXXL: split columns stay readable (rows wrap, nothing truncated mid-word); the readable cap is off.
- [ ] E2 Dark Mode: the selected-row highlight is visible in both appearances; placeholders readable.
- [ ] E3 German and Japanese: "Aufgabe auswählen" / "試験を選択" placeholders fit; list rows wrap.
- [ ] E4 VoiceOver on iPad Tasks/Exams: the list is read first, then the detail; the selected row says "Selected";
      after choosing a row, VoiceOver can move into the detail with a swipe right past the list.
- [ ] E5 Reduce Motion: switching rows and resizing do not add animations of our own.
- [ ] E6 Empty data (blank seed / no tasks): the placeholder shows on the right, the list shows its empty state.
