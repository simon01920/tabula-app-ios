# Phase 3 plan — Tasks, exams, reminders (notifications + AlarmKit), health check

Status: started 2026-10-10 (the human approved Phase 2 and asked for Phase 3 end-to-end). Orchestrator: Opus 5.5.
ROADMAP: attachments, subtasks, priorities, exams tab, rule model, planner, Time Sensitive, AlarmKit alarms, health check screen.
Specs: PRODUCT.md (Tasks, Exams), NOTIFICATIONS.md, `docs/spikes/ALARMKIT.md`, DOMAIN_MODEL.md (**frozen**, and it already has `TaskItem`, `Subtask`, `AttachmentRef`, `Exam`, `ReminderRule`, `ReminderOverride`, so no schema change is needed), the Phase 1 reminder planner (`TimetableCore/Reminders`).

## 0. Decisions
1. **Tabs:** Today · Timetable · **Tasks** · **Exams** · Settings (5 tabs, iOS 26 `TabView`).
2. **The planner stays the single source of truth.** The iOS adapter only *applies* `ReminderPlan` diffs to `UNUserNotificationCenter` and `AlarmManager`. It never decides timing.
   - **Re-plan triggers:** launch, foreground, any data change (debounced), significant time change / time zone / locale, a notification action, and `BGAppRefreshTask` (verify the API and Info.plist keys in Apple's docs).
   - **IDs:** planner IDs (`rem.` prefix). Snoozes use a separate prefix the planner ignores.
3. **Delivery tiers:**
   - **Standard.**
   - **Time Sensitive:** `interruptionLevel = .timeSensitive`. The entitlement is paid-only, so it lives in the CI-only paid entitlements file. Without it, iOS delivers the notification as standard, and the health check says so.
   - **Loud alarm:** AlarmKit, used only from user-created rules (D7), with fixed-time alarms and stop/snooze via the existing `AlarmLiveActivity`.
   - Phase 0 findings apply: there is no fixed alarm limit (handle `maximumLimitReached`), and alarms need their own authorisation.
4. **Notification actions:** *Mark done* (applies `completedAt` and creates the repeat successor via `TaskItem.nextOccurrence`, following the caller rule) and *Snooze 1 h / Tomorrow morning*. Handled in the app's `UNUserNotificationCenterDelegate`; no extension needed.
5. **Permissions in context**, never at launch: a pre-explainer sheet the first time a reminder would be scheduled; AlarmKit authorisation only when the user picks the *Loud alarm* tier.
6. **Reminders health check** (Settings → Reminders):
   - permission states: notifications, Time Sensitive setting, AlarmKit;
   - a Focus allow-list hint;
   - Low Power Mode;
   - Background App Refresh status;
   - an explanation of silent mode / Action button;
   - pending count against the 64 cap, plus a saturation notice;
   - a "send test notification" button (and a test alarm when authorised).
7. **Attachments:**
   - Files live in the App Group container under `Attachments/<attachmentID>/<fileName>`; the database holds only an `AttachmentRef`.
   - Sources: photos (PhotosPicker), files (fileImporter, copied in), links (never opened automatically; open with confirmation), voice notes (AVAudioRecorder, which needs `NSMicrophoneUsageDescription`).
   - Free/Pro quota comes from `EntitlementsProvider.limit(.attachmentBytes)` (all-access for now).
   - Orphaned files (no live reference) are cleaned up after deletion and at launch. Atomic copy-in; never delete a file a live ref points to.
8. **Tasks:**
   - Tabs: Today / Upcoming / Overdue / Completed. Filter by subject; sort by due or priority.
   - Quick add, and an editor with: title, kind, subject, due (date / date+time / "next <subject> lesson" resolved via the schedule engine → `linkedLesson`), priority, notes, subtasks (reorder, check), repeat, reminder override, attachments.
   - Completing a repeating task inserts its successor.
9. **Exams:** upcoming prominent (date/time, subject, room, topics, countdown, colour escalating with closeness), history, editor (kind, date, times, room/building, topics, notes, reminder override), and a university exam-period view (from `CalendarBreak.kind == examPeriod`).
10. **Cross-feature:**
    - Today shows "Due today" tasks and the next exam.
    - Timetable lesson tiles get badges ("2 tasks", "Exam") — the reference pattern.
    - Lesson detail lists linked tasks with "Add homework for this lesson".
11. **Release hygiene:** `-TabulaScreen` routes work only in DEBUG (Phase 2 decision P2-6).
12. **Info.plist strings** (camera/microphone/AlarmKit, display name) get localised via `InfoPlist.xcstrings` on the Xcode path and generated `InfoPlist.strings` on the xtool path.
13. **Unchanged constraints:**
    - Subject order stays alphabetical (the schema change needs explicit human approval).
    - No physical device: notification and alarm *delivery* is device-checklist only. Simulator screenshots cover the UI and the health check.

## 1. Stages, model tier, ownership
| Stage | Agent (tier) | Why this tier | Scope |
|---|---|---|---|
| A Reminder engine adapter + shell | `notifications-engineer` (**Opus high**) | OS integration, data-changing actions, timing correctness | `App/Sources/Reminders/**` (scheduler, AlarmKit adapter, delegate/actions, re-plan coordinator, BG refresh, permission service, health-check model), 5-tab shell, stub roots `TasksRootView`/`ExamsRootView`, stub components `AttachmentsSection`/`ReminderOverrideSection`, Release route gating |
| B1 Tasks | `swiftui-engineer-sonnet` (Sonnet medium) | Well-specified lists/forms on an existing foundation | `App/Sources/Tasks/**`, pure logic in `TimetableUI/Tasks/` |
| B2 Exams | `swiftui-engineer-sonnet` (Sonnet medium) | Same | `App/Sources/Exams/**`, `TimetableUI/Exams/` |
| B3 Attachments | `sync-storage-engineer` (**Opus high**) | File storage, quota, orphan cleanup, data-loss risk | `App/Sources/Attachments/**`, `TimetableUI/Attachments/` |
| B4 Reminder settings + health check UI + override component | `swiftui-engineer-sonnet` (Sonnet medium) | Forms on Stage A's models | `App/Sources/Settings/Reminders*`, `App/Sources/Reminders/UI/**` |
| C1 Cross-feature integration (Today, lesson badges, lesson detail) | `swiftui-engineer` (**Opus high**) | Touches the core views and the schedule engine | Today/Timetable files |
| C2 Localisation (new keys × 12, InfoPlist strings) | `localization-engineer-sonnet` | Mechanical | catalog, InfoPlist |
| C3 Screenshot routes + CI | `env-ci-engineer-sonnet` | Mechanical | workflow list |
| QA (each stage gate + final) | `qa-reviewer` (**Opus high**) | Always Opus | read-only |

## 2. Definition of done
- Both build paths green; core and UI tests green; 12 languages complete.
- Simulator screenshots of the Tasks/Exams/editor/health-check routes (light/dark/AX, sk + de), inspected by the orchestrator.
- Planner→adapter diff logic unit-tested (TimetableUI seam, fake notification centre).
- Device checklist: `docs/checklists/PHASE3_DEVICE.md`, with the NOTIFICATIONS.md test matrix.
- Gate report with the per-task model tier.
