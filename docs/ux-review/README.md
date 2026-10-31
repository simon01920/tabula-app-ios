# Tabula — UI/UX review package

**What Tabula is:** an iOS 26+ (and later watchOS) school and university timetable app with homework, exams and
reminders. Users: pupils in elementary and secondary school, and university students. Five tabs: **Today ·
Timetable · Tasks · Exams · Settings**. It runs in 12 languages (en, sk, cs, pl, hu, ro, de, fr, uk, sr Cyrillic and
Latin, ja, zh-Hans).

**How these screenshots were made:**
- iOS Simulator (largest iPhone Pro Max), from a DEBUG build on GitHub Actions.
- Every screen is in **light**, **dark** and **largest accessibility text** (AX-XXXL).
- **Sample data:** a Slovak secondary school (class 2.B, A/B weeks), plus university and elementary profiles. The
  subject names are in Slovak even in the English UI; that is the sample data, not untranslated UI.
- The clock is fixed at **Tue 13 Oct 2026, 10:20** (Europe/Bratislava), so "Now" is a Slovak lesson.
- The `…_sk` files show the Slovak UI.

**Fixed constraints:**
- Standard SwiftUI controls (iOS 26 Liquid Glass applies automatically).
- Dynamic Type and VoiceOver must keep working.
- Text on user-chosen subject colours must stay readable.
- No hard-coded or concatenated strings; everything is translated.
- There is no designer yet: the current look is engineering defaults.

**Not in screenshots:** real Home Screen widgets and Live Activities (shown here through a DEBUG gallery that
approximates them), system permission dialogs, notifications and alarms, the Watch app (Phase 5).

**Seeds used:** `empty` (onboarding), `secondary`, `university`, `elementary`.


## Onboarding

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Welcome · School type** (`onboarding`) | First launch, step 1 of 4: product line, four school-type cards, compact 'App language · Change' row (opens iOS Settings). | empty · en | [light](screens/1-onboarding/onboarding_empty-light.png) | [dark](screens/1-onboarding/onboarding_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding_empty-ax-xxxl-text.png) |
| **School type (selected)** (`onboarding.school-type`) | Step 1 with Secondary selected; Continue enabled. | empty · en | [light](screens/1-onboarding/onboarding.school-type_empty-light.png) | [dark](screens/1-onboarding/onboarding.school-type_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.school-type_empty-ax-xxxl-text.png) |
| **School type (selected)** (`onboarding.school-type`) | Step 1 with Secondary selected; Continue enabled. | empty · sk | [light](screens/1-onboarding/onboarding.school-type_empty_sk-light.png) | [dark](screens/1-onboarding/onboarding.school-type_empty_sk-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.school-type_empty_sk-ax-xxxl-text.png) |
| **How do you want to start?** (`onboarding.start`) | Step 2: 'Set up my timetable' (default) or 'Just look around' (sample data, removable). Imports hidden until they work. | empty · en | [light](screens/1-onboarding/onboarding.start_empty-light.png) | [dark](screens/1-onboarding/onboarding.start_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.start_empty-ax-xxxl-text.png) |
| **Your week** (`onboarding.week`) | Step 3: school-day chips, repeat pattern; here alternating weeks with 'Which week is this week?', calendar odd/even and term dates. | empty · en | [light](screens/1-onboarding/onboarding.week_empty-light.png) | [dark](screens/1-onboarding/onboarding.week_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.week_empty-ax-xxxl-text.png) |
| **Your week — alternating days** (`onboarding.week-days`) | Step 3 (elementary): Day A / Day B anchored on today or the next school day. | empty · en | [light](screens/1-onboarding/onboarding.week-days_empty-light.png) | [dark](screens/1-onboarding/onboarding.week-days_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.week-days_empty-ax-xxxl-text.png) |
| **Lesson times** (`onboarding.times`) | Step 4: fixed lesson periods (generator + preview), steppers + direct minute entry, 'I'll Do This Later', 'Start Using Tabula'. | empty · en | [light](screens/1-onboarding/onboarding.times_empty-light.png) | [dark](screens/1-onboarding/onboarding.times_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.times_empty-ax-xxxl-text.png) |
| **Lesson times — individual** (`onboarding.times-individual`) | Step 4 (university): individual start and end times with a default length. | empty · en | [light](screens/1-onboarding/onboarding.times-individual_empty-light.png) | [dark](screens/1-onboarding/onboarding.times-individual_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.times-individual_empty-ax-xxxl-text.png) |
| **Sample-data banner** (`onboarding.sample-banner`) | After 'Just look around': 'This is sample data · Remove' above Today; Remove deletes only the sample. | secondary · en | [light](screens/1-onboarding/onboarding.sample-banner_secondary-light.png) | [dark](screens/1-onboarding/onboarding.sample-banner_secondary-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.sample-banner_secondary-ax-xxxl-text.png) |

