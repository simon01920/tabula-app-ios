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
| **Welcome** (`onboarding`) | First launch, step 1 of 7: welcome + language (uses the iPhone language, link to per-app language). | empty · en | [light](screens/1-onboarding/onboarding_empty-light.png) | [dark](screens/1-onboarding/onboarding_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding_empty-ax-xxxl-text.png) |
| **Start** (`onboarding.start`) | Last onboarding step: import from photo / QR (coming soon), start blank, sample data. | empty · en | [light](screens/1-onboarding/onboarding.start_empty-light.png) | [dark](screens/1-onboarding/onboarding.start_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.start_empty-ax-xxxl-text.png) |
| **Who are you?** (`onboarding.profile`) | Profile: elementary / secondary / university / other; drives presets. | empty · en | [light](screens/1-onboarding/onboarding.profile_empty-light.png) | [dark](screens/1-onboarding/onboarding.profile_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.profile_empty-ax-xxxl-text.png) |
| **Who are you?** (`onboarding.profile`) | Profile: elementary / secondary / university / other; drives presets. | empty · sk | [light](screens/1-onboarding/onboarding.profile_empty_sk-light.png) | [dark](screens/1-onboarding/onboarding.profile_empty_sk-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.profile_empty_sk-ax-xxxl-text.png) |
| **Rotation** (`onboarding.rotation`) | Does the schedule change between weeks (A/B, odd/even, N-week cycle)? | empty · en | [light](screens/1-onboarding/onboarding.rotation_empty-light.png) | [dark](screens/1-onboarding/onboarding.rotation_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.rotation_empty-ax-xxxl-text.png) |
| **Time structure** (`onboarding.time`) | Bell schedule vs free-form times. | empty · en | [light](screens/1-onboarding/onboarding.time_empty-light.png) | [dark](screens/1-onboarding/onboarding.time_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.time_empty-ax-xxxl-text.png) |
| **Fields to show** (`onboarding.fields`) | Room, building, teacher, type, notes, bring list. | empty · en | [light](screens/1-onboarding/onboarding.fields_empty-light.png) | [dark](screens/1-onboarding/onboarding.fields_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.fields_empty-ax-xxxl-text.png) |
| **Reminders** (`onboarding.reminders`) | Which reminder kinds to turn on; delivery tiers explained. | empty · en | [light](screens/1-onboarding/onboarding.reminders_empty-light.png) | [dark](screens/1-onboarding/onboarding.reminders_empty-dark.png) | [ax-xxxl-text](screens/1-onboarding/onboarding.reminders_empty-ax-xxxl-text.png) |

## Today

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Today** (`today`) | Tab 1. Now/next lesson with time left, today's lessons, due tasks, next exam. | elementary · en | [light](screens/2-today/today_elementary-light.png) | [dark](screens/2-today/today_elementary-dark.png) | [ax-xxxl-text](screens/2-today/today_elementary-ax-xxxl-text.png) |
| **Today** (`today`) | Tab 1. Now/next lesson with time left, today's lessons, due tasks, next exam. | secondary · en | [light](screens/2-today/today_secondary-light.png) | [dark](screens/2-today/today_secondary-dark.png) | [ax-xxxl-text](screens/2-today/today_secondary-ax-xxxl-text.png) |
| **Today** (`today`) | Tab 1. Now/next lesson with time left, today's lessons, due tasks, next exam. | secondary · sk | [light](screens/2-today/today_secondary_sk-light.png) | [dark](screens/2-today/today_secondary_sk-dark.png) | [ax-xxxl-text](screens/2-today/today_secondary_sk-ax-xxxl-text.png) |
| **Today** (`today`) | Tab 1. Now/next lesson with time left, today's lessons, due tasks, next exam. | university · en | [light](screens/2-today/today_university-light.png) | [dark](screens/2-today/today_university-dark.png) | [ax-xxxl-text](screens/2-today/today_university-ax-xxxl-text.png) |

