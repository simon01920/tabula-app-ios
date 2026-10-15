# NOTIFICATIONS & REMINDERS

## Why not Critical Alerts
The human asked for reminders that ring even when the phone is silenced. Critical Alerts need a special Apple-approved entitlement that is rarely granted, and a homework app is unlikely to qualify, so do NOT build on it. iOS 26 provides **AlarmKit** (system alarms that ring through Silent and Focus with the same permission model as the Clock app) and **Time Sensitive** notifications (break through Focus/scheduled summary but not the silent switch). Use those.

## Delivery tiers (per reminder rule, user-selectable)
1. **Standard** notification.
2. **Time Sensitive** notification (capability `Time Sensitive Notifications`; user can still deny per-app/Focus).
3. **Loud alarm** via AlarmKit: full-screen alert, sound through Silent/Focus. Needs `NSAlarmKitUsageDescription` and an explicit separate authorisation. Opt-in per rule, clearly described, recommended only for what truly matters (e.g. exam tomorrow). Verify alarm-count limits, repeat/snooze behaviour, Watch behaviour and App Review expectations from Apple docs; record in docs/ENVIRONMENT.md.

## Rule model
A rule = target kind (homework / exam / lesson / pack-tonight) + offsets before due (e.g. 3 days, 1 day, morning-of at 07:00, custom) + optional **second reminder** (follow-up if not completed, e.g. +2 h or next morning) + tier + quiet-hours exceptions. Defaults per profile; fully user-configurable; global and per-task overrides. Notification actions: Mark done, Snooze (1 h / tomorrow).

## Scheduling (64 pending cap)
iOS keeps at most 64 pending local notifications per app. The planner in `TimetableCore` produces a prioritised, rolling window (soonest and highest-tier first) and the app re-plans on launch, foreground, relevant data change, and background refresh. Never drop reminders silently: if the window is saturated, log it and show a gentle in-app notice. AlarmKit alarms are budgeted separately by verified limits.

## Permissions UX
Request in context with a pre-explainer. Provide an in-app "Reminders health check": notification permission, Time Sensitive, AlarmKit authorisation, Focus allow-list hint, Low Power Mode, silent switch explanation, background refresh status.

## Test matrix (on device)
Silent switch on/off · each Focus (DND, Sleep, custom) · Low Power Mode · app force-quit · reboot · time-zone change · DST change · airplane mode · Watch mirrored delivery · permission revoked/re-granted · 100+ tasks (cap behaviour).

## Implementation (Phase 3 Stage A, 2026-10-10)
- **Single source of truth:** `TimetableCore.ReminderPlanner`. The adapter (`TimetableUI/Reminders`, Linux-tested) diffs
  the plan against what is really pending and applies it through `NotificationCenterClient` (UNUserNotificationCenter)
  and `AlarmClient` (AlarmKit). It never decides timing. Re-plan triggers: launch, foreground, data change (1 s debounce,
  coalesced), time zone / locale / significant time change, notification action, AlarmKit authorization change,
  `BGAppRefreshTask`, and an in-app timer at `nextReplanDate`.
- **IDs:** planner `rem.<16 hex>` (wall-clock based, stable across zone changes); snoozes `snooze.<rem id>` (one per
  reminder); health-check test `tabula.test.…`. Non-planner ids are never touched by the diff, except snoozes of
  completed/deleted tasks and exams. Loud alarms use the planner's deterministic UUID; only alarms in the adapter's
  ledger (or with a planner-derived id) are ever cancelled. Diff, never wipe-and-reschedule.
- **In-progress alarms and due notifications** (Stage A QA fix): alarms the daemon reports ringing, snoozed or paused,
  or whose fire time has passed, and pending notifications at or past their fire time are never removed by a re-plan
  unless their task/exam is no longer open; re-plans are kept ≥ 1 min away from every fire instant. The planner's
  reserve of the 64 slots is `max(4, pending snoozes/tests/other requests)`. A change of language, locale, hour cycle
  or zone replaces every planner notification once (render signature).
- **Tiers:** Standard → `.active`; Time Sensitive → `.timeSensitive` (paid entitlement only; otherwise iOS delivers it as
  standard and the health check says so); Loud alarm → AlarmKit `.fixed` alarm with a 9-minute Snooze countdown (Live
  Activity), only from user rules (D7), soft limit 10, learned lower limit after `maximumLimitReached` → overflow is
  delivered as notifications and shown as a notice.
- **Actions:** Mark as Done (task/exam; repeating tasks get their successor per DOMAIN_MODEL §3.9, tombstone-safe),
  Remind Me in 1 Hour, Remind Me Tomorrow (07:00 local), tap → deep link (Tasks/Exams tab, `tasks.detail` /
  `exams.detail` when registered). Foreground presentation: banner + list + sound.
- **Trigger time zone:** calendar trigger with explicit Gregorian calendar + zone = the plan's zone (absolute instant);
  ambiguous DST wall-clock times use an exact interval trigger. Apple does not document the trigger's zone semantics
  (docs/ENVIRONMENT.md §21).
- **Permissions:** never at launch; notification prompt only from explicit UI (B4's pre-explainer), AlarmKit prompt only
  when the user picks a Loud-alarm rule; the adapter never triggers AlarmKit's implicit prompt.
- **In-context offer (Phase 3 final QA fix Q1):** after a user save of a task or exam (editor Save, Tasks quick add,
  lesson detail "Add homework" → task editor, onboarding finish; `AppModel.apply(_:origin: .userSave)`), the re-plan
  that covers it offers the pre-explainer once when `ReminderPermissionOffer.shouldOffer` holds: permission
  `.notDetermined`, ≥ 1 planner request in the plan (`ReminderRunResult.plannedRequestCount`, counted before add
  failures), and not declined before. Closing it while still not determined ("Not Now" or a swipe) is remembered per
  install (`tabula.reminders.permissionOfferDeclined.v1` in the App Group defaults) and the save trigger never offers
  it again; the Settings toggles, the override section and the health check's Allow button still do. Launch,
  foreground, background refresh, timer and notification-action re-plans never offer it. The shell presents it from
  the root (`RootPresentation.swift`) only when no other sheet is open.
- **Deep links over open sheets (QA fix Q6):** a tap is kept as `AppNavigation.pendingLink`; clean tab sheets are asked
  to close (`.closesForDeepLink`), then the item's tab and detail are shown. Editors with unsaved changes, running
  attachment copies and voice recordings (`.protectsUnsavedWork`) are never closed: the target appears right after
  that sheet closes. Links not shown within 10 minutes are dropped (`RootPresentationPolicy`).
- **Health check model:** `ReminderHealthCheck` (rows for notifications, Time Sensitive, loud alarms, Focus, Silent mode,
  Low Power, Background App Refresh, pending vs 64, saturation, alarm overflow, hidden/locked app). UI in B4.
- **Device matrix:** `docs/checklists/PHASE3_DEVICE.md` §A.
