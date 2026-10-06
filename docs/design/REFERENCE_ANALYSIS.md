# Reference screenshot analysis (input for Phase 2 UI planning)

Source: 18 competitor/reference screenshots supplied by the human (`examples/`, 2026-10-04).
Purpose: extract patterns worth adopting, anti-patterns to avoid, and **scope differences vs our specs** (flagged, not silently adopted).
Status: analysis only — no UI decisions are final until the Phase 2 plan is approved.

## 1. What each reference shows

| # | File (examples/) | What it shows | Most useful idea |
|---|---|---|---|
| 1 | IMG_3251 | Day view of **vertical colour tiles** (period badge, room + teacher, clock + time range), week strip Mo–Fr with selected-day pill and **task dots** under days, time gutter, tab bar (Schedule / Assignments / Settings) + floating "+" | Our "Big vertical tiles" view for elementary; week strip with dots |
| 2 | IMG_3252 | Widgets: large **Now card with "41 min 32 sec left" + Now pill**, Next list, Tomorrow list, "3 more…"; small Today; small **Next with "Bring: spikes, water"**; medium Now + Tomorrow | Now & Next widget set; bring-list surfacing |
| 3 | IMG_3253 | (Dark, iOS 26 glass header) **Share sheet: QR + 8-char code + Copy**, "Synchronization ★" and "Include tasks" toggles; 7-day week strip | Almost exactly our SHARING.md flow |
| 4 | IMG_3254 | Pastel **proportional time-block grid** (start time top, end time bottom, subject centred); bottom bar with `< College >` timetable switcher + "+" | Weekly time-block view; timetable switcher |
| 5 | IMG_3255 | **Timetables manager**: per timetable Days toggles, "Reset day", Theme picker, Delete | Multiple timetables management screen |
| 6 | IMG_3256 | **Wallpaper themes** with translucent cells | Themes with legibility protection |
| 7 | msedge_4Jend… | Calendar app: List/Day/Week/Month/Planner switcher, colour naming ("Family") | **Named colours** (also an accessibility win) |
| 8 | msedge_antjt… | Dark landscape week; editor with colour grid, **"Which weeks? 1 2 3 4"**, day chips, start/end, reminder toggle; Room/Professor/Notes; lesson rows showing **"Assignment – Sun, Dec 16" / "Midterm Exam – Sat, Dec 8" inline** | N-week rotation in editor; tasks/exams badges on lessons |
| 9 | msedge_cyFDR… | Schedule / Bell schedule / Timer; numbered list with countdown chip; period×day grid; **countdown ring "Time until class ends"**; homework cards with attachment counts | Now & Next countdown ring; bell-schedule screen |
| 10 | msedge_Dhf7q… | Planner: lesson cards with **"4 tasks"** badge, "In Person" tag; Tasks Today/Upcoming/Completed; Exams Upcoming/Completed by date; task + exam widgets | Task-count badge on lessons; exams tab layout |
| 11 | msedge_GGtK3… | General calendar: month chips, week columns, day planner + Today tasks sheet, To-do with Overdue/Today | Overdue section pattern |
| 12 | msedge_HcaFm… | **Periods as columns × days as rows** (landscape-friendly), lunch band; assignments grouped by subject; share as image; **"Select subject" sheet for a tapped cell** (Thursday · Period 3) | Fastest data entry: tap a cell → pick subject |
| 13 | msedge_htbWf… | Dense period grid; Edit class: colour, **time-slot chips (Mon 2, Tue 1…)**, **multi-select time-slot grid**, room; timetable picker; large grid widget | Multi-select slot assignment |
| 14 | msedge_lGrFH… | Numbered colour list w/ countdown; homework by day with **subject-coloured completion circles**; **statistics donut** (time per subject); event editor with links/files/reminder offset | Completion circles; statistics (see §4) |
| 15 | msedge_SIv75… | **Lock-screen timetable wallpaper**; builder; theme settings (background, header colour, grid lines, first day of week, weekdays, start/end hour, 12/24h); multiple schedules | Wallpaper export (see §4) |
| 16 | msedge_V1mim… | Horizontal **day pager** with colour rows + "Now" badge; tasks; widget gallery; **colour packs with 3 shades** (Classic/Sunset/Ocean/Pro); subject editor | Palette packs |
| 17 | msedge_WRM1K… | AI timetable **generator**, student/admin modes, teacher constraints | **Out of scope** (we import, we don't generate) |
| 18 | msedge_xMsPn… | Dark planner: agenda with Overdue, week time-blocks with **current-time line**, widgets, "2 of 5 completed" progress, month with dots + day agenda | Current-time indicator; progress summary |

## 2. Patterns to adopt (mapped to specs)

| Pattern | Refs | Spec hook | Note |
|---|---|---|---|
| Vertical colour tiles for the day | 1, 16 | PRODUCT › Views (tiles = elementary default) | Period badge + time range + only enabled, non-empty fields |
| Week strip with selected-day pill and dots for tasks/exams | 1, 3, 10, 18 | PRODUCT › Views | Dots need a VoiceOver summary ("2 tasks, 1 exam") |
| Now & Next with live countdown (ring + "x min left") | 2, 9, 14 | PRODUCT › Agenda/Now & Next; Widgets | `Text(timerInterval:)`, never per-second timelines |
| Current-time line in time-block view | 18 | PRODUCT › weekly time-block | Respect Reduce Motion |
| Breaks/lunch as visual bands | 1, 12 | Bell schedule model | Breaks are slots without lessons, still rendered |
| Tap empty cell → "Select subject" sheet; multi-select slots | 12, 13 | PRODUCT › editors | **Biggest UX lever**: entering a full week must take < 3 min |
| Lesson shows due tasks/exams inline ("4 tasks", "Exam – Fri") | 8, 10 | PRODUCT › Tasks/Exams | Badge must not appear when count is 0 (field rule spirit) |
| Bring list surfaced on Next widget / "Pack tonight" | 2 | PRODUCT › Extra features | Already in spec |
| QR + 8-char code + Copy + "Include tasks" | 3 | SHARING.md | Matches spec; code alphabet already excludes 0/O/1/I/L |
| Timetable switcher + timetables manager (days, reset day, theme) | 4, 5 | PRODUCT › Multiple timetables | |
| Palette packs with shades; named colours | 7, 16 | PRODUCT › Themes | Colour names double as accessibility labels |
| Wallpaper themes with translucent cells | 6 | PRODUCT › Themes (legibility protection) | Needs automatic scrim/contrast check |
| Subject-coloured completion circles | 14 | PRODUCT › Tasks | Never colour-only: add checkmark + strikethrough |
| N-week rotation chooser in lesson editor ("Which weeks? 1 2 3 4") | 8 | PRODUCT › Rotation | Only shown if rotation ≠ None |
| Overdue section first | 11, 18 | PRODUCT › Tasks tabs | |
| Standard iOS 26 glass toolbars/tab bar | 3 | PRODUCT › Themes (Liquid Glass via standard controls) | Ref 3 already shows the iOS 26 grouped glass header buttons |

## 3. Anti-patterns to avoid

1. **Low-contrast text on saturated or pastel tiles** (white on yellow "Lunch" in ref 1; coloured text on pastel in refs 4/13). → Text colour chosen by a contrast function in `TimetableCore` (WCAG 2.x contrast ratio ≥ 4.5:1 for body text), user colour preserved for the tile.
2. **Decorative diagonal stripes** behind text (ref 1) reduce legibility → optional at most, off with Increase Contrast.
3. **Truncation of key info** ("Track p…", ref 2) → user short names + per-script smart truncation (LOCALIZATION.md).
4. **Ambiguous US-only times** ("12:11 – 1:01" without AM/PM, ref 2) → locale formatters, user 12/24h override.
5. **Tiny dense grids** (refs 13, 17) at default Dynamic Type → adaptive layout; grid switches to list at accessibility sizes.
6. **Colour as the only carrier of meaning** (refs 14, 18) → icons/labels/shape as well.
7. **Landscape-only week view** (ref 8) → portrait-capable, landscape optional.
8. Paywall markers that hide what's free (ref 3 "★") → OK as a hint only with an honest explanation sheet (MONETIZATION.md).

## 4. Scope differences vs specs — NOT adopted, decisions for the human

| Seen in | Feature | Spec status | Recommendation |
|---|---|---|---|
| 3 | **"Synchronization"** of a shared timetable (live updates from the sharer) | Not in SHARING.md (share is one-shot) | Defer to post-v1; needs a server-side update channel |
| 14 | **Statistics** (time per subject donut) | Listed under Pro in PRODUCT.md but **no spec exists** | Human: keep in Pro? If yes, a short spec is needed before Phase 10 |
| 15 | **Lock-screen wallpaper export** of the timetable | Not in spec | Cheap add-on to Phase 8 image export (a "wallpaper" size preset); decide at Phase 8 plan |
| 7 | Weather, video-conference links | Not in spec | Skip |
| 17 | Timetable **generation**, admin/teacher modes | Not in spec | Out of scope |
| 9, 12 | Grades/GPA directory | Explicitly excluded in v1 | Keep excluded (data model stays open) |

## 5. Navigation sketch to evaluate in the Phase 2 plan (proposal, not decided)

Tab bar (iOS 26 standard `TabView`, Liquid Glass): **Today** (Now & Next header with countdown + day tiles) · **Timetable** (selected view: grid / time-block / tiles, week strip, `< timetable >` switcher) · **Tasks** (Overdue / Today / Upcoming / Completed) · **Exams** (upcoming prominent, history) · **Settings**. Floating/primary "+" context-aware (lesson in Timetable, task in Tasks, exam in Exams). PRODUCT.md requires a dedicated Exams tab, so five tabs; the alternative "Planner" tab with Tasks/Exams segments is noted for discussion.