## Today

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Today — in a lesson** (`today`) | Tab 1, one order for every profile: hero (NOW · until 10:45, room, ink progress, '25 min left', next lesson line), Due today with '1 overdue task ›', Rest of today (+ collapsed 'Earlier today'), Next exam (title first). Subtitle 'Tue, Oct 13 · Week B'. | elementary · en | [light](screens/2-today/today_elementary-light.png) | [dark](screens/2-today/today_elementary-dark.png) | [ax-xxxl-text](screens/2-today/today_elementary-ax-xxxl-text.png) |
| **Today — in a lesson** (`today`) | Tab 1, one order for every profile: hero (NOW · until 10:45, room, ink progress, '25 min left', next lesson line), Due today with '1 overdue task ›', Rest of today (+ collapsed 'Earlier today'), Next exam (title first). Subtitle 'Tue, Oct 13 · Week B'. | secondary · en | [light](screens/2-today/today_secondary-light.png) | [dark](screens/2-today/today_secondary-dark.png) | [ax-xxxl-text](screens/2-today/today_secondary-ax-xxxl-text.png) |
| **Today — in a lesson** (`today`) | Tab 1, one order for every profile: hero (NOW · until 10:45, room, ink progress, '25 min left', next lesson line), Due today with '1 overdue task ›', Rest of today (+ collapsed 'Earlier today'), Next exam (title first). Subtitle 'Tue, Oct 13 · Week B'. | university · en | [light](screens/2-today/today_university-light.png) | [dark](screens/2-today/today_university-dark.png) | [ax-xxxl-text](screens/2-today/today_university-ax-xxxl-text.png) |
| **Today — before school** (`today.before-school`) | Fixed clock 7:20: 'First lesson · in 40 min', subject, room, time, bring list when present. | secondary · en | [light](screens/2-today/today.before-school_secondary-light.png) | [dark](screens/2-today/today.before-school_secondary-dark.png) | [ax-xxxl-text](screens/2-today/today.before-school_secondary-ax-xxxl-text.png) |
| **Today — break** (`today.break`) | Fixed clock 8:53: 'Next · in 2 min', Chemistry, its room and time. | secondary · en | [light](screens/2-today/today.break_secondary-light.png) | [dark](screens/2-today/today.break_secondary-dark.png) | [ax-xxxl-text](screens/2-today/today.break_secondary-ax-xxxl-text.png) |
| **Today — after school** (`today.after-school`) | Fixed clock 16:00: 'Done for today', tomorrow's first lesson, pack list; the day's lessons under 'Earlier today', then Tomorrow. | secondary · en | [light](screens/2-today/today.after-school_secondary-light.png) | [dark](screens/2-today/today.after-school_secondary-dark.png) | [ax-xxxl-text](screens/2-today/today.after-school_secondary-ax-xxxl-text.png) |
| **Today — holiday** (`today.holiday`) | Thu Oct 29: 'Jesenné prázdniny · until Fri, Oct 30' and Monday's first lesson. | secondary · en | [light](screens/2-today/today.holiday_secondary-light.png) | [dark](screens/2-today/today.holiday_secondary-dark.png) | [ax-xxxl-text](screens/2-today/today.holiday_secondary-ax-xxxl-text.png) |