## Timetable

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Timetable (default view)** (`timetable`) | Tab 2, in the profile's default view. | secondary · en | [light](screens/3-timetable/timetable_secondary-light.png) | [dark](screens/3-timetable/timetable_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable_secondary-ax-xxxl-text.png) |
| **Grid view** (`timetable.grid`) | Week grid (periods x days) with change/cancel markers and task/exam badges. | secondary · en | [light](screens/3-timetable/timetable.grid_secondary-light.png) | [dark](screens/3-timetable/timetable.grid_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.grid_secondary-ax-xxxl-text.png) |
| **Grid view** (`timetable.grid`) | Week grid (periods x days) with change/cancel markers and task/exam badges. | secondary · sk | [light](screens/3-timetable/timetable.grid_secondary_sk-light.png) | [dark](screens/3-timetable/timetable.grid_secondary_sk-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.grid_secondary_sk-ax-xxxl-text.png) |
| **Week time-blocks** (`timetable.week`) | Proportional week view (university default). | university · en | [light](screens/3-timetable/timetable.week_university-light.png) | [dark](screens/3-timetable/timetable.week_university-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.week_university-ax-xxxl-text.png) |
| **Day view** (`timetable.day`) | One day, proportional time blocks. | secondary · en | [light](screens/3-timetable/timetable.day_secondary-light.png) | [dark](screens/3-timetable/timetable.day_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.day_secondary-ax-xxxl-text.png) |
| **Tiles view** (`timetable.tiles`) | Big vertical tiles (elementary default). | elementary · en | [light](screens/3-timetable/timetable.tiles_elementary-light.png) | [dark](screens/3-timetable/timetable.tiles_elementary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.tiles_elementary-ax-xxxl-text.png) |
| **Lesson detail** (`timetable.lesson-detail`) | Tap a lesson: time, room, teacher, homework for this lesson, changes on this day. | secondary · en | [light](screens/3-timetable/timetable.lesson-detail_secondary-light.png) | [dark](screens/3-timetable/timetable.lesson-detail_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.lesson-detail_secondary-ax-xxxl-text.png) |
| **Quick add** (`timetable.quick-add`) | Fast add of a lesson from the timetable. | secondary · en | [light](screens/3-timetable/timetable.quick-add_secondary-light.png) | [dark](screens/3-timetable/timetable.quick-add_secondary-dark.png) | [ax-xxxl-text](screens/3-timetable/timetable.quick-add_secondary-ax-xxxl-text.png) |

## Editors

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Timetables manager** (`editor.timetables`) | Settings/Timetable: list of timetables (multiple allowed). | secondary · en | [light](screens/4-editors/editor.timetables_secondary-light.png) | [dark](screens/4-editors/editor.timetables_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.timetables_secondary-ax-xxxl-text.png) |
| **Timetable editor** (`editor.timetable`) | Name, rotation, term dates, time zone. | secondary · en | [light](screens/4-editors/editor.timetable_secondary-light.png) | [dark](screens/4-editors/editor.timetable_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.timetable_secondary-ax-xxxl-text.png) |
| **Subjects list** (`editor.subjects`) | All subjects; Reorder mode (new in Phase 4). | secondary · en | [light](screens/4-editors/editor.subjects_secondary-light.png) | [dark](screens/4-editors/editor.subjects_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.subjects_secondary-ax-xxxl-text.png) |
| **Subject editor** (`editor.subject`) | Name, colour, emoji/icon, teacher, room. | secondary · en | [light](screens/4-editors/editor.subject_secondary-light.png) | [dark](screens/4-editors/editor.subject_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.subject_secondary-ax-xxxl-text.png) |
| **Lesson editor** (`editor.lesson`) | Edit an existing lesson (day, period/time, room, week A/B...). | secondary · en | [light](screens/4-editors/editor.lesson_secondary-light.png) | [dark](screens/4-editors/editor.lesson_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.lesson_secondary-ax-xxxl-text.png) |
| **New lesson** (`editor.lesson-new`) | Same editor, empty. | secondary · en | [light](screens/4-editors/editor.lesson-new_secondary-light.png) | [dark](screens/4-editors/editor.lesson-new_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.lesson-new_secondary-ax-xxxl-text.png) |
| **Bell schedule** (`editor.bell`) | Periods and break lengths; variants. | secondary · en | [light](screens/4-editors/editor.bell_secondary-light.png) | [dark](screens/4-editors/editor.bell_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.bell_secondary-ax-xxxl-text.png) |
| **Terms & holidays** (`editor.terms`) | School year, semesters, breaks, exam periods. | secondary · en | [light](screens/4-editors/editor.terms_secondary-light.png) | [dark](screens/4-editors/editor.terms_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.terms_secondary-ax-xxxl-text.png) |
| **Change for one day** (`editor.day-change`) | One-off override: cancel / move / substitute / room change. | secondary · en | [light](screens/4-editors/editor.day-change_secondary-light.png) | [dark](screens/4-editors/editor.day-change_secondary-dark.png) | [ax-xxxl-text](screens/4-editors/editor.day-change_secondary-ax-xxxl-text.png) |

