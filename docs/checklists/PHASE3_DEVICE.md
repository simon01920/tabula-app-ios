# Phase 3 — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x) + Apple Watch Series 7 (watchOS 26.x). Same format as `PHASE2_DEVICE.md`:
**Setup → Steps → Expected**, plus an Observed column and ✔ / ✘ / ? (unclear). Each Phase 3 stage appends its own
section. Notification and alarm **delivery** cannot be simulated (no Mac, no Simulator locally): everything in section
A is device-only.

iOS version: ________ · watchOS version: ________ · Haptics in Silent Mode: on / off · Build: xtool / TestFlight ·
Tester: ________ · Date: ________

---

## A. Reminder engine adapter (Stage A — notifications, Time Sensitive, loud alarms, actions, background refresh)

Implements NOTIFICATIONS.md "Test matrix (on device)", extended with the Phase 0 spike's findings
(`docs/spikes/ALARMKIT.md` §5, §8). Phase 0 probe rows (ALARMKIT.md §11) test the raw APIs; the rows here test the
**app's adapter** (planner → diff → `UNUserNotificationCenter` / AlarmKit).

### A0. Setup and tools
- **Builds.** Local xtool build (`bash scripts/xtool-dev.sh`): free account, so **no Time Sensitive entitlement** —
  run the TS rows only as "E0/E9-style" observations (what iOS does without it). Rows marked **[TS]** need a
  CI/TestFlight build with `TABULA_PAID_ACCOUNT=1` (paid account, deferred).
