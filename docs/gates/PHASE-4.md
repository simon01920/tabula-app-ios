# Phase 4 gate report — Widgets, Live Activities, App Intents (+ Phase 3 carry-overs)

Status: **READY FOR REVIEW — waiting for your approval** (2026-10-23) · Plan: `docs/specs/PHASE4_PLAN.md` · Device checklist: `docs/checklists/PHASE4_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| A Snapshot + widget foundation + *Now & Next* | widgets-watch-engineer · **Opus high** | `WidgetSnapshot` (versioned JSON in the App Group, wall-clock values) with a pure builder; a timeline planner identical to the Today header (≤ 29 entries, reload ≤ 6 h); the app writes the snapshot on every change (debounced, atomic, unchanged content skipped); shared views in TimetableUI; *Now & Next* in small, medium and the three Lock Screen families; Pro gate; `tabula://open/…` deep links; DEBUG widget gallery | `c9577d5`, `7684124`; 36 tests |
| A QA | qa-reviewer · **Opus high** | Ready apart from doc collisions. **Major:** a stale timeline after a time-zone change (no reload for days). Nine minors (dead preview timer, frozen last entry, writer rewriting on every launch, contrast) | — |
| A fixes | widgets-watch-engineer · **Opus high** | Reload capped at 6 h plus a system time-zone reset; cut at midnight; cheap live preview; writer seeded from disk; background-task assertion; contrast-safe progress tint | `b192aaf`, `5318422`; merged `85005ee` |
| C1 `Subject.sortIndex` (approved P3-2) | core-domain-engineer · **Opus high** | Optional field, **no schema bump**: old files re-encode byte for byte, and older apps keep the value via `UnknownFields`. Canonical order (index, then name, then id); dense reorder stamps only the changed subjects; share key `s[i].o`; reorder UI with VoiceOver move actions; every subject list and picker follows the order | `03fdd7a`, `b4b5046`, `210c97e`; 37 core + 6 UI tests |
| C1 QA → fixes | qa-reviewer → core-domain-engineer · **Opus** | Ready. **Major:** two "Done" buttons in reorder mode. Minors: an `Int.max` overflow trap, an empty save from a no-op drag, no VoiceOver position announcement, a footer saying "Tap Edit" while Edit is disabled. All fixed | `45015a6`; merged `36da8b2` |
| C2 Translation review document (P3-3) | localization-engineer-sonnet · **Sonnet medium** | `docs/localization/review/index.html`: every phrase side by side in 13 languages, with filter, search and placeholder highlighting. Per-language CSVs (BOM, `;`-tolerant) with `corrected`/`note` columns and `[ok]` approval; `l10n-review-import.py` with placeholder validation; a 30-check round-trip test; a staleness hash in validate | `2a8c1a4`; merged `b6de569`. Layout checked in the browser by the orchestrator |
| C3 Device runbook (P3-7) | env-ci-engineer-sonnet · **Sonnet medium** | `docs/DEVICE_SETUP.md` and `scripts/device-doctor.sh` | `d6e2052`; merged `2890df9` |
| First device install | orchestrator · Opus (with the human) | USB/IP pairs, but the app upload hangs (usbmuxd bug). The **working route is Apple Devices + `scripts/win-usbmuxd-relay.py`**. xtool 1.22.2 is needed for login (1.20.1 fails with -80045). **Tabula was installed on the iPhone 16 Pro (iOS 27.0.1)** | `6a776f3`; ENVIRONMENT §29 |
| B1 *Today*, *Homework*, *Next exam* widgets | widgets-watch-engineer-sonnet · **Sonnet medium** | All three static widgets with gallery pages; overdue tasks first; escalating exam countdown; checkbox seam for B3 | `5028993`; 425 UI tests |
| B1 QA → fixes | qa-reviewer · **Opus** → Sonnet | Not ready. **Majors:** the exam widget showed a finished exam and went dark the next day; the snapshot could reach 23–27 KB (over the Watch budget); the Homework count was partial. Fixed with an exams list and rollover, a 19,000 B trim, and a true `openTaskCount`; plus 8 minors | `e982102`; merged `845279f` |
| B2 Live Activities (current lesson + exam day, P3-6) | widgets-watch-engineer · **Opus high** | Pure planner (start, update, end, adopt after relaunch, swipe-away ledger); `ContentState` with the day's instants, so the timers count without updates; Lock Screen and Dynamic Island layouts; Settings → Live Activities. iOS 26's scheduled start is behind "Start automatically" (**default off**, P4-B2-1) | `4f979ce` |
| B2 QA → fixes | qa-reviewer · **Opus** → Opus | Not ready. **Blocking:** turning off auto-start did not cancel scheduled starts. **Majors:** a moved exam was never shown again; a pending activity changed in the background was lost; a ledger race. All fixed, with 15 new tests | `869b3e8`, `c192a0f`; merged `0274dc6` |
| B3 App Intents (P3-5) | notifications-engineer · **Opus high** | `MarkTaskDone`/`MarkExamDone` as `LiveActivityIntent`s running in the app process, through the same mutation as notification Mark done (idempotent, one successor); widget checkbox; loud-alarm **Done**; timetable choice for Now & Next and Today; App Shortcuts "What's next?" and "Add homework". **The xtool dev build has no intent metadata**, so a compile-time flag gives it the old links and Snooze | `9bb4672`; 17 tests (484 UI) |
| QA final | qa-reviewer · **Opus high** | **Gate-ready** (no blocking). **Majors:** marking an exam done didn't await the Live Activity end; the Xcode build with App Intents was unproven until CI ran. Confirmed the B1 and B2 fixes, snapshot compatibility, the frozen schema and the docs numbering | 540 core + 484 UI tests; clean xtool builds (base + `--app-intents`) |
| B3 final fixes | notifications-engineer · **Opus high** | Exam/task Done awaits the Live Activity end and the widget flush (intent and notification paths); a failed Done still stops the alarm; **hard snapshot budget** (true worst case 16,383 B ≤ 19,000); 44×44 pt checkbox (on TestFlight builds medium shows 2 rows, large 7; RISKS #85); "Open Tabula" Siri fallback; timetable picker not discoverable; flush before removing notifications; the alarm button policy is part of the render signature | `8376f9a`; merged `c47e808`; 487 UI tests; clean builds with 0 warnings (base + `--app-intents`) |
| Xcode path with App Intents | CI | **iOS CI green on `c47e808`**: the XcodeGen iOS + watchOS build with `TABULA_APP_INTENTS` (App Intents metadata, `AppShortcuts.xcstrings`), the Linux tests and the xtool path. This settles final-QA major M2 | run 39877356548 |
| Widget visual fixes (orchestrator screenshot review) | widgets-watch-engineer-sonnet · **Sonnet medium** | Live Activity titles cut with "…" at 48 chars / 112 B (not mid-word at 24); Homework rows primary/secondary instead of link blue; exam Lock Screen line "Thu 22 · 10:00 · room" (no truncated end time); gallery captions in the scene's zone | `ccb5873`; merged `d894f1b`; 489 UI tests |
| ECC agents/skills (human request) | orchestrator | Installed a vetted subset of everything-claude-code (Swift reviewers, a11y, SwiftUI / Liquid Glass / concurrency skills); details in `.claude/THIRD_PARTY.md` | `1e5fb80` |

**Tier split:** Opus high did A, C1, B2 and B3 (plus their fix rounds) and all 6 QA runs. Sonnet medium did C2, C3 and B1 (plus B1's fix round). Every blocking and major defect was found by an Opus QA run: 2 on Opus-built stages (B2, B3), 3 on Sonnet-built B1.

## Runtime evidence
### Final merged state (`d894f1b` and later), verified
- **iOS CI** green on `c47e808` (run 39877356548) and on `d894f1b` (run 39878488985). Each run covers:
  - the Linux core and UI tests;
  - the XcodeGen iOS + watchOS build **with App Intents**;
  - the xtool path.
- **validate.sh** ALL CHECKS PASSED: **540 core + 489 UI tests**; String Catalog about 1,266 keys, InfoPlist 5 keys and AppShortcuts 4 phrases, each complete in 12 languages.
- **Clean xtool builds** have 0 warnings: the base variant (what we install on the phone) and the `--app-intents` variant.
- **Snapshot:** the true worst case is 16,383 B against a hard cap of 19,000 B, so the Watch (< 20 KB) can reuse it.

### Screenshot review (orchestrator)
- **Widget and Live Activity galleries** (run 39874696823) were reviewed.
- **Four visual defects** were found and fixed (`ccb5873`):
  1. a Live Activity title cut mid-word;
  2. Homework rows in link blue with a low-contrast due line;
  3. a truncated exam time on the Lock Screen;
  4. gallery captions in UTC.
- **The fixes were checked in run 39878489004:** the full subject name now shows, and captions read 10:20.
- **Good, no change needed:** the Today widget (past lessons dimmed, the current one highlighted, tomorrow after school), the exam countdown escalation, Pro and "Open Tabula" states, the Live Activities settings, and the subject reorder list.
- The curated set is in [`docs/screenshots/phase4/`](../screenshots/phase4/).

### UI/UX review package (human request)
- **Contents:** **185 screenshots, 65 screen/seed/language combinations, 8 sections:**
  - onboarding, Today, Timetable (all 5 views), editors, Tasks, Exams, Settings;
  - widgets and Live Activities;
  - light, dark and largest text, plus Slovak for the key screens.
- **How it was made:** iOS Simulator, CI runs 39877562723, 39877566060, 39877569444 and 39878489004.
- **Where:** index at [`docs/ux-review/README.md`](../ux-review/README.md), with context for the reviewer, what each screen is and how to reach it. The images are in `docs/ux-review/screens/`, kept local and git-ignored because of size. Regenerate with `scripts/ux-review-index.py`.
- **Next step:** this is the input for the human's UX consultation, which produces `design_ui_ux_fix.md`.

### Device
- **Done:** the Phase 3/4 dev build is **installed on the iPhone 16 Pro** (2026-10-16) through the relay route.
- **Not yet run:**
  - `PHASE4_DEVICE.md`;
  - the earlier device checklists;
  - everything that needs TestFlight.

## Not done / known limits
- **Real widget data needs an App Group.** Free-team dev builds on the phone show "Open Tabula" in widgets. Live Activities and everything else work without it (RISKS #65).
- **All App Intent behaviour needs a TestFlight build, so the paid account:**
  - the widget checkbox;
  - alarm Done;
  - the timetable picker;
  - Siri / Shortcuts.
- **Untested Live Activity behaviour:** the switch to the next lesson without the app (stale-date redraw, RISKS #73), background refresh timing, and how intrusive the alert is when an activity starts automatically. Device checklist only.
- **Translations:** all new strings are machine-made `needs_review`. Use the review document in `docs/localization/review/`.
- **Watch is Phase 5:** complications and Smart Stack. The snapshot is already sized for it.

## Decisions taken (reviewable)
- Widgets read only a snapshot written by the app, never the database. The free team has no App Group, so dev builds on the phone show **"Open Tabula"** in widgets; real widget data needs the paid team or TestFlight (RISKS #65).
- Everything is `StaticConfiguration` first. App Intent features exist only in Xcode/TestFlight builds (flag `TABULA_APP_INTENTS`), because xtool cannot produce intent metadata.
- Live Activities start only from the foreground unless "Start automatically" is on, because every scheduled start alerts. Exams outrank lessons in the Dynamic Island.
- The snapshot stays at version 1. All new keys are optional, so older readers ignore them.
- CI: the repo became **public** (the human's decision, Actions billing). The screenshot timeout was raised to 45 min.

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P4-1** | **Approve Phase 4** and continue to Phase 5 (Watch) | Approve |
| P4-2 | P4-B2-1: "Start automatically" Live Activities default **off** (each scheduled start lights the screen and plays a sound) | Keep off; try it on the device |
| P4-3 | Lock Screen privacy: Live Activities show the subject, room and exam title on a locked phone. Add a "Hide details on Lock Screen" option? | Add it in the UI/UX overhaul |
| P4-4 | RISKS #82: task and exam **loud alarms show "Done" instead of "Snooze"** (AlarmKit allows only one extra button). This changes the 9-minute Snooze in NOTIFICATIONS.md | Accept "Done" (it closes the loop); Snooze stays for lesson, pack-tonight and test alarms |
| P4-5 | The "Add homework" Siri/Shortcuts action was not in the plan; it only opens the editor | Accept |
| P4-6 | All App Intent behaviour (widget checkbox, alarm Done, timetable picker, Siri) is unverifiable until a TestFlight build exists, which needs the paid account | Accept for now; it goes on the paid-account switchover list |

## Next
- **UI/UX overhaul:** when `design_ui_ux_fix.md` arrives, it gets its own plan. It covers the app screens, widgets and Live Activities, using the installed `liquid-glass-design`, `swiftui-patterns` and `accessibility` skills.
- **Phase 5:** Watch app and complications (today/tomorrow, current lesson countdown, next lesson, Smart Stack, offline cache from the snapshot).
