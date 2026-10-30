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