## Timetable

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Grid view** (`timetable.grid`) | Week grid (periods x days): room always on line 2, one badge slot (cancelled > exam > tasks > change), highlighter on the current period, quiet free slots. | secondary · en | [light](screens/3-timetable/timetable.grid_secondary-light.png) | [dark](screens/3-timetable/timetable.grid_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.grid_secondary-ax-xxxl-text.png) |
| **Grid — next week** (`timetable.grid-next-week`) | The grid one week ahead: the 'Today' button appears and the subtitle shows the other rotation week. | secondary · en | [light](screens/3-timetable/timetable.grid-next-week_secondary-light.png) | [dark](screens/3-timetable/timetable.grid-next-week_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.grid-next-week_secondary-ax-xxxl-text.png) |
| **Grid — symbol legend** (`timetable.grid-legend`) | The one-time TipKit legend of the change symbols (forced visible for the screenshot). | secondary · en | [light](screens/3-timetable/timetable.grid-legend_secondary-light.png) | [dark](screens/3-timetable/timetable.grid-legend_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.grid-legend_secondary-ax-xxxl-text.png) |
| **Week time-blocks** (`timetable.week`) | Proportional week view (university default); now line above the blocks with a time label in the gutter. | university · en | [light](screens/3-timetable/timetable.week_university-light.png) | [dark](screens/3-timetable/timetable.week_university-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.week_university-ax-xxxl-text.png) |
| **Day view** (`timetable.day`) | One day, proportional time blocks (time is the primary datum). At the largest text size: compact date header (previous / date picker / next) and full-width subject names. | secondary · en | [light](screens/3-timetable/timetable.day_secondary-light.png) | [dark](screens/3-timetable/timetable.day_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.day_secondary-ax-xxxl-text.png) |
| **Tiles view** (`timetable.tiles`) | Big vertical tiles (elementary default): past tiles dimmed, highlighter 'NOW' on the current tile. | elementary · en | [light](screens/3-timetable/timetable.tiles_elementary-light.png) | [dark](screens/3-timetable/timetable.tiles_elementary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.tiles_elementary-ax-xxxl-text.png) |
| **Lesson detail** (`timetable.lesson-detail`) | Tap a lesson: time (a changed time in the change colour, usual time struck through), room, teacher, homework, changes on this day. | secondary · en | [light](screens/3-timetable/timetable.lesson-detail_secondary-light.png) | [dark](screens/3-timetable/timetable.lesson-detail_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.lesson-detail_secondary-ax-xxxl-text.png) |
| **Quick add** (`timetable.quick-add`) | Tap a free slot: opaque sheet, header 'Every Monday · Week B · Period 7 (13:40–14:25)'. | secondary · en | [light](screens/3-timetable/timetable.quick-add_secondary-light.png) | [dark](screens/3-timetable/timetable.quick-add_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.quick-add_secondary-ax-xxxl-text.png) |

## Editors

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Timetables manager** (`editor.timetables`) | Settings/Timetable: list of timetables (multiple allowed). | secondary · en | [light](screens/4-editors/editor.timetables_secondary-light.png) | [dark](screens/4-editors/editor.timetables_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.timetables_secondary-ax-xxxl-text.png) |
| **Timetable editor** (`editor.timetable`) | Name, rotation, term dates, time zone. | secondary · en | [light](screens/4-editors/editor.timetable_secondary-light.png) | [dark](screens/4-editors/editor.timetable_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.timetable_secondary-ax-xxxl-text.png) |
| **Lesson editor** (`editor.lesson`) | Edit an existing lesson (day, period/time, room, week A/B...). | secondary · en | [light](screens/4-editors/editor.lesson_secondary-light.png) | [dark](screens/4-editors/editor.lesson_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.lesson_secondary-ax-xxxl-text.png) |
| **Bell schedule** (`editor.bell`) | One row per period with computed breaks; schedule picker (Regular / Shortened / New). | secondary · en | [light](screens/4-editors/editor.bell_secondary-light.png) | [dark](screens/4-editors/editor.bell_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.bell_secondary-ax-xxxl-text.png) |
| **Bell period detail** (`editor.bell-period`) | Name, kind, start/end of one period; 'Used by N lessons'; Delete Period. | secondary · en | [light](screens/4-editors/editor.bell-period_secondary-light.png) | [dark](screens/4-editors/editor.bell-period_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.bell-period_secondary-ax-xxxl-text.png) |
| **Terms & holidays** (`editor.terms`) | School year, semesters, breaks, exam periods. | secondary · en | [light](screens/4-editors/editor.terms_secondary-light.png) | [dark](screens/4-editors/editor.terms_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.terms_secondary-ax-xxxl-text.png) |
| **Change for one day** (`editor.day-change`) | One-off override: cancel / move / substitute / room change. | secondary · en | [light](screens/4-editors/editor.day-change_secondary-light.png) | [dark](screens/4-editors/editor.day-change_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.day-change_secondary-ax-xxxl-text.png) |

