# Phase 3 gate report — Tasks, exams, reminders (notifications + AlarmKit), health check

Status: **DRAFT — B1/B3 finishing, integration pending** · Plan: `docs/specs/PHASE3_PLAN.md` · Device checklist: `docs/checklists/PHASE3_DEVICE.md`

## Stages and model tier
| Stage | Agent / tier | Result | Evidence |
|---|---|---|---|
| A Reminder adapter + 5-tab shell | notifications-engineer · **Opus high** | Planner→iOS adapter (diff-apply to `UNUserNotificationCenter` + AlarmKit), Mark done / snooze actions, re-plan coordinator (launch, active, data change, time change, BG refresh), permission + health-check models, 5 tabs, Release route gating | `69bfc5e`, `0bf788e`, `5fca444`; 210 UI tests |
| A QA | qa-reviewer · **Opus high** | **Blocking found:** a re-plan cancelled loud alarms that were ringing or snoozed (and could cancel one at its own fire time). Also: stale language in pending notifications, snoozes not counted in the 64 cap, save-after-replan order, zero-debounce cancellation | — |
| A fixes | notifications-engineer · **Opus high** | All fixed. In-progress or past-due alarms are kept unless their item is closed; the re-plan time is never within 1 min of a fire instant; a render signature re-adds notifications on language/format change; the cap reserve follows pending snoozes | `7292eeb`; 8 new tests (218 UI) |
| A delta QA | qa-reviewer · **Opus high** | **All 5 findings fixed; Stage A ready for the gate.** Tests judged meaningful. Residual: a time-zone change during a snoozed loud alarm reschedules it, ending the snooze (device-checklist row) | 253 UI tests, real exit 0 |
| B2 Exams | swiftui-engineer-sonnet · **Sonnet medium** | Exams tab: prominent next exam, countdown, escalation (text + colour), history, editor, exam-period section | `a272a72`, `6452a58`; ~30 tests |
| B4 Reminder settings + health check | swiftui-engineer-sonnet · **Sonnet medium** | Per-kind rules, rule editor (offsets, follow-up, tier with honest explanations, quiet hours), permission pre-explainer (never at launch), health check, per-item override section | `6704172`…`ccc52b3`; 10 tests |
| B1 Tasks | swiftui-engineer-sonnet · **Sonnet medium** | _finishing_ | |
| B3 Attachments | sync-storage-engineer · **Opus high** | _finishing_ | |
| C1 Cross-feature integration | swiftui-engineer · **Opus high** | _pending_ | |
| QA final | qa-reviewer · **Opus high** | _pending_ | |

After merging A + A fixes + B2 + B4 (`779f743`), the orchestrator verified: `validate.sh` **ALL CHECKS PASSED**, with **502 core + 253 UI tests** and **1,021 keys complete in 12 languages**; the xtool build passes; pushed.

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
