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

### B3b. Using, editing, cleanup (data-loss sensitive)
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B3.9 | Tap photo / PDF row | Quick Look opens; Done returns to the editor | | |
| B3.10 | Tap a link row | Confirmation "Open this link?" showing the **full URL**; only "Open Link" opens Safari | | |
| B3.11 | Voice note: tap row (play), tap again (pause); start another one | Only one plays at a time; icon toggles play/pause; stops when the editor closes | | |
| B3.12 | Rename, Move Up/Down (context menu), drag to reorder, swipe → Delete (confirm); Save; reopen | Order and names persist; deleted row gone; other attachments intact | | |
| B3.13 | Add a large photo, **Cancel** the editor; reopen | Not listed (orphan). Usage footer may still include it for up to 24 h (grace period), then drops after the next launch / change | | |
| B3.14 | Delete a task that has attachments; wait ~5 s; open another task's editor and read the usage footer | Usage drops (files of the deleted task removed after save; they were older than 24 h) — for a task created today the files stay until 24 h have passed | | |
| B3.15 | Add an attachment, keep the editor open > 1 min while switching apps; come back; Save | The file is still there (open editor protects it) | | |
| B3.16 | Force-quit during a large file copy ("Adding…"), relaunch | No half file listed; nothing breaks (abandoned staging is cleaned after 1 h) | | |
| B3.17 | Device backup (Finder or iCloud), restore to the same/another device | Attachments come back with the tasks (App Group container in backup — record result) | | |

### B3c. Accessibility and languages
| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| B3.18 | VoiceOver on a row | Reads title + details; hint ("Opens a preview." / "Asks before opening the link." / "Plays the voice note."); rotor actions Rename, Move Up, Move Down, Delete | | |
| B3.19 | Dynamic Type AX5 | Thumbnails scale, titles wrap (3 lines), no clipped buttons | | |
| B3.20 | sk / de / ja | All attachment strings translated (no raw `attachments.*` keys); sizes formatted per locale ("1,2 MB") | | |
