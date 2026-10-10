# Phase 2 — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x). Until a device is available, run what is possible on the CI simulator
(`.github/workflows/ui-screenshots.yml`) and tick the rest later. Each stage appends its own section; keep the
format: **Setup → Steps → Expected**, plus the standard state matrix (empty, normal, long text, Dynamic Type XXL /
AX5, dark mode, German-length strings, CJK, VoiceOver).

Builds: local `bash scripts/xtool-dev.sh` (base variant, installs + launches) or a TestFlight/CI build. Launch
arguments (DEBUG builds only) via Xcode scheme / `xcrun simctl launch booted sk.simondev.tabula <args>`:
`-TabulaSeed empty|blank|elementary|secondary|university`, `-TabulaNow 2026-10-13T10:20:00+02:00` (or `live`),
`-TabulaTimeZone Europe/Bratislava`, `-TabulaScreen <route id>`, `-AppleLanguages "(de)"`. On a device without
Xcode, use **Settings → Developer** instead (sample data, onboarding reset, recovery tests).

---

## A. Foundation (Stage A — app shell, state, persistence, routing)

### A1. First launch → onboarding
- Setup: delete the app (or simulator: `-TabulaSeed empty`).
- Steps: launch.
- Expected: a short "Loading…" at most, then the welcome screen ("Welcome to Tabula", one "Get Started" button);
  **no** tab bar. No banner.
- Steps: tap **Get Started**.
- Expected: the tab bar appears (Today · Timetable · Settings) without relaunch; Today shows "No lessons today" with
  today's full date in the device language (no subjects exist yet).

### A2. Persistence across relaunch
- Steps: Settings → Appearance → **Dark**; wait 1 s; force-quit (app switcher); relaunch.
- Expected: still dark, tab bar shown directly (onboarding not repeated). Repeat with **Light** and **System**.
- Steps: change appearance, then immediately press Home (background) and force-quit within 1 s.
- Expected: the change survived (save is flushed when the scene leaves `active`).
- Settings → Developer → Store: "Last save" shows `saved(generation: n)`; "Data source" shows **App Group: …/Tabula**
  (if it shows "Application Support (fallback)" the App Group is not provisioned — free team / xtool #284: note it,
  widgets will not see the data).

### A3. Appearance
- Expected for each of System / Light / Dark: whole app follows (tab bar, lists, sheets), including the Developer
  screen. System follows Control Centre dark-mode toggling live.
- Tab bar: standard iOS 26 Liquid Glass look (no custom background).

### A4. Store banners (recovery / read-only) — Settings → Developer → "Recovery tests"
- Restore: make two changes (e.g. appearance twice, 1 s apart) so a backup exists → **Corrupt tabula.json** →
  force-quit → relaunch.
  Expected: banner at the top "Data restored from a backup" + explanation, icon + text, ✕ button (44 pt) dismisses
  it; data is the state from before the last change. Developer → Store shows the banner list empty after dismissing.
- Without backup (fresh install, one change only) → corrupt → relaunch.
  Expected: full-screen "Your data can't be opened" (no onboarding offered, nothing deleted). Recover by deleting the
  app (Phase 6 adds restore).
- Read-only: **Mark tabula.json as schema v99** → force-quit → relaunch.
  Expected: non-dismissible banner "Update Tabula to make changes" (lock icon); Settings → Appearance picker is
  disabled; data visible. Then **Set back to schema v1** → relaunch → banner gone, picker enabled.
- Banner layout: long German text wraps (no truncation), works at AX5 (scrolls the content below, not cut off), dark
  mode legible, VoiceOver reads title + message as one element and the ✕ as "Dismiss".

### A5. Launch routes (simulator / Xcode)
- `-TabulaSeed secondary -TabulaScreen today` → Today tab with 7 lessons of Tue 13 Oct 2026 (ISO week 42 = week B: Matematika, Chémia,
  SJL, Biológia, Nemecký jazyk, Geografia, Etická výchova) with times "8:00 – 8:45" style (24 h, scenario setting).
- `-TabulaScreen timetable` / `settings` → that tab selected. `-TabulaScreen onboarding` → welcome screen even with data.
- `-TabulaScreen debug` (and `debug-platform`, `debug-localization`, `debug-macros`, `debug-import`, `debug-alarms`,
  `debug-developer`) → standalone debug screens; "Launch route" row shows `requested "<id>" → <id>`.
