# Phase 4U visual verification (2026-10-31)

Reviewer: qa-reviewer (Opus), read-only. Inputs: 182 CI screenshots (`docs/ux-review/screens/`, clock Tue 13 Oct 2026 10:20), the Opus and Astra reviews, and `docs/specs/UX_OVERHAUL_PLAN.md`. HIG references used (apple-design skill): `color.md` › "Avoid using the same color to mean different things", `typography.md` › "Keep text truncation to a minimum as font size increases" / "Consider adjusting your layout at large font sizes", `accessibility.md` › contrast (4.5:1 up to 17 pt), `layout.md`, `toolbars.md`, `widgets.md`.

**Method and limits.** Every screen was viewed as a light | dark | AX-XXXL montage. Contrast was pixel-sampled only where flagged. Screenshots are not proof of on-device behaviour. Code was read only to name likely causes. No screenshot exists for exam detail (H15), the subjects editor (M18), the Watch, or Increase Contrast / Reduce Motion, so those are **Unverified**.

Paths below are relative to `docs/ux-review/screens/`.

## 1. Finding status

Counts: **Fixed 58 · Partial 24 · Not fixed 2 · Deferred-by-design 1 · Unverified 2** (87 IDs).

### Opus review
| ID | status | evidence file | note |
|---|---|---|---|
| C1 | Fixed | 4-editors/editor.bell_secondary-light.png | Cancel · Bell Schedule · Save |
| C2 | Fixed | 7-settings/settings.colours_secondary-light.png | Pro capsule ink; chips gone; empty slots quiet |
| C3 | Fixed | 5-tasks/tasks_secondary-light.png | Filters replaced by grouped list |
| H1 | Fixed | 7-settings/settings.reminder-rule_secondary-light.png | Pickers 24 h; onboarding follows System (12 h en-US) |
| H2 | Partial | 8-widgets-live-activities/widgets.gallery_secondary-light.png | App "25 min left"; widgets/LA keep "25:00", "2:00" |
| H3 | Partial | 2-today/today.before-school_secondary-light.png | One order; hero lesson repeated in list |
| H4 | Fixed | 3-timetable/timetable.grid-next-week_secondary-light.png | Today button, ⋯ menu, subtitle |
| H5 | Partial | 3-timetable/timetable.grid-legend_secondary-light.png | Badge covers room ("JAZ", "Aul") |
| H6 | Fixed | 5-tasks/tasks_secondary-ax-xxxl-text.png | Inline form gone |
| H7 | Fixed | 5-tasks/tasks.overdue_secondary-light.png | Neutral rings, subject tile |
| H8 | Fixed | 4-editors/editor.lesson_secondary-light.png | Every Week / A / B segmented |
| H9 | Fixed | 7-settings/settings.reminder-health_secondary-light.png | No Time Sensitive; green summary |
| H10 | Fixed | 7-settings/settings.reminders_secondary-light.png | One row per kind |
| H11 | Fixed | 7-settings/settings_secondary-light.png | Subjects/Bell/Terms rows pushed |
| H12 | Fixed | 1-onboarding/onboarding.start_empty-light.png | 4 steps, no dead imports |
| H13 | Partial | 7-settings/settings.reminders_secondary-ax-xxxl-text.png | "Home-work"; times step overflows |
| H14 | Fixed | 3-timetable/timetable.quick-add_secondary-light.png | Opaque, "Every Monday · Week B" |
| H15 | Unverified | — (no exams.detail screenshot) | Code: ExamDetailView.swift:142 takenIt |
| M1 | Fixed | 4-editors/editor.timetable_secondary-light.png | No header/label echo |
| M2 | Fixed | 3-timetable/timetable.lesson-detail_secondary-light.png | Sentence-case headers, Title Case buttons |
| M3 | Fixed | 4-editors/editor.terms_secondary-light.png | Holidays; Week A/B glossary |
| M4 | Partial | 4-editors/editor.timetable_secondary-light.png | "weekdays and a day cycle" footer remains |
| M5 | Fixed | 4-editors/editor.day-change_secondary-light.png | Grey hint, Save disabled |
| M6 | Partial | 4-editors/editor.bell-period_secondary-light.png | Empty Name field has no prompt |
| M7 | Fixed | 5-tasks/tasks.detail_secondary-light.png | Standard X close |
| M8 | Fixed | 6-exams/exams_secondary-light.png | One room glyph everywhere |
| M9 | Fixed | 2-today/today_secondary-light.png | Time/room primary |
| M10 | Fixed | 2-today/today_secondary-light.png | "1 overdue task ›" row |
| M11 | Fixed | 3-timetable/timetable.week_university-light.png | Line above cards; but crosses text (D3) |
| M12 | Fixed | 3-timetable/timetable.day_secondary-light.png | Bold time line |
| M13 | Fixed | 3-timetable/timetable.tiles_elementary-light.png | No ✓, dim past, NOW; see D4 |
| M14 | Fixed | 3-timetable/timetable.grid_secondary-light.png | Empty slots plain |
| M15 | Fixed | 3-timetable/timetable.lesson-detail_secondary-light.png | "Cancel, Move or Substitute…" |
| M16 | Fixed | 4-editors/editor.timetable_secondary-light.png | Chips; order follows System week start |
| M17 | Fixed | 4-editors/editor.timetables_secondary-light.png | No Edit; Active grey |
| M18 | Unverified | — (no editor.subjects screenshot) | Not captured |
| M19 | Fixed | 4-editors/editor.terms_secondary-light.png | No inline ⊖; Holidays |
| M20 | Fixed | 4-editors/editor.day-change_secondary-light.png | New labels, date once |
| M21 | Partial | 5-tasks/tasks.editor_secondary-light.png | Editor still "Date ⌃⌄" over "Date" |
| M22 | Fixed | 5-tasks/tasks.detail_secondary-light.png | "Weekly on Tuesday" |
| M23 | Fixed | 5-tasks/tasks_secondary-light.png | One grouped background |
| M24 | Fixed | 6-exams/exams_university-light.png | Chevron inside, title first, banner |
| M25 | Fixed | 6-exams/exams.editor_secondary-light.png | When: During a lesson |
| M26 | Fixed | 7-settings/settings.colours_secondary-light.png | Swatches, Apply to All; no lock glyph |
| M27 | Fixed | 7-settings/settings.calendar_secondary-light.png | Advanced row |
| M28 | Fixed | 7-settings/settings.reminder-health_secondary-light.png | Open Settings button |
| M29 | Partial | 8-widgets-live-activities/widgets.gallery_secondary-light.png | Inline fixed; small still "Slovenský jazyk a li…" |
| M30 | Deferred-by-design | 8-widgets-live-activities/widgets.gallery-pro_secondary-light.png | Free/Pro split needs human |
| M31 | Partial | 8-widgets-live-activities/widgets.gallery-homework_secondary-light.png | Circles shown; intent flag unverifiable |
| L1 | Partial | 3-timetable/timetable.lesson-detail_secondary-light.png | "Thursday, October 15, 2026" still |
| L2 | Fixed | 2-today/today_secondary-light.png | navigationSubtitle |
| L3 | Fixed | 3-timetable/timetable.grid_secondary-light.png | Rows fill height |
| L4 | Partial | 7-settings/settings.about_secondary-light.png | Feedback + Privacy; no Rate |
| L5 | Not fixed | 3-timetable/timetable.tiles_elementary-light.png | Tab bar turns cyan |
| L6 | Not fixed | 3-timetable/timetable.grid_secondary-light.png | MAT still uses ÷ glyph |
| L7 | Fixed | 7-settings/settings.about_secondary-light.png | Acknowledgments, Colors |
| L8 | Partial | 3-timetable/timetable.grid-next-week_secondary-ax-xxxl-text.png | Title truncates with Today button |
| L9 | Fixed | 8-widgets-live-activities/widgets.gallery-evening_secondary-light.png | Done for today + ANJ 08:00 |
| L10 | Fixed | 8-widgets-live-activities/widgets.gallery-homework_secondary-light.png | Two tasks in small |
| R1 | Partial | 2-today/today.break_secondary-light.png | Hero lesson duplicated in list |
| R2 | Partial | 5-tasks/tasks.quick-add_secondary-light.png | Quick-entry sheet renders blank |
| R3 | Fixed | 7-settings/settings_secondary-light.png | Pushed rows |
| R4 | Fixed | 7-settings/settings.reminders_university-light.png | Summary rows, toggle in detail |
| R5 | Fixed | 1-onboarding/onboarding.week_empty-light.png | 4 steps |
| R6 | Fixed | 4-editors/editor.bell_secondary-light.png | Period rows + break rows |