## Tasks

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Tasks — Today** (`tasks`) | Tab 3. Segments Today / Upcoming / Overdue / Completed, quick add. | secondary · en | [light](screens/5-tasks/tasks_secondary-light.png) | [dark](screens/5-tasks/tasks_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks_secondary-ax-xxxl-text.png) |
| **Tasks — Today** (`tasks`) | Tab 3. Segments Today / Upcoming / Overdue / Completed, quick add. | secondary · sk | [light](screens/5-tasks/tasks_secondary_sk-light.png) | [dark](screens/5-tasks/tasks_secondary_sk-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks_secondary_sk-ax-xxxl-text.png) |
| **Tasks — Upcoming** (`tasks.upcoming`) | Upcoming segment. | secondary · en | [light](screens/5-tasks/tasks.upcoming_secondary-light.png) | [dark](screens/5-tasks/tasks.upcoming_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.upcoming_secondary-ax-xxxl-text.png) |
| **Tasks — Overdue** (`tasks.overdue`) | Overdue segment. | secondary · en | [light](screens/5-tasks/tasks.overdue_secondary-light.png) | [dark](screens/5-tasks/tasks.overdue_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.overdue_secondary-ax-xxxl-text.png) |
| **Tasks — Completed** (`tasks.completed`) | Completed segment. | secondary · en | [light](screens/5-tasks/tasks.completed_secondary-light.png) | [dark](screens/5-tasks/tasks.completed_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.completed_secondary-ax-xxxl-text.png) |
| **Task detail** (`tasks.detail`) | Tap a task: type, due, repeat, notes, subtasks, attachments. | secondary · en | [light](screens/5-tasks/tasks.detail_secondary-light.png) | [dark](screens/5-tasks/tasks.detail_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.detail_secondary-ax-xxxl-text.png) |
| **Task editor** (`tasks.editor`) | Edit a task (title, kind, subject, due incl. 'next lesson', priority, subtasks, repeat, reminder, attachments). | secondary · en | [light](screens/5-tasks/tasks.editor_secondary-light.png) | [dark](screens/5-tasks/tasks.editor_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.editor_secondary-ax-xxxl-text.png) |
| **New task** (`tasks.editor-new`) | Same editor, empty. | secondary · en | [light](screens/5-tasks/tasks.editor-new_secondary-light.png) | [dark](screens/5-tasks/tasks.editor-new_secondary-dark.png) | [ax-xxxl-text](screens/5-tasks/tasks.editor-new_secondary-ax-xxxl-text.png) |

