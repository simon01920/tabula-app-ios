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
| B1.17 | Two exams on one day; the day after an exam | After the first exam ends the widget switches to the second one with its countdown; the day after the last exam it shows "No Upcoming Exams" (or the next exam), not "Open Tabula" | | |

Known difference (accepted, QA minor): on a Friday evening the Today widget (lessons over, nothing tomorrow) shows the Stage A status "No more lessons today" with the Monday lesson, while the Today tab words it slightly differently. Not a bug; no code change.

## B2

Live Activities for (a) the current lesson and (b) exam day (Phase 4 Stage B2, PHASE4_PLAN §0.5, decision P3-6). Rules
and constants: `Packages/TimetableUI/Sources/TimetableUI/Widgets/LiveActivityPlanner.swift` (header); facts:
ENVIRONMENT §31; risks: RISKS #73–#79.

### B2.0 Setup and what each build can prove
- **Any build works**, including a free-team xtool build: ActivityKit needs no entitlement and no App Group (the content
  travels inside the activity). `NSSupportsLiveActivities = YES` is in `Config/App-Info.plist` (both paths; checked by
  `validate_config.py`).
- **Data.** Real store only. Seed launches (`-TabulaSeed …`) never start Live Activities (seed data must not reach the
  real Lock Screen).
- **Diagnostics.** Settings → Developer → *Live Activities*: system enabled, last run (`<time>: n lesson + m exam steps`,
  plus failures such as `start: …visibility` or `schedule: …`), next evaluation, whether one runs, and "Run the Live
  Activity planner now".
- **Settings.** Settings → *Live Activities* → "Current lesson" (on), "Exam day" (on), "Start automatically" (**off** by
  default; decision needed, see the B2 report).
- **CI gallery** (`ui-screenshots.yml`, light + dark): `widgets.gallery-live` (lesson in progress: Lock Screen, expanded,
  compact + minimal; in a break), `widgets.gallery-live-exam` (exam countdown, exam in progress, the final lesson
  state), `settings.live-activities`. Compare the device with them.
- Test timetable: a day with ≥ 3 lessons and a 5–10 min break, the first one 20–30 min from now (edit a lesson's time
  or add a one-off override), and an exam today with a start and an end time a few hours ahead.
- Devices: iPhone 16 Pro Max (Dynamic Island, Always-On); Apple Watch Series 7 paired (Smart Stack, B2.35).

