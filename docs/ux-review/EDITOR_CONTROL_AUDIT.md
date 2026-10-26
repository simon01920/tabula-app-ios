# Editor control audit (Astra F05 §5, UX overhaul stage U5b)

Date: 2026-10-26. Base: main `19133c0`. Branch: the U5b worktree branch. Auditor: `swiftui-engineer` (Opus).

**Method.** Every visible control of every editor screen and nested page or sheet was read in the SwiftUI source before
and after U5b. "Observed result" is what the code does, not what a device showed: the app cannot be run here
(CLAUDE.md rule 4). Each row ends with the test that proves it: a Linux unit test (`swift test`, TimetableUI) where the
behaviour is logic, else a numbered step of the on-device checklist (`docs/checklists/UX_DEVICE.md` § U5b, "D-n").

**Decisions** (Astra §5): **Keep** = working action (may have been changed); **Disable** = temporarily unavailable,
disabled with a nearby reason; **Remove** = gone from the flow (no-op, duplicate, developer-only or replaced);
**Info** = shown as text, not as an enabled control.

Scope: owned by U5b and changed here: subject editor, subjects list, lesson editor (new and edit), bell schedule
editor, terms & holidays, change for one day, timetable settings, timetables manager. Audited only, findings for U2:
task editor, exam editor (last two tables; nothing changed there).

## Summary

| Decision | Count |
|---|---|
| Keep | 83 |
| Disable (with reason) | 7 |
| Remove | 18 |
| Info | 12 |
| **Total rows (U5b editors)** | **120** |
| Findings for U2 (task + exam editors) | 18 |

Removed enabled no-ops and duplicates: the four bell-schedule **Edit** buttons and the **•••** overflow (C1), **Sort by
Time** (the list is always in time order and saving sorts), the per-period **⊖** and **lock**, the timetables manager's
**⋯** menu and its **Edit Settings** item (same as the row tap), the raw **Symbol name** field, the contrast number.
Cancel and Save stay distinct on every Save/Cancel editor. No editor has two same-scope saves: the only immediate-apply
actions inside a Save/Cancel editor are destructive actions on a *different* object with their own confirmation
(Delete Lesson / Subject, Reset Timetable) and Undo of an *already saved* day change; each is named for what it commits.

## Subject editor (`editor.subject`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 1 | Cancel (toolbar) | Leave; confirm discard when edited | EditorScaffold: discard dialog when dirty | Keep | D-1 |
| 2 | Save (toolbar) | Store one subject, close | Saves via `saveSubjectMutation`; disabled while the name is blank | Keep | `SubjectDraftTests`, D-1 |
| 3 | Preview tile | Show how tiles look | Non-interactive, one VoiceOver element | Info | D-2 |
| 4 | "Text contrast 15.1 : 1" footer | — | Developer number (M4) → removed | Remove | D-2 |
| 5 | Low-contrast / blends warnings | Warn only when a colour fails | Footer text with icon | Info | D-2 |
| 6 | Name | Edit name | Text field; red "Enter a name" only after the first edit (M5) | Keep | D-3 |
| 7 | Short name | Edit short name | Text field | Keep | D-3 |
| 8 | Palette row | Browse another pack's colours | Was a blue `Menu` label that looked like a button → normal row with value and chevron, pushes the palette list (M18) | Keep | D-4 |
| 9 | Palette list: pack rows | Show that pack's swatches, pop back | Checkmark on the current pack | Keep | D-4 |
| 10 | Palette list: Pro packs | Unavailable on Free | Lock icon, row disabled, footer "Packs with a lock come with Tabula Pro." | Disable | D-4 |
| 11 | Colour swatches | Pick the colour | Sets `colorChoice`; selected trait for VoiceOver | Keep | `SubjectDraftTests`, D-4 |
| 12 | Custom colour (ColorPicker) | Any colour | System picker | Keep | D-4 |
| 13 | Icon: None / Emoji / Symbol | Choose the icon kind | Segmented; section header "Icon" no longer equals a segment ("Symbol") | Keep | D-5 |
| 14 | Emoji field | One emoji | Keeps the first character | Keep | `EditorBasicsTests` |
| 15 | Symbol grid | Pick a symbol | Suggestions plus a symbol stored by older data, so it stays selectable | Keep | D-5 |
| 16 | "Symbol name" text field | — | Raw SF Symbol names; a typo silently showed nothing → removed | Remove | D-5 |
| 17 | Defaults: room, building, teacher, notes | Prefill new lessons | Were hidden by the timetable's display setting → always offered (D10) | Keep | `subjectCreatedFromTheLessonEditorKeepsTheDraft`, D-6 |
| 18 | Delete Subject (existing only) | Delete with impact list | Sheet with counts, then delete; not shown for a new subject | Keep | `TimetableManagementTests`, D-7 |

