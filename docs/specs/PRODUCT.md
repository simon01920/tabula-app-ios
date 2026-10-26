# PRODUCT — Tabula

Working name **Tabula** (Latin "table/tablet"; reads as timetable in most European languages). App Store name availability and EUIPO/USPTO trademark checks are a human to-do; fallbacks: Horarium, Periodo.

## Vision
One app for the whole school day: timetable, homework, assignments, exams, reminders — on iPhone, widgets and Apple Watch. "Best of everything": the flexibility of a customisable grid, the polish of the best-looking apps, and a planner that is part of the product, not bolted on.

## Onboarding (drives everything)
Goal: ask the minimum, then pre-configure tiles, fields, grid and reminders. Everything is changeable later in Settings; nothing is locked by the onboarding choice.

Steps:
1. **Language** (defaults to device language if supported).
2. **Who are you?** Elementary school · Secondary/High school · University/College · Other (custom).
3. **Rotation:** "Does your schedule change between weeks/days?" → None · Day A/B · Odd/Even weeks · N-week cycle (2–6) · Different per semester. Ask for term/semester dates if applicable (skippable).
4. **Time structure:** Fixed bell schedule (editable periods) or free-form times. Preset by profile (below).
5. **Fields to show:** Room · Building/Faculty · Teacher · Lesson type (lecture/seminar/lab) · Notes · "Bring" list. Preset by profile; each toggleable.
6. **Reminders:** which kinds to turn on (homework, exams, lessons) and when; explain delivery tiers (standard / time sensitive / loud alarm) with honest Focus and silent-switch guidance. Permissions are requested in context, not all at once.
7. **Start:** Import from photo · Import via QR/code · Start blank · Use sample data.

### Profile presets
| | Elementary | Secondary | University | Other |
|---|---|---|---|---|
| Time structure | Bell schedule, 45-min periods | Bell schedule, 45-min periods | Free-form, 90-min default blocks | Ask |
| Fields on | Room, Teacher, Bring | Room, Teacher, Notes | Building/Faculty, Room, Teacher, Type, Notes | All off |
| Rotation prompt | Light | Yes | Yes + semester range + odd/even | Ask |
| Default view | Big vertical tiles | Grid | Week time-blocks | Grid |
| Exams | Simple | Prominent | Prominent + exam period | Simple |
| Terminology | Lesson | Lesson | Class/Lecture | Lesson |
Presets are data in `TimetableCore` (testable), not hard-coded in views.

## Timetable
- Multiple timetables ("School", "Sport", "College"), each with own days, grid, theme, fields.
- Subjects: name, unique colour, optional emoji/icon, optional short name for grid cells.
- Lessons: subject, slot (period or start/end), room, building/faculty, teacher, type, notes, bring-list.
- Field rule: disabled → hidden in summaries (cards, lesson detail, widgets). Editors always offer every optional field under "More details", and changing the setting never deletes a value (UX overhaul decision D10, 2026-10-23, `docs/specs/UX_OVERHAUL_PLAN.md`; it replaced "hidden everywhere, including editor"). Enabled but empty → absent from read-only views; no placeholders, dashes or blank lines.
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