- `-TabulaScreen nonsense` → normal app; Developer screen shows `UNKNOWN "nonsense" → app shell`.
- Release/TestFlight build with `-TabulaSeed secondary`: **ignored** (real data shown); no Settings → Developer row.

### A6. Foundation primitives on the Today placeholder (`-TabulaSeed elementary`, B2 replaces the screen)
- Expected on Tue 13 Oct: 5 lessons; *Výtvarná výchova* has badge "Room changed" (icon + text) and room "Knižnica";
  *Hudobná výchova* is struck through with badge "Cancelled".
- Subject badges: emoji on the subject colour; the yellow/pastel colours keep a visible edge in light mode,
  dark navy colours (ocean pack, via Developer sample data later) keep an edge in dark mode.
- Field rule: elementary shows only room, teacher, bring-list lines; a lesson without bring list shows **no empty line
  or dash**. `-TabulaSeed university`: building, room, teacher, lesson type ("Lecture"/"Seminar"/"Lab"); no notes line
  where notes are empty.
- VoiceOver on a lesson row reads one sentence, e.g. "Výtvarná výchova, period 4, 10:55 to 11:40, room Knižnica,
  teacher Mgr. Novotná, bring vodové farby, štetce, and obrus, changed: Room changed" (wording in the device language
  once translated).

### A7. Time zone, locale, 12/24 h
- Device set to 12-hour (Settings → General → Date & Time → 24-Hour Time off) with a fresh install (onboarding
  default `hourCycle auto`): times show "8:00 AM" style in en-US; Slovak region keeps 24 h.
- Change the device time zone while the app is open → Developer → "Time zone" updates without relaunch.
- Region with Sunday first (en-US) → Developer → "First weekday sunday"; Slovak → monday.
- `-TabulaSeed secondary` has `hourCycle h24`: always 24 h even on a 12 h device.

### A8. State matrix for the foundation screens (welcome, Today placeholder, Settings placeholder, banners, problem screen)
| State | How | Expected |
|---|---|---|
| Empty | `-TabulaSeed empty` / `blank` | welcome screen / "No lessons today" + date; no blank rows |
| Normal | `-TabulaSeed secondary` | list of lessons, badges |
| Long text | Developer → sample data, then (B3) rename a subject to 60+ chars | wraps, no truncation of the time line |
| Dynamic Type XXL / AX5 | Settings → Accessibility → Larger Text | every text scales; banner ✕ stays tappable; nothing clipped |
| Dark mode | Appearance Dark | all text legible; subject badge text black/white per contrast |
| German | `-AppleLanguages "(de)"` | strings fall back to English until stage C1 (expected now); layout holds long strings |
| CJK | `-AppleLanguages "(ja)"` | dates/times/weekday names in Japanese format (年月日, 時), list separator "、" after C1 |
| VoiceOver | VoiceOver on | tabs announced with names; lesson rows one element; banner text + Dismiss |

### A9. Not verifiable without a device / simulator run (open items)
- `@Observable` / macro-based `@State` runtime behaviour on the **xtool** build (OpenAppleMacros expansion at run time).
- Plural selection through `String(format:locale:arguments:)` with catalog plurals (`LocalizedTextRenderer`, Darwin path);
  Linux tests only cover positional substitution.
- `Locale.Components.hourCycle` forcing 12/24 h in `Date.FormatStyle` on iOS (verified only on Linux swift-foundation).
- `Locale.firstDayOfWeek` honouring the user's "First Day of Week" preference.
- App Group container availability on the xtool-signed build (free team → Application Support fallback).
- Liquid Glass tab bar appearance; `.bar` material banner under the status bar; sheet presentation for `.sheet` routes
  (no sheet route exists yet — B3).

---

## B2. Today + Timetable views (Stage B2)

Nothing in this section has been seen running: it compiles (xtool, 0 compiler warnings) and the view state is
Linux-tested (`TimetableViewStateTests`), but the UI itself is unverified. Reference instant of every seed:
Tue 2026-10-13 10:20 Europe/Bratislava (`-TabulaNow` default). Secondary seed: ISO week 42 = **Week B**; Thu 15 Oct
has a short day (30-min lessons), ANJ cancelled, MAT moved to "Aula" with a substitute teacher, an extra INF lesson;
holidays Thu 29 – Fri 30 Oct ("Jesenné prázdniny").