## Subjects list (`editor.subjects`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 19 | Done (sheet) | Close | Hidden while reordering (no two "Done") | Keep | D-8 |
| 20 | Done (embedded in Settings) | — | Parent Back pops; no own Done | Remove | D-30 |
| 21 | Edit (toolbar) | Reorder mode | Was "Reorder", disabled with < 2 subjects → "Edit" like the timetables manager, hidden with < 2 (M17/M18); VoiceOver "Reorder Subjects" | Keep | D-8 |
| 22 | Done (reorder mode) | End reordering | VoiceOver "Done reordering" | Keep | D-8 |
| 23 | + Add Subject | New subject sheet | Disabled only without a timetable | Keep | D-8 |
| 24 | Empty state: Add Subject | Same as + | The call to action of the empty state (justified second entry point) | Keep | D-8 |
| 25 | Row tap | Edit the subject | Sheet with the subject editor | Keep | D-8 |
| 26 | Swipe: Delete | Delete with impact list | Same confirmation as the editor | Keep | D-8 |
| 27 | Context menu: Delete | Same as swipe | Secondary path, same scope | Keep | D-8 |
| 28 | Drag handles (reorder mode) | Reorder, persisted | `reorderSubjectsMutation`; a drop in place applies nothing | Keep | `SubjectOrderMutationTests` |
| 29 | VoiceOver Move up / Move down | Reorder without dragging | Announces the new position | Keep | `SubjectOrderMutationTests`, D-8 |
| 30 | Footer "Tap Reorder to change the order…" | — | Instructions for a control (M5) → only "New subjects are added at the end of the list." | Remove | D-8 |