### B2.1 Start, update, end — lesson
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B2.1 | Open Tabula **more than 15 min** before the first lesson, lock | No Live Activity yet (the window opens 15 min before) | | |
| B2.2 | Open Tabula **≤ 15 min** before the first lesson, lock | Lock Screen: "First Lesson", subject, room · time, "Starts in" + live countdown; Dynamic Island compact: badge + countdown | | |
| B2.3 | Wait until the lesson starts **without opening the app** | At the start the activity switches to "Now", the lesson's "Time left" countdown and progress bar (stale-date re-render, RISKS #73). Record whether it switched on time | | |
| B2.4 | Wait until the lesson ends, still without opening the app | Record what the Lock Screen shows in the break. Expected "Next" + the next lesson counting down (needs a second re-render, which only an update gives: if it shows 0:00 for the old lesson, RISKS #73 materialised) | | |
| B2.5 | Open Tabula in the break, go back to the Lock Screen | Updated at once: "Next" + next lesson countdown; Developer shows `1 lesson + 0 exam steps` (one update) | | |
| B2.6 | Keep Tabula open in the foreground across a lesson boundary | The in-app timer updates the activity within ~1 s of the boundary | | |
| B2.7 | Edit the current lesson's room in Tabula | Lock Screen shows the new room within ~1 s; no second activity appears | | |
| B2.8 | After the last lesson (app open, or opened later) | "No more lessons today" with a check mark; removed from the Lock Screen ≈ 15 min after the last lesson; gone from the Dynamic Island at once | | |
| B2.9 | Long-press the compact Dynamic Island | Expanded: badge + caption (leading), timer (trailing), subject (center), room · time, "Time left", progress, "Next: …" (bottom); compare with `widgets.gallery-live` (the gallery only approximates the region placement) | | |
| B2.10 | Start another app's Live Activity (e.g. a Clock timer) | Tabula shows the minimal presentation (subject badge); tapping it opens Tabula on **Today** | | |
| B2.11 | Tap the Lock Screen activity / the compact island | Tabula opens on Today | | |

### B2.2 Relaunch adoption, settings, permission
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B2.12 | With a lesson activity running, force-quit Tabula, relaunch | The same activity continues; **no duplicate**; Developer: `0 lesson …` steps or one update | | |
| B2.13 | Swipe the activity away on the Lock Screen, open Tabula again the same day | It does **not** come back today (ledger); the next school day it starts again. An activity Tabula ended itself (holiday, setting off) does come back when the reason goes away (B2.42) | | |
| B2.14 | Settings → Live Activities → "Current lesson" off | The running lesson activity disappears at once; switching it on again during lessons starts a new one at once | | |
| B2.15 | iOS Settings → Tabula → Live Activities off, back to Tabula → Settings → Live Activities | Running activities end; the page shows "Live Activities are turned off for Tabula…" + "Open Settings" (opens Tabula's page in the Settings app); turning them on again removes the note and (during lessons) the lesson activity starts again | | |
| B2.16 | Holiday / cancelled day / move all of today's lessons to tomorrow while the activity runs | The activity ends at once | | |
| B2.17 | Let the day change with an activity still shown, open Tabula next morning | Yesterday's activity is gone | | |
| B2.18 | Change the time zone (Settings → General → Date & Time) with an activity running, open Tabula | Times follow the timetable rule ("follow device": same wall-clock times); one update | | |

### B2.3 Exam day
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B2.19 | Exam today at T (with an end time); open Tabula after T − 6 h | Lock Screen: "Exam today", title (+ subject badge), room · time, "Starts in" + live countdown (hours shown) | | |
| B2.20 | A lesson and the exam activity run together | The **exam** is in the Dynamic Island (relevance 100 vs 50) and first on the Lock Screen | | |
| B2.21 | At T, without opening the app | Switches to "In progress" with "Time left" to the end + progress (stale-date re-render) | | |
| B2.22 | After the end | "Exam finished", removed ≈ 15 min later | | |
| B2.23 | Edit the exam's time / mark it done / delete it while it runs | Time: updated at once; done or deleted: the activity ends at once | | |
| B2.24 | Exam without a start time | No exam Live Activity (documented) | | |
| B2.25 | Tap the exam activity | Tabula opens the exam's detail | | |

### B2.4 Start automatically (scheduled starts, iOS 26)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B2.26 | Turn "Start automatically" on in the evening after school, close Tabula, don't open it until the next lessons | 15 min before the first lesson the activity starts **on its own** with an alert ("First Lesson", "Mathematics at 8:00"): screen lights up, expanded island, notification sound; the Watch shows the alert | | |
| B2.27 | Exam tomorrow at 10:00 with auto-start on; open Tabula the evening before | The exam activity starts at **06:00** with "Exam today" / "<title> at 10:00" | | |
| B2.28 | With a scheduled start pending, move tomorrow's first lesson earlier and open Tabula | The pending activity is replaced; it starts 15 min before the new time (one alert only) | | |
| B2.29 | Record how loud / intrusive the scheduled-start alert is with Focus and the silent switch | Input for the default on/off decision | | |

### B2.5 Always-On, StandBy, Low Power Mode, background refresh, Watch, accessibility
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B2.30 | Always-On (dimmed Lock Screen) with a lesson running | Readable; progress bar grey (reduced luminance); the timer keeps counting (Always-On may update it less often) | | |
| B2.31 | StandBy (charging, landscape) | Minimal presentation at the top; tapping shows the Lock Screen layout scaled up; readable in Night Mode (red tint) | | |
| B2.32 | Low Power Mode on during lessons, app closed | Timers keep counting; background refresh is reduced, so updates come at the next foreground — record whether the boundary re-renders (B2.3) still happen | | |
| B2.33 | App closed for a whole school day, Background App Refresh on | Developer "Last run" shows background runs (record the times); compare them with the lesson boundaries (the refresh request asks for the next boundary while an activity runs; each background refresh runs the reminders first, so reminders keep working even if ActivityKit is slow) | | |
| B2.34 | A day longer than 8 h (15 min before the first lesson to the end of the last) | The system ends the activity after 8 h (Apple limit); it is not restarted that day (documented, RISKS #75) | | |
| B2.35 | Apple Watch paired, activity running | The Smart Stack shows it (system layout from the compact presentation: badge + timer); a tap offers to open Tabula on the iPhone (no watch app until Phase 5); record readability | | |
| B2.36 | VoiceOver on the Lock Screen activity and on the compact island | Lock Screen: one sentence ("Now, Mathematics, 8:00 to 8:45, room 214, ends at 8:45, Next, 8:55, Biology"); compact timer: "Mathematics, ends at 8:45" | | |
| B2.37 | Largest Dynamic Type | Lock Screen text scales within the 160 pt limit without overlaps (the system may truncate); record clipping | | |
| B2.38 | A loud AlarmKit alarm with snooze (existing) while a lesson activity runs | The alarm's countdown activity still works; both coexist | | |
| B2.39 | With a lesson and an exam start scheduled (auto-start on, in the evening), switch "Start automatically" off | Nothing starts the next morning (both pending activities were cancelled at once); switched on again, the next foreground schedules them again | | |
| B2.40 | Swipe an exam activity away, then move the exam to tomorrow | Tomorrow the exam activity starts again (the ledger is per exam and day) | | |
| B2.41 | Two exams today (e.g. 8:00 and 13:00); swipe the first away, open Tabula after 7:00 | The second exam's activity starts (its window opened at 7:00); without the swipe it starts once the first ended | | |
| B2.42 | While the lesson activity runs, cancel today (day change), then undo it | The activity ends, then starts again after the undo (a planner end does not block a restart) | | |
| B2.43 | With a start scheduled for tomorrow, change tomorrow's first lesson on another device (sync) without opening Tabula | The pending activity is kept and starts at its old time, then the next run updates it; opening Tabula before then replaces it with one at the new time | | |

Watch complication refresh: not part of B2 (no complications yet; Phase 5).