**CI screenshot routes (B2):** `today`, `timetable`, `timetable.grid`, `timetable.week`, `timetable.day`,
`timetable.tiles`, `timetable.lesson-detail`, `timetable.quick-add` with `-TabulaSeed secondary`, plus
`today@elementary`, `timetable@elementary` (opens in Tiles), `timetable.week@university`, `today@blank`,
`timetable.grid@blank`, and `today` with `-TabulaNow 2026-10-13T20:00:00+02:00` (day over),
`2026-10-17T11:00:00+02:00` (weekend), `2026-10-29T09:00:00+02:00` (holiday), `2026-10-13T06:30:00+02:00` (before
school). Light, dark, AX5, sk + de.

### B2.1 Today — Now & Next header
- Setup: `-TabulaSeed secondary -TabulaScreen today`.
- Expected: card with "● Now" pill, the lesson running at 10:20 with emoji badge, time range, room/teacher lines;
  "Time left" + big countdown (**paused** at the fixed clock), progress bar in the subject colour; divider; "Next" +
  next subject, time range, room. With `-TabulaNow live` on a school day the countdown ticks every second and the
  header switches to the next lesson at the exact end minute.
- `-TabulaNow 2026-10-13T06:30:00+02:00` → "First Lesson" + "Starts in" countdown (h:mm:ss).
- `…T20:00…` → "No more lessons today", "Next Lesson · Tomorrow, <time range>"; below today's tiles (all with a
  check mark) a "Tomorrow" section with Wednesday's lessons.
- `2026-10-17T11:00` (Saturday) → "No lessons today", next lesson "Mon 19 Oct, …"; section "Next School Day".
- `2026-10-29T09:00` → "Jesenné prázdniny" with "Holidays" under it; next lesson Mon 2 Nov.
- Cancelled day: create one with the day-change editor (B3) → "Lessons are cancelled today" + the note.
- `-TabulaSeed blank` → "No lessons yet" empty state (no header card, no dashes). No timetable → "No timetable yet".

### B2.2 Today — tiles
- Tiles in the subject colour; text black or white (never coloured text on colour); pastel tiles keep a hairline
  edge in light mode, dark ones in dark mode; Increase Contrast adds an outline to every tile.
- Current lesson has a 3-pt ring; past lessons a check mark (no dimming, so contrast is kept).
- Between lessons: "Break · 10 min" / "Lunch · 50 min" / "Free period · 1 hr, 35 min"; none before the first or after
  the last lesson; overlapping lessons get no separator.
- `-TabulaSeed elementary`: *Výtvarná výchova* badge "Room changed", room "Knižnica", bring line; *Hudobná výchova*
  struck through + "Cancelled". No teacher/notes lines where the field is empty or hidden.
- Compact density (Timetable → options → Compact) → tiles show only room/building/teacher lines.
- Tap a tile → lesson detail sheet.

### B2.3 Timetable — week bar, strip, options
- `-TabulaScreen timetable.day`: bar "12 Oct – 16 Oct" + capsule "Week B"; ‹ › (44 pt) move a week; day pills Mo–Fr,
  today (13) in a red circle, Thursday has an orange dot, the selected day a tinted pill. Swipe left/right on the
  content moves a day (day views) / a week (grid, week) — check it does not fight vertical scrolling.
- Leaving the current week/day shows a "Today" toolbar button that jumps back.
- Options menu (top right, icon = current view): View (Grid / Week / Day / Tiles), Density, **Show Week** → Week A /
  Week B (secondary only; Week A jumps to 19 Oct), "Change for This Day…" in Day/Tiles (disabled until B3's
  `editor.day-change` exists).
- Picking a view persists it per timetable (force-quit, relaunch → same view). The title becomes a timetable menu
  only when there are 2+ timetables (B3 manager).
- VoiceOver on a day pill: "Thursday, 15 October 2026, n lessons, n changes" (the dot is never the only cue); the
  selected pill announces "Selected".

### B2.4 Grid (`timetable.grid`)
- Day headers aligned with the columns; period column shows number, start and end (compact: start only); break rows
  are thin bands, lunch a band with a fork-and-knife.
- 5 columns on iPhone 16 Pro Max portrait without horizontal scrolling; a 6/7-day timetable (B3 settings) still fits;
  landscape → wider cells.
- Cells: emoji + short name (SJL, MAT…), room in comfortable density; Thursday cells show corner icons (changed,
  cancelled + struck through, extra); multi-period lessons span rows including the break between.