## Lesson editor (`editor.lesson`, `editor.lesson-new`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 31 | Cancel / Save | Discard / store one lesson | EditorScaffold; Save disabled while something blocks | Keep | `LessonDraftTests` |
| 32 | Subject picker | Choose subject | New lessons fill empty room/building/teacher from the subject (D10: whatever the display setting) | Keep | `newLessonUsesContextAndSubjectDefaults` |
| 33 | New Subject (nested sheet) | Create a subject and select it, keep the lesson draft | Child Save selects the new subject; child Cancel changes nothing; typed fields are never overwritten | Keep | `subjectCreatedFromTheLessonEditorKeepsTheDraft`, D-11 |
| 34 | Day picker | Weekday / cycle day | | Keep | `LessonDraftTests` |
| 35 | Week A / Week B switches + footer "If no week is selected…" | — | Both off meant every week (H8) → removed | Remove | D-10 |
| 36 | Every Week / Week A / Week B (two-week cycle) | Choose the weeks | Segmented; inline list at accessibility sizes; maps to `cycleWeeks` nil / [1] / [2] | Keep | `segmentsRoundTripThroughTheModel`, `storedWeeksMapToTheSegment`, D-10 |
| 37 | Week checklist (3+ week cycles) | Choose several weeks | "Every week" first and checked by default; no "nothing checked" state | Keep | `listStartsOnEveryWeekAndNeverHasTwoMeanings`, `listSelectionRoundTripsThroughTheModel` |
| 38 | Period / Times segmented | Entry mode | Carries the times over | Keep | `slotModeSwitchCarriesTimes` |
| 39 | Period picker, Periods in a row | Choose slot | The stepper appears only when a span > 1 fits | Keep | `slotModeSwitchCarriesTimes` |
| 40 | Starts / Ends (times) | Free times | Red "ends before it starts" only after the first edit (M5) | Keep | `blockingIssues` |
| 41 | Applies picker | Always / terms / date range | Section header "Applies" repeating the label removed (M1) | Keep | D-12 |
| 42 | Term switches | Limit to terms | "No terms yet" text when there are none | Keep | `blockingIssues` |
| 43 | "No terms yet. Add terms in the timetable settings." | — | Text, not a button | Info | D-12 |
| 44 | From / Until | Date range | | Keep | `blockingIssues` |
| 45 | "Rule from a newer version" | — | Read-only label, value preserved | Info | `roundTripOfUnchangedDraftEqualsTheLesson` |
| 46 | More details (disclosure) | Reveal optional fields | New; starts expanded when any optional field has a value (D10) | Keep | `editorsOfferEveryFieldWhateverTheDisplaySetting`, D-13 |
| 47 | Room, Building, Teacher, Type, Notes | Edit | Were hidden by `fieldVisibility` → always offered under More details (F06/D10) | Keep | `hiddenFieldIsStillEditedAndKept`, D-13 |
| 48 | What to bring: items, ⊖ per item, Add Item | Edit the list | Shown with More details expanded; ⊖ is labelled "Remove Item" for VoiceOver | Keep | `emptyEnabledFieldIsStoredAsAbsent` |
| 49 | Overlaps section | Warn, never block | Text rows | Info | `conflictsAreReportedWithOtherSubjects` |
| 50 | Delete Lesson (existing only) | Delete with impact | Not offered on an unsaved new lesson | Keep | `TimetableManagementTests`, D-14 |

