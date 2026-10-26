# PRODUCT — Tabula

Working name **Tabula** (Latin "table/tablet"; reads as timetable in most European languages). App Store name availability and EUIPO/USPTO trademark checks are a human to-do; fallbacks: Horarium, Periodo.

## Vision
One app for the whole school day: timetable, homework, assignments, exams, reminders — on iPhone, widgets and Apple Watch. "Best of everything": the flexibility of a customisable grid, the polish of the best-looking apps, and a planner that is part of the product, not bolted on.

## Onboarding (drives everything)
Goal: ask the minimum, then pre-configure tiles, fields, grid and reminders. Everything is changeable later in Settings; nothing is locked by the onboarding choice.

Steps (Phase 4U U6, UX_OVERHAUL_PLAN D8: 7 steps became 4; back = the standard navigation back chevron, one full-width primary button at the bottom):
1. **Welcome · School type.** "Choose your school type": Elementary school · Secondary/High school · University/College · Other, with the product line "Your classes, tasks, and exams in one place." A compact row "App language: English · Change" opens iOS Settings (the app uses the device language by default); the chosen school type survives the relaunch iOS does after a per-app language change.
2. **How do you want to start?** "Set up my timetable" (primary, preselected) · "Just look around": creates the school type's sample timetable and opens the app with a dismissible banner "This is sample data · Remove". Remove deletes only that sample timetable with its children and the sample task/exam (tracked device-locally, outside the synced data); everything the user created stays (their tasks/exams only lose links to the sample). Import from photo / QR is hidden until it works.
3. **Your week.** School days as chips (in the locale's week order); "How does your timetable repeat?" → Same every week · Alternating weeks (A/B) · Alternating days (A/B) · Custom cycle (3–6 weeks). Alternating weeks ask "Which week is this week?" (A or B) and offer "Follow calendar odd/even weeks" explicitly; alternating days ask which day the next school day is; a custom cycle asks which week this week is. Term/semester dates are a separate, optional toggle available with every pattern ("Different per semester" is not a rotation: lessons can be limited to terms in the lesson editor).
4. **Lesson times.** "Fixed lesson periods" (use the same lesson times each day; generator + live preview) or "Individual start and end times" (default length). Steppers plus direct number entry; "I'll do this later" finishes with the suggested times. The last button reads "Start Using Tabula".

Not asked any more (defaults from the profile, changeable later): **fields to show** (the preset's "Fields on"; editors always offer every field) and **reminders** (the preset rules with their default switches: homework and exams on for every profile; notification permission is requested in context, the first time a reminder has something to deliver; delivery tiers are explained in Settings → Reminders).

### Profile presets
| | Elementary | Secondary | University | Other |
|---|---|---|---|---|
| Time structure | Bell schedule, 45-min periods | Bell schedule, 45-min periods | Free-form, 90-min default blocks | Ask |
| Fields on | Room, Teacher, Bring | Room, Teacher, Notes | Building/Faculty, Room, Teacher, Type, Notes | Room, Teacher |
| Rotation prompt | Light | Yes | Yes + semester range + odd/even | Ask |
| Default view | Big vertical tiles | Grid | Week time-blocks | Grid |
| Exams | Simple | Prominent | Prominent + exam period | Simple |
| Terminology | Lesson | Lesson | Class/Lecture | Lesson |
Presets are data in `TimetableCore` (testable), not hard-coded in views.

## Timetable
- Multiple timetables ("School", "Sport", "College"), each with own days, grid, theme, fields.
- Subjects: name, unique colour, optional emoji/icon, optional short name for grid cells.
- Lessons: subject, slot (period or start/end), room, building/faculty, teacher, type, notes, bring-list.
- Field rule: disabled → hidden everywhere (including editor). Enabled but empty → absent from the UI; no placeholders, dashes or blank lines.
- Per-day overrides (e.g. short Friday); one-off overrides (substitution, cancellation, room change); term ranges; holidays/breaks; rotation resolution; conflict warnings (warn, never block).

## Views (selectable per timetable, remembered)
Classic grid (periods × days) · weekly time-block (proportional, landscape layout) · daily · vertical tiles · Agenda/Now & Next with live countdown ring · density compact/comfortable · 5/6/7-day week · week start day · 12/24h.

## Tasks (homework, assignments, to-dos)
Title, subject link, due date/time, priority levels (low/normal/high/urgent), notes, **attachments** (photos, files, links, voice notes), **subtasks**, repeat, completion. Tabs: Today / Upcoming / Overdue / Completed; filter by subject; sort by due/priority. Quick-add from app, widget, Watch, App Intents/Siri. No GPA/grade tracking in v1 (an optional simple average per subject may come later; keep data model open).

## Exams
Dedicated tab: upcoming prominent with date/time, subject, room, topics, countdown and escalating colour; history for past exams; reminder ladders (user-chosen); exam period view for universities.

## Widgets / Live Activity / Watch
See ROADMAP phases 4–5. Widgets: small, medium, large, Lock Screen (circular/rectangular/inline), StandBy; Today, Now & Next with live remaining time, upcoming homework, next exam countdown; configurable through App Intents. Live Activity for current lesson. Watch: today/tomorrow, current lesson remaining time, next lesson, complication/Smart Stack; offline cache. Current-lesson remaining time also in the iPhone Today/Now header.

## Themes
Palette packs, per-subject colours, light/dark/auto, optional wallpaper background with legibility protection, alternate app icons later. Use standard SwiftUI controls so iOS 26 Liquid Glass applies naturally.

## Sharing / Export / AI import
See SHARING.md, AI_IMPORT.md. Export: image (grid/week/day, themed), PDF, CSV, XLSX (decide library vs minimal writer in the phase plan), `.ics`; user chooses type and view.

## Extra features (all wanted for v1 scope, scheduled across phases)
Live Activity/Dynamic Island · Lock Screen & StandBy widgets · Focus filter (auto-silence during lessons) · App Intents/Shortcuts/Siri ("What's next?") · one-off overrides · "Pack tonight" reminder from the bring-list · free-period planner (suggest homework for gaps) · attachments · `.ics`/Apple Calendar export · term and holiday ranges · Watch complication · localisation in 12 languages · iPad layout (stretch, after v1 core).

## Free vs Pro (proposal — configurable behind `Entitlements`)
Free: 1 timetable, grid/day/tile views, tasks (subtasks, priorities), exams, standard + Time Sensitive reminders, small/medium widgets, iCloud sync, QR/code share and import.
Pro: unlimited timetables, all widget sizes + Lock Screen + Live Activity, Watch app, loud alarm reminders, AI import, exports (image/PDF/CSV/XLSX/ICS), wallpapers/theme packs, extra attachment capacity, statistics.
See MONETIZATION.md.
