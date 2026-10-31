# Phase 6 — manual on-device checklist (iCloud sync)

Format as in `PHASE4_DEVICE.md`: **Steps → Expected**, Observed, ✔ / ✘ / ? (unclear). Nothing here can be simulated
locally: sync is compiled only into **TestFlight builds with `TABULA_PAID_ACCOUNT = 1`** (`TABULA_CLOUDKIT`), so every
row except S1.0 needs the paid account (PAID_ACCOUNT_SWITCHOVER steps 1–8). Use two iPhones (A, B) signed in to the same
iCloud account unless a row says otherwise. Watch the CloudKit Console (development environment) → Records → zone
`Tabula` while testing.

**Before the App Store release:** CloudKit Console → the container `iCloud.sk.simondev.tabula` → *Deploy Schema
Changes…* from Development to **Production** (record types `timetable`, `subject`, `bellSchedule`, `lesson`, `term`,
`calendarBreak`, `scheduleOverride`, `task`, `exam`, `reminderRule`, `settings`; fields `payload` Bytes, `schemaVersion`
Int64). A production build cannot create record types: without this step sync fails for every user.

iOS version A/B: ________ · Build: TestFlight ____ · Tester: ________ · Date: ________

---

## S1 — CloudKit sync

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| S1.0 | xtool or free build → Settings | "iCloud Sync · Not Available" row, footer "iCloud sync arrives with the App Store version…"; no switch, no crash | | |
| S1.1 | A: fresh install, onboarding, add a homework item. Settings › iCloud Sync | Switch on by default; footer goes "Syncing…" → "Last synced just now." Console shows records in zone `Tabula` | | |
| S1.2 | B: fresh install (no onboarding), open the app, wait ≤ 1 min | B shows A's timetable and homework without onboarding; no first-sync alert | | |
| S1.3 | Both online: edit a lesson room on A | B updates within ~1 min while open (silent push), or at the next launch; reminders and the widget on B follow | | |
| S1.4 | **Airplane mode** on both. A: rename subject X, B: change X's colour. Turn both online | Both end with the new name **and** the new colour (field-level merge) | | |
| S1.5 | Airplane on both. A and B edit the **same** field differently (A first, B a minute later). Online | Both show B's value (later write wins) | | |
| S1.6 | Airplane on B. **First** B: complete homework H (offline). **Then** A: delete H. B online | H is deleted on both (the delete is newer than B's edit) | | |
| S1.7 | Airplane on B. A: delete homework H. Later B: edit H's title offline. Online | H comes back on both with B's title (an edit after the delete resurrects) | | |
| S1.8 | Subtasks: A adds subtask "a", B (offline) adds "b" to the same task. Online | The task has both subtasks on both devices | | |
| S1.9 | **First sync with data on both sides:** B with its own timetable, iCloud Sync off; turn it on | Alert "Data on This iPhone and in iCloud" with Merge (bold, top), Keep This iPhone, Use iCloud (red) | | |
| S1.10 | S1.9 → Merge | Both devices show both timetables; nothing lost | | |
| S1.11 | S1.9 again (reinstall B) → Keep This iPhone | A converges on B's data; items that were only in iCloud disappear on both | | |
| S1.12 | S1.9 again → Use iCloud | B shows iCloud's data; B-only items disappear (kept as tombstones) | | |
| S1.13 | Kill the app while the S1.9 alert is shown; relaunch | The alert comes back; nothing was merged yet | | |
| S1.14 | **iCloud signed out:** iOS Settings → sign out of iCloud on B (keep data on the iPhone when iOS asks) | B keeps all its data; footer "Sign in to iCloud in the Settings app…" | | |
| S1.15 | Sign in again (same account) | Sync resumes; if both sides hold data the first-sync alert appears (expected: the ledger was reset) | | |
| S1.16 | Sign in with a **different** account on B | B's data stays; first-sync alert if that account has Tabula data | | |
| S1.17 | **Delete/restore:** iOS Settings → [name] → iCloud → Manage storage → Tabula → Delete data | Both devices keep their data; footer "Tabula's data in iCloud was deleted…"; the switch turns off | | |
| S1.18 | S1.17 → turn iCloud Sync on again on A | A uploads everything (Console shows records again); B after its own switch-on gets the first-sync alert | | |
| S1.19 | Settings › iCloud Sync off on A, edit on A, on again | The edit made while off arrives on B after switching on | | |
| S1.20 | iCloud storage full (test account) | Footer "Your iCloud storage is full…"; local edits still save | | |
| S1.21 | Background push: B in the background, edit on A | B updates without being opened (check the widget); if not, note it (RISKS #94) | | |
| S1.22 | VoiceOver + largest Dynamic Type: Settings › iCloud section and the first-sync alert | Switch label "iCloud Sync, on/off"; the footer status is read; alert buttons readable, no truncation | | |
| S1.23 | Slovak UI: the same screens | Texts from the catalog (no English, no keys) | | |

## S2 — Backup / restore and stranded data (PHASE6_PLAN decisions 5–6)

Works on a free-team xtool build except S2.7–S2.9 (need a build that newly gets the App Group: paid account or xtool PR #284).
Record build, iOS version, app language. Each row: Pass / Fail + note.

| # | Steps | Expected |
|---|---|---|
| S2.1 | Settings › Backup. VoiceOver on, then AX5 text size | Row "Backup" (green tile) above About & Feedback. Page: Export Backup, Restore from Backup…, footer says attachments are not included. Every row reads its name; nothing truncated at AX5 |
| S2.2 | Export Backup → Save to Files (On My iPhone) | Share sheet opens with `Tabula YYYY-MM-DD.tabulabackup`; the file saves |
| S2.3 | Edit a lesson, Restore from Backup… → pick the S2.2 file → Merge | Dialog "Restore Backup" with the backup's date; Merge is the plain (non-red) choice. "Backup Restored"; data otherwise unchanged; the lesson keeps whichever edit is newer |
| S2.4 | Add a task, Restore → same file → Replace… | Red confirmation "Replace All Data?" names the data types and says the copy goes to Settings › Backup › Automatic copies. Cancel changes nothing |
| S2.5 | Repeat S2.4, tap Replace | The added task is gone; "Automatic copies" lists a new entry; sharing it saves a `.tabulabackup` that restores the task (S2.3 flow) |
| S2.6 | Pick a non-backup file (a photo/PDF), then a backup file truncated on a computer, then a not-downloaded iCloud Drive file | Plain-word alert each time ("isn't a Tabula backup" / "damaged" / "couldn't be opened"), all ending "Nothing was changed."; data unchanged |
| S2.7 | Free-team build with data → install a build with the App Group (same bundle id) → launch | No onboarding; the old timetable, tasks and attachments are there; Developer screen: "Stranded-data migration movedIn"; widgets show data |
| S2.8 | As S2.7 but the group store already has data (onboarded on the group build first) | Both data sets present (merged), nothing lost; Developer screen "merged"; Settings › Backup › Automatic copies has two pre-migration entries |
| S2.9 | Relaunch after S2.7/S2.8 | Developer screen "nothingToDo"; no new automatic copies |
