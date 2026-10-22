# Phase 4 — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x) + Apple Watch Series 7 (watchOS 26.x). Same format as `PHASE3_DEVICE.md`:
**Steps → Expected**, plus an Observed column and ✔ / ✘ / ? (unclear). Each Phase 4 stage adds its own self-contained
`##` section (several agents edit this file; keep sections independent).

iOS version: ________ · Build: xtool / TestFlight · Tester: ________ · Date: ________

---

## C1

**Subject order (`Subject.sortIndex`, P3-2, approved 2026-10-16).** Subjects have a manual order; every subject list and
picker follows it (DOMAIN_MODEL §3.3). Never-ordered timetables stay alphabetical until the first reorder or the first
new subject. No UI can be previewed locally: everything here is device-only.

Setup: a timetable with at least 5 subjects created **before** installing this build (e.g. the Phase 3 build's sample
data or a manually built timetable), so the upgrade path is tested. Optional second device / older build for C1.12.

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.1 | Install this build over the Phase 3 build (keep data), open Timetable → options → Subjects | All subjects present; order is **alphabetical** (no order stored yet); no error banner; footer "Tap Reorder to change the order. New subjects are added at the end." (with only one subject: "New subjects are added at the end of the list.") | | |
| C1.2 | Tap **Reorder** (top left) | Drag handles appear on every row; no delete buttons; Reorder becomes **Done** and the sheet's own Done (top right) is hidden, so only one Done is visible; VoiceOver reads it as "Done reordering". With 0–1 subjects, Reorder is disabled | | |
| C1.3 | Drag the last subject to the top, tap Done. Then drag a row and drop it where it was | The row stays at the top; reopening the Subjects sheet and relaunching the app keep the order. The drop in place changes nothing (Developer screen: last mutation label not "reorder subjects") | | |
| C1.4 | Open the subject picker in: lesson editor (new lesson), day-change editor (substitute / extra lesson), timetable quick add (tap an empty grid slot), Tasks → quick-add subject menu, task editor, exam editor | Every list shows the **same order** as the Subjects sheet (moved subject first) | | |
| C1.5 | Tasks tab → options menu → Subject filter (have tasks for ≥ 3 subjects) | Filter subjects follow the manual order; with several timetables, grouped in the timetables-list order | | |
| C1.6 | Subjects → **+**, create "Aaa test" | New subject appears at the **end** of the list (not alphabetically first), and at the end of every picker in C1.4 | | |
| C1.7 | Edit an existing subject (rename it), Save | Its position does not change | | |
| C1.8 | VoiceOver on, Subjects sheet: focus the 2nd row, swipe up/down (rotor Actions) | Actions "Move up" and "Move down" are offered; the first row offers only "Move down", the last only "Move up". Activating one moves the row immediately and VoiceOver announces "Moved to position N of M" | | |
| C1.9 | Repeat C1.8 in Slovak (or another non-English language) | Action names, the announcement ("Presunuté na pozíciu N z M") and the Reorder button are translated in sk; footer translated | | |
| C1.10 | Dynamic Type at the largest accessibility size, Edit mode | Rows wrap, reorder handles stay reachable; the footer is readable | | |
| C1.11 | *(only once the share UI exists — not built yet; core-tested: `SubjectOrderShareBackupTests`)* Share the timetable (link or QR), import it on the same device | The imported timetable's subjects appear in the **same manual order** as the source | | |
| C1.12 | (optional, two devices or an older build) Reorder differently on two devices offline, then sync / exchange data | Both devices end with the same order (deterministic merge, DOMAIN_MODEL §3.3); a later full reorder on one device wins | | |
| C1.13 | *(only once the backup UI exists — not built yet; core-tested)* Export a backup, change the order, restore the backup (replace) | The order from the backup is restored | | |

Not testable on device yet: CloudKit sync, the share UI and the backup UI are not built, so C1.11–C1.13 wait for those
stages (the logic is covered by TimetableCore tests on Linux).

---

## A. Widget snapshot + *Now & Next* (Stage A)

### A0. Setup and what each build can prove
Build: xtool (free team) / xtool (paid team) / TestFlight · App Group available (Developer → Platform probes): yes / no