- **Data.** Until stages B1/B2 merge there is no task/exam editor. Use the real store (onboarding → *Elementary*
  profile: its preset "pack tonight" rule fires at 19:00 the evening before a school day with a bring-list; add a
  bring-list item to tomorrow's first lesson in the lesson editor) and **Settings → Developer → Reminders** (DEBUG):
  "Send test notification (5 s)", "Schedule test alarm (60 s)", "Re-plan now", permission buttons, last-run report,
  health rows. After B1/B2: add a homework due tomorrow 08:00 (preset homework rule: day before at 17:00) and an exam;
  for quick tests give an item a custom reminder a few minutes ahead (B4 override UI).
- **Loud alarms** come only from a **user** rule with tier Loud alarm (decision D7) and need *Settings → Reminders →
  loud alarms on* + AlarmKit permission (B4 UI). Until B4: the developer screen's "Schedule test alarm" exercises the
  same `LiveAlarmClient` path (fixed schedule, Snooze countdown, `TabulaAlarmMetadata`).
- **Seed mode never schedules for real**: `-TabulaSeed …` uses in-memory clients (developer screen shows
  "Clients: in-memory fakes"). Add `-TabulaReminders live` only when you deliberately want sample data on the device.
- iPhone 16 Pro Max has **no Ring/Silent switch**: toggle Silent with the Action button or Control Center.
- Default state unless a row says otherwise: phone locked, face up, Silent ON, no Focus, Low Power OFF, Watch off
  wrist, app in the background (not force-quit), Wi-Fi on.

### A1. Permissions, registration, first plan
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A1.1 | Fresh install, launch, finish onboarding | **No** permission prompt at launch (PHASE3_PLAN §0.5). Developer → Reminders: last run "launch", health "Notifications: Not allowed yet" | | |
| A1.2 | Developer → "Request notification permission" → Allow | System prompt (alert + sound, no badge option). Health row → "Allowed."; a re-plan runs (reason "permission") | | |
| A1.3 | Developer → "Send test notification", lock | Banner + sound after ~5 s, title "Test reminder" in the device language | | |
| A1.4 | Long-press a delivered planned reminder (task/exam) | Actions **Mark as Done · Remind Me in 1 Hour · Remind Me Tomorrow** with icons, localised. Pack tonight: only "in 1 Hour"; lesson: none | | |
| A1.5 | Settings → Notifications → Tabula → off; return to app | Health row "Turned off in Settings…" (problem) with "Open Settings"; re-plan still runs without errors (`add` may fail → listed under Failures) | | |
| A1.6 | Re-enable notifications, return | Row back to "Allowed."; pending count restored after the re-plan | | |
| A1.7 | Developer → "Request AlarmKit permission" | Separate AlarmKit prompt with the `NSAlarmKitUsageDescription` text; row "Loud alarms: Allowed." (only shown when a Loud-alarm rule exists) | | |
| A1.8 | Developer → health rows | Low Power, Background App Refresh, pending "Scheduled: n (iOS limit: 64)", Focus + Silent hints, all localised | | |

### A2. Delivery matrix — Standard notification (planned reminder or test notification)
| ID | Condition | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A2.1 | Silent OFF | Banner + default sound | | |
| A2.2 | Silent ON | Banner, **no sound** (haptic only if Haptics in Silent Mode on) | | |
| A2.3 | Focus: Do Not Disturb (Tabula not allowed) | Silenced, appears in Notification Center | | |
| A2.4 | Focus: Sleep | Silenced | | |
| A2.5 | Focus: custom "School", Tabula **allowed** | Delivered with banner | | |
| A2.6 | Focus: custom, Tabula **not** allowed | Silenced | | |
| A2.7 | Low Power Mode ON | Delivered on time (local notifications do not need the app) | | |
| A2.8 | Schedule (re-plan), then **force-quit** Tabula | Delivered on time | | |
| A2.9 | Re-plan, then **reboot**, unlock once | Delivered on time (or right after boot if the time passed during boot — record) | | |
| A2.10 | App **in foreground** when it fires | Banner + sound shown (delegate presents `.banner, .list, .sound`) | | |
| A2.11 | Airplane mode ON | Delivered | | |
| A2.12 | Watch on wrist, iPhone locked (mirroring) | Shown on the Watch with the same actions; Mark done from the Watch works (see A5.1) | | |

### A3. Delivery matrix — Time Sensitive
> Planner rule D6: Time Sensitive only when the reminder fires ≤ 60 min before the item (else Standard). Use a
> "30 minutes before" offset. **[TS]** rows need the paid-account build.

| ID | Condition | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A3.0 | xtool build: read health row "Time Sensitive" | Record the value (expected "Not available in this version…" = `notSupported`; ALARMKIT.md Q4) and whether a TS reminder still arrives as Standard | | |
| A3.1 [TS] | Silent ON | **No sound** (TS does not override Silent) | | |
| A3.2 [TS] | DND Focus, Tabula not allowed, Focus "Time Sensitive Notifications" allowed | **Breaks through** (banner, screen lights) | | |
| A3.3 [TS] | Same, Focus TS allowance OFF | Held like Standard | | |
| A3.4 [TS] | Sleep Focus | Record | | |
| A3.5 [TS] | First TS delivery ever | System explains Time Sensitive and offers to turn it off | | |
| A3.6 [TS] | Settings → Notifications → Tabula → Time Sensitive OFF | Health row "Turned off…"; delivery like Standard | | |
| A3.7 [TS] | Watch on wrist | Delivered; swipe offers "Turn off Time Sensitive" | | |
| A3.8 [TS] | Low Power ON / force-quit / reboot | Same as A2.7–A2.9 | | |

### A4. Delivery matrix — Loud alarm (AlarmKit)
> Use a user rule with tier Loud alarm (after B4) or the developer "Schedule test alarm (60 s)".

| ID | Condition | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A4.1 | Silent OFF | Full-screen alarm, title = the reminder title (e.g. "Exam: Maths test"), sound | | |
| A4.2 | Silent ON | **Rings with sound** | | |
| A4.3 | DND / Sleep / custom Focus (Tabula not allowed) | Rings in every Focus | | |
| A4.4 | Low Power ON | Undocumented — record (expected to ring) | | |
| A4.5 | Force-quit after scheduling | Rings | | |
| A4.6 | Reboot, unlock once | Rings | | |
| A4.7 | Reboot, do **not** unlock | Record (system countdown UI only before first unlock, F14) | | |
| A4.8 | App unlocked in the foreground | Record (forum: may be silent/no UI) | | |
| A4.9 | Tap **Snooze** | Countdown Live Activity "Snoozed: …" (Lock Screen + Dynamic Island, localised); rings again after **9 min** | | |
| A4.10 | Press side or volume button while ringing | Stops | | |
| A4.11 | Watch on wrist (mirroring) | Alert forwarded to the Watch; record haptic/sound and whether Stop/Snooze work there | | |
| A4.12 | Tabula hidden or "Require Face ID" | **Does not ring** (silent failure, F6); health row "Hidden or locked app" explains it | | |
| A4.13 | Settings → Tabula → Alarms OFF, return to app | Re-plan runs (reason "alarmAuthorization"); the loud-alarm reminder becomes a Time Sensitive notification (developer screen: alarm count 0, tier change "alarmsUnavailable"); health row "Turned off…" | | |
| A4.14 | Mark the exam done (A5) | Its alarm is cancelled (developer screen: "−1 alarms"); nothing rings | | |
| A4.15 | Debug probe alarm (Phase 0 probes) scheduled, then re-plan | Probe alarm untouched (not in the adapter's ledger) | | |

### A5. Actions, snooze, deep links
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A5.1 | Locked phone: long-press a homework reminder → **Mark as Done** (app not running) | App does not open; afterwards the task shows completed; its follow-up reminders are gone (developer: re-plan reason "notificationAction") | | |
| A5.2 | Mark done on a **repeating** task | Completed + the next occurrence appears (due per repeat rule) with its own reminders; doing it twice from two notifications does not create two tasks | | |
| A5.3 | Delete the next occurrence, then Mark done the original again from an old notification | The deleted occurrence is **not** recreated (tombstone rule) | | |
| A5.4 | **Remind Me in 1 Hour** | No app launch; a notification with the same text arrives 1 h later, same actions | | |
| A5.5 | **Remind Me Tomorrow** | Arrives tomorrow at 07:00 local time | | |
| A5.6 | Snooze, then snooze the snoozed one again | Only one pending snooze for that reminder (developer pending count +1, not +2) | | |
| A5.7 | Snooze a task reminder, then complete the task in the app | The pending snooze is removed at the next re-plan ("stale snoozes −1") | | |
| A5.8 | Tap a task reminder | App opens on the **Tasks** tab (and the task detail once B1 registers `tasks.detail`) | | |
| A5.9 | Tap an exam reminder | **Exams** tab (+ `exams.detail` after B2); lesson → Timetable; pack tonight → Today | | |
| A5.10 | Tap an action while the app is in the foreground | Works the same; no duplicate banner | | |

### A6. Time zone, DST, clock
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A6.1 | Reminder at 19:00 local. Settings → General → Date & Time: automatic OFF, zone 1 h **west**; open Tabula | Re-plan (reason "environment"); developer "Next notification" shows 19:00 in the new zone; pending count unchanged (same ids, re-mapped — no duplicates) | | |
| A6.2 | Same change but **do not open** Tabula before 19:00 old time | Fires at the **original instant** (explicit-zone calendar trigger; device-only fact, record) | | |
| A6.3 | Zone 1 h **east**, open Tabula | Re-mapped; a reminder whose new time is already past is not delivered late twice | | |
| A6.4 | DST: set date to 2026-10-25 01:50 (Europe), reminder at 02:30 | Record which 02:30 it fires at (ambiguous hour → interval trigger to the planned instant) | | |
| A6.5 | DST spring-forward (2027-03-28 01:50), reminder at 02:30 | Fires at 03:30 (planner shifts nonexistent times forward) | | |
| A6.6 | Loud alarm planned for 07:00, change zone, open app | Alarm cancelled and re-scheduled for 07:00 in the new zone (`.fixed` alarms don't follow zones; the re-plan does) | | |
| A6.7 | Restore automatic time | Everything re-maps back; developer report shows changes only, no duplicates | | |
| A6.8 | App open across midnight | Re-plan at midnight (significant time change) — "today/tomorrow" wording of new reminders correct | | |

### A7. Background refresh, capacity, limits
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A7.1 | Developer → "Background refresh request" after a re-plan | Shows a date ≥ 15 min ahead and ≤ 12 h ahead (no "failed: …") | | |
| A7.2 | Leave the phone overnight without opening Tabula (Background App Refresh ON) | Next morning: developer "Last run" reason "backgroundRefresh" (opportunistic — record if it never runs) | | |
| A7.3 | Settings → General → Background App Refresh → Tabula OFF | Health row "Off: Tabula updates reminders only while you use it" + Open Settings | | |
| A7.4 | Low Power Mode ON | Health row warning "background updates are paused" | | |
| A7.5 | 100+ tasks with reminders (after B1; or many pack-tonight days) | Pending ≤ 64; health row "Reminder limit" with the dropped count; nothing beyond 64 silently lost (planner drops are reported) | | |
| A7.6 | Several loud-alarm rules until AlarmKit refuses (or the probe's limit button) | Developer "Failures … maximumLimitReached", "Learned alarm limit: n"; overflow arrives as notifications; health row "Loud alarm limit" | | |
| A7.7 | Force-quit + reboot after A7.6 | Same pending set after the next launch (no duplicates, ledger intact) | | |

### A8. Shell (5 tabs)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| A8.1 | Launch normally | Tab bar: Today · Timetable · Tasks · Exams · Settings (Liquid Glass), localised in sk/de/ja | | |
| A8.2 | Tasks / Exams tabs (before B1/B2) | Empty state with icon, title, explanation; Dynamic Type AX5 wraps; VoiceOver reads title + text | | |
| A8.3 | Release/TestFlight build launched with `-TabulaScreen settings` (Xcode scheme) | Ignored: the normal shell opens (P2-6) | | |

---

## B2. Exams tab (Stage B2) — device only; the UI was written without being seen

Setup: seed or real data. Useful states: (1) no exams, (2) one exam, (3) exams today / tomorrow / in 3 days / in 6 days /
in 20 days, (4) completed and past exams, (5) university profile with 3+ exams and with an exam-period break
(Terms & breaks editor, kind "Exam period"), (6) a timetable with room/building/notes switched off. Repeat key rows with
Dynamic Type AX5, dark mode, German/Hungarian (long), Japanese/Chinese, and VoiceOver. Launch routes for screenshots:
`exams`, `exams.history`, `exams.detail`, `exams.editor`, `exams.editor-new`.

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B2.1 | Exams tab with no exams | Empty state (graduation cap, "No Exams Yet", explanation) + "Add Exam" button; "+" in the top right | | |
| B2.2 | Add one exam 20 days away | Big card on top: "Next Exam", "in 20 days" in large type, subject badge, title, type, date, time/room only if set; neutral (grey) frame | | |
| B2.3 | Change the date to 6 / 3 / 1 / 0 days away | Frame colour escalates (accent, orange, red, red; thicker from 3 days), icon changes, countdown text reads "in 6 days", "in 3 days", "Tomorrow", "Today" — meaning is readable without colour (try greyscale filter) | | |
| B2.4 | Add several more exams across weeks | Below the card: sections "This week" / "Next week" / "Week of 2 Nov"; next exam is not repeated; order by date then start time (exam without start time after those with) | | |
| B2.5 | First weekday Sunday vs Monday with an exam on a Sunday | Lands in the week group the chosen first weekday implies | | |
| B2.6 | Row content | Order: when (icon + text), title, "Subject · Type", date, time, room/building, topics preview (first 3, "…" if more). Absent fields leave no blank line, dash or placeholder | | |
| B2.7 | Timetable field visibility: switch Room off (timetable editor) | Room disappears from card, rows, detail, editor; its stored value is not lost (switch on again: back). Same for Building and Notes | | |
| B2.8 | Swipe a row left | "Mark Done" (green); the exam moves to History; if it was the next exam the following one becomes the card | | |
| B2.9 | History segment | Completed and past exams, newest first, checkmark for completed; swipe: "Mark Done" (past, open) or "Mark as Not Done" (completed; future ones return to Upcoming) | | |
| B2.10 | History with nothing in it | "No Past Exams" empty state inside the list; segment control stays | | |
| B2.11 | Only past exams exist, Upcoming segment | "No Upcoming Exams" empty state | | |
| B2.12 | University profile, 2+ exams, no exam-period break | One "Exam period" section with the range first-last exam and "n exams" | | |
| B2.13 | Add an exam-period break (Terms & breaks, kind Exam period) around two exams | Section titled with the break's name, dates, count, "In progress" badge while today is inside; those exams are listed under it (not under weeks); a break of another timetable does not claim exams of this one | | |
| B2.14 | Tap an exam | Detail pushed: title, status/countdown, date, time, type, subject, room, building (only existing ones), topics list, notes, Mark Done button; "Edit" top right | | |
| B2.15 | Detail, Edit, Delete Exam, confirm | Editor closes, detail pops back to the list; exam gone | | |
| B2.16 | Editor: empty title | Save disabled, hint "Enter a title…"; enables with a title | | |
| B2.17 | Editor: start time on, end time on, set end before start | Red "end time must be after the start time", Save disabled; fixing re-enables. Turning start off hides end and stores neither | | |
| B2.18 | Editor topics: add 3, drag to reorder, delete one, leave one blank | Drag handles and delete controls are always visible; blank topic is dropped on save; order kept | | |
| B2.19 | Editor: Cancel after a change | "Discard changes?" confirmation; swipe-down blocked while dirty; Cancel without change closes at once | | |
| B2.20 | Editor: reminder section | Shows the (stub) reminder row until stage B4; saving keeps an existing override unchanged | | |
| B2.21 | Exam with a type outside the 7 known (e.g. imported "viva") | Shown with its own word; the editor keeps it selectable | | |
| B2.22 | Notification tap for an exam (section A) | Exams tab + detail sheet of that exam ("Done" closes it; "Mark Done" works) | | |
| B2.23 | VoiceOver on card / row | One element: "Title, Subject, Type, Tomorrow, Tuesday 20 October 2026, 10:00 - 10:45, Room X"; swipe actions offered as actions; week/period headers have header trait | | |
| B2.24 | Dynamic Type AX5, de, ja | Card, rows, editor wrap without clipping; toolbar "+" and all buttons at least 44 pt; segment control usable | | |
| B2.25 | Dark mode / Increase Contrast | Card frame and fill legible; subject badge text legible; no text drawn on the escalation colour | | |
| B2.26 | Midnight rollover with the Exams tab open | Countdown texts update ("Tomorrow" becomes "Today") after the day changes / app becomes active | | |
| B2.27 | Plurals: exam 2, 5, 21 days away in sk, pl, uk, cs | Grammatically correct forms | | |
## B4. Reminder settings, rule editor, override section, permission explainer, health check (Stage B4)
UI written without being seen (no Simulator): check layout, wording and behaviour on the device. Routes for CI screenshots:
`settings.reminders`, `settings.reminder-rule` (homework rule), `settings.reminder-health`, `reminders.permission`.
Repeat the visual checks in: empty (no rules) / normal / long text, Dynamic Type XXL and AX5, dark mode, German
(longest strings), Japanese or Chinese, Slovak (plural forms 1/2/5 minutes), VoiceOver.

### B4.1 Settings → Reminders
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B4.1.1 | Open Settings → Reminders (fresh install, no permission yet) | No system prompt appears. Rows: health link, one switch per kind (Homework, Assignments, Exams, Before a lesson/class, To-dos; "Pack your bag" only if the bring list is an enabled lesson field), Time Sensitive, loud alarms, quiet hours, explanations | | |
| B4.1.2 | Switch Homework on while notifications are "not determined" | Pre-explainer sheet opens (no system prompt yet). "Not Now" closes it and keeps the rule on | | |
| B4.1.3 | In the sheet tap "Allow Notifications" | System prompt appears; sheet closes; health shows Notifications OK after allowing | | |
| B4.1.4 | Deny in the prompt, switch another kind on | No explainer again (permission is determined); health row says "Turned off in Settings" with Open Settings | | |
| B4.1.5 | Row under each enabled kind: "Times and delivery" | Opens the rule editor, 44 pt row | | |
| B4.1.6 | Switch a kind off and on | Rule keeps its edited values (rule disabled, not deleted); summary line shows times and a non-Standard tier name | | |
| B4.1.7 | Time Sensitive switch + stepper (5–240 min) | Footer explains: breaks through Focus, not the silent switch; stepper text uses correct plural (sk: 1 minúta / 2 minúty / 5 minút) | | |
| B4.1.8 | Loud alarms switch on | Policy on, AlarmKit prompt appears (own permission); deny: note "Turned off in Settings…"; switch off turns the policy off | | |
| B4.1.9 | Global quiet hours on, set 22:00 to 07:00 | Two time rows appear; a reminder planned inside the window moves to 07:00 (Debug screen plan / next notification); off removes rows | | |
| B4.1.10 | Read-only store | Controls disabled | | |

### B4.2 Rule editor (Settings → Reminders → kind → Times and delivery)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B4.2.1 | Open the editor of a kind with no rule yet | "Remind me" off, nothing else shown; switching on creates the rule with the profile preset's times | | |
| B4.2.2 | Add Reminder Time menu | Presets (15 minutes, 1 hour, on the day at 07:00, 1/3/7 days before at 18:00) not already present, plus "Custom Time…"; adding the same twice is impossible | | |
| B4.2.3 | Tap a time row | Editor: type picker, amount stepper (plural text updates), clock time for "days before"; back arrow keeps the change | | |
| B4.2.4 | Swipe a time row to delete, delete all | Footer warns "Add at least one reminder time"; no crash, rule plans nothing | | |
| B4.2.5 | Follow-up: None / A while later / Next morning | Delay picker (30 min to 6 h) or time row appears; footer says "only if not done" and never loud | | |
| B4.2.6 | Tier rows: Standard, Time Sensitive, Loud alarm | Each shows title + honest explanation; selected row has check mark and VoiceOver "selected"; Time Sensitive footer shows the N-minute policy (or "turned off" when the policy is off) | | |
| B4.2.7 | Select Loud alarm | Policy turns on, AlarmKit prompt; after deny the denied note and Open Settings appear. Plan (Debug screen) contains an alarm only after allowing | | |
| B4.2.8 | Quiet hours for this kind | Toggle and two time rows; a reminder inside moves to the end, skipped when after the due time | | |
| B4.2.9 | After any edit | The rule is user-made (alarms possible); Debug screen shows a re-plan within about 1 s | | |

### B4.3 Per-item override (inside the task and exam editors, after B1/B2 embed it)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B4.3.1 | Open a task editor, section "Reminders" | "Use default reminders" on; footer lists the default (e.g. "1 day before, at 18:00"); if the kind is off: "No default reminders are switched on…" | | |
| B4.3.2 | Turn "Use default" off | Rows: Remind me, Times (Same as default / Custom), Delivery, Follow-up. First time with notifications "not determined": pre-explainer sheet | | |
| B4.3.3 | Remind me off | Other rows disappear; saving the task plans no reminders for it | | |
| B4.3.4 | Times: Custom | Seeds with the default times; add/remove/edit as in B4.2 (rows push inside the sheet's navigation) | | |
| B4.3.5 | Delivery: Loud alarm | Policy on + AlarmKit prompt; the item's reminder rings at the chosen time (A4) | | |
| B4.3.6 | Follow-up: Same as default / None / A while later / Next morning | Planner follows it (Debug screen) | | |
| B4.3.7 | Turn "Use default" back on and save | `reminderOverride` is gone (default reminders apply again) | | |

### B4.4 Pre-explainer sheet (`reminders.permission`)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B4.4.1 | Open it from the health check ("Allow Notifications" action) | Explains why and what arrives; buttons 44 pt+; nothing requested until "Allow Notifications" | | |
| B4.4.2 | Open it while the permission is denied | Footer says notifications are off; primary button becomes "Open Settings" and opens the app's notification settings | | |
| B4.4.3 | Cold launch | The sheet never appears at launch | | |

### B4.5 Health check (`settings.reminder-health`)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B4.5.1 | Open it | Summary line plus rows; every row has a symbol AND a status word (OK / Info / Check / Problem); pull to refresh works | | |
| B4.5.2 | Toggle Low Power Mode in Control Center, come back | Low Power row updates (warning) | | |
| B4.5.3 | Turn Background App Refresh off in iOS Settings, return | Row shows the warning with "Open Settings" | | |
| B4.5.4 | Change the notification permission in iOS Settings, return | Row follows; "Open Settings" lands on the app's notification settings page | | |
| B4.5.5 | With a Loud-alarm rule and alarm permission not determined | Alarms row warns with "Allow Loud Alarms"; tapping asks AlarmKit | | |
| B4.5.6 | Send Test Notification | "Sent. It arrives in a few seconds." then a banner after about 5 s (Standard) | | |
| B4.5.7 | Send Test Alarm (only visible once alarms are allowed) | Rings after about 60 s with Stop/Snooze; result line says scheduled | | |
| B4.5.8 | Create 70+ reminders (many tasks) | Scheduled row shows x of 64 and the "reminder limit" warning with explanation | | |
| B4.5.9 | Silent mode / Focus rows | Readable at AX5; VoiceOver reads title, status word, detail as one element | | |

Unverifiable without a device: the system permission prompts, delivery, Focus behaviour, whether the notification settings URL lands on the app's page, and every visual aspect.
## B1. Tasks tab (Stage B1 — unverified on device; the UI was never run or seen)
Seed launches: `-TabulaSeed secondary` (since C1: 8 tasks — 1 overdue, 1 due today, 4 upcoming, 2 completed; see C1). Routes: `tasks`, `tasks.upcoming|overdue|completed`, `tasks.editor`, `tasks.editor-new`, `tasks.detail`.

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B1.1 | Empty store: open Tasks | Empty state (icon, title, text); quick-add visible; no placeholders/dashes anywhere | | |
| B1.2 | Quick-add "Homework", subject Maths | Row appears in Upcoming; footer before adding shows "Due <date>, at the subject's next lesson"; without subject "Due tomorrow"; due matches the next non-cancelled Maths lesson | | |
| B1.3 | Segment chips | Counts correct; Overdue chip red with warning icon while it has tasks; chips scroll sideways in German/AX5 | | |
| B1.4 | Row look | Circle in subject colour (outline when open, filled + checkmark when done), strikethrough when done; high/urgent badge with icon+text; "2/5", paperclip, repeat icons only when present; light subject colours still visible in dark mode | | |
| B1.5 | Tap circle / swipe right | Task completes, moves to Completed; repeating task creates next occurrence; swipe again on Completed reopens | | |
| B1.6 | Swipe left, Delete | Confirmation naming the task; Delete removes it, Cancel keeps it | | |
| B1.7 | Filter by subject, sort by priority | List and counts follow; filtered-empty message when nothing matches; filter icon filled while active | | |
| B1.8 | Make a task due today 08:00 (time passed) | Appears under Overdue; leave app open across a due time: moves within a minute | | |
| B1.9 | Detail sheet | Title, subject, type, due (relative), priority (only if not Normal), repeat lines, notes only if set, subtasks tappable inline, Complete/Reopen, Delete, Edit | | |
| B1.10 | Editor new: empty title | Save disabled, hint under title; Cancel with edits asks to discard; swipe-down blocked while dirty | | |
| B1.11 | Due "Next lesson of the subject" with no subject / subject without lesson | Inline red messages, Save disabled; with lesson: resolved date shown, saved task has due date + link | | |
| B1.12 | Repeat weekly Mon+Wed, every 2 weeks, end date before due | Error shown; fix; complete the task: next due follows ISO-week rule | | |
| B1.13 | Subtasks: add, check, Reorder (drag handles), swipe delete | Order and checks persist after Save; reorder mode works inside the Form (unverified API behaviour) | | |
| B1.14 | Reminder-override and attachments sections | Present (stubs or B3/B4); editing other fields does not lose them | | |
| B1.15 | Edit task, delete in editor | Editor and detail close | | |
| B1.16 | Notification tap on a task | Tasks tab with the detail sheet of that task | | |
| B1.17 | VoiceOver on a row | One sentence (title, subject, due, priority, subtasks...); actions: open, mark done/not done, delete | | |
| B1.18 | Dynamic Type AX5, dark mode, long title, ja/zh, German | No clipping, 44 pt targets, texts wrap; chips scroll | | |
| B1.19 | Plurals sk/pl/uk/ro: "In 3 days", "5 days overdue", "Every 3 weeks" | Correct forms | | |

## C1. Cross-feature integration (Stage C1 — Today work, lesson badges, lesson detail tasks; never run or seen)
Seed: `-TabulaSeed secondary` at the fixed clock Tue 2026-10-13 10:20 (Europe/Bratislava). Since C1 it has: FYZ lab
report **overdue** (due Mon 12), NEJ "Nemčina – Lektion 3" **due today** (2/5 subtasks, weekly repeat), ANJ due Wed 14,
MAT due Thu 15, SJL due Mon 19 08:00, INF **high-priority assignment linked to Wed 21's double period**, two completed
(DEJ, BIO due today), exams: **past DEJ test Mon 12** (History segment), CHE test Thu 22 (9 days → Today card), BIO Tue 27.
`-TabulaSeed university`: "Skúškové obdobie – zimný semester" (4 Jan – 12 Feb 2027, `examPeriod`) with two finals.

**Badge rule** (LessonWork.swift): a linked task → exactly its occurrence; otherwise subject + due date → the first
non-cancelled lesson of that subject that day; an exam → the lesson containing its start, else that first lesson. Each
task/exam counts once. Open tasks only (completed tasks are listed in the lesson detail, not counted); exams count even
when marked done.

### C1.1 Today
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.1.1 | `today@secondary` | Order: Now & Next header → "Due today" (one row: Nemčina – Lektion 3, 2/5, repeat icon) with a red "1 overdue" chip → CHE "Next exam" card ("in 9 days") → today's tiles | | |
| C1.1.2 | Tap the row's text | Task detail sheet over Today (Today stays selected); Done closes it | | |
| C1.1.3 | Tap the row's circle | Task completes and leaves "Due today"; the repeat creates next Tuesday's task (Tasks → Upcoming); the NEJ tile badge disappears | | |
| C1.1.4 | Tap "1 overdue" | Tasks tab opens on the Overdue segment (FYZ lab report); tapping it again from Today later re-selects Overdue | | |
| C1.1.5 | Tap the exam card | Exam detail sheet of the CHE test; Done closes it | | |
| C1.1.6 | Nothing due + nothing overdue (complete/delete them) | The "Due today" section is absent (no empty placeholder); card still shows when an exam is ≤ 14 days away, absent otherwise | | |
| C1.1.7 | Empty store / blank seed | Unchanged empty states; no badges, no sections | | |
| C1.1.8 | Today's NEJ tile and the header (when NEJ is current/next) | "☑ 1 task" capsule under the tile's fields; BIO tile shows no badge (its task is completed) | | |

### C1.2 Lesson badges (grid / week / day / tiles / list fallback)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.2.1 | `timetable.grid@secondary` (week of 12 Oct) | Compact "☑1" on Mon FYZ, Tue NEJ, Wed ANJ, Thu MAT; graduation cap on Mon DEJ; these cells drop their room line; nothing else badged | | |
| C1.2.2 | Next week (swipe) | "☑1" on Mon SJL and Wed INF (double period, once), cap on Thu CHE | | |
| C1.2.3 | Week time-blocks view | Same badges on blocks ≥ 40 pt tall; short blocks rely on VoiceOver | | |
| C1.2.4 | Day view / big tiles (`timetable.tiles@secondary`) | Full capsules "☑ 1 task" / "🎓 Exam" on the tile; wrap under each other in German/AX sizes | | |
| C1.2.5 | Dynamic Type AX5 on the grid | List fallback rows show the full capsules; 44 pt rows; nothing clipped | | |
| C1.2.6 | Cell tap targets | Grid cells still ≥ 44 pt wide (5-day week on iPhone 16 Pro Max); badges do not steal taps | | |
| C1.2.7 | Dark mode, light subject colours (yellow) | Compact badge uses the tile's legible foreground; capsules readable on material | | |
| C1.2.8 | VoiceOver on a badged cell | One sentence ending "…, 1 open task" / "…, exam on this day" (no separate badge element) | | |
| C1.2.9 | Add a task due today for a subject with two lessons today | Badge only on the first (or the first non-cancelled) lesson | | |

### C1.3 Lesson detail "Homework & tasks"
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.3.1 | `timetable.lesson-detail@secondary` (Thu MAT, room change) | Header shows status badge + "☑ 1 task"; section "Homework & tasks" lists the worksheet; "Add homework for this lesson" button | | |
| C1.3.2 | Tap the circle | Completes; row stays, struck through (completed listed after open); header badge disappears; tap again reopens | | |
| C1.3.3 | Tap the row text | Task detail sheet on top of the lesson detail | | |
| C1.3.4 | "Add homework for this lesson" on Wed 21 INF | Task editor: kind Homework, subject Informatika, due "lesson" showing Wed 21 Oct with its start time; Save → badge "☑ 2 tasks" on that cell only | | |
| C1.3.5 | Same on a one-off (added) lesson (Thu 15 INF consultation) | Saved task has due = that date, no link; shows on that lesson (subject rule) | | |
| C1.3.6 | Change the subject inside the prefilled editor | Due re-resolves to that subject's next lesson (existing editor behaviour) | | |
| C1.3.7 | Lesson without tasks | Section shows only the add button (no "no tasks" placeholder) | | |

### C1.4 Deep links (notification tap, Stage A delegate) — verified in code, not on device
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.4.1 | Tap a task reminder, app in background | Tasks tab + task detail sheet (`tasks.detail` reads `presentedItem`) | | |
| C1.4.2 | Tap an exam reminder, app killed (cold launch) | Exams tab + exam detail sheet after loading | | |
| C1.4.3 | Tap a reminder while a Today sheet (lesson detail) is open | Known risk: the shell's sheet cannot present over another sheet; note what happens | | |

### C1.5 Text and languages
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.5.1 | `tasks@secondary@sk`, `exams@secondary@de`, Today in de/hu/fr | "1 úloha"/"2 úlohy"/"5 úloh", "1 Aufgabe"; "Heute fällig"; overdue chip fits or wraps under the heading | | |
| C1.5.2 | ja / zh-Hans | タスク1件 / 1 项任务 fit on tiles; no clipping | | |
| C1.5.3 | Long task title (100+ chars) in "Due today" and the lesson detail | Wraps, no truncation of the circle control | | |

Unverifiable without a device: every visual aspect (badge fit inside 44 pt grid cells, ViewThatFits wrapping, capsule
contrast on subject colours), sheet-over-sheet presentation from the lesson detail, the Tasks-tab rebuild on the overdue
chip (state of filters resets by design), and notification deep links.

---

## B3. Attachments (photos, files, links, voice notes)

Nothing in this section has been seen running: the UI compiles (xtool, 0 warnings) but was never displayed. Storage
rules are Linux-tested (`AttachmentStoreTests`). Open a task in the task editor (B1) → Attachments section.
Files: `<store directory>/Attachments/<ATTACHMENT-UUID>/<name>` (Settings → Developer shows the store directory).
To inspect files on a device: Finder/Xcode "Download Container" on a Mac later, or count rows + the usage footer.

### B3a. Adding
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B3.1 | Add Attachment → Photo → pick a HEIC photo; Save the task; reopen | Row with a sharp, correctly rotated thumbnail, title "Photo", size; still there after reopening and after force-quit | | |
| B3.2 | Add Attachment → File → pick a PDF from On My iPhone; then several files at once | One row per file, PDF icon + file name + size; "Adding…" row while copying | | |
| B3.3 | File → pick a file in iCloud Drive that shows a cloud icon (not downloaded) | It is copied (or a clear "Couldn’t Add Attachment" alert) — never a 0-byte file; note which | | |
| B3.4 | Add Attachment → Link → type `example.com/x` | Row shows host `example.com`, detail `https://example.com/x` | | |
| B3.5 | Link → `javascript:alert(1)`, `file:///etc/hosts`, `https://bank.com@evil.example` | "Not a Web Address" alert, nothing added | | |
| B3.6 | Voice Note → Record (first time) | Microphone permission prompt appears only now, with the English usage text; after Allow: timer runs; Stop; Save → row "Voice note", duration, play button | | |
| B3.7 | Deny microphone (Settings → Privacy → Microphone → Tabula off) → Record | Alert "Microphone Access Is Off" with Open Settings (opens Tabula's Settings page) | | |
| B3.8 | Record, then Cancel; also swipe down while recording | Cancel discards; swipe-down is blocked while recording or with an unsaved recording | | |
| B3.8a | Add a large file (≥ 100 MB video via Files) and immediately try Save / swipe the editor down | Bottom bar "Adding attachment… You can save when it’s done."; Save greyed out; swipe-down blocked; when the bar disappears the row is there and Save works; reopen → attachment present | | |
| B3.8b | File → pick a folder or a Pages/Keynote package | Alert "Folders and packages can’t be attached…"; nothing added | | |
| B3.8c | Record a voice note, receive a phone call (or start Siri / an alarm) while recording | Recording stops, footnote "Recording stopped because of an interruption…"; Save keeps what was recorded | | |
| B3.8d | Record for 10 minutes | Stops by itself at 10:00 with "Recording stopped at the 10-minute limit."; Save works | | |
| B3.8e | (Quota, after Phase 10 or with a debug Free tier) record a voice note that does not fit | Error alert with **Try Again** / **Delete Recording**; the recording is not lost until Delete is chosen | | |

### B3b. Using, editing, cleanup (data-loss sensitive)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B3.9 | Tap photo / PDF row | Quick Look opens; Done returns to the editor | | |
| B3.10 | Tap a link row | Confirmation "Open this link?" showing the **full URL**; only "Open Link" opens Safari | | |
| B3.11 | Voice note: tap row (play), tap again (pause); start another one | Only one plays at a time; icon toggles play/pause; stops when the editor closes | | |
| B3.12 | Rename, Move Up/Down (context menu), drag to reorder, swipe → Delete (confirm); Save; reopen | Order and names persist; deleted row gone; other attachments intact | | |
| B3.13 | Add a large photo, **Cancel** the editor; reopen | Not listed (orphan). Usage footer may still include it for up to 24 h (grace period), then drops after the next launch / change | | |
| B3.14 | Delete a task that has attachments; wait ~5 s; open another task's editor and read the usage footer | Usage drops (files of the deleted task removed after save; they were older than 24 h) — for a task created today the files stay until 24 h have passed | | |
| B3.15 | Add an attachment, keep the editor open > 1 min while switching apps, scroll the Attachments section off screen and back, open Quick Look; Save | The file is still there (the editor protects every ID it touched until it closes) | | |
| B3.16 | Force-quit during a large file copy ("Adding…"), relaunch | No half file listed; nothing breaks (abandoned staging is cleaned after 1 h) | | |
| B3.17 | Device backup (Finder or iCloud), restore to the same/another device | Attachments come back with the tasks (App Group container in backup — record result) | | |

### B3c. Accessibility and languages
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B3.18 | VoiceOver on a row | Reads title + details; hint ("Opens a preview." / "Asks before opening the link." / "Plays the voice note."); rotor actions Rename, Move Up, Move Down, Delete | | |
| B3.19 | Dynamic Type AX5 | Thumbnails scale, titles wrap (3 lines), no clipped buttons | | |
| B3.20 | sk / de / ja | All attachment strings translated (no raw `attachments.*` keys); sizes formatted per locale ("1,2 MB") | | |

## Screenshot fixes (CI simulator findings on b854087)

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| SF1 | Tasks tab, quick-add section, no subject; then pick a subject with an upcoming lesson | Between Subject and Add a non-tappable row "Due" with value "Tomorrow", then a "Thu, Oct 15 · next lesson" style date; no footer under the section, so the task list below has no stray "Due tomorrow" caption; sk/de/ja translated; AX5 wraps the value | | |
| SF2 | Task detail of a task with a date-only due date and weekly repeat (seed secondary, "Nemčina – Lektion 3") | Due row shows "Today" (overdue: red with warning icon); the Repeat row follows immediately, no blank gap or stray separator; a task without due date / linked lesson / priority shows none of those rows | | |
| SF3 | Exams tab at Dynamic Type AX-XXXL, German: next-exam card and list rows | Subject badge sits above the title; the title wraps by words over the full width (no one-syllable lines); normal sizes keep the badge beside the title | | |
| SF4 | Settings → Reminders with VoiceOver, enabled kinds | Each "Times and delivery" row is read as "<kind>, times and delivery" (e.g. "Homework, times and delivery"), translated in sk/de/ja | | |