## Bell schedule editor (`editor.bell`, `editor.bell-period`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 51 | Cancel / title / Save | One toolbar | Before: `.toolbar { EditButton() }` on a `Group` of sections; SwiftUI applies a Group's modifier to each child, so each section added an Edit button, pushing title and Save into "•••" (C1). After: only the scaffold's toolbar | Keep | D-15 |
| 52 | Edit ×4 | — | One per section, all toggling the same edit mode (C1) | Remove | D-15 |
| 53 | ••• overflow | — | Held the title and Save (C1) | Remove | D-15 |
| 54 | Schedule picker | Show Regular / weekday / single-date schedules | New; lists every live schedule of the timetable, including ones only day changes use (before: those could not be edited at all) | Keep | `occasionalSchedulesAreLoadedAndKept`, D-16 |
| 55 | Name | Rename the shown schedule | Blank name blocks Save with "Enter a name." | Keep | `blankScheduleNameBlocksSaving` |
| 56 | Used on (weekday chips) | Assign weekdays to a schedule | Replaces the weekday switch rows; a weekday belongs to one schedule | Keep | `weekdaysBelongToOneVariant`, D-17 |
| 57 | Period row "1  08:00–08:45 ›" | Open the period | One row per period instead of 4 (Label/Kind/Starts/Ends) | Keep | `rowsNumberLessonsAndComputeBreaks`, D-16 |
| 58 | "10 min break" line | Show the gap | Computed, not editable | Info | `rowsNumberLessonsAndComputeBreaks` |
| 59 | Lock icon on a row | — | Unexplained (Opus R6) → removed; the detail page says "Used by N lessons" | Remove | D-18 |
| 60 | ⊖ on a row | — | Moved to the detail page (Delete Period) | Remove | D-18 |
| 61 | Detail: Name, Kind, Starts, Ends | Edit the period | Error / overlap shown under the times | Keep | `overlapIsAWarningAndInvertedTimesBlock` |
| 62 | Detail: "Used by N lessons" | Explain why it can't be deleted | Counts recurring lessons and extra/moved lessons of day changes | Info | `usageCountsLessonsAndDayChanges` |
| 63 | Detail: Delete Period | Remove the period | Disabled while used, footer "Lessons use this period…" | Disable | `periodsUsedByLessonsCannotBeRemoved`, D-18 |
| 64 | Add Period | Append a period after the last | 45 min, 5 min after the last | Keep | `addPeriodAppendsAfterTheLastOne` |
| 65 | Sort by Time | — | The list is always shown in time order and saving sorts: no visible effect | Remove | D-16 |
| 66 | Regenerate from Lesson Length… | Rebuild periods with the onboarding generator | New page: first start, lesson length, breaks, count, preview | Keep | `regenerationReadsTheScheduleAndKeepsPeriodIDs`, D-19 |
| 67 | Regenerate: lesson count stepper minimum | Never drop a used period | Minimum = last used lesson period, footer explains | Disable | `regenerationNeverDropsAPeriodInUse` |
| 68 | Regenerate: Replace Periods | Apply to the draft, pop | Disabled only when the preview is empty (all lessons would run past midnight); the empty preview is the visible reason | Disable | D-19 |
| 69 | Add Schedule for a Day (weekday menu) | — | Replaced by New Schedule + Used on | Remove | D-17 |
| 70 | Remove ‹variant› buttons | — | Replaced by Delete Schedule for the shown schedule | Remove | D-17 |
| 71 | New Schedule | Copy the shown schedule | Same period IDs, so lessons keep their periods; no weekday until assigned | Keep | `newScheduleWithoutWeekdaysIsStoredAndCanBeAssigned` |
| 72 | Delete Schedule (not Regular) | Remove the schedule | Disabled while day changes use it, with the count | Disable | `usageCountsLessonsAndDayChanges`, D-17 |

## Terms & holidays (`editor.terms`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 73 | Cancel / Save | Discard / store all | | Keep | `TermsDraftTests` |
| 74 | Term name, start, end | Edit | Red "end before start" inline | Keep | `invalidRangesBlockAndUsedTermsAreLocked` |
| 75 | Red ⊖ inside the name row | — | Permanent accidental-delete risk (M19) → swipe to delete (`onDelete`, VoiceOver "Delete" action) | Remove | D-20 |
| 76 | Swipe: Delete term | Delete an unused term | `deleteDisabled` for terms lessons use | Keep | `addEditDeleteRoundTrip`, D-20 |
| 77 | Lock icon on a used term | — | Unexplained → removed | Remove | D-20 |
| 78 | "Used by lessons, so it can't be deleted." | Explain the missing Delete | In the row | Info | D-20 |
| 79 | Add Term | Append a term | | Keep | `addEditDeleteRoundTrip` |
| 80 | Holiday name, kind, start, end | Edit | "Breaks" renamed "Holidays" in the UI (D11), model names unchanged | Keep | D-21 |
| 81 | ⊖ on a holiday | — | → swipe to delete | Remove | D-21 |
| 82 | Add Holiday | Append a holiday | Was "Add Break" | Keep | D-21 |
| 83 | Footer "Terms with a lock…" | — | Referred to a lock nobody understood | Remove | D-20 |