### Astra review
| ID | status | evidence file | note |
|---|---|---|---|
| F01 | Partial | 1-onboarding/onboarding.times_empty-ax-xxxl-text.png | Overflows sideways; "Wednes…" chip |
| F02 | Fixed | 2-today/today_secondary-ax-xxxl-text.png | Teacher dropped at AX |
| F03 | Partial | 3-timetable/timetable.day_secondary-ax-xxxl-text.png | Full-width tiles; header pill shows year |
| F04 | Partial | 3-timetable/timetable.tiles_elementary-dark.png | Past tiles 1.9–2.5:1 |
| F05 | Partial | 4-editors/editor.lesson_secondary-light.png | Unlabelled "Always ⌃⌄" picker |
| F06 | Fixed | 4-editors/editor.lesson_secondary-light.png | "More details" row |
| F07 | Fixed | 1-onboarding/onboarding.week_empty-light.png | Repeat question + which-week anchor |
| F08 | Fixed | 1-onboarding/onboarding_empty-light.png | Step 1 of 4 |
| F09 | Fixed | 1-onboarding/onboarding.start_empty-light.png | Imports hidden |
| F10 | Fixed | 1-onboarding/onboarding.sample-banner_secondary-light.png | Default real setup; Remove banner |
| F11 | Partial | 1-onboarding/onboarding.times_empty-light.png | Renamed; values lack "min" unit |
| F12 | Fixed | 7-settings/reminders.permission_secondary-light.png | In-context explainer |
| F13 | Fixed | 1-onboarding/onboarding_empty-light.png | Product line, compact language row |
| F14 | Partial | 2-today/today_university-light.png | Next lesson in hero and list |
| F15 | Partial | 5-tasks/tasks.detail_secondary-light.png | Subtasks still "2/5" |
| F16 | Fixed | 2-today/today_elementary-light.png | Exam title first |
| F17 | Partial | 2-today/today_secondary-light.png | Lesson rows tinted like links |
| F18 | Fixed | 3-timetable/timetable.day_secondary-light.png | Larger subject/time |
| F19 | Partial | 3-timetable/timetable.day_secondary-light.png | Gutter label; line crosses text |
| F20 | Fixed | 3-timetable/timetable.grid-legend_secondary-light.png | ⋯ menu, legend, ⓘ day marker |
| F21 | Partial | 3-timetable/timetable.tiles_elementary-light.png | Tiles restrained; grid/day full fills |
| F22 | Fixed | 4-editors/editor.bell-period_secondary-light.png | Consistent 24 h under 24 h setting |