## Tasks

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Tasks — Today** (`tasks`) | Tab 3. One grouped list: Overdue, Today, Tomorrow, This week, Later, No date (counts in headers); filter menu and + in the toolbar; completed behind a button at the end. | secondary · en | [light](screens/5-tasks/tasks_secondary-light.png) | [dark](screens/5-tasks/tasks_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks_secondary-ax-xxxl-text.png) |
| **Tasks — Today** (`tasks`) | Tab 3. One grouped list: Overdue, Today, Tomorrow, This week, Later, No date (counts in headers); filter menu and + in the toolbar; completed behind a button at the end. | secondary · sk | [light](screens/5-tasks/tasks_secondary_sk-light.png) | [dark](screens/5-tasks/tasks_secondary_sk-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks_secondary_sk-ax-xxxl-text.png) |
| **Tasks — Overdue** (`tasks.overdue`) | Same list scrolled to the Overdue section. | secondary · en | [light](screens/5-tasks/tasks.overdue_secondary-light.png) | [dark](screens/5-tasks/tasks.overdue_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.overdue_secondary-ax-xxxl-text.png) |
| **Tasks — Completed** (`tasks.completed`) | Same list with the completed tasks shown and scrolled to. | secondary · en | [light](screens/5-tasks/tasks.completed_secondary-light.png) | [dark](screens/5-tasks/tasks.completed_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.completed_secondary-ax-xxxl-text.png) |
| **Task detail** (`tasks.detail`) | Tap a task: type, due, repeat, notes, subtasks, attachments. | secondary · en | [light](screens/5-tasks/tasks.detail_secondary-light.png) | [dark](screens/5-tasks/tasks.detail_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.detail_secondary-ax-xxxl-text.png) |
| **Task editor** (`tasks.editor`) | Edit a task (title, kind, subject, due incl. 'next lesson', priority, subtasks, repeat, reminder, attachments). | secondary · en | [light](screens/5-tasks/tasks.editor_secondary-light.png) | [dark](screens/5-tasks/tasks.editor_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.editor_secondary-ax-xxxl-text.png) |
| **Quick entry** (`tasks.quick-add`) | The + sheet: focused title, subject (current or next lesson), due (next lesson / tomorrow / pick a date), type with a description, More options. | secondary · en | [light](screens/5-tasks/tasks.quick-add_secondary-light.png) | [dark](screens/5-tasks/tasks.quick-add_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.quick-add_secondary-ax-xxxl-text.png) |

## Exams

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | secondary · de | [light](screens/6-exams/exams_secondary_de-light.png) | [dark](screens/6-exams/exams_secondary_de-dark.png) | [ax-xxxl-text](screens/6-exams/exams_secondary_de-ax-xxxl-text.png) |
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | secondary · en | [light](screens/6-exams/exams_secondary-light.png) | [dark](screens/6-exams/exams_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams_secondary-ax-xxxl-text.png) |
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | university · en | [light](screens/6-exams/exams_university-light.png) | [dark](screens/6-exams/exams_university-dark.png) | [ax-xxxl-text](screens/6-exams/exams_university-ax-xxxl-text.png) |
| **Exams — History** (`exams.history`) | Past exams. | secondary · en | [light](screens/6-exams/exams.history_secondary-light.png) | [dark](screens/6-exams/exams.history_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams.history_secondary-ax-xxxl-text.png) |
| **Exam editor** (`exams.editor`) | Kind, date, times, room/building, topics, reminder. | secondary · en | [light](screens/6-exams/exams.editor_secondary-light.png) | [dark](screens/6-exams/exams.editor_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams.editor_secondary-ax-xxxl-text.png) |

