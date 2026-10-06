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