## 2. New visual defects (ranked)

### Critical
**D1. Tasks "+" quick-entry sheet is blank.** Evidence: `5-tasks/tasks.quick-add_secondary-light.png` (dark and AX are blank too).
- *Likely cause:* in `App/Sources/Tasks/TaskQuickEntrySheet.swift:27-56` the body is `Group { if let initial { EditorScaffold… } }.onAppear { initial = initialDraft() }`. `Group` is transparent, so `.onAppear` attaches to its children. While `initial` is nil there are no children, so `onAppear` never fires and the sheet stays empty.
- *Fix:* build the draft in `init` with `State(initialValue:)`, or attach `.onAppear`/`.task` to a real container (for example `ZStack { … }` or a `Color.clear` placeholder).
- *Verify on device:* the screenshot is consistent with this cause, but a capture-timing artifact is not ruled out.

### High
**D2. Onboarding step 4 overflows sideways at AX-XXXL.** Evidence: `1-onboarding/onboarding.times_empty-ax-xxxl-text.png`; milder in `onboarding.times-individual_empty-ax-xxxl-text.png`. Title, cards and the button are clipped on both edges.
- *Likely cause:* a row HStack of label + fixed-width minute `TextField` + `Stepper` has an ideal width wider than the screen, and the scroll content adopts it.
- *Fix:* use `AdaptiveStack` rows at accessibility sizes (label above, field and stepper below), remove fixed widths, and add `.frame(maxWidth: .infinity)`.

