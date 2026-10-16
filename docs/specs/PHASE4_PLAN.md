# Phase 4 plan — Widgets, Live Activity, App Intents (+ carried-over Phase 3 decisions)

Status: started 2026-10-16. The human approved Phase 3 and asked for Phase 4 end-to-end. Orchestrator: Opus 5.5.

- **ROADMAP:** Phase 4, Widgets & Live Activity.
- **PRODUCT.md "Widgets / Live Activity / Watch":** small, medium and large; Lock Screen (circular, rectangular, inline); StandBy. Content: Today, Now & Next with live remaining time, upcoming homework, next-exam countdown. Configurable through App Intents. A Live Activity for the current lesson.
- **Carried over from the Phase 3 gate:**
  - **P3-2:** `Subject.sortIndex`, approved.
  - **P3-3:** the translation review document.
  - **P3-5:** loud-alarm Mark done through App Intents.
  - **P3-6:** exam-day live countdown.
  - **P3-7:** the device runbook. The human connects the iPhone later in this phase.

## 0. Decisions
1. **Snapshot architecture.** The app writes a compact, versioned `WidgetSnapshot` (Codable JSON) to the App Group after every data change, on day change, on locale change and on foreground. Widgets read only the snapshot. They never open the database and never run the schedule engine.
   - The snapshot is built by a pure, Linux-tested builder in `TimetableUI`. It holds resolved lessons for today and tomorrow (+ the next school day), open tasks due within 7 days, the next exam, the entitlement tier, the 12/24 h and language settings, and pre-rendered strings where formatting needs the app's renderer.
   - Watch (Phase 5) reuses the same builder (the Watch snapshot must be < 20 KB).
   - Timelines have **< 30 entries** (ARCHITECTURE.md), with an entry at each lesson boundary. Live remaining time uses `Text(timerInterval:)`, so it needs no reloads.
   - Fallback when there is no App Group (free team; RISKS #56): widgets show a clear "Open Tabula" state, never stale or wrong data.
2. **Static first, intents second.**
   - xtool does not generate `Metadata.appintents` (RISKS #19, ENVIRONMENT §1). So every widget kind ships as a **`StaticConfiguration`** that works on both build paths.
   - App Intent features are added on top, and the plan does not depend on them working in local dev builds:
     - `AppIntentConfiguration` (pick a timetable);
     - interactive `Button(intent:)` for Mark done;
     - `LiveActivityIntent` for alarms;
     - App Shortcuts ("What's next?").
   - Each one degrades to a deep link (`widgetURL` / `Link` → `AppNavigation`) on builds without metadata. The device checklist records which path was tested.
3. **Widget kinds** (names are user-visible, so they go in the catalog):
   - *Now & Next*:
     - systemSmall and systemMedium;
     - accessoryRectangular (current or next lesson plus a live timer);
     - accessoryCircular (minutes left, as a gauge);
     - accessoryInline ("Math · 12 min left" / "Next: Bio 10:55").
   - *Today*: systemMedium and systemLarge, with the day's lessons, changes and due tasks.
   - *Homework*: systemSmall, systemMedium and systemLarge, with open tasks by due date. On the intent path a checkbox marks a task done.
   - *Next exam*: systemSmall and accessoryRectangular/Circular, showing the countdown in days or "Today 08:00".
   - **StandBy:** systemSmall content with `containerBackground` and the accented/vibrant rendering modes handled (`widgetRenderingMode`).
4. **Free/Pro** (MONETIZATION.md, `ProFeature` already has `.largeWidgets`, `.lockScreenWidgets`, `.liveActivity`):
   - The gate comes from the snapshot's tier. The current tier is all-access.
   - A gated family shows an "Available in Tabula Pro" view; families are never removed. The gate itself is unit-tested.
5. **Live Activity.**
   - **(a) The current lesson:**
     - It shows the subject, room and remaining time, and the next lesson.
     - It is started from the app (foreground) when a lesson is running or starts within N minutes, if the user has enabled it (Settings → Live Activity, default on). It ends after the last lesson.
     - The `ContentState` carries the remaining lessons of the day, so the timer views keep counting without updates. Lesson changes are applied by app updates on foreground and BG refresh. If a push-to-start / scheduled-start API exists in iOS 26/27, the engineer verifies it in Apple's docs before using it.
     - There is no server: push updates are out of scope.
   - **(b) Exam day:** when an exam is today, a countdown Live Activity to its start, then "in progress" until its end (P3-6).
   - Lock Screen and Dynamic Island compact, minimal and expanded layouts. Accessibility: the timers have spoken labels.
6. **Deep links:** widget taps open the right screen through the existing `AppNavigation` / `RootPresentationPolicy`, without new routing.
7. **`Subject.sortIndex` (P3-2, approved).**
   - The new field is optional (`Int?`). Decoding v1 data without it is unchanged. Subjects sort by `sortIndex`, then by name.
   - Share format, sync metadata, conflict merge and the backup are all updated.
   - DOMAIN_MODEL.md is updated, and a test proves old JSON loads.
   - The UI gets a reorder control in subject management, and every subject list and picker follows the order.
8. **Translation review document (P3-3).**
   - A script generates, from both catalogs:
     - a **side-by-side HTML page**, with every key in English plus all 12 languages, the context comment, a state badge, and a filter/search;
     - one **CSV per language for reviewers** (key, comment, English, current translation, *corrected*, *note*), with a UTF-8 BOM so it opens in Excel;
     - an **import script** that applies the reviewers' corrections back into the catalog and marks them `translated`.
   - Plural variations appear as separate rows.
9. **Device runbook (P3-7):** `docs/DEVICE_SETUP.md`. It covers: usbipd-win to attach the iPhone to WSL; the xtool Apple ID sign-in, done by the human, who never pastes the password into chat; build, install and launch with `scripts/xtool-dev.sh`; logs and troubleshooting; and which checklist rows to run first. It is executed when the human says the phone is connected.
10. **Screenshots of widgets:**
    - Simulator screenshots cannot capture the Home Screen widgets.
    - Instead, a DEBUG-only `widgets.gallery` route renders each widget view, at its exact family size, from a seeded snapshot. It covers light and dark, and the accented mode where possible.
    - This requires the widget views to live in code that both the app and the extension compile (decided in Stage A).
11. **Unchanged constraints:**
    - No paid account, so no push notifications and no Time Sensitive.
    - Persisted schema changes need approval: P3-2 has it, and nothing else may change.

## 1. Stages, model tier, ownership
| Stage | Agent (tier) | Why this tier | Scope |
|---|---|---|---|
| A Snapshot + widget foundation + Now & Next | `widgets-watch-engineer` (**Opus high**) | Architecture, time correctness, extension/app data boundary | `WidgetSnapshot` builder + timeline planner (TimetableUI, tests), app-side writer + reload triggers, extension reader, shared widget views module, Pro gate, *Now & Next* in all its families, `widgets.gallery` route, remove the Phase 0 hello widget |
| C1 `Subject.sortIndex` | `core-domain-engineer` (**Opus high**) | Persisted schema, sync, share codec | TimetableCore model/codec/merge/tests, DOMAIN_MODEL.md, subject reorder UI + sorted pickers |
| C2 Translation review document | `localization-engineer-sonnet` (Sonnet medium) | Scripted, mechanical | `scripts/l10n-review-export.py` / `l10n-review-import.py`, `docs/localization/review/` |
| C3 Device runbook | `env-ci-engineer-sonnet` (Sonnet medium) | Documentation + script checks | `docs/DEVICE_SETUP.md`, script preflight (`xtool-dev.sh doctor` or similar) |
| B1 Today / Homework / Next exam widgets | `widgets-watch-engineer-sonnet` (Sonnet medium) | Well-specified views on Stage A's foundation | the extension's widget kinds, gallery entries, strings |
| B2 Live Activities (lesson + exam day) | `widgets-watch-engineer` (**Opus high**) | ActivityKit lifecycle, timing, background | attributes, app-side controller, settings toggle, layouts |
| B3 App Intents (Mark done in widget, alarm intents, timetable configuration, "What's next?") | `notifications-engineer` (**Opus high**) | Data-changing intents across processes, xtool metadata gap | intents, the app/extension write path, degrade-to-deeplink |
| QA (each stage + final) | `qa-reviewer` (**Opus high**) | Always Opus | read-only |

Order: A, C1, C2 and C3 run in parallel. B1, B2 and B3 start after A merges. Final QA, then the gate.

## 2. Definition of done
- Both build paths are green; core and UI tests are green; 12 languages are complete.
- Snapshot builder and timeline planner tests cover DST, midnight rollover, an empty day, a holiday, cancelled lessons and time-zone change.
- Widget gallery screenshots in light and dark, inspected by the orchestrator.
- Device checklist `docs/checklists/PHASE4_DEVICE.md`.
- Gate report with the model tier for each task.
