# Tabula: UI/UX review and fix list

**Reviewed:** 23 Oct 2026 · **Build in screenshots:** 0.1.0 (1), iOS 26, iPhone Pro Max simulator
**Scope:** `README.md` + all 185 screenshots in `screens/` (light, dark, AX-XXXL; en, sk, de). No source code, so fixes are SwiftUI *hints*, not file:line patches.
**Method:** Apple HIG (June–Oct 2026 pages) through five lenses: accessibility → platform conventions → visual craft → interaction → writing. Contrast ratios were **measured from screenshot pixels** (WCAG formula), not estimated.
**Priorities agreed with you:** elementary, secondary and university users get **equal weight**; fixes + a light visual identity; **full redesigns only where a screen is unintuitive** (section 8).

### Severity legend

| Tag | Meaning |
|---|---|
| **Critical** | Broken, inaccessible, or so confusing people get lost. Fix before anything else. |
| **High** | Real friction: wrong/misleading element, inconsistency people notice, poor readability. |
| **Medium** | Sub-optimal pattern, redundancy, missed system component. |
| **Low** | Polish. |

Every finding has an ID (`C1`, `H4`, `M12`, `L3`) so you can reference it in commits and issues. Screenshot links open the exact evidence.

---

## Contents

1. [Summary](#1-summary)
2. [Top 10 quick wins](#2-top-10-quick-wins)
3. [What works, keep it](#3-what-works-keep-it)
4. [Critical](#4-critical)
5. [High](#5-high)
6. [Medium, by area](#6-medium-by-area)
7. [Low / polish](#7-low--polish)
8. [Redesign proposals (R1–R6)](#8-redesign-proposals)
9. [Light visual identity: "Exercise book"](#9-light-visual-identity-exercise-book)
10. [Copy, terminology and capitalisation](#10-copy-terminology-and-capitalisation)
11. [Prioritised fix plan](#11-prioritised-fix-plan)
12. [Open questions and what I could not verify](#12-open-questions-and-what-i-could-not-verify)
13. [Appendix: measured contrast, HIG pages cited](#13-appendix)

---

## 1. Summary

**Overall rating: Critical issues, on a solid foundation.**

Tabula already does several hard things right. It uses standard SwiftUI controls throughout and adapts the week grid into an agenda list at the largest text size. Text on subject colours auto-switches black/white and measures **4.9–15:1**. It translates cleanly (German fits) and asks for notification permission in context. The problems are not "bad engineering". They are what happens when every screen was built correctly in isolation and nobody owned the whole flow. They fall into five themes:

| Theme | Typical examples |
|---|---|
| **Broken / dead elements** | Bell-schedule toolbar shows `Edit Edit Edit Edit •••` (C1). "Time Sensitive" can be chosen but "is not available in this version" (H9). "Coming soon" options in onboarding. Lock Screen widgets that only say "Available in Tabula Pro". |
| **Redundancy** | 4-row inline "New task" form *and* a `+` button (H6). A reminder toggle on the list *and* inside the detail page. Section header that repeats the row label (`Rotation / Rotation`, `Applies / Applies`…). Current lesson shown twice on Today. |
| **Unclear meaning** | Unlabelled view-switcher icon that changes glyph per view (H4). "25:00" time left reads like a clock time (H2). Week A/B toggles where *both off = every week* (H8). Three rows all called "Times and delivery". |
| **Inconsistency** | 12-hour pickers next to 24-hour text on the same screen (H1). Done vs Close. Edit vs Reorder. Custom chips (Tasks) vs segmented control (Exams). Door icon vs map-pin icon for "room". Mixed capitalisation. |
| **Size & hierarchy** | The exam countdown is the biggest text on Today, bigger than the lesson you're in (H3). Lesson time on Day cards is the smallest text. Task filter chips are ~52 pt tall. Onboarding at AX-XXXL leaves one option visible per screen (H13). |

**Thesis of the app (as it should be):** *"Where do I need to be, what do I need to bring, and what's due?"* Today the UI answers this, but it shouts everything at the same volume. **Point of view:** none yet beyond the colourful week grid, which is the one memorable thing. Section 9 proposes a small identity rooted in school materials (ink blue, red correction pen, highlighter) that stays 100% native.

---

## 2. Top 10 quick wins

Highest impact for least effort. Do these first.

| # | Fix | ID | Effort |
|---|---|---|---|
| 1 | Fix the bell-schedule toolbar (one toolbar, title, Cancel/Save) | C1 | S |
| 2 | Fix the 5 measured contrast failures (Pro badge 1.9:1, "Open language settings" 2.2:1, Tasks chips 2.9:1, yellow checkbox 1.7:1, empty-slot outlines 1.7–2.2:1) | C2 | S |
| 3 | Make the selected Tasks filter always visible (or replace chips with grouped list, R2) | C3 | S |
| 4 | Apply the app's 24-hour setting to every `DatePicker` | H1 | S |
| 5 | Hide "Time Sensitive" until it works; stop the permanent "Some things need a look" warning | H9 | S |
| 6 | Replace "25:00" with "25 min left · ends 10:45" | H2 | S |
| 7 | Replace Week A/B toggles with "Every week / Week A / Week B" | H8 | S |
| 8 | Neutral task checkboxes; subject colour moves to a dot/tile | H7 | S |
| 9 | Remove duplicated header/label pairs across editors | M1 | S |
| 10 | Label the timetable view switcher and add "Today" | H4 | S |

---

## 3. What works, keep it

Be careful not to lose these in the next iteration.

- **AX-XXXL adaptation of the grid.** At the largest size the 5-column grid becomes a day-by-day agenda instead of unreadable cells ([grid AX](screens/3-timetable/timetable.grid_secondary-ax-xxxl-text.png)). This is exactly what `typography.md › Consider adjusting your layout at large font sizes` asks for.
- **Automatic text colour on subject colours.** Measured: black on teal `#00897B` 4.86:1, black on red `#E53935` 4.97:1, white on purple `#8E24AA` 7.04:1, black on yellow 15:1. All pass. Light colours (yellow) automatically get an outline. Keep the algorithm; just stop *showing* its numbers to students (M4).
- **Permission priming** ([explainer](screens/7-settings/reminders.permission_secondary-light.png)). It's asked in context, honest, says "No ads, nothing else", and has a clear prominent "Allow Notifications" plus "Not Now". Textbook.
- **Onboarding step 4 "Lesson times"** generator with live **Preview** ([time](screens/1-onboarding/onboarding.time_empty-light.png)). It works the way students think ("lessons are 45 min, 8 per day, long break after 2nd").
- **Lesson detail → "Changes on this day" → "Usually 08:00–08:45"** ([detail](screens/3-timetable/timetable.lesson-detail_secondary-light.png)). Showing the *usual* value next to the changed one is excellent.
- **Break separators** ("🚶 Break · 10 min") between lessons in Tiles/Today list. Glanceable and friendly.
- **Exams use a real segmented control** (Upcoming / History). Correct component; Tasks should follow (C3).
- **Widgets: Today medium/large** ([today widget](screens/8-widgets-live-activities/widgets.gallery-today_secondary-light.png)). Past lessons dimmed, current row highlighted with a bar, "+1 more". Very glanceable.
- **Holiday state** in widgets (umbrella, holiday name, next lesson after the break). Thoughtful.
- **Save stays disabled until required fields are filled** (New Lesson/Task/Exam), with a hint. Right pattern; only the hint placement needs work (M6).
- **Translations fit**: German "Einstellungen" and "Nächste Prüfung" don't truncate; Slovak settings wrap gracefully.

---

## 4. Critical

### C1 · Bell-schedule editor toolbar is broken (wrong buttons)
**Where:** [bell light](screens/4-editors/editor.bell_secondary-light.png), [bell AX](screens/4-editors/editor.bell_secondary-ax-xxxl-text.png)
**What:** The top bar shows **Cancel · Edit · Edit · Edit · Edit · •••** and no title and no Save. People can't tell which "Edit" does what or how to save. This is a bug, not a design choice. Almost certainly a `.toolbar {}` (or `EditButton()`) attached *inside* a `ForEach`/`Section`, so every period or variant contributes its own toolbar item and the overflow collapses the rest into `•••`.
**Why:** `toolbars.md › Make sure the meaning of each control is clear`: *"Don't make people guess or experiment to figure out what a toolbar item does."*
**Fix (SwiftUI):**
- Attach exactly one `.toolbar` to the root view of the sheet, never inside rows/sections.
- Match every other editor: `ToolbarItem(placement: .cancellationAction) { Button("Cancel") }`, `ToolbarItem(placement: .confirmationAction) { Button("Save") }`, `.navigationTitle("Bell Schedule")`.
- If reordering periods is needed, use a single `EditButton()` *or* drag handles via `.onMove`, not one per section.
- Then restructure the screen (R6).

### C2 · Text and control contrast failures (measured)
**What:** Five elements fail WCAG/HIG minimums (pixel-measured; full table in section 13):

| Element | Screen | Colours | Ratio | Needs |
|---|---|---|---|---|
| "Pro" badge next to palettes | [Appearance](screens/7-settings/settings.appearance_secondary-light.png) | `#7FC3FF` on white | **1.88:1** | 4.5:1 |
| "Open language settings" button | [Welcome](screens/1-onboarding/onboarding_empty-light.png) | `#0088FF` on grey capsule `#CDCDCF` | **2.22:1** | 4.5:1 |
| Unselected Tasks chips ("Upcoming (4)") | [Tasks](screens/5-tasks/tasks_secondary-light.png) | `#0088FF` on `#E9E9EB` | **2.90:1** | 4.5:1 |
| Yellow subject checkbox ring | [Upcoming](screens/5-tasks/tasks.upcoming_secondary-light.png) | ring vs white | **1.74:1** | 3:1 (non-text) |
| Dashed "+" empty-slot cells (interactive) | [Grid](screens/3-timetable/timetable.grid_secondary-light.png) | `#ADADB0`/`#C7C7CC` on white | **1.7–2.2:1** | 3:1 (non-text) |

**Why:** `accessibility.md › Contrast`: text "Up to 17 pts → 4.5:1". `color.md`: *"Avoid using the same color to mean different things."* Light blue reads as "link", so a light-blue "Pro" looks tappable *and* is unreadable.
**Fix (SwiftUI):**
- Pro badge: `Text("Pro").font(.caption.weight(.semibold)).padding(.horizontal, 6).background(.quaternary, in: Capsule())` with `.foregroundStyle(.secondary)` (5.2:1). Or use the Ink accent from section 9 (8.5:1).
- "Open language settings": use `.buttonStyle(.bordered)` *on a white card* or a plain `Link` row. Never tinted text on a grey fill.
- Tasks chips: replace with `Picker(...).pickerStyle(.segmented)` or the grouped list in R2. If you keep chips, unselected text must be `.primary`.
- Checkboxes: see H7. Neutral ring `Color(.secondaryLabel)` ≈ 5.2:1.
- Empty slots: see M14. Either no outline (tap target stays) or `Color(.tertiaryLabel)` solid 1-pt stroke **plus** the `+` glyph in `.secondary`.

### C3 · Tasks: the active filter can be invisible ("where am I?")
**Where:** [Completed](screens/5-tasks/tasks.completed_secondary-light.png), [Tasks AX](screens/5-tasks/tasks_secondary-ax-xxxl-text.png)
**What:** The four filters are a horizontally scrolling chip row. The 4th, "Completed", sits **off-screen**, so when it's selected *none of the visible chips look selected*. You see a list of struck-through tasks with no indication of which list this is. At AX-XXXL only one and a half chips fit. The unselected "Overdue" chip is also permanently pink/red, louder than the selected chip, so it competes for attention even when you didn't pick it.
**Why:** `segmented-controls.md › Limit the number of segments`: *"no more than about five segments on iPhone"*. A system segmented control would show all four. `tab-bars.md` spirit: the current location must always be visible.
**Fix:** Preferred: drop filters and use **one grouped list** (Overdue → Today → Tomorrow → This week → Later, completed behind a "Show completed" toggle). See **R2**. Minimum fix: `Picker("Show", selection: $filter) { … }.pickerStyle(.segmented)` with short labels (Today · Upcoming · Overdue · Done). Show counts in section headers, not in the segment titles, so German/Slovak fit.

---

## 5. High

### H1 · 12-hour pickers next to 24-hour text
**Where:** [onboarding time](screens/1-onboarding/onboarding.time_empty-light.png) (8:00 AM vs preview), [bell](screens/4-editors/editor.bell_secondary-light.png), [exam editor](screens/6-exams/exams.editor_secondary-light.png), and most visibly [reminder rule](screens/7-settings/settings.reminder-rule_secondary-light.png): "1 day before, **at 17:00**" and "Next morning at **7:00 AM**" on the *same screen*.
**What:** Settings › Calendar & time says **Time format: 24-hour** ([calendar](screens/7-settings/settings.calendar_secondary-light.png)). Your own formatted text obeys it; system `DatePicker`s follow the device locale (en-US → 12 h). Students copying times from a paper timetable will mistype.
**Fix (SwiftUI):** build one locale with the chosen hour cycle and inject it at the app root:
```swift
var comps = Locale.Components(locale: .current)
comps.hourCycle = use24h ? .zeroToTwentyThree : .oneToTwelve
let timeLocale = Locale(components: comps)
// RootView().environment(\.locale, timeLocale)
```
Also consider defaulting **Time format** to *System* (iOS already has Settings › General › Date & Time › 24-Hour Time). `settings.md`: *"Minimize the number of settings you offer."*

### H2 · "25:00 Time left" is ambiguous
**Where:** [Today](screens/2-today/today_secondary-light.png), widgets ("Starts in 2:00", "1:30:00"), [Live Activity](screens/8-widgets-live-activities/widgets.gallery-live_secondary-light.png)
**What:** At 10:20 in the morning, "25:00" reads as a clock time (or mm:ss); "2:00" could be 2 minutes, 2 hours or 2 o'clock. Ticking seconds ("1:30:00" before an exam) add stress without adding information.
**Fix:**
- In the app: **"25 min left · ends 10:45"**. Use `TimelineView(.everyMinute)` + `Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))`, with `.monospacedDigit()`.
- In Live Activities keep the live `Text(timerInterval:countsDown:)` (it's the system idiom there), but always pair it with a unit label ("left", "until start") and switch to minutes-only above 60 min ("in 1 h 30 min").
- Exams: never show seconds; "Today 10:00 · in 1 h 30 min".

### H3 · Today: wrong hierarchy, duplicated lesson, order varies by profile
**Where:** [secondary](screens/2-today/today_secondary-light.png), [elementary](screens/2-today/today_elementary-light.png), [university](screens/2-today/today_university-light.png)
**What:**
1. **"in 9 days" is the largest text on the screen** (~34 pt bold), larger than the lesson you're sitting in. Today's job is *now/next*. The exam is context.
2. **Current lesson shown twice** on university and elementary: in the Now card *and* as a highlighted card in the day list right below.
3. **Section order changes by profile and data**: elementary is Now → Exam → Day; secondary is Now → Due → Exam → …; university is Now → Day. Users switching schools (or helping a sibling) relearn the screen.
4. "Next Exam" card style changes by profile: grey + outline vs blue tint.
5. The red "Now" badge with a dot looks like a *recording/live* indicator and shares red with errors/overdue. The progress bar takes the subject colour, so a red subject's progress bar reads as an alarm.
6. "1 overdue" is a tinted capsule floating at the right of "Due today". It's unclear whether it's tappable.

**Fix:** see **R1** (full redesign proposal).

### H4 · Timetable toolbar: mystery icon, no "Today", no edit entry
**Where:** [grid](screens/3-timetable/timetable.grid_secondary-light.png), [week](screens/3-timetable/timetable.week_university-light.png), [day](screens/3-timetable/timetable.day_secondary-light.png), [tiles](screens/3-timetable/timetable.tiles_elementary-light.png)
**What:**
- The only toolbar button is an unlabelled icon whose glyph **changes with the current view** (3×3 grid / list / two rows). People can't predict what it does: does it show the current view or the next one?
- No **Today** button: after swiping to another week there's no one-tap way back.
- No way to **edit the timetable** from the Timetable tab itself. Editing is buried in Settings (see H11).
- "Week B" is a tinted capsule with a border that looks like a button. Is it one?

**Why:** `toolbars.md › Make sure the meaning of each control is clear`. `pull-down-buttons.md`: a pull-down presents *"commands or items that are directly related to the button's action."*
**Fix (SwiftUI):**
```swift
.toolbar {
  ToolbarItem(placement: .topBarLeading) {
    if !isCurrentWeek { Button("Today") { jumpToToday() } }
  }
  ToolbarItem(placement: .topBarTrailing) {
    Menu {
      Picker("View", selection: $viewMode) {
        Label("Grid", systemImage: "square.grid.3x3").tag(ViewMode.grid)
        Label("Week", systemImage: "calendar.day.timeline.left").tag(ViewMode.week)
        Label("Day", systemImage: "list.bullet.rectangle").tag(ViewMode.day)
        Label("Tiles", systemImage: "rectangle.grid.1x2").tag(ViewMode.tiles)
      }
      Divider()
      Button("Edit Timetable", systemImage: "pencil") { … }
      Button("Add Lesson", systemImage: "plus") { … }
    } label: { Label("View options", systemImage: "ellipsis") }   // one stable glyph
  }
}
```
Make "Week B" plain secondary text (or a real button that explains the rotation, but then style it as one).

### H5 · Grid cells: room disappears, markers unexplained, no "now"
**Where:** [grid](screens/3-timetable/timetable.grid_secondary-light.png), [grid dark](screens/3-timetable/timetable.grid_secondary-dark.png)
**What:**
- **The room line is replaced** by the task badge ("≡ 1") or the exam cap. MAT Thu P2 and ANJ Wed P1 show tasks *instead of* the room, so on the days you have homework you lose where to go.
- **Change markers** are 14 pt circles in a corner (↻ changed, ⊗ cancelled, ⊕ extra) with no legend. ↻ (`arrow.triangle.2.circlepath`) means *sync/repeat* elsewhere in iOS and in this app (task repeat icon). The **orange dot under THU 15** has no explanation.
- **Cancelled lessons stay full-colour** (ANJ Thu P4 only has strikethrough), so they still look like a lesson you attend.
- **No "now" in the grid**: at 10:20 on Tue the current cell (SJL P3) looks like every other cell. The Day/Week views show only a red dot (M11).

**Fix:**
- Fixed cell anatomy: line 1 = short name, line 2 = **room (always)**, bottom-right = **one** badge slot with priority exam > task > change. Use `ViewThatFits` to drop the emoji first when space is tight.
- Cancelled: `opacity(0.35)` + diagonal hatch or `.strikethrough` + `xmark` badge; VoiceOver label "Cancelled".
- Distinct symbols per meaning: time changed `clock.badge.exclamationmark`, room changed `arrow.right.square`, substitute `person.2.badge.gearshape` (or `person.fill.questionmark`), cancelled `xmark.circle.fill`, extra `plus.circle.fill`. Use the **same** symbol in the grid, lesson-detail badge and Today list (M8).
- Day-header dot: replace with a small symbol (e.g. `exclamationmark.circle`) and an accessibility label "Changes on Thursday". Or drop it and rely on the cell badges.
- Current period: highlighter outline/marker on the cell (section 9) and the column header of today tinted.
- Add a one-time **legend** (`.popoverTip` from TipKit) the first time a change marker appears.

### H6 · Tasks: a permanent 4-row "New task" form duplicates the `+` button
**Where:** [Tasks](screens/5-tasks/tasks_secondary-light.png), [AX](screens/5-tasks/tasks_secondary-ax-xxxl-text.png)
**What:** Every filter (except Completed) starts with a form card: New task / Subject / Due / Add. It takes ~25% of the screen at default size and **100% at AX-XXXL**, so no tasks are visible at all. "New task" is drawn in **pure black `#000000`** (measured), so it reads as a heading, not a placeholder. Meanwhile the toolbar `+` opens the full editor. That's two ways to do one thing, and the inline one is the worse one.
**Fix:** remove the inline form. Make `+` open a short **quick-entry sheet** with the title field focused and smart defaults (subject = next lesson's subject, due = next lesson). See **R2**.

### H7 · Subject colour on task checkboxes collides with status colours
**Where:** [Upcoming](screens/5-tasks/tasks.upcoming_secondary-light.png), [Overdue](screens/5-tasks/tasks.overdue_secondary-light.png), [Completed](screens/5-tasks/tasks.completed_secondary-light.png)
**What:** The checkbox ring takes the subject colour: **red** for Slovak (looks overdue), **green** for Physics *next to* "1 day overdue" (green = done?), **yellow** at 1.74:1 (invisible), **brown** (looks disabled). Completed checkmarks are black on teal/blue fills.
**Why:** `color.md`: *"Avoid using the same color to mean different things."* `toggles.md`: *"Avoid relying solely on different colors to communicate state."*
**Fix:** checkbox = neutral `Image(systemName: done ? "checkmark.circle.fill" : "circle")` with `.foregroundStyle(done ? .tint : .secondary)`. Show the subject as the small emoji tile you already use in widgets (Homework widget does this well) or a 4-pt leading colour bar. Status colours (red = overdue only) then stay unambiguous.

### H8 · Week A/B toggles: "none selected = every week"
**Where:** [Edit lesson](screens/4-editors/editor.lesson_secondary-light.png), [New lesson](screens/4-editors/editor.lesson-new_secondary-light.png)
**What:** Two switches, A and B, both **off** for a lesson that happens every week, explained by a footer: "If no week is selected, the lesson takes place every week." This inverts everyone's mental model: off means *no*. Turning both on (the intuitive "every week") presumably also works, so two states mean the same thing.
**Fix:** `Picker("Weeks", selection: $weeks) { Text("Every week"); Text("Week A"); Text("Week B") }.pickerStyle(.segmented)`. For N-week cycles use a multi-select list with **"Every week" as the first, default-checked row**. Delete the footer.

### H9 · "Time Sensitive" can be chosen but doesn't exist; permanent false warning
**Where:** [Onboarding reminders](screens/1-onboarding/onboarding.reminders_empty-light.png), [Reminder rule](screens/7-settings/settings.reminder-rule_secondary-light.png), [Reminder Check](screens/7-settings/settings.reminder-health_secondary-light.png), [Reminders](screens/7-settings/settings.reminders_secondary-light.png)
**What:** Users can select **Time Sensitive** delivery. The health check then reports *"Not available in this version of the app: Time Sensitive reminders arrive like normal ones"*. Because that row is a ⚠ "Check", the summary is **always** "Some things need a look", and the Reminders screen always shows a warning triangle. Nothing the user does can clear it. That trains people to ignore the one warning that might matter (permissions off).
**Fix:** hide the Time Sensitive tier (or show it disabled with "Coming later") until the entitlement ships. Exclude *app-side* limitations from the health summary. Only user-fixable problems should produce a warning.

### H10 · Reminders settings: duplicated toggles and identical row labels
**Where:** [Reminders](screens/7-settings/settings.reminders_secondary-light.png), [Homework rule](screens/7-settings/settings.reminder-rule_secondary-light.png)
**What:**
- Each kind has a toggle row **plus** a separate "Times and delivery ›" row under it. The detail page has *another* "Remind me" toggle for the same setting.
- "Times and delivery" appears **three times**. VoiceOver reads three identical buttons; sighted users have to look up to see which kind it belongs to.
- Rows appear and disappear when toggled (Assignments has no "Times and delivery" row while off), so the list jumps.
- Settings root calls this screen "How reminders are delivered"; the screen is titled "Reminders".

**Fix:** one row per kind, Apple-Settings style: `Homework · 1 day before, 17:00 ›` / `Assignments · Off ›`. The toggle lives only in the detail. See **R4**.

### H11 · Settings structure: one-row sections, buried editors, stacked sheets
**Where:** [Settings](screens/7-settings/settings_secondary-light.png), [Timetables](screens/4-editors/editor.timetables_secondary-light.png), [Subjects](screens/4-editors/editor.subjects_secondary-light.png)
**What:**
- Six sections, each holding **one row** whose section header repeats it ("Calendar & time" → "Week start, time format, time zone"). It's a long scroll for six items.
- "Manage timetables" is **blue text without a chevron** (looks like an action) but navigates; siblings are black with chevrons.
- **Subjects, Bell schedule, Terms** aren't visible at top level. They're reachable only through Manage timetables → timetable → … The editors are all sheets, so you end up with sheet-on-sheet-on-sheet. `modality.md`: *"Let people dismiss a modal view before presenting another one."*
- "Lessons are called: Lesson" shows no chevron or picker indicator; it looks like static text.

**Fix:** see **R3**. Push with `NavigationLink` inside the Settings `NavigationStack`, and give Subjects / Bell schedule / Terms their own rows.

### H12 · Onboarding: too long, risky default, dead options
**Where:** all [onboarding](screens/1-onboarding/) screens
**What:**
- **7 steps** before you see the app. Step 1 is nearly empty: a small icon and a language card that only links to iOS Settings.
- **Step 7 preselects "Use sample data"**. A student who just configured 6 steps for *their* school can tap "Get started" and land in a fake Slovak timetable. If sample data overrides their answers, the previous six steps were wasted (open question Q2).
- Two **"Coming soon"** rows (Import from photo / QR) are dead ends on the most important decision screen.
- **Fields** step offers "Building / faculty" and "Type (lecture, seminar, lab)" to a secondary pupil. Copy: "Hidden details disappear everywhere, including the editor."
- **Reminders** step adds three long cards about delivery tiers that *look* selectable (card style = choice style on every previous step) but are just explanations.
- "Different per semester" is listed as a *rotation* type but it's about dates, not a weekly rotation. Term dates also appear as a separate toggle on the same step.

**Why:** `onboarding.md`: *"design a flow that's fast, fun, and optional"* and *"doesn't require people to memorize a lot of information."*
**Fix:** see **R5** (4 steps, sample data as an explicit "Just look around" path, no dead options).

### H13 · Largest text size (AX-XXXL): layouts that stop working
**Where:** [profile AX](screens/1-onboarding/onboarding.profile_empty-ax-xxxl-text.png), [Today AX](screens/2-today/today_secondary-ax-xxxl-text.png), [Exams AX](screens/6-exams/exams_secondary-ax-xxxl-text.png), [Tasks AX](screens/5-tasks/tasks_secondary-ax-xxxl-text.png)
**What:**
- Onboarding: the fixed bottom bar with side-by-side Back/Next takes ~17% of the height. Header + subtitle fill the first screen. The icon column forces "Elemen-tary" hyphenation; less than one option is visible.
- Exams: the subject emoji tile scales to ~170 pt. The hero card's chevron sits **outside** the card.
- Today: "Now" pill + title + icon column fill the screen before the time left appears.
- Tasks: see H6, the form fills the screen.

**Why:** `typography.md › Consider adjusting your layout at large font sizes`: *"consider using a stacked layout where text appears above secondary items."*
**Fix (SwiftUI):**
```swift
@Environment(\.dynamicTypeSize) private var size
let layout = size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
layout { icon; texts }
```
- Cap decorative icons: `@ScaledMetric(relativeTo: .title) var tile: CGFloat = 44` then `.frame(width: min(tile, 64))`, or `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` on the icon only.
- Onboarding: Back → standard toolbar back chevron (also fixes M7). The bottom bar keeps one full-width button in `.safeAreaInset(edge: .bottom)`.

### H14 · "Add Lesson" quick-add: see-through sheet, ambiguous scope
**Where:** [quick add](screens/3-timetable/timetable.quick-add_secondary-light.png)
**What:**
- The glass sheet is so transparent that the **colourful grid bleeds through behind the subject list**: pink, blue, green blobs behind text. The grey header text ("Monday, October 12, 2026 / Period 7 · 13:40–14:25") sits on that blur.
- The header names a **specific date** (a past Monday), yet the action adds a timetable slot. Does it create *every Monday (Week B)* or *only 12 Oct*? Students will be unsure whether they just changed their whole year.

**Fix:** `.presentationBackground(Color(.systemGroupedBackground))` (or present at `.large` detent where the sheet is opaque). Header: **"Every Monday · Week B · Period 7 (13:40–14:25)"**, or "Only Mon 12 Oct" if it's a one-off, with a toggle between the two if both are possible.

### H15 · Exam detail: "Mark Done" means what?
**Where:** [exam detail](screens/6-exams/exams.detail_secondary-light.png)
**What:** A full-width "Mark Done" on an exam that's **in 9 days**. Done studying? Exam taken? Delete? It moves the exam to History, presumably, but nothing says so.
**Fix:** rename to **"Move to History"**, or better **"I've Taken This Exam"**, shown only on or after the exam date. Optional: offer to record a grade (History becomes useful; students love tracking grades).

---

## 6. Medium, by area

### Cross-cutting patterns

**M1 · Section header repeats the row label.** Seen in: Rotation/Rotation ([timetable settings](screens/4-editors/editor.timetable_secondary-light.png)), Applies/Applies ([lesson](screens/4-editors/editor.lesson_secondary-light.png)), Due/Due ([task editor](screens/5-tasks/tasks.editor_secondary-light.png)), Follow-up/Follow-up ([rule](screens/7-settings/settings.reminder-rule_secondary-light.png)), What changes/What changes ([day change](screens/4-editors/editor.day-change_secondary-light.png)), Mode/Mode ([appearance](screens/7-settings/settings.appearance_secondary-light.png)), Term dates/Add term dates ([rotation](screens/1-onboarding/onboarding.rotation_empty-light.png)).
*Fix:* keep the header, hide the control label: `Picker("Rotation", …).labelsHidden()`. For inline pickers use `Section("Mode") { Picker(…).pickerStyle(.inline).labelsHidden() }`. Or drop the header when a section has one row.

**M2 · Capitalisation is mixed** ("Next Exam" vs "Due today"; "Changes on This Day" vs "Homework & tasks"; "Add Reminder Time" vs "Add subtask"; "No Upcoming Exams" vs "No more lessons today"). `writing.md`: *"Choose a style for each UI element type and use it consistently."* Rules and string list in section 10.

**M3 · Terminology drifts** (Homework / Assignments / To-do / Tasks; "Breaks" = holidays *and* gaps between lessons; "Odd / even weeks" in onboarding vs "Alternating weeks · Counting: By calendar week" in settings; "**Week Párny**" mixes English with a Slovak label, a concatenated string). Glossary in section 10.

**M4 · Developer language shown to students.** "Text contrast 15.1 : 1", "This colour is close to the background, so its tiles get an outline", "Scheduled reminders 16 (iOS limit: 64)", "This timetable has lessons, so it can't switch between weekdays and a day cycle. Reset the timetable first.", "Tabula is built with Swift and SwiftUI. No third-party libraries are bundled."
*Fix:* hide the contrast number entirely (only warn when a colour *fails*: "Text may be hard to read on this colour"). Move iOS limits to a collapsed "Technical details" `DisclosureGroup`. Rewrite constraints as plain choices ("To use a day cycle, start a new timetable").

**M5 · Footers that explain controls, and premature errors.** "Drag to reorder. Tap a timetable to edit its settings."; "Terms with a lock are used by lessons and can't be removed" (no lock visible); red "**Enter at least one change.**" shown *before the user did anything* ([day change](screens/4-editors/editor.day-change_secondary-light.png)). `entering-data.md`: validate *"as soon as people enter them"*, not before.
*Fix:* if a control needs a manual, change the control. Show validation only after interaction (`@FocusState` / first edit), and rely on the disabled Save.

**M6 · Text fields don't look like text fields.** Titles are right-aligned like values ("Title … Nemčina – Lektion 3"). Empty fields show just the label (Title / Room / Notes look like static rows) or a black placeholder ("New task", "New subtask"). The "Enter a title to save the exam." hint sits under *Start time*, far from Title ([new exam](screens/6-exams/exams.editor-new_secondary-light.png)).
*Fix:* the first row of every editor is a full-width, leading-aligned `TextField("Title", text: $title, prompt: Text("e.g. Worksheet p. 12"))` in `.title3`. Keep placeholders in the system placeholder colour, and put the hint directly under the field as `.footnote.foregroundStyle(.secondary)`. `text-fields.md › Show a hint in a text field`.

**M7 · Close/Back buttons aren't the standard ones.** Detail sheets (Lesson, Task, Exam) use a text "Done" on the leading side; onboarding uses a text "Back" button whose capsule is invisible (`#FCFCFC` on `#F7F7F7`, **1.04:1**; dark 1.07:1). `toolbars.md › Use the standard Back and Close buttons`: *"don't use a text label that says Back or Close."*
*Fix:* detail sheets: leading `Button(role: .close) { dismiss() }` (iOS 26 renders the standard ✕), trailing "Edit". Onboarding: standard navigation back chevron.

**M8 · Same meaning, different icons; same icon, different meanings.** Room = door (Today/Timetable) vs map pin (Exams). At small sizes the door glyph reads as "▌". ↻ = "time changed" (badge) and "repeat" (task). Calendar icon appears twice in one exam card.
*Fix:* one symbol per concept app-wide (suggest room = `mappin.and.ellipse`, repeat = `repeat`, changes per H5). Write the mapping into a small `enum AppSymbol` so it can't drift.

**M9 · Key data in low-contrast grey on grey cards.** Lesson time and room on the Today card, "Time left", "Next Exam": system secondary `#848489` on card `#F1F1F1` = **3.29:1**; "Step 1 of 7" 3.44:1. Apple's secondary label is acceptable for *secondary* info, but times and rooms are primary here.
*Fix:* times and rooms in `.primary` (+ `.monospacedDigit()`), labels in `.secondary`. Use white cards on the grouped background (as editors do) instead of grey cards on white (as Today/onboarding do). The latter also lowers contrast.

### Today
**M10 · Redundant metadata.** Under "Due today" every task repeats "📅 Today". On the Tasks › Today filter too. Hide the due label when it equals the section. The "1 overdue" capsule should be a clear row ("1 overdue task ›") or a section of its own (R1).

### Timetable
**M11 · Now line hidden behind cards** in Week and Day views: only a red dot at the left edge is visible ([week](screens/3-timetable/timetable.week_university-light.png), [day](screens/3-timetable/timetable.day_secondary-light.png)). Draw it above cards (`.zIndex(1)`), full column width, with a small time label "10:20".
**M12 · Day-view cards: the time is the smallest text** (~11 pt, smaller than room and teacher). Time is the primary datum. Use `.subheadline.weight(.semibold).monospacedDigit()` for the time and `.footnote` for the teacher.
**M13 · Tiles (elementary): two look-alike circle badges.** A filled ✓ (lesson finished) next to the circled period number. Kids read ✓ as "I did my homework". Past tiles: dim them (`opacity 0.6`), no ✓. Current tile: border only today. Add the explicit **"Now"** marker (section 9), since 7-year-olds benefit from words.
**M14 · Dashed "+" on every empty slot** (9 boxes in the sample week) is visual noise and fails 3:1 (C2). Empty slots should stay quiet: plain background, tap/long-press still opens Add. Show the dashed `+` only in an explicit **Edit** mode or on press.
**M15 · Lesson detail labels collide.** Section "Changes on This Day" and button "Change for This Day" are nearly identical but do different things. The changed time in the Date/Time row isn't highlighted. *Fix:* button "Cancel, Move or Substitute…" (or "Change Just This Lesson…"). Show the changed time with the badge colour plus the strikethrough usual time.

### Editors
**M16 · Timetable settings: 7 day switches.** Replace with a weekday chip row, `Toggle(isOn:) { Text("Mo") }.toggleStyle(.button)` ×7, ordered by the user's week start (currently Sunday first, while Slovak schools start on Monday). Name + emoji + days under "General" mixes identity with schedule; split them.
**M17 · Timetables manager.** "Edit" does nothing useful with a single, undeletable timetable. The ⋯ menu *and* row tap do similar things. "✓ Active" in blue looks like a button. *Fix:* hide Edit when count = 1. One action path: row tap → settings, swipe for delete/duplicate. Show "Active" as a secondary text checkmark.
**M18 · Subjects & subject editor.** Toolbar says "Reorder" here but "Edit" in Timetables. Why reorder subjects at all? (Sort alphabetically by default; keep reordering if it drives picker order, but name it Edit.) In the subject editor, "Palette" is a **blue** navigation row, styled like a button. Use a normal row with chevron.
**M19 · Terms & breaks.** The red ⊖ is permanently inline inside the *Name* row, an accidental-delete risk. Use swipe-to-delete or Edit mode. Rename **Breaks → Holidays** (frees "break" for gaps between lessons).
**M20 · Change for one day.** Date shown twice (picker + grey line). "Follow another day" and "Short day" are unclear → **"Use another day's timetable"**, **"Shortened lessons"**. Premature red error (M5).

### Tasks
**M21 · Task editor "Due: Date / Date".** The README says due supports *next lesson*, the smartest option for homework, but it's hidden behind a picker that defaults to "Date". *Fix:* `Picker("Due", …)` with **Next lesson (Tue 20 Oct)** · Tomorrow · Pick a date…; default to next lesson for Homework.
**M22 · Task detail.** "Type: Homework" value grey, "Due: Today" value black. "Repeat" has an icon, the others don't. "Every week / On Tue" splits across two right-aligned lines. Make value styling consistent and use one line: "Weekly on Tuesday".
**M23 · Visual seam.** Header area is white, list area grouped grey, with a hard edge under the chips ([tasks](screens/5-tasks/tasks_secondary-light.png)). Use one background (`.scrollContentBackground` + grouped background everywhere) so the header and the list feel like one page.

### Exams
**M24 · Exams list.**
- The hero card's chevron is **outside** the card (layout bug; also at AX).
- Two calendar icons in one card.
- Relative time ("in 14 days") is printed *above* the exam title; lead with the title.
- "in 91 days" carries no meaning. Show the date beyond ~14 days.
- University exam-period header is plain unstyled text ("Skúškové obdobie… / Jan 4 – Feb 12 / 2 exams"). Make it a proper section header or a banner card ([university](screens/6-exams/exams_university-light.png)).
- *Fix:* put the `NavigationLink` around the whole card. Use `.contentShape(.rect)` and the system chevron inside.

**M25 · Exam editor: 4 rows for time** (Start toggle, Starts, End toggle, Ends). Students think "the exam is in period 3 on Thursday". *Fix:* `Picker("When", …)`: **During a lesson** (pick the lesson, times auto-filled) · Custom time · All day.

### Settings
**M26 · Appearance.**
- App-level Light/Dark: `dark-mode.md`: *"Avoid offering an app-specific appearance setting."* Remove, or at least move to the bottom.
- Palette names are blue (look like links). Pro palettes give no hint what happens on tap (upsell? locked?).
- Choosing a palette **doesn't recolour anything** ("Colours you already chose… do not change"), which defeats the obvious expectation.
- The "Colours in this palette" list has no clear purpose.
- *Fix:* palette rows as a `Picker` with swatch preview and a `lock.fill` + "Pro" capsule. After choosing: an **"Apply to all subjects"** button with Undo.

**M27 · Calendar & time.** Time-zone override is advanced for students. Put it in a `DisclosureGroup("Advanced")`. Default Time format to *System* (H1).
**M28 · Reminder Check.** Status words "OK / Check / Info" duplicate the icons. Warning colour is **blue** ⚠ on the Reminders root but **orange** ⚠ inside. "Settings → Focus" is text; make it a button that opens iOS Settings (`UIApplication.openSettingsURLString`).

### Widgets & Live Activities
**M29 · Lock Screen truncation drops the important part.** "Slovenský jazyk a literatúra · 25…" (inline), "No more lessons t…", "Slovenský jazyk a l…". *Fix:* time first, short name second: "25 min · SJL", "Done for today", "Next 08:00 ANJ". The circular Now & Next shows a **spinner-like glyph** above the time, which reads as *loading*. Use `Gauge(value:).gaugeStyle(.accessoryCircular)` for lesson progress.
**M30 · Pro-gated Lock Screen widgets show only an ad** ("Available in Tabula Pro"). `widgets.md`: *"Aim to create a widget that gives people quick access to the content they want."* An ad-only widget will be removed and resented. *Fix:* free tier gets a reduced but useful version (next lesson + room, no countdown); Pro adds the live countdown/progress.
**M31 · Homework widget checkboxes.** If they're not interactive, they're elements that do nothing: remove them. If they are, make them `Button(intent: ToggleTaskIntent(taskID:))` (`widgets.md`: *"the Reminders widget includes toggles to mark a task as completed"*) with ≥44 pt targets. There's also an oversized gap between circle and subject tile.

---

## 7. Low / polish

| ID | Finding | Fix |
|---|---|---|
| L1 | Dates include the current year ("Tuesday, October 13, 2026") | `.formatted(.dateTime.weekday(.wide).day().month(.wide))`; show year only if ≠ current |
| L2 | Today has a tall empty navigation bar above the title | iOS 26 `.navigationSubtitle("Tue 13 Oct · Week B")` and delete the date header lower down |
| L3 | Grid leaves ~200 pt empty under period 8 | Let rows grow: `.containerRelativeFrame(.vertical)` divided by period count, with a min height |
| L4 | About lacks Contact/Feedback, Privacy Policy link, Rate | Add these 3 rows; drop the "built with SwiftUI" line |
| L5 | Tab bar over saturated tiles turns cyan/pink; selected label less legible | Add bottom content margin `.contentMargins(.bottom, 24, for: .scrollContent)` so tiles end above the bar at rest |
| L6 | Sample data mixes emoji icons with one SF Symbol (÷) | Fine for user data; keep sample data consistent (all emoji) |
| L7 | English uses British spellings ("Colour", "Acknowledgements") | Decide: if `en` = US, use "Color/Acknowledgments" and add `en-GB` if desired (Q8) |
| L8 | Timetable title "🏫 Gymnázium – 2.B" is at the 15-char limit (`toolbars.md`) | Long names truncate: move rotation/week into `.navigationSubtitle` |
| L9 | Evening widget "No more lessons today" + circular ✓ says nothing | "Done for today" + circular shows tomorrow's first time "08:00" |
| L10 | Small homework widget: big empty gap between count and top task | Use the space for 2 tasks, or bigger type |

---

## 8. Redesign proposals

Only for screens where fixing individual findings isn't enough. All use standard SwiftUI components.

### R1 · Today: one job, one order, every profile

**Principle:** Now/Next first, then what's due, then the rest of the day, then upcoming exams. **Same order for all profiles**; content density adapts (elementary = bigger, bring list; university = building).

```
┌──────────────────────────────────────┐
│ Today                          ⋯     │  large title
│ Tue 13 Oct · Week B                  │  .navigationSubtitle (iOS 26)
│ ┌──────────────────────────────────┐ │
│ │ ▓NOW▓                until 10:45 │ │  highlighter marker (§9)
│ │ 📖 Slovenský jazyk a literatúra  │ │  .title2 semibold
│ │ 📍 214 · Mgr. Kováčová           │ │  .body, primary colour
│ │ ━━━━━━━━━━━━━░░░░░  25 min left  │ │  neutral/ink progress, not subject red
│ ├──────────────────────────────────┤ │
│ │ NEXT 10:55  🧬 Biológia · 📍 214 │ │  one line
│ └──────────────────────────────────┘ │
│                                      │
│ Due today                            │
│ ○ Nemčina – Lektion 3   💬  2/5  ↻   │
│ ⚠ 1 overdue task                  ›  │  plain row → Tasks/Overdue
│                                      │
│ Rest of today                        │
│ 10:55  🧬 Biológia            214    │  compact rows; current lesson NOT repeated
│ 11:50  💬 Nemecký jazyk      JAZ-1   │
│ 12:45  🌍 Geografia           214    │
│                                      │
│ Next exam                            │
│ 🧪 Písomka – organická chémia     ›  │
│    Thu 22 Oct · in 9 days            │  .subheadline, NOT 34 pt
└──────────────────────────────────────┘
```

**States of the hero card** (currently only "during a lesson" is designed):

| Moment | Hero shows |
|---|---|
| Before school | "First lesson 08:00 · ANJ · 📍 JAZ-2" + **What to bring** (bring list) |
| Break | "Next: Chémia in 2 min · 📍 Lab CHE" |
| During lesson | As above |
| After school | "Done for today 🎒 Tomorrow starts 08:00 with ANJ" + pack-your-bag list |
| Holiday / weekend | "Jesenné prázdniny until Sun 1 Nov" (reuse widget design) |

**SwiftUI hints:** `List` with `.listStyle(.insetGrouped)` sections (free Dynamic Type, VoiceOver rotor, swipe actions on tasks). The hero is one `Section` with a custom row. `TimelineView(.everyMinute)` drives state changes.

### R2 · Tasks: one grouped list, fast add

**Problem cluster:** C3 (invisible filter), H6 (inline form), H7 (checkbox colours), M10, M23.

```
┌──────────────────────────────────────┐
│ Tasks                       ⏷    +   │  ⏷ = Menu: subject, type, Show completed
│                                      │
│ OVERDUE · 1                          │  red-pen header (only colour use)
│ ○ Laboratórny protokol – hustota…    │
│   ⚛ Fyzika · was due Mon 12 Oct      │
│                                      │
│ TODAY · 1                            │
│ ○ Nemčina – Lektion 3      2/5  ↻    │
│   💬 Nemecký jazyk                    │
│                                      │
│ TOMORROW                             │
│ ○ Slovná zásoba – Unit 4             │
│   🗣 Anglický jazyk                   │
│                                      │
│ THIS WEEK                            │
│ ○ Pracovný list – kvadratické…  Thu  │
│ ○ Slohová práca: úvaha   Mon 08:00   │
│                                      │
│        Show 2 completed tasks        │  button at end of list
└──────────────────────────────────────┘
```

**Quick-entry sheet** (from `+`, `.presentationDetents([.medium, .large])`):

```
 Cancel          New Task            Add      ← Add = .borderedProminent
┌────────────────────────────────────────┐
│ What do you need to do?                │  TextField, focused, .title3
└────────────────────────────────────────┘
 Subject   [💬 Nemecký jazyk ▾]            defaults to current/next lesson's subject
 Due       [Next lesson · Tue 20 Oct ▾]   Next lesson | Tomorrow | Pick date…
 Type      [ Homework | To-do | Assignment ]  segmented
 ▸ More options                          DisclosureGroup: priority, notes,
                                          subtasks, repeat, reminder, attachments
```

Why this works: it matches the Reminders app's mental model (people already know it). Overdue is visible *without* a dedicated filter, and nothing important is ever off-screen. Adding a task takes title + one tap.

### R3 · Settings: information architecture

```
┌──────────────────────────────────────┐
│ Settings                             │
│ TIMETABLE                            │
│ 🏫 Gymnázium – 2.B         Active  › │ → Timetable settings (name, days, rotation)
│ 📚 Subjects                    12  › │
│ 🔔 Bell schedule        8 periods  › │
│ 🗓 Terms & holidays                › │
│ ＋ Add Another Timetable…            │  (Manage list appears only if >1)
│                                      │
│ NOTIFICATIONS                        │
│ ⏰ Reminders      Homework, Exams… › │
│ 🏝 Live Activities            On   › │
│                                      │
│ GENERAL                              │
│ 🎓 School type         Secondary ⌃⌄ │
│ 🕐 Date & time               System › │
│ 🎨 Colours                   Classic › │
│ 🌐 Language                  English › │  opens iOS Settings
│                                      │
│ ℹ About & Feedback                 › │
└──────────────────────────────────────┘
```

- All rows **push** (`NavigationLink`) inside the Settings tab's `NavigationStack`. Sheets only for *create* flows (new subject, new timetable).
- Use Apple-style icon tiles (`Label` with a rounded coloured square), consistent with iOS Settings.
- "Lessons are called" moves into Timetable settings (it's per school type) as a proper `Picker`.
- The Timetable tab's menu (H4) deep-links to the same screens via `NavigationPath`.

### R4 · Reminders settings

```
Reminders
┌──────────────────────────────────────┐
│ ⚠ Notifications are off           › │  ONLY when user-fixable (H9)
└──────────────────────────────────────┘
REMIND ME ABOUT
│ ✏️  Homework     1 day before, 17:00 › │
│ 📄  Assignments                  Off › │
│ 🎓  Exams                 2 reminders › │
│ 🔔  Before a lesson              Off › │
│ 🎒  Pack your bag     Evening, 20:00 › │

DELIVERY CHECK
│ 🩺  Test reminders & troubleshoot    › │
```

Rule page (one toggle, top): **Remind me** [toggle] → *When* (list + "Add Time") → *If not done* ("Remind again next morning at 07:00") → *Delivery* (Standard · Loud alarm; Time Sensitive hidden until available) → *Quiet hours*.

### R5 · Onboarding: 7 steps → 4

| New step | Contains | Replaces |
|---|---|---|
| 1. **Welcome · Who are you?** | 4 profile cards; footnote "App language: English · Change" | old 1 + 2 |
| 2. **How do you want to start?** | "Set up my timetable" · "Just look around (sample data)". Sample → straight into the app with a banner "This is sample data · Remove". Import rows hidden until they work. | old 7 (moved first!) |
| 3. **Your week** | School days (chips), rotation with pictures ("Same every week" / "Week A & Week B" / "Day A & Day B" / "Longer cycle") | old 3 |
| 4. **Lesson times** | Bell generator + preview (keep as is), "I'll do this later" link | old 4 |

- **Fields to show**: derived from profile (school → room, teacher; university → + building, type). Editable later in Timetable settings.
- **Reminders**: ask in context the first time someone adds homework or an exam (your permission explainer already exists). Default Homework + Exams on.
- Buttons: "Continue" → last step "**Start Using Tabula**". Back = standard toolbar chevron.
- At AX sizes: cards stack the icon above the text (H13).

### R6 · Bell schedule editor

```
 Cancel        Bell Schedule          Save
 Schedule   [ Regular day ▾ ]                ← variants: Regular / Shortened / + New
┌──────────────────────────────────────┐
│ 1   08:00 – 08:45                  › │
│       break 10 min                   │  computed, secondary, not editable here
│ 2   08:55 – 09:40                  › │
│       break 20 min                   │
│ 3   10:00 – 10:45                  › │
│ …                                    │
│ ＋ Add Period                        │
└──────────────────────────────────────┘
 [ Regenerate from lesson length… ]       ← reuses the onboarding generator
```

Today each period takes 4 rows (Label 🔒 / Kind / Starts / Ends): 32 rows for 8 periods, and the lock's meaning is never explained. One row per period with a detail page cuts that to 8 rows. Breaks become visible, which is how pupils read a bell schedule on the classroom wall.

---

## 9. Light visual identity: "Exercise book"

**Grounding:** Central-European pupils write in **royal-blue fountain-pen ink**, teachers correct in **red**, and everyone **highlights** with yellow markers. Those three materials already carry meaning for every student, so the palette explains itself. Platform check: standard components stay; only tint, a few semantic colours, and number styling change.

### Tokens

| Token | Role | Light | Dark | Contrast (measured/computed) |
|---|---|---|---|---|
| `ink` | App tint: buttons, links, selection, progress | `#2541B2` | `#8EA2FF` | 8.5:1 on white · 7.1:1 on `#1C1C1E` · white text on ink 8.5:1 |
| `correction` | Overdue, cancelled, destructive *only* | `#C62828` | `#FF6961` | 5.6:1 on white · 6.0:1 on `#1C1C1E` |
| `highlighter` | The "Now" marker *only* | `#FFE04A` fill + black text | same | black on it 16:1 |
| `pencil` | Secondary text | system `.secondary` (use `#6C6C70` on white cards) | system | 5.2:1 on white |
| Surfaces | Paper | system grouped backgrounds | system | — |
| Subject colours | Content layer | keep current palettes + auto text colour | keep | 4.9–15:1 (passes) |

`.tint(Color("Ink"))` at the root replaces iOS 26 system blue `#0088FF` (3.5:1 on white, 2.2:1 on grey). It also fixes C2's blue-on-grey problems. Provide an **Increase Contrast** variant in the asset catalog (`ink` → `#1A2F85`).

### Type

- System **SF Pro** for everything, as now.
- **SF Pro Rounded + monospaced digits for numbers that matter**: period numbers, times, countdowns: `.fontDesign(.rounded).monospacedDigit()`. Friendly for 7-year-olds, still serious for university, and digits don't jiggle as time ticks.
- Scale: Large Title (screen) → Title 2 semibold (current lesson) → Headline (row titles) → Body (room, teacher) → Footnote (metadata). Nothing below Footnote for real data.

### Signature element: the highlighter "Now"

One consistent marker for *the present moment*, used in **every** place that shows time: Today hero, grid cell, Week/Day now-line, Tiles, Today widget row, Live Activity, Lock Screen. A short yellow highlighter swipe behind the word **NOW** (black text, 16:1), slightly rounded, like a real marker stroke. It replaces the current red "recording" dot (which collides with error red) and the black/white borders. It's the one bold element; everything else stays quiet.

### Motion (one moment)

When a task is checked, the checkmark **draws like a pen stroke** (SF Symbols 7 draw-on effect, iOS 26), in ink. Respect `accessibilityReduceMotion` (instant swap). No other decorative motion.

### Self-critique

*Would I propose this for a different app?* No. Ink/correction/highlighter only makes sense for school. *Does it fight the platform?* No: standard controls, one tint, semantic colours used for exactly one meaning each. *What could be removed?* The red "Now" dot, the black current-lesson borders, the calendar glyph before "in 9 days", and the blue tint on the elementary exam card. All four are replaced by the single highlighter.

---

## 10. Copy, terminology and capitalisation

### Capitalisation rules (pick once, apply everywhere)

| Element | Style | Example |
|---|---|---|
| Navigation titles, tab names | Title Case | "Bell Schedule", "Terms & Holidays" |
| Buttons & menu items | Title Case, start with a verb | "Add Term", "Add Subtask", "Move to History" |
| Section headers, row labels, footers, body | Sentence case | "Due today", "Next exam", "Changes on this day" |
| Empty states | Sentence case | "No upcoming exams" |

Strings to change (non-exhaustive): "Next Exam" → "Next exam"; "Changes on This Day" → "Changes on this day"; "Add subtask" → "Add Subtask"; "Add homework for this lesson" → "Add Homework"; "No Upcoming Exams" → "No upcoming exams"; "Next Lesson" (widget) → "Next lesson"; "Reminder Check" title stays Title Case.

### Glossary (one word per concept)

| Concept | Use | Stop using |
|---|---|---|
| Anything with a due date | **Task** (types: Homework, Assignment, To-do) | mixing "Tasks"/"Homework" as list names |
| Gap between lessons | **Break** | — |
| Days off school | **Holidays** | "Breaks" (Terms & Breaks) |
| A/B rotation | **Week A / Week B** (or "Odd/even week" as a *counting* option) | "Alternating weeks", "Week Párny" |
| One-off override | **Change** (Cancel, Move, Substitute, Room change) | "Change for This Day" + "Changes on This Day" pair |
| Free-form times | **Custom times** | "Free times" (reads as "spare time") |
| School type | **School type** | "I am in", "Who are you?", "Profile" (three names) |

> **Your call:** the real difference between *Homework*, *Assignment* and *To-do* in your data model decides whether all three should exist. If Assignment = "homework with a longer deadline", merge it into Homework and drop a reminder kind. Write one sentence per type here; it becomes the in-app description in the Type picker.

### Rotation labels must be localised, never concatenated

"Week " + userLabel produced **"Week Párny"**. Use full format strings per rotation type (`"Week %@"` only for user-named weeks A/B). For odd/even use dedicated keys: "Odd week" / "Even week" → sk "Nepárny týždeň" / "Párny týždeň".

---

## 11. Prioritised fix plan

Effort: **S** ≤ ½ day · **M** 1–3 days · **L** ~1 week.

| Phase | Goal | Items | Effort |
|---|---|---|---|
| **1. Broken & inaccessible** | Nothing is wrong or unreadable | C1, C2, C3 (min fix), H1, H9, H15, H14 (background), M24 chevron, M31 (remove or wire) | S–M |
| **2. Clarity** | Every control says what it does | H2, H4, H5, H7, H8, M1, M2, M3, M4, M5, M6, M7, M8, M9, M15, M20, M21 | M |
| **3. Restructure** | Fix the confusing flows | R2 Tasks → R4 Reminders → R3 Settings → R6 Bell → R1 Today → R5 Onboarding, plus H13 at each step | L |
| **4. Identity & polish** | Look designed, not default | Section 9 tokens + highlighter, M11–M14, M26–M30, Lows | M |

Re-capture the screenshot set after each phase (light/dark/AX) and diff against this report.

---

## 12. Open questions and what I could not verify

**Questions for you** (answers change specific fixes):

| # | Question | Affects |
|---|---|---|
| Q1 | Does **Add Lesson** (grid quick add) create a weekly slot or a one-off for that date? | H14 copy |
| Q2 | If the user picks **Use sample data** at the end of onboarding, are their answers from steps 2–6 discarded? | H12, R5 |
| Q3 | Are the **Homework widget circles** interactive (App Intents)? | M31 |
| Q4 | What is the current tap path to **Subjects**, **Bell schedule** and **Terms**? | H11, R3 |
| Q5 | Is **"Lessons are called"** tappable, and what does it rename? | H11 |
| Q6 | What does **Mark Done** do to an exam? | H15 |
| Q7 | Difference between **Homework / Assignment / To-do**? (see "Your call" in section 10) | M3 |
| Q8 | Is the base English meant to be **British**? | L7 |

**Not verifiable from screenshots:** VoiceOver labels, order and rotor (e.g. whether icon-only buttons have `accessibilityLabel`s), real Home/Lock Screen widget rendering modes (tinted/clear), real Dynamic Island, haptics, motion, Reduce Transparency / Increase Contrast, iPad and landscape layouts, the Watch app.

---

## 13. Appendix

### Measured contrast (pixel-sampled from the light-mode screenshots)

| Element | Background | Foreground | Ratio | Result |
|---|---|---|---|---|
| Pro badge | `#FFFFFF` | `#7FC3FF` | 1.88:1 | ❌ |
| Yellow task checkbox | `#FFFFFF` | ring | 1.74:1 | ❌ (non-text 3:1) |
| Empty-slot dashed outline | `#FFFFFF` | `#ADADB0` | 2.24:1 | ❌ (non-text 3:1) |
| "Open language settings" | `#CDCDCF` | `#0088FF` | 2.22:1 | ❌ |
| Unselected Tasks chip | `#E9E9EB` | `#0088FF` | 2.90:1 | ❌ |
| Onboarding Back capsule vs bar | `#F7F7F7` | `#FCFCFC` | 1.04:1 | ⚠ invisible boundary |
| Secondary text on grey card | `#F1F1F1` | `#848489` | 3.29:1 | ⚠ OK for secondary, not for times/rooms |
| "Step 1 of 7", grid end times | `#FFFFFF` | `#8A8A8E` | 3.44:1 | ⚠ same |
| System blue text / white on blue | `#FFFFFF` | `#0088FF` | 3.52:1 | ⚠ system default; replaced by `ink` 8.5:1 |
| Black on teal subject | `#00897B` | `#000000` | 4.86:1 | ✅ |
| Black on red subject | `#E53935` | `#000000` | 4.97:1 | ✅ |
| White on pink subject | `#D81B60` | `#FFFFFF` | 4.95:1 | ✅ |
| White on purple subject | `#8E24AA` | `#FFFFFF` | 7.04:1 | ✅ |
| White on indigo subject | `#3949AB` | `#FFFFFF` | 7.73:1 | ✅ |
| Black on yellow subject | `#FDD835` | `#000000` | 15.05:1 | ✅ |

### HIG pages cited
`accessibility.md`, `typography.md`, `color.md`, `layout.md`, `dark-mode.md`, `toolbars.md`, `tab-bars.md`, `segmented-controls.md`, `pull-down-buttons.md`, `buttons.md`, `toggles.md`, `text-fields.md`, `entering-data.md`, `sheets.md`, `modality.md`, `onboarding.md`, `settings.md`, `writing.md`, `widgets.md`, `live-activities.md`, `lists-and-tables.md`, `feedback.md`. All are from the apple-design skill's mirror of developer.apple.com (pages last changed June–Oct 2026).