**D3. The day-view now line strikes through the current lesson text.** Evidence: `3-timetable/timetable.day_secondary-light.png` (and dark): "10:00–10:45 · 214" is unreadable. Also on the week view (Mon LA block).
- *Likely cause:* the line overlay is drawn above the cards across the full width.
- *Fix:* draw the full line only in the gutter and free columns. Over a card, use a short leading stub or a knockout so the line never crosses text (F19 acceptance).

**D4. Past (dimmed) tiles fail contrast.** Evidence: `3-timetable/timetable.tiles_elementary-dark.png`. Measured text on tile: dark SJL **1.88:1**, dark MAT **2.52:1**, light SJL **4.11:1**. Time and room are body text, so 4.5:1 applies.
- *Likely cause:* `.opacity(~0.6)` is applied to the whole tile, text included.
- *Fix:* dim only the fill, or use a desaturated fill token, and keep the text on its tested on-fill colour. Add contrast tests.

**D5. Today lesson and exam rows render in ink link tint.** This covers the times, names, room glyphs, the "Room changed"/"Canceled" badge text and the struck-through name. Evidence: `2-today/today_secondary-light.png`, `today_elementary-light.png`, `today.holiday_secondary-light.png`.
- *Cause:* `Button { actions.openLesson } label: { TodayLessonRow }` in a `List` takes the accent tint (`App/Sources/Today/TodayRootView.swift:198`; the exam row at :156).
- *Fix:* add `.foregroundStyle(.primary)` (secondary for metadata) on the row label, or use `.buttonStyle(.plain)` plus `.contentShape(.rect)`. Keep the badge colours explicit.
- *HIG:* `color.md` › "Avoid using the same color to mean different things"; ink means action (D1).

**D6. Grid badges cover the room line.** Evidence: `3-timetable/timetable.grid-legend_secondary-light.png` shows "JAZ", "Aul", "Lab FY", "Telocvič"; `timetable.grid_secondary-light.png` shows ANJ Wed P1, MAT Thu P2 and NEJ Tue P5. This breaks H5 "room always".
- *Likely cause:* the badge is a `.overlay(alignment: .bottomTrailing)` over centred line 2, with no reserved space.
- *Fix:* reserve a trailing inset on the room line when a badge is present, or move the badge to the top-trailing corner.

### Medium
**D7. Word-internal breaks at AX-XXXL in icon list rows.** Examples: "Gymnázi-um" (`7-settings/settings_secondary-ax-xxxl-text.png`, `4-editors/editor.timetables_secondary-ax-xxxl-text.png`), "Home-work" and "Assign-ments" (`settings.reminders_secondary-ax-xxxl-text.png`), "Notifica-tions" (`settings.reminder-health_secondary-ax-xxxl-text.png`).
- *Cause:* the icon column keeps the title column narrow, and the U1 `AdaptiveStack` is not used in these rows.
- *Fix:* stack the icon above the title at accessibility sizes (`typography.md` › "Consider adjusting your layout at large font sizes").

**D8. Before school and in a break, the hero lesson is also the first "Rest of today" row.** The "Next" lesson in the hero is likewise always repeated as list row 1. Evidence: `2-today/today.before-school_secondary-light.png`, `today.break_secondary-light.png`, `today_university-light.png`.
- *Fix:* exclude the hero lesson from `remainingItems`, and drop either the hero "Next" line or the duplicate row.

**D9. Unlabelled standalone pickers.** The lesson editor shows "Always ⌃⌄" alone in a section (`4-editors/editor.lesson_secondary-light.png`). The task editor Due section shows "Date ⌃⌄" above a "Date" row (`5-tasks/tasks.editor_secondary-light.png`), so M21 persists.
- *Cause:* `.labelsHidden()` with no section header.
- *Fix:* give each a visible label ("Applies", "Due") via the `Picker` title or `LabeledContent`.