## Change for one day (`editor.day-change`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 84 | Cancel / Save | Discard / store one change | Save disabled while something blocks; red reasons only after the first edit (M5) | Keep | `eachKindBuildsItsOverrideAndValidates`, D-22 |
| 85 | Date picker | Choose the date | Full date repeated in the footer → removed (M20) | Keep | D-22 |
| 86 | Kind (inline list) | Choose what changes | Label repeating the header hidden (M1); "Use another day's timetable", "Shortened lessons" (M20) | Keep | D-22 |
| 87 | Lesson picker | Choose the lesson | Choosing another lesson resets a started move | Keep | `invalidMovedTimesBlockAndOtherLessonResetsTheMove` |
| 88 | Substitute subject, room, building, teacher | Change for the day | Room/building/teacher were hidden by the display setting → always (D10) | Keep | `moveSubstituteAndNoteBuildOnePatch` |
| 89 | Note (change a lesson) | Note for this occurrence | New (`LessonPatch.notes`) | Keep | `moveSubstituteAndNoteBuildOnePatch` |
| 90 | Move to another time + slot rows | Move the lesson that day | New (`LessonPatch.slot`); makes "Cancel, Move or Substitute…" true (M15) | Keep | `moveSubstituteAndNoteBuildOnePatch`, D-23 |
| 91 | Note (no school) | Reason | | Keep | `eachKindBuildsItsOverrideAndValidates` |
| 92 | Bell schedule picker (shortened) | Choose a schedule | | Keep | `eachKindBuildsItsOverrideAndValidates` |
| 93 | Edit Bell Schedules (nested sheet) | Edit the schedules offered here | Before: the editor could not show schedules without a weekday (e.g. "Shortened"), so it could not edit what this picker offers. Now it lists them | Keep | `occasionalSchedulesAreLoadedAndKept`, D-24 |
| 94 | Use timetable of (day), Week | Follow another day | | Keep | `eachKindBuildsItsOverrideAndValidates` |
| 95 | Extra lesson: subject, room, building, teacher, notes, slot | Add a one-off lesson | Building and notes added (D10) | Keep | `extraLessonKeepsEveryOfferedField` |
| 96 | Undo (existing change) | Remove that saved change at once | Was an icon-only arrow explained by a footer → labelled "Undo" button, footer removed | Keep | D-25 |
| 97 | Existing changes list | Show what is already changed | Text rows | Info | D-25 |
| 98 | "No lessons on this date…" footer | Explain why lesson kinds are missing | Kinds that need a lesson are hidden | Info | D-22 |

