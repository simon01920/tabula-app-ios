# Phase 4 — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x) + Apple Watch Series 7 (watchOS 26.x). Same format as `PHASE3_DEVICE.md`:
**Steps → Expected**, plus an Observed column and ✔ / ✘ / ? (unclear). Each Phase 4 stage appends its own section.
Widgets, Lock Screen, StandBy, timeline reloads and widget taps cannot be simulated here (no Mac; the CI simulator
cannot place widgets): everything below is device-only. The CI `widgets.gallery*` screenshots only prove the views'
layout at the family sizes (see A0).

iOS version: ________ · Build: xtool (free team) / TestFlight · App Group available (Developer → Platform probes):
yes / no · Tester: ________ · Date: ________

---

## A. Widget snapshot + *Now & Next* (Stage A)

### A0. Setup and what each build can prove
- **App Group is required.** The app writes `<App Group>/Widgets/widget-snapshot.json`; the widget only reads it.
  On a **free-team xtool build the App Group is filtered out** (xtool PR #284, RISKS #47/#56/#62): the widget can only
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
| A1.2 | Tap it | Tabula opens on the **Today** tab | | |
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
| A2.14 | iOS Settings → Tabula → Language → another language | Widget strings follow the app's language (snapshot `languageCode`); the gallery name/description follow the system | | |
| A2.15 | Large text (Settings → Display → Text Size max) | Text scales within the widget without overlapping; long subject names truncate with "…" | | |
| A2.16 | VoiceOver on the widget | One sentence: "Now, <subject>, 8:00 to 8:45, room 214, ends at 8:45, Next, …" (no raw keys, no timer gibberish) | | |

### A3. Lock Screen, StandBy, rendering modes
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A3.1 | accessoryRectangular during a lesson | "Subject · room", hourglass + live countdown, "Next: …" — legible in vibrant (grey) rendering | | |
| A3.2 | accessoryCircular during a lesson | Ring that **empties live** over the lesson with subject label + countdown inside (RISKS #65: if the ring does not render circular / does not move, record what you see) | | |
| A3.3 | accessoryCircular in a break / free day | Subject label + start time / status symbol | | |
| A3.4 | accessoryInline during a lesson | "Math · 12:34" live; in a break "Next: Biology, 9:50" | | |
| A3.5 | Always-On display (lock the phone) | Lock Screen widgets stay legible; countdown keeps (or freezes per system policy) | | |
| A3.6 | StandBy (charging, landscape, locked): add Now & Next | Small layout scaled up, background removed, text legible; at night (red tint) still readable | | |
| A3.7 | Home Screen → Customize → Tinted / Clear icons | Subject badges become outlined marks; timer is the accent group; nothing invisible | | |
| A3.8 | Tap a Lock Screen widget (unlock) | Opens Tabula on Today | | |

### A4. Refresh triggers, background refresh, low power, time zone
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A4.1 | Edit a lesson, immediately swipe Home | Widget shows the change (writer flushes when the scene leaves `active`) | | |
| A4.2 | Open + close the app 10× without changes | Read-back time does **not** change each time (unchanged snapshot is not rewritten → no reload spent) | | |
| A4.3 | Don't open the app for 2 school days (phone used normally) | Widget keeps advancing lesson by lesson (≤ 29 entries per timeline, reload at the last entry); Background App Refresh may rewrite the snapshot (read-back time) | | |
| A4.4 | Background App Refresh **off** for Tabula, don't open the app until past the covered days | Widget shows "Open Tabula" + "Open the app to update…" once the snapshot's days are over — never yesterday's lessons | | |
| A4.5 | Low Power Mode on for a school day | Countdown still ticks; boundaries still switch (timeline entries need no app); reloads may be delayed — note how much | | |
| A4.6 | Settings → General → Date & Time → time zone to New York (automatic off), app **not** opened | Note what the widget shows (WidgetKit may not reload on a zone change, RISKS #64). Then open the app → widget re-plans: an 08:00 lesson shows at 08:00 New York time ("follow device") | | |
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