**D10. Weekday chips truncate at AX: "Wednes…".** Evidence: `4-editors/editor.timetable_secondary-ax-xxxl-text.png`, `1-onboarding/onboarding.week_empty-ax-xxxl-text.png`.
- *Fix:* use abbreviated symbols, or one chip per row, at accessibility sizes.

**D11. Exam relative time sits on its own outdented line.** "in 9 days" and "Yesterday" break the icon column. Evidence: `6-exams/exams_secondary-light.png`, `exams.history_secondary-light.png`, `exams_secondary_de-light.png`.
- *Fix:* put date and relative time in one `Label` title ("Thu, Oct 22 · in 9 days").

**D12. Picker values are middle-truncated at AX** ("Sl...eratúra", "Neme...jazyk"). Evidence: `4-editors/editor.lesson_secondary-ax-xxxl-text.png`, `5-tasks/tasks.editor_secondary-ax-xxxl-text.png`.
- *Fix:* use `.pickerStyle(.navigationLink)` at accessibility sizes.

**D13. Next-week title truncates.** "Gymnázium –…" at default size; at AX the subtitle loses the week ("Oct 19 – Oct 23 ·…"). Evidence: `3-timetable/timetable.grid-next-week_secondary-light.png`.
- *Fix:* fold Today into the ⋯ menu, or shrink the prev/next group.

**D14. The legend tip truncates at AX** ("Symbols in t…", "Substitute te…"). Evidence: `3-timetable/timetable.grid-legend_secondary-ax-xxxl-text.png`.
- *Fix:* allow multi-line title and rows.

**D15. The current year still shows in dates.** Examples: lesson detail "Thursday, October 15, 2026", AX agenda headers "Monday, October 12, 2026", the AX day pill "Oct 13, 2026", and task row "Oct 21, 2026". Evidence: `3-timetable/timetable.grid_secondary-ax-xxxl-text.png`, `5-tasks/tasks.completed_secondary-light.png`.
- *Fix:* route these through the shared year-omitting formatter (L1).

### Low
- **D16.** Liquid Glass tab bar tinted by saturated tiles (`timetable.tiles_elementary-light.png`, `timetable.day_secondary-ax-xxxl-text.png`). Fix: add a bottom content margin.
- **D17.** Onboarding times: the minute fields have no "min" unit. "Break after lesson 2" wraps to 3 lines because of the wide field. "Lessons per day" has no field, which is inconsistent (`onboarding.times_empty-light.png`).
- **D18.** The disabled "Continue" on Welcome is nearly invisible in light (`onboarding_empty-light.png`).
- **D19.** Widgets: the progress bar uses the subject red (H3 point 5 is still open there), and the small widget shows a truncated full name instead of the short name (`widgets.gallery_secondary-light.png`).
- **D20.** In dark, the first Ocean swatches are invisible on the card, and Pro palettes have no lock glyph (`settings.colours_secondary-dark.png`).
- **D21.** At AX, the hero "NOW until / 10:45" wraps awkwardly (`today_secondary-ax-xxxl-text.png`), and the About "↗" glyphs sit alone on a line (`settings.about_secondary-ax-xxxl-text.png`).
- **D22.** The exam-period banner is inset narrower than the cards and has low separation in dark (`exams_university-dark.png`).
- **D23.** On the holiday Today, the "Due today" header holds only the overdue row (`today.holiday_secondary-light.png`).
- **D24.** Single-line title fields truncate at AX ("Gymnázium –…", "Písomka – org…", "1. polrok 2026…"). Fix: `axis: .vertical`.

Slovak (`tasks_secondary_sk`, `onboarding.school-type_empty_sk`, `widgets.gallery_secondary_sk`) and German (`exams_secondary_de`) show no truncation beyond the defects listed above.

## 3. Watch
**Not verified.** The README lists `watch-Apple_Watch_Series_12__46mm_.png` as unrecognised, but the file is not in the repo. `9-other/` holds only `debug.design_*`. Re-download the CI artifact to check it.