## Timetable settings (`editor.timetable`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 99 | Cancel / Save (sheet) | Discard / store | | Keep | `TimetableDraftTests` |
| 100 | Cancel (embedded) | — | Shown only while edited (replaces Back so edits are never lost silently); Save pops | Keep | D-30 |
| 101 | Name, Emoji | Identity | Own section, split from the days (M16) | Keep | D-26 |
| 102 | Seven weekday switches | — | → weekday chips (M16) | Remove | D-26 |
| 103 | School days chips | Choose school days | Button-style toggles in the user's week order (Monday first for sk) | Keep | `dayChoicesFollowTheRotation`, D-26 |
| 104 | Rotation picker | Kind of rotation | Header "Rotation" repeating the label removed (M1); family changes locked with a reason when lessons exist | Keep | `rotationFamilyAndMinimumLengthGuards` |
| 105 | Week / day cycle fields | Configure the rotation | Unchanged | Keep | `rotationRoundTripsForAllKinds` |
| 106 | "This week is A" | Confirm the rotation | Text | Info | D-26 |
| 107 | Lesson times picker, default length | Time structure | | Keep | `switchingToBellScheduleCreatesADefaultOne` |
| 108 | Edit Bell Schedule | Open the bell editor | Sheet, or pushed when embedded (no stacked sheets) | Keep | D-27 |
| 109 | Details on lesson cards (switches) | What summaries show | Copy now says hidden details stay saved and editable (D10) | Keep | `changingVisibilityNeverChangesStoredValues`, D-13 |
| 110 | Default view, density, palette | Appearance | | Keep | `unchangedDraftReproducesTheTimetable` |
| 111 | Terms & Holidays | Open the terms editor | Sheet, or pushed when embedded | Keep | D-27 |
| 112 | Reset Timetable… | Clear the lessons (the last timetable can't be deleted) | New here, impact confirmation; disabled with a reason when there are no lessons | Keep | `TimetableManagementTests`, D-28 |

## Timetables manager (`editor.timetables`)

| # | Control | Intended result | Observed in code (before → after) | Decision | Test |
|---|---|---|---|---|---|
| 113 | Done | Close | Hidden while reordering; not shown embedded | Keep | D-29 |
| 114 | Edit | Reorder | Was always visible, even with one timetable → only with two or more (M17) | Keep | D-29 |
| 115 | + Add Timetable | New timetable sheet | Disabled at the plan limit with "Your plan includes N timetables." | Disable | D-29 |
| 116 | Row tap | Settings | Sheet, or pushed when embedded | Keep | D-29 |
| 117 | ⋯ menu + "Edit Settings" | — | Repeated the row tap (M17) | Remove | D-29 |
| 118 | Swipe right: Show This Timetable | Make it the shown one | Only for inactive rows; also in the context menu | Keep | D-29 |
| 119 | Swipe left: Delete / Duplicate; context menu: Duplicate, Reset Timetable…, Delete Timetable… | Actions | Delete hidden for the last timetable; footer says why and where Reset is | Disable | `TimetableManagementTests`, D-29 |
| 120 | "✓ Active" | Show which is shown | Was blue, button-like → secondary text with checkmark | Info | D-29 |

(The New Timetable sheet's name, emoji, structure picker and Cancel/Save were checked and kept; it is now internal so
Settings can present it.)

## Findings for U2: task editor (`tasks.editor`, `tasks.editor-new`), audit only

| # | Control | Observation in code | Suggested decision |
|---|---|---|---|
| U2-1 | Title | Right-aligned `LabeledTextField` (axis vertical) | Keep; adopt U1 title style (M6) |
| U2-2 | Kind picker | No description per kind (D5) | Keep; add one-line descriptions |
| U2-3 | Subject picker | Existing subjects only; no "Create subject" (Astra §5 expects it, with the parent draft kept) | Decide: add a nested New Subject like the lesson editor (pattern proven there) |
| U2-4 | Due picker + header "Due" | Header repeats the label (M1) | Keep; drop one |
| U2-5 | Next lesson info row | Text | Info |
| U2-6 | Priority picker | | Keep |
| U2-7 | Notes | Header "Notes" and field label "Notes" (M1) | Keep; drop one |
| U2-8 | Subtasks: check, title, swipe delete | | Keep |
| U2-9 | Subtasks: "Reorder" in the section header | Wording differs from "Edit" (M18) | Keep; rename "Edit" |
| U2-10 | New subtask field + Add Subtask | Return key and the button do the same; button disabled until text (visible reason: empty field) | Keep (one visible path, keyboard shortcut) |
| U2-11 | Repeat weekday buttons | Own `WeekdayToggle` | Keep; consider the shared `WeekdayChips` / U1 chip style |
| U2-12 | Reminder override: tier picker | May offer Time Sensitive without the entitlement (H9/D7) | Hide per D7 (U5a/U1 owns the helper) |
| U2-13 | Attachments menu (photo, file, link, voice note) | All four call real presenters in code; not verified on a device | Keep; device-test each |
| U2-14 | Delete task | Confirmation dialog | Keep |

## Findings for U2: exam editor (`exams.editor`, `exams.editor-new`), audit only

| # | Control | Observation in code | Suggested decision |
|---|---|---|---|
| U2-15 | Room, building, notes | Hidden by `fieldVisibility`; `ExamDraft.examForSave(visibility:)` keeps hidden values. Violates D10/F06 | Offer all under "More details", drop the visibility filter on save |
| U2-16 | "Enter a title to save the exam." | Footer of the time section, far from the title (M6) | Move under the title |
| U2-17 | Topics | Always in edit mode (permanent drag handles and ⊖) | Swipe to delete + Edit, like Terms (M19) |
| U2-18 | Subject picker | No "Create subject" | Same decision as U2-3 |