## Settings

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Settings** (`settings`) | Tab 5. Timetable / Notifications / General / About & Feedback groups with icon tiles; every row pushes. | secondary · en | [light](screens/7-settings/settings_secondary-light.png) | [dark](screens/7-settings/settings_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings_secondary-ax-xxxl-text.png) |
| **Colors** (`settings.colours`) | Colour palette picker (swatch preview, Pro capsule + lock), preview tile, Apply to All Subjects with Undo. No Light/Dark override (D3). Alias: settings.appearance. | secondary · en | [light](screens/7-settings/settings.colours_secondary-light.png) | [dark](screens/7-settings/settings.colours_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.colours_secondary-ax-xxxl-text.png) |
| **Date & Time** (`settings.calendar`) | Week start, time format (System by default), time zone inside the collapsed Advanced group. | secondary · en | [light](screens/7-settings/settings.calendar_secondary-light.png) | [dark](screens/7-settings/settings.calendar_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.calendar_secondary-ax-xxxl-text.png) |
| **About & Feedback** (`settings.about`) | Version, Send Feedback / Privacy Policy (placeholder targets), privacy summary, Acknowledgements. | secondary · en | [light](screens/7-settings/settings.about_secondary-light.png) | [dark](screens/7-settings/settings.about_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.about_secondary-ax-xxxl-text.png) |
| **Reminders** (`settings.reminders`) | One row per kind (name + summary, Off), quiet hours, loud alarms, Test reminders & troubleshoot; attention row only for user-fixable problems. | secondary · en | [light](screens/7-settings/settings.reminders_secondary-light.png) | [dark](screens/7-settings/settings.reminders_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminders_secondary-ax-xxxl-text.png) |
| **Reminders** (`settings.reminders`) | One row per kind (name + summary, Off), quiet hours, loud alarms, Test reminders & troubleshoot; attention row only for user-fixable problems. | university · en | [light](screens/7-settings/settings.reminders_university-light.png) | [dark](screens/7-settings/settings.reminders_university-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminders_university-ax-xxxl-text.png) |
| **Reminder kind page** (`settings.reminder-rule`) | Remind me switch, times, follow-up, delivery (Standard / Loud alarm; Time Sensitive only where supported), quiet hours. | secondary · en | [light](screens/7-settings/settings.reminder-rule_secondary-light.png) | [dark](screens/7-settings/settings.reminder-rule_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminder-rule_secondary-ax-xxxl-text.png) |
| **Reminder check** (`settings.reminder-health`) | Summary of user-fixable problems, checks with Open Settings buttons, collapsed Technical details, test buttons. | secondary · en | [light](screens/7-settings/settings.reminder-health_secondary-light.png) | [dark](screens/7-settings/settings.reminder-health_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminder-health_secondary-ax-xxxl-text.png) |
| **Live Activities** (`settings.live-activities`) | Lesson / exam-day Live Activity switches, Start automatically. | secondary · en | [light](screens/7-settings/settings.live-activities_secondary-light.png) | [dark](screens/7-settings/settings.live-activities_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.live-activities_secondary-ax-xxxl-text.png) |
| **Notification permission explainer** (`reminders.permission`) | Shown in context before iOS asks for notification permission. | secondary · en | [light](screens/7-settings/reminders.permission_secondary-light.png) | [dark](screens/7-settings/reminders.permission_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/reminders.permission_secondary-ax-xxxl-text.png) |

## Widgets & Live Activities

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Now & Next widget** (`widgets.gallery`) | DEBUG gallery: Home Screen small/medium + Lock Screen families (during a lesson, in a break). | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery_secondary-dark.png) | — |
| **Now & Next widget** (`widgets.gallery`) | DEBUG gallery: Home Screen small/medium + Lock Screen families (during a lesson, in a break). | secondary · sk | [light](screens/8-widgets-live-activities/widgets.gallery_secondary_sk-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery_secondary_sk-dark.png) | — |
| **Now & Next — evening/holiday** (`widgets.gallery-evening`) | After school and holiday states. | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-evening_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-evening_secondary-dark.png) | — |
| **Pro / unavailable states** (`widgets.gallery-pro`) | Free-tier 'Available in Tabula Pro' and 'Open Tabula' states. | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-pro_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-pro_secondary-dark.png) | — |
| **Today widget** (`widgets.gallery-today`) | Medium/large. | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-today_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-today_secondary-dark.png) | — |
| **Homework widget** (`widgets.gallery-homework`) | Small/medium/large. | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-homework_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-homework_secondary-dark.png) | — |
| **Homework widget** (`widgets.gallery-homework`) | Small/medium/large. | secondary · sk | [light](screens/8-widgets-live-activities/widgets.gallery-homework_secondary_sk-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-homework_secondary_sk-dark.png) | — |
| **Next exam widget** (`widgets.gallery-exam`) | Small + Lock Screen. | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-exam_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-exam_secondary-dark.png) | — |
| **Lesson Live Activity** (`widgets.gallery-live`) | Lock Screen + Dynamic Island (approximation). | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-live_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-live_secondary-dark.png) | — |
| **Exam-day Live Activity** (`widgets.gallery-live-exam`) | Lock Screen + Dynamic Island (approximation). | secondary · en | [light](screens/8-widgets-live-activities/widgets.gallery-live-exam_secondary-light.png) | [dark](screens/8-widgets-live-activities/widgets.gallery-live-exam_secondary-dark.png) | — |

## Other

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **debug.design** (`debug.design`) |  | secondary · en | [light](screens/9-other/debug.design_secondary-light.png) | [dark](screens/9-other/debug.design_secondary-dark.png) | [ax-xxxl-text](screens/9-other/debug.design_secondary-ax-xxxl-text.png) |

---
182 screenshots in 64 screen/seed/language combinations. Regenerate: `python3 scripts/ux-review-index.py <downloaded artifacts dir>`.

Unrecognised files: watch-Apple_Watch_Series_12__46mm_.png
