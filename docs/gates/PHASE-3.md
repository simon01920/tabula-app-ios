# Phase 3 gate report — Tasks, exams, reminders (notifications + AlarmKit), health check

Status: **READY FOR REVIEW — waiting for your approval** (2026-10-15) · Plan: `docs/specs/PHASE3_PLAN.md` · Device checklist: `docs/checklists/PHASE3_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| A Reminder adapter + 5-tab shell | notifications-engineer · **Opus high** | Planner→iOS adapter (diff-apply to `UNUserNotificationCenter` + AlarmKit), Mark done / snooze actions, re-plan coordinator (launch, active, data change, time change, BG refresh), permission + health-check models, 5 tabs, Release route gating | `69bfc5e`, `0bf788e`, `5fca444`; 210 UI tests |
| A QA | qa-reviewer · **Opus high** | **Blocking found:** a re-plan cancelled loud alarms that were ringing or snoozed (and could cancel one at its own fire time). Also: stale language in pending notifications, snoozes not counted in the 64 cap, save-after-replan order, zero-debounce cancellation | — |
| A fixes | notifications-engineer · **Opus high** | All fixed. In-progress or past-due alarms are kept unless their item is closed; the re-plan time is never within 1 min of a fire instant; a render signature re-adds notifications on language/format change; the cap reserve follows pending snoozes | `7292eeb`; 8 new tests (218 UI) |
| A delta QA | qa-reviewer · **Opus high** | **All 5 findings fixed; Stage A ready for the gate.** Tests judged meaningful. Residual: a time-zone change during a snoozed loud alarm reschedules it, ending the snooze (device-checklist row) | 253 UI tests, real exit 0 |
| B2 Exams | swiftui-engineer-sonnet · **Sonnet medium** | Exams tab: prominent next exam, countdown, escalation (text + colour), history, editor, exam-period section | `a272a72`, `6452a58`; ~30 tests |
| B4 Reminder settings + health check | swiftui-engineer-sonnet · **Sonnet medium** | Per-kind rules, rule editor (offsets, follow-up, tier with honest explanations, quiet hours), permission pre-explainer (never at launch), health check, per-item override section | `6704172`…`ccc52b3`; 10 tests |
| B1 Tasks | swiftui-engineer-sonnet · **Sonnet medium** | Tasks tab: disjoint segments (Today/Upcoming/Overdue/Completed; a past-time task due today counts as Overdue; undated → Upcoming), subject filter, sort, quick-add, subject-colour completion, swipe actions, editor (subtasks, repeat, "next <subject> lesson" → date + linkedLesson), detail | `20de12b`, `2061d45`, `41d16c1`; merged `738dfe7` (270 UI tests, 1,133 keys) |
| B3 Attachments | sync-storage-engineer · **Opus high** | Store under `<store>/Attachments/<UUID>/<sanitised name>`; atomic copy-in through `.staging`; quota via `EntitlementsProvider.limit(.attachmentQuotaMB)`; orphan cleanup after a 24 h grace, protecting files referenced by an open editor; photo, file, link (open after confirmation) and voice-note sources | `d2b4909`, `f026deb`, `cb1a13f`, `22931f8` |
| B3 QA | qa-reviewer · **Opus high** | **Blocking found:** saving while an attachment was still copying ("Adding…") lost it. Also: cleanup could run after a failed save; folders and symlinks were accepted; voice notes had no retry, interruption handling or limit | — |
| B3 fixes | sync-storage-engineer · **Opus high** | Editor-scoped `AttachmentEditorSession` blocks Save and dismiss while copying (`EditorScaffold.isBusy`); cleanup gated on read-only, problem and saveFailed; folders and links rejected; voice-note retry, interruption handling and size limit | `5eabbeb`, `8351b83`; merged `b854087` |
| B3 delta QA | qa-reviewer · **Opus high** | **Ready.** All blocking and major findings fixed; the new store and policy tests are meaningful (real temp directories, symlink, package). Three low findings (late recorder callback, temp leak after editor close, an unhosted empty state) were folded into the final fix round. The session logic is App-target-only, so it is covered by device rows B3.8a–e | validate ALL CHECKS PASSED (502 core + 316 UI); xtool build, 0 warnings |
| C1 Cross-feature integration | swiftui-engineer · **Opus high** | Today: "Due today" list, overdue chip (→ Tasks › Overdue), next exam within 14 days; lesson-tile badges with a deterministic matching rule (`LessonWork.swift`, PLAN §0.10); lesson detail lists linked tasks with "Add homework for this lesson" (prefilled); richer secondary and university seeds; 17 new screenshot routes | `259bb0a`, `59a1ac2`, `fe60e90` |
| Screenshot review | orchestrator · Opus | Reviewed 17 Phase 3 screens × light/dark/AX-XXXL (51 PNGs, CI run 38598668336). Four findings: the quick-add footer "Due tomorrow" read as the header of the task list; a blank gap in the task-detail Due row; at AX sizes the exam-card title wrapped one syllable per line; the reminder "Times and delivery" rows were indistinguishable for VoiceOver | see *Runtime evidence* |
| Screenshot fixes | swiftui-engineer-sonnet · **Sonnet medium** | Quick-add Due row (label + value) instead of a footer, refreshed on appear, day change and every minute; task-detail Due without an empty icon slot; exam card and rows stack the icon at accessibility sizes; per-kind VoiceOver labels | `e04aa92`, merged `52ec6c1` |
| QA final | qa-reviewer · **Opus high** | **Not gate-ready.** **Blocking:** the notification permission was never offered in the normal flow (onboarding switches rules on; the explainer was wired only to the Settings toggles). **Major:** CI red on HEAD (SwiftPM segfault); Info.plist strings English-only (C2 not done); gate draft stale. **Minor:** an open editor could undo a "Mark done" from a notification; a notification tap did nothing under an open sheet; stale quick-add hint. Confirmed OK: re-plan on every write, repeat successor via the shared caller rule, schema untouched, Release gating, both build paths share one Info.plist | validate ALL CHECKS PASSED (502 + 316); xtool build OK |
| Final QA fixes | notifications-engineer · **Opus high** | **Q1:** in-context permission offer, shown once after the first *user save* that schedules a reminder while permission is undetermined; never at launch, foreground, BG refresh or actions; "Not now" remembered; one root presenter. **Q5:** editors merge with the stored entity at save (a completion made elsewhere is kept; a deleted item is never resurrected). **Q6:** deep links close clean sheets and wait for unsaved editors (never discard edits). Plus the 3 B3 lows | `4012b13`, `d3018b6`; 15 new tests (316 → 331 UI); merged `d227674` |
| C2 Info.plist localisation | localization-engineer-sonnet · **Sonnet medium** | `Resources/InfoPlist.xcstrings` (display name, microphone, camera, photos, AlarmKit) in 12 languages; Xcode compiles it, while the xtool path generates `<lang>.lproj/InfoPlist.strings` (`scripts/infoplist-strings.py`); validate checks the keys against the plist | `744819f`, merged `92e0a72`; xtool bundle shows 13 `InfoPlist.strings` |
| C3 Screenshot routes + CI | (done inside C1 · Opus) | 17 Phase 3 routes added to `ui-screenshots.yml` by C1, so no separate Sonnet task was needed | `59a1ac2` |
| Delta QA (final fixes) | qa-reviewer · **Opus high** | **Gate-ready, no blocking findings.** Confirmed: offer only after `.userSave` (editors, quick add, onboarding) and never at launch, foreground, BG refresh or actions; no polling leak or loop in the deep-link presenter; schema untouched; new keys complete. Medium: the explainer could show twice (override section then root offer). Low: two root-sheet races; xtool widget gets the app's InfoPlist.strings; doc gaps | xtool build at `d227674`: exit 0, **0 warnings** |
| Polish (delta-QA items) | notifications-engineer · **Opus high** | Any explainer closed without an answer records the decline, so the explainer never shows twice. Root sheet state comes from `onAppear` with a 2 s retry, so a link is retried rather than lost. The widget gets no `InfoPlist.strings` on either path (enforced by validate and CI). Docs: reopen never offers; the offer uses the whole plan; Q5 successor note; Q6.7 dropped | `5c5defe`; 3 new tests (334 UI); xtool build 0 warnings, widget 0 `InfoPlist.strings` |

After merging A + A fixes + B2 + B4 (`779f743`), the orchestrator verified: `validate.sh` **ALL CHECKS PASSED**, with **502 core + 253 UI tests** and **1,021 keys complete in 12 languages**; the xtool build passes; pushed.

**Final merged state (`d227674`), verified by the orchestrator:** `validate.sh` **ALL CHECKS PASSED**, with **502 core + 331 UI tests**. The String Catalog has **1,200 keys** and InfoPlist.xcstrings **5 keys**, both complete in 12 languages. The xtool build passes, with 13 localisations and 13 `InfoPlist.strings` in both the app and the widget.

**Tier split:**
- **Opus high:** 6 tasks (A, A fixes, B3, B3 fixes, C1, final QA fixes) plus all 5 QA runs.
- **Sonnet medium:** 5 tasks (B1, B2, B4, screenshot fixes, C2; C3 was absorbed into C1).

The Sonnet work needed one orchestrator-found fix round (the screenshot findings). Every blocking defect in the phase was found by an Opus QA run, on Opus-built work (A, B3) as well as on cross-stage integration (permission flow).

## Runtime evidence
### Screenshot review (orchestrator, CI run 38598668336 at `5cd08b9`: 17 screens × light/dark/AX = 51 PNGs, no crash)
- **Today:**
  - The "Due today" section shows the NEJ task, with a "1 overdue" chip.
  - The next exam card shows "in 9 days".
  - At AX-XXXL the layout reflows without clipping.
- **Timetable grid:** subject tiles carry "1 task" and "Exam" badges exactly where the matching rule puts them.
- **Lesson detail:** a "Homework & tasks" section with "Add homework for this lesson", and the day's change ("Time changed, usually 08:00–08:45").
- **Tasks:**
  - Segment chips: Today (1), Upcoming (4), Overdue (1, red with an icon), Completed.
  - Rows show subject, due text, subtasks 2/5 and repeat.
  - Overdue shows "1 day overdue" in red with an icon, so it is not signalled by colour alone.
  - Slovak works.
  - **Bug:** the quick-add footer read like a list header (fixed).
- **Task detail:** type, due, repeat "Every week on Tue", notes, subtasks with strike-through. **Bug:** a blank gap after Due (fixed).
- **Exams:**
  - The featured "Next Exam — in 9 days" card has date, time, room and topics.
  - The university profile shows the exam period "Skúškové obdobie – zimný semester, Jan 4 – Feb 12, 2 exams" with "in 91 days" / "in 100 days".
  - History shows yesterday's DEJ test.
  - German AX: the title wrapped by syllable (fixed).
- **Reminders:**
  - Settings → Reminders shows a per-kind toggle with a summary ("1 day before, at 17:00", "2 reminders").
  - The health check honestly reports "Some things need a look".
  - The permission pre-explainer says what you get, "no ads, nothing else", and "Not Now".
  - The rule editor shows offsets, the delivery tier and quiet hours.
- **Observation, not a bug:** the seed data is Slovak while the UI is English, so list joins read "limity and derivácie". This is correct behaviour for an English UI.

### Final screenshot verification (orchestrator, CI run 38731163398 at `d227674`: 51 PNGs, no crash)
- **Tasks:** the quick-add card now has a **Due — Tomorrow** row, and no stray "Due tomorrow" text above the list.
- **Task detail:** Type → Due "Today" → Repeat "Every week On Tue" with no gap.
- **Exams, German AX-XXXL:** the subject icon stacks above the title, which wraps by word ("Písomka – organická chémia").
- **Curated set:** 17 screens in [`docs/screenshots/phase3/`](../screenshots/phase3/).

### Final verification of the merged result
- **Last full CI:** iOS CI 38731163246 at `d227674` is green (Linux core and UI tests, XcodeGen iOS + watchOS build, xtool build). Xcode log: `Compile XCStrings InfoPlist.xcstrings` for TabulaApp.
- **Polish merge, verified locally:** `validate.sh` ALL CHECKS PASSED (**502 core + 334 UI tests**, 1,200 keys + 5 InfoPlist keys × 12 languages). The xtool build has 0 warnings, the app 13 `InfoPlist.strings`, the widget 0.
- **Gate push:** iOS CI [38734651111](https://github.com/simon01920/tabula-app-ios/actions/runs/38734651111) at `4bd6828` (includes the polish merge) is **green on all jobs**: Linux core and UI tests and validation; xtool/SwiftPM build (with the widget `InfoPlist.strings` = 0 check); XcodeGen iOS + watchOS build.

### CI
- **Segfault on `b854087`:** iOS CI run 38600687712 failed once. `swift-package` itself segfaulted inside libdispatch during the Linux `swift test Packages/TimetableUI`; it was not a test failure.
- **Rerun:** the failed job was rerun on the same commit and is **green**. This is recorded as a toolchain flake (ENVIRONMENT §22 note); if it recurs, CI gets a single retry.

## Tooling finding (affects all earlier evidence)
`wsl.exe -d Ubuntu -- bash -lc '…; echo $?'` always printed exit 0, because WSL's login shell expands `$?` first. Gate verdicts were based on the scripts' own summary lines, so they stand. All commands now use `--exec`. Recorded in ENVIRONMENT §22 and CLAUDE.md.

## Decisions taken (reviewable)
- **Exams:** shown from all timetables. A past exam that isn't marked done moves to History with "Mark done". For a university profile with no exam-period break and ≥ 2 upcoming exams, a derived "Exam period" section is shown. Topics have no done-state (frozen schema).
- **Reminder settings:** changes apply immediately (no Save/Cancel). A disabled rule is kept, not deleted. The Time Sensitive lead is editable (5–240 min, default 60).
- **Alarms:**
  - Self-imposed cap of 10 per plan, lowered for 24 h after AlarmKit refuses one; the real limit is undocumented.
  - Loud-alarm snooze is 9 min, the iOS Clock default.
  - Alarm stop/snooze cannot mark an item done; that needs App Intents (RISKS #51).
- **Notification triggers** use an explicit calendar and time zone. Fall-back DST-ambiguous times use interval triggers. Apple doesn't document the time-zone handling, so device check A-TZ decides.
- **Permission (final QA fix):**
  - The explainer appears once, after the first save of a task or exam (also quick-add, "Add homework" and onboarding finish) that schedules at least one reminder while iOS permission is still undetermined.
  - "Not now" is final for that trigger. The Settings toggles and the health check still offer it.
- **Deep links over sheets:** clean sheets close for a notification tap. An editor with unsaved changes is never closed; the target opens right after the user saves or cancels. A link older than 10 minutes is dropped.
- **Editors vs. outside changes:** saving merges with the stored item. A completion made meanwhile (e.g. Mark done from a notification) is kept. An item deleted meanwhile shows "could not be applied" and is not resurrected.
- **Quick add:**
  - With a subject, the due date is that subject's next lesson; otherwise it is tomorrow.
  - The due date is shown as a row in the quick-add card.
- **Today:** the next exam is shown only when it is ≤ 14 days away.

## Not done / known limits
- **No physical device:**
  - **What is verified:** compile, Linux tests and simulator screenshots.
  - **What only the device checklist (`docs/checklists/PHASE3_DEVICE.md`, about 270 rows) can verify:**
    - every *delivery* behaviour: notifications on the lock screen, Time Sensitive, AlarmKit loud alarms (silent mode, Focus, snooze), notification actions;
    - background refresh;
    - the permission prompt flow;
    - voice recording and photo/file import;
    - VoiceOver.
  - Phase 3 is the most device-dependent phase so far.
- **Time Sensitive needs the paid account:** the entitlement sits only in the paid entitlements file. Until then, iOS delivers these reminders as standard ones, and the health check says so.
- **Loud alarms cannot mark an item done** from Stop/Snooze; that needs App Intents (RISKS #51). Mark done works from normal notifications.
- **Attachment files do not sync** yet; only their references do. The bytes stay on the device until CloudKit assets arrive in Phase 6 (RISKS #55).
- **Translations are machine-made:** about 1,200 + 5 keys × 12 languages, all `needs_review` (`docs/localization/REVIEW.md`).
- **Xcode-path InfoPlist localisation is unproven** until CI lists `sk.lproj/InfoPlist.strings` in the bundle (ENVIRONMENT, "UNVERIFIED").
- **Open risks this phase:** #50–#60 in `docs/RISKS.md`.
  - #53: orphan loud alarms after a lost adapter ledger.
  - #58: UIKit sheet detection.
  - #59: an edge case with Quick Look over a dirty editor.

## Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P3-1** | **Approve Phase 3** and move on to Phase 4 (widgets and Live Activity) | Approve |
| P3-2 | *(re-asked P2-2)* **Subject order:** add an optional `sortIndex` to `Subject` (additive schema change, needs your approval), or keep alphabetical | Add it (small, backward compatible). It also orders subject pickers in Tasks/Exams |
| P3-3 | *(re-asked P2-5)* **Native review of translations:** who reviews sk/cs/pl/hu/ro/de/fr/uk/sr/ja/zh? | You review Slovak now; the others before release (Phase 11) |
| P3-4 | **Permission "Not now" is final** for the save trigger (RISKS #60). Alternative: ask again after N days or N saves | Keep it final: it is less naggy, and Settings and the health check still offer it |
| P3-5 | **Loud alarm Stop/Snooze → Mark done** needs App Intents (`LiveActivityIntent`) | Do it in Phase 4, together with the Live Activity / widget intents work |
| P3-6 | **Exam-day countdown:** today it shows days ("Today", "Tomorrow", "in N days"). Option: a live hours/minutes countdown on exam day | Add it in Phase 4 as a Live Activity (natural fit) |
| P3-7 | **Device testing:** Phase 3 delivery behaviour needs the iPhone (and the Watch for alarms). When can we run `PHASE3_DEVICE.md`? | Before Phase 5 at the latest; a free Apple ID install covers most rows except Time Sensitive |

## Next: Phase 4 preview
- **Widgets:** WidgetKit in all families (Home, Lock Screen, StandBy) with Now/Next, today's lessons, due tasks and the next exam.
- **Live Activity:** the current lesson, and the exam countdown (P3-6).
- **App Intents:** "Mark done" from widgets and alarms (P3-5). Whether `LiveActivityIntent` works on both build paths must be proven first (RISKS #51).
