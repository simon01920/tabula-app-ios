# Phase 4U — manual on-device checklist (UX overhaul)

Device: iPhone 16 Pro Max (iOS 26.x). Same format as `PHASE4_DEVICE.md`: **Steps → Expected**, plus an Observed column and
✔ / ✘ / ? (unclear). Each Phase 4U stage adds its own self-contained `##` section (several stages edit this file; keep
sections independent). The Phase 4 CI gallery pages (`widgets.gallery*`) show the layouts; **only the device shows the
live values, the tinted / vibrant Lock Screen modes and the system's relative-time wording**.

iOS version: ________ · Build: xtool / TestFlight · Tester: ________ · Date: ________

---

## U7 Widgets and Live Activities

Needs a build with the App Group (paid-team xtool or TestFlight; free-team builds only show "Open Tabula").
Rows U7.9–U7.10 need a build with `TABULA_APP_INTENTS` (TestFlight or `xtool-dev.sh --app-intents`).
Setup: the Secondary profile (or your own timetable) with a lesson in progress; add Now & Next (small, medium, Lock
Screen inline / rectangular / circular), Today (medium, large), Homework (small, medium, large), Next exam (small,
Lock Screen rectangular / circular) and start a lesson Live Activity (Settings → Live Activities).

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| U7.1 | Lock Screen **inline** widget during a lesson | Reads `25 min · SJL` (time first, then the short name), never a long subject name cut at the end. The minutes tick down on their own; no seconds | | |
| U7.2 | Inline widget in a break and after the last lesson | Break: `Next 8:55 BIO`. After school: `Done for today` (never "No more lessons t…") | | |
| U7.3 | **Rectangular** widget in a lesson, in a break, after school | Lesson: `24:59 left` over `SJL · 214` over `Next: BIO, 10:55`. Break: `Next 8:55 BIO` over the full name · room. After school: `Done for today` over `Next: BIO, Tomorrow, 8:00` | | |
| U7.4 | **Circular** widget in a lesson | A ring (not a spinner glyph) that shrinks as the lesson runs, short name and time left in the centre. Note: the real widget uses the system's date-relative ring, because `Gauge` has no live timer (the gallery shows the `Gauge` look). Check the ring moves without the app open | | |
| U7.5 | Circular widget after school and on a holiday | Short name of the next lesson over its **start time** (e.g. `ANJ` / `8:00`); a check mark / icon only when no next lesson exists | | |
| U7.6 | Small and medium **Now & Next** during a lesson, then in a break | Highlighter `NOW` marker (yellow, black text) beside the badge; `24:59` with **left** under it. Break: `1 h 30 min`-style text or `mm:ss` with **until start** under it; nothing reads as a clock time | | |
| U7.7 | Before school with the first lesson 60+ min away, then wait or change the clock | Countdown reads `1 h 30 min` + **until start** (system relative text; wording such as "1 hr, 30 min" is the system's, record it), no seconds. Below 60 min it switches to `mm:ss` + unit | | |
| U7.8 | **Today** widget (medium, large) during a lesson | The current row has the yellow `NOW` marker, no grey plate, no accent bar; past rows dimmed; the cancelled row struck through. In a tinted Home Screen the marker is an outlined box | | |
| U7.9 | **Homework** medium / large (intents build): look at a row | Circle on the left margin edge, ~11 pt gap to the subject badge (was ~28 pt); 44 pt tall rows; tapping the circle completes the task, tapping the row opens it | | |
| U7.10 | Homework medium / large on a **non-intents** build | No circles at all; the whole row is the link | | |
| U7.11 | **Homework small** with 3+ open tasks, with exactly 1 task | 3+ tasks: count and the top **two** tasks (title + due text). One task: the larger single-task layout. Overdue shows a red-orange icon and the word | | |
| U7.12 | **Next exam** small and rectangular on the exam day, more than 1 h before | `Today, 10:00` and `1 h 30 min` + **until start** (minutes, never seconds); during the exam `25 min` + **left** | | |
| U7.13 | **Live Activity** (Lock Screen banner) during a lesson | Yellow `NOW` marker in place of the word "Now"; trailing `24:59` over **left**; progress bar; `Next: …` line | | |
| U7.14 | Live Activity before a lesson and for an exam | Caption `Next` / `Exam today`, trailing time with **until start**; exam countdown in minutes with no seconds | | |
| U7.15 | Dynamic Island: compact, minimal, expanded (long-press) | Compact trailing shows minutes (`25 min`), not `mm:ss`; expanded trailing shows value + unit; expanded leading shows the `NOW` marker; nothing clipped at the leading edge | | |
| U7.16 | After the last lesson the Live Activity ends | Final content says `Done for today` | | |
| U7.17 | Home Screen **Tinted** and **Clear** appearance; Lock Screen with a tint colour | Highlighter becomes an outlined `NOW` box; text stays readable; the accent group (timer, `NOW`) is tinted | | |
| U7.18 | Increase Contrast, dark appearance | Ink-coloured glyphs (status icons) stay legible; the highlighter keeps black text | | |
| U7.19 | Largest Dynamic Type (AX5) and a long Slovak / German subject | Lock Screen text keeps the time visible; the home widgets wrap or scale, nothing overlaps | | |
| U7.20 | Settings language Slovak, then German | Unit words (`zostáva` / `übrig`, `do začiatku` / `bis Beginn`), `Done for today` (`Dnes hotovo` / `Für heute fertig`) and abbreviated durations are in the app language in every widget | | |
| U7.21 | Low Power Mode on, then off | Widgets keep showing the right text; the live timers are unaffected (system-driven) | | |
| U7.22 | VoiceOver on a widget and on the Live Activity | One sentence each, naming the lesson, the end / start time and the time left (e.g. "25 min left"); the `NOW` marker is not read twice | | |

Not testable on device yet: nothing in U7 depends on a missing feature. Open design questions are in the stage report
(M30 Free/Pro gate is untouched; it needs a human decision).