- Empty lesson slots: dashed outline + faint "+"; tap → quick-add sheet. Next week shows Week A's lessons.
- Holiday week (26 Oct): Thu/Fri columns shaded with an umbrella + "Jesenné prázdniny".
- Dynamic Type AX1–AX5 → the grid becomes a **list** (sections per day, "Free period" rows with +, "Break"/"Lunch
  break" separators only between lessons); back to XXXL → grid.
- VoiceOver: order Monday period 1…n, then Tuesday…; a cell reads "<full date>: Matematika, period 1, 8:00 to 8:45,
  room 214, …"; an empty slot "<full date>, period 3, <time>, free" + hint "Adds a lesson in this period."
- `-TabulaSeed university` (free-form times): rows are the distinct time slots of the week.

### B2.5 Week time-blocks (`timetable.week`)
- Blocks proportional to duration, hour labels left, hour lines; the short Thursday is visibly shorter.
- Red current-time line + dot in today's column at 10:20 (fixed clock); live clock → moves once a minute, never
  animated (also with Reduce Motion).
- Overlapping lessons sit side by side in lanes. At AX sizes this view shows the grid's list.

### B2.6 Day (`timetable.day`) and Tiles (`timetable.tiles`)
- Day: one column on a time axis with name, time range, room/teacher/type lines in taller blocks, status badge top
  right, now line on today. At AX sizes the day is shown as tiles.
- Tiles (elementary default): big tiles + separators, current lesson ringed. A day without lessons → "No lessons" /
  holiday name / "Lessons cancelled" + full date.

### B2.7 Lesson detail (`timetable.lesson-detail`)
- Secondary seed opens the modified Thursday MAT: badge "Changed", date, time, period, Room "Aula", Teacher
  "Mgr. Novák (suplovanie)"; "Changes on This Day": Time changed (Usually: <regular time>), Room changed
  (Usually: 214), Substitute teacher (Usually: Mgr. Horváth). A Friday 5th-period lesson shows "Only in Week A".
- Hidden fields (switch Teacher off in B3 settings) disappear here too, including their "Usually" values.
- "Edit" / "Change for This Day" disabled with "Editing isn't available in this version yet." until B3 registers
  `editor.lesson` / `editor.day-change`; afterwards they open those editors with `\.editorContext` set.
- One-off extra lesson (Thursday INF): Edit disabled, footer says it exists only on this day.

### B2.8 Quick add (`timetable.quick-add`)
- Sheet (medium/large): header = full date + "Period n · time"; subjects alphabetically with badges; footer "The
  lesson is added to Week B only…" (secondary). Tap a subject → sheet closes, the cell is filled; the same slot in
  Week A stays free. Read-only store → inline error, nothing changes.
- "New Subject…" disabled until B3 registers `editor.subject`. `-TabulaSeed blank` → "No subjects yet".

### B2.9 State matrix
| State | How | Expected |
|---|---|---|
| Empty | `blank` seed | Today "No lessons yet"; grid of dashed free slots; quick add "No subjects yet" |
| Normal | `secondary`, `elementary`, `university` | as above |
| Long text | B3: subject name 60+ chars, 8-char short name, long room/notes | tiles wrap the name; grid scales the short name (≥ 60 %, 2 lines); notes ≤ 3 lines |
| Dynamic Type XXL / AX5 | Larger Text | countdown scales; grid/week → list, day → tiles at AX; day pills ≥ 44 pt; nothing clipped in tiles |
| Dark mode | Appearance Dark | tile text contrast, outlines on dark colours, red now line visible, badges legible (material) |
| German | `-AppleLanguages "(de)"` | after C1: long captions wrap; week range scales to fit |
| CJK | `-AppleLanguages "(ja)"` | short weekday names (月 火 …), Japanese dates, list separator "、" |
| VoiceOver | VoiceOver on | one element per lesson with the full sentence; header readable; grid column-major; hints on cells/slots |

### B2.10 Not verifiable here (needs device / simulator)
- `Text(timerInterval:pauseTime:)` / `ProgressView(timerInterval:)` frozen with a fixed clock and ticking live otherwise;
  TimelineView(.everyMinute) refresh after returning from background.
- Grid geometry (offset-positioned cells and their hit testing), 7 columns at 375 pt (≈ 45 pt columns), VoiceOver
  sort-priority order inside the ZStack.
- `toolbarTitleMenu` with Liquid Glass; swipe gesture vs. ScrollView/List scrolling.
- `Duration.UnitsFormatStyle` output per language.
- Editor sheets reading `\.editorContext` (depends on B3).