- **App Group is required.** The app writes `<App Group>/Widgets/widget-snapshot.json`; the widget only reads it.
  On a **free-team xtool build the App Group is filtered out** (xtool PR #284, RISKS #47/#56/#65): the widget can only
  show "Open Tabula" (rows A1.1–A1.2 still apply). Every other row needs a build with the group: a paid-team xtool
  build or TestFlight (`TABULA_PAID_ACCOUNT=1`). Record which build you used.
- **Data.** Use the real store (onboarding → Secondary profile, or your own timetable). Seed launches (`-TabulaSeed …`)
  never write a snapshot (seed data must not reach the real widgets).
- **Diagnostics.** Settings → Developer → Platform probes → "Widget read-back" shows what the extension saw at its
  last timeline: `Now & Next: snapshot v1 from <time>, <n> entries, read <time>` (or `no snapshot`).
- **CI gallery** (`ui-screenshots.yml`): `widgets.gallery` (lesson, break), `widgets.gallery-evening` (after school,
  holiday), `widgets.gallery-pro` (free-tier Pro placeholders, "Open Tabula" states). Compare the device with them.
- Add the widget: long-press Home Screen → Edit → Add Widget → **Tabula** → **Now & Next** (small, medium). Lock
  Screen: long-press the Lock Screen → Customize → Lock Screen → add circular / rectangular below the clock and the
  inline one above it.

### A1. Gallery, first snapshot, fallback
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A1.1 | Free-team xtool build: add the small widget | Widget gallery lists "Now & Next" with the localised description; the placed widget shows **"Open Tabula"** + "Open the app once…" — never stale or invented lessons | | |
| A1.2 | Precondition: open Tabula, switch to the **Tasks** tab, go Home (app stays in memory). Tap the widget. Repeat after force-quitting Tabula (cold launch) | Tabula opens on the **Today** tab both times (proves the `tabula://open/today` deep link, RISKS #66; without it the app would stay on Tasks) | | |
| A1.3 | Group build, fresh install, before onboarding finished: add the widget | "Open Tabula" + "Set up your timetable in the app." | | |
| A1.4 | Finish onboarding with lessons, go Home (≤ 2 s) | Widget switches to real content within seconds (app wrote + `reloadAllTimelines`); Developer read-back shows a snapshot from the last minute | | |
| A1.5 | Widget gallery preview with no data yet | Preview shows the sample "during a lesson" content, not an empty widget | | |

### A2. Now & Next states and live time (small + medium)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A2.1 | During a lesson | "Now", subject badge (user colour, readable text), name, room (or time), **large live countdown** "m:ss" ticking every second without the app, progress bar filling, "Next: <subject>, <time>" | | |
| A2.2 | Watch the countdown reach 0:00 at the lesson end | Within ~1 min the widget switches to the next state (entry at the boundary); never shows negative time | | |
| A2.3 | In a break between lessons | "Next" + subject + time range · room + "Starts in" live countdown to the start | | |
| A2.4 | Before the first lesson | Caption "First Lesson" | | |
| A2.5 | After the last lesson | "No more lessons today" + "Next Lesson" row with **"Tomorrow, 8:00"** | | |
| A2.6 | Leave it overnight; check after 00:00 | The same lesson now shows as today's "First Lesson" with "Starts in"; no "Tomorrow" | | |
| A2.7 | Saturday / free day | "No lessons today" + next lesson with its weekday and date | | |
| A2.8 | During a calendar break (holiday) | The break's name (or "Holidays") + next lesson after the break | | |
| A2.9 | Day cancelled (Today → day change "Cancel day" with a note) | "Lessons are cancelled today" + the note | | |
| A2.10 | Cancel one lesson (lesson detail → day change) | The cancelled lesson is skipped as current and as next; widget updates within seconds of saving | | |
| A2.11 | Change a lesson's room for today | Upcoming state shows the badge "Room changed" | | |
| A2.12 | Medium family | Left: as small; right: "Next"/"Later" with up to 3 lessons of that day (badge, name, time · room) | | |
| A2.13 | Settings → 12/24 h → change | All widget times switch format after the app writes (go Home) | | |
| A2.14 | iOS Settings → Tabula → Language → another language | Widget strings follow the app's language (snapshot `languageCode`); the gallery name/description follow the system (RISKS #69) | | |
| A2.15 | Large text (Settings → Display → Text Size max) | Text scales within the widget without overlapping; long subject names truncate with "…" | | |
| A2.16 | VoiceOver on the widget | One sentence: "Now, <subject>, 8:00 to 8:45, room 214, ends at 8:45, Next, …" (no raw keys, no timer gibberish) | | |

### A3. Lock Screen, StandBy, rendering modes
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A3.1 | accessoryRectangular during a lesson | "Subject · room", hourglass + live countdown, "Next: …" — legible in vibrant (grey) rendering | | |
| A3.2 | accessoryCircular during a lesson | Ring that **empties live** over the lesson with subject label + countdown inside (RISKS #68: if the ring does not render circular / does not move, record what you see) | | |
| A3.3 | accessoryCircular in a break / free day | Subject label + start time / status symbol | | |
| A3.4 | accessoryInline during a lesson | "Math · 12:34" live; in a break "Next: Biology, 9:50" | | |
| A3.5 | Always-On display (lock the phone) | Lock Screen widgets stay legible; countdown keeps (or freezes per system policy) | | |
| A3.6 | StandBy (charging, landscape, locked): add Now & Next | Small layout scaled up, background removed, text legible; at night (red tint) still readable | | |
| A3.7 | Home Screen → Customize → Tinted / Clear icons | Subject badges become outlined marks; timer is the accent group; nothing invisible | | |
| A3.8 | Precondition: leave Tabula on the **Tasks** tab, lock the phone. Tap a Lock Screen widget, unlock | Opens Tabula on **Today** (not Tasks), RISKS #66 | | |

### A4. Refresh triggers, background refresh, low power, time zone
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A4.1 | Edit a lesson, immediately swipe Home | Widget shows the change (writer flushes when the scene leaves `active`) | | |
| A4.2 | Open + close the app 10× without changes | Read-back time does **not** change each time (unchanged snapshot is not rewritten → no reload spent) | | |
| A4.3 | Don't open the app for 2 school days (phone used normally) | Widget keeps advancing lesson by lesson (≤ 29 entries per timeline, cut at a midnight, a reload at least every 6 h: read-back time advances); Background App Refresh may rewrite the snapshot (read-back time) | | |
| A4.4 | Background App Refresh **off** for Tabula, don't open the app until past the covered days | Widget shows "Open Tabula" + "Open the app to update…" once the snapshot's days are over — never yesterday's lessons | | |
| A4.5 | Low Power Mode on for a school day | Countdown still ticks; boundaries still switch (timeline entries need no app); reloads may be delayed — note how much | | |
| A4.6 | Settings → General → Date & Time → time zone to New York (automatic off), app **not** opened | Note what the widget shows (WidgetKit may not reload on a zone change, RISKS #67). Then open the app → widget re-plans: an 08:00 lesson shows at 08:00 New York time ("follow device") | | |
| A4.7 | Same with a fixed-zone timetable (Settings → Calendar → fixed zone) | Lessons keep the home zone's clock | | |
| A4.8 | DST night (last Sunday of October / March) with the widget placed | No skipped / duplicated lesson state; Monday's lessons at the right wall-clock time | | |

### A5. Pro gate (only testable with a free tier; the shipping tier is all-access until Phase 10)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A5.1 | (Later, free tier) Lock Screen families | "Available in Tabula Pro" (rectangular/inline) / lock + "Pro" (circular); small/medium unchanged. Today: compare with the `widgets.gallery-pro` screenshot | | |

### A6. Watch (Phase 5, not part of Stage A)
Watch pairing, WatchConnectivity snapshot transfer, complication refresh and watch low-power rows are added in Phase 5.
Stage A only guarantees the snapshot format they will reuse: < 20 KB for the seeded scenarios (Linux test
`encodedSnapshotStaysSmall`).

---

## B1

**Today, Homework and Next exam widgets** (StaticConfiguration, no App Intents yet). Same build caveats as A0: a free-team
xtool build has no App Group, so every widget shows "Open Tabula" (row B1.1); the rest needs a group build. CI gallery
pages for comparison: `widgets.gallery-today`, `widgets.gallery-homework`, `widgets.gallery-exam`.

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B1.1 | Add Today (medium), Homework (small) and Next Exam (small) on a free-team build | Each shows "Open Tabula" + the hint; gallery names/descriptions localised | | |
| B1.2 | Today medium during a lesson | Header "Today" + date; rows from the current lesson on (3-4); current row on a plate with a bar; cancelled lessons struck through with "Cancelled"; changed ones carry an icon + text line | | |
| B1.3 | Today large | Whole day, ended lessons dimmed; "Due today" with up to 3 tasks (overdue-today ones with a warning icon) | | |
| B1.4 | After the last lesson; then past midnight | "Tomorrow" header with tomorrow's lessons and "Due tomorrow"; after 00:00 it reads "Today" | | |
| B1.5 | Holiday / free day / cancelled day | Same wording as Now & Next with the next lesson | | |
| B1.6 | Homework small / medium / large | Small: count + top task; medium 3 rows, large 9, "+N more"; overdue first with a warning icon AND text ("2 days overdue"); due texts Today / Tomorrow / Fri | | |
| B1.7 | Tap a Homework row (medium), then the small widget | Opens that task's detail (`tabula://open/task/<id>`, RISKS #66); small opens the top task | | |
| B1.8 | Complete the last open task in the app | Widget turns to "All done" within seconds | | |
| B1.9 | Task with a due time: wait until a minute after it | Row turns overdue without opening the app | | |
| B1.10 | Next Exam small, exam 2+ days away | Subject, title, date, time, room; "in N days" with a calendar icon | | |
| B1.11 | Exam tomorrow; exam day before the start | "Tomorrow" (alert icon); "Today, 10:00" + live "Starts in" countdown ticking without the app | | |
| B1.12 | During / after the exam | "In progress" with a "Time left" countdown; later "Finished" | | |
| B1.13 | Lock Screen: rectangular + circular Next Exam | Rectangular: subject, icon + countdown/timer, date; circular: icon + days number; tap opens the exam | | |
| B1.14 | Tinted Home Screen / Lock Screen (accented, vibrant) | Subject colours become outlined marks; text stays legible; overdue still has icon + word | | |
| B1.15 | VoiceOver on each widget | One sentence per widget (Today, small Homework, exam); Homework rows one sentence each | | |
| B1.16 | Largest Dynamic Type; non-English app language | No clipped essential text; strings translated | | |