## Exams

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | secondary · de | [light](screens/6-exams/exams_secondary_de-light.png) | [dark](screens/6-exams/exams_secondary_de-dark.png) | [ax-xxxl-text](screens/6-exams/exams_secondary_de-ax-xxxl-text.png) |
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | secondary · en | [light](screens/6-exams/exams_secondary-light.png) | [dark](screens/6-exams/exams_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams_secondary-ax-xxxl-text.png) |
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | secondary · sk | [light](screens/6-exams/exams_secondary_sk-light.png) | [dark](screens/6-exams/exams_secondary_sk-dark.png) | [ax-xxxl-text](screens/6-exams/exams_secondary_sk-ax-xxxl-text.png) |
| **Exams — Upcoming** (`exams`) | Tab 4. Prominent next exam with countdown; exam period (university). | university · en | [light](screens/6-exams/exams_university-light.png) | [dark](screens/6-exams/exams_university-dark.png) | [ax-xxxl-text](screens/6-exams/exams_university-ax-xxxl-text.png) |
| **Exams — History** (`exams.history`) | Past exams. | secondary · en | [light](screens/6-exams/exams.history_secondary-light.png) | [dark](screens/6-exams/exams.history_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams.history_secondary-ax-xxxl-text.png) |
| **Exam detail** (`exams.detail`) | Tap an exam. | secondary · en | [light](screens/6-exams/exams.detail_secondary-light.png) | [dark](screens/6-exams/exams.detail_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams.detail_secondary-ax-xxxl-text.png) |
| **Exam editor** (`exams.editor`) | Kind, date, times, room/building, topics, reminder. | secondary · en | [light](screens/6-exams/exams.editor_secondary-light.png) | [dark](screens/6-exams/exams.editor_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams.editor_secondary-ax-xxxl-text.png) |
| **New exam** (`exams.editor-new`) | Same editor, empty. | secondary · en | [light](screens/6-exams/exams.editor-new_secondary-light.png) | [dark](screens/6-exams/exams.editor-new_secondary-dark.png) | [ax-xxxl-text](screens/6-exams/exams.editor-new_secondary-ax-xxxl-text.png) |

## Settings

| Screen | What it is / how to reach it | Seed · language | Light | Dark | Largest text |
|---|---|---|---|---|---|
| **Settings** (`settings`) | Tab 5. Root list. | secondary · en | [light](screens/7-settings/settings_secondary-light.png) | [dark](screens/7-settings/settings_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings_secondary-ax-xxxl-text.png) |
| **Settings** (`settings`) | Tab 5. Root list. | secondary · sk | [light](screens/7-settings/settings_secondary_sk-light.png) | [dark](screens/7-settings/settings_secondary_sk-dark.png) | [ax-xxxl-text](screens/7-settings/settings_secondary_sk-ax-xxxl-text.png) |
| **Appearance** (`settings.appearance`) | Mode (system/light/dark), colour palette packs (Ocean/Sunset/Pastel are Pro), colours in the palette. | secondary · en | [light](screens/7-settings/settings.appearance_secondary-light.png) | [dark](screens/7-settings/settings.appearance_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.appearance_secondary-ax-xxxl-text.png) |
| **Calendar & time** (`settings.calendar`) | Week start, 12/24-hour format, time zone (follow device or fixed). | secondary · en | [light](screens/7-settings/settings.calendar_secondary-light.png) | [dark](screens/7-settings/settings.calendar_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.calendar_secondary-ax-xxxl-text.png) |
| **About** (`settings.about`) | About the app. | secondary · en | [light](screens/7-settings/settings.about_secondary-light.png) | [dark](screens/7-settings/settings.about_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.about_secondary-ax-xxxl-text.png) |
| **Reminders** (`settings.reminders`) | Per-kind reminder rules + health check entry. | secondary · en | [light](screens/7-settings/settings.reminders_secondary-light.png) | [dark](screens/7-settings/settings.reminders_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminders_secondary-ax-xxxl-text.png) |
| **Reminder rule** (`settings.reminder-rule`) | Offsets, follow-up, delivery tier (standard / time sensitive / loud alarm), quiet hours. | secondary · en | [light](screens/7-settings/settings.reminder-rule_secondary-light.png) | [dark](screens/7-settings/settings.reminder-rule_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminder-rule_secondary-ax-xxxl-text.png) |
| **Reminder health check** (`settings.reminder-health`) | Permissions, Focus, Low Power, background refresh, pending count, test buttons. | secondary · en | [light](screens/7-settings/settings.reminder-health_secondary-light.png) | [dark](screens/7-settings/settings.reminder-health_secondary-dark.png) | [ax-xxxl-text](screens/7-settings/settings.reminder-health_secondary-ax-xxxl-text.png) |
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

---
185 screenshots in 65 screen/seed/language combinations. Regenerate: `python3 scripts/ux-review-index.py <downloaded artifacts dir>`.
