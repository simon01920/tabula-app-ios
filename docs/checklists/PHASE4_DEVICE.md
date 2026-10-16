# Phase 4 — manual on-device checklist

Device: iPhone 16 Pro Max (iOS 26.x) + Apple Watch Series 7 (watchOS 26.x). Same format as `PHASE3_DEVICE.md`:
**Steps → Expected**, plus an Observed column and ✔ / ✘ / ? (unclear). Each Phase 4 stage adds its own self-contained
`##` section (several agents edit this file; keep sections independent).

iOS version: ________ · Build: xtool / TestFlight · Tester: ________ · Date: ________

---

## C1

**Subject order (`Subject.sortIndex`, P3-2, approved 2026-10-16).** Subjects have a manual order; every subject list and
picker follows it (DOMAIN_MODEL §3.3). Never-ordered timetables stay alphabetical until the first reorder or the first
new subject. No UI can be previewed locally: everything here is device-only.

Setup: a timetable with at least 5 subjects created **before** installing this build (e.g. the Phase 3 build's sample
data or a manually built timetable), so the upgrade path is tested. Optional second device / older build for C1.12.

| ID | Steps | Expected | Observed | ✔/✘ |
|---|---|---|---|---|
| C1.1 | Install this build over the Phase 3 build (keep data), open Timetable → options → Subjects | All subjects present; order is **alphabetical** (no order stored yet); no error banner; footer "Tap Edit to change the order. New subjects are added at the end." | | |
| C1.2 | Tap **Edit** (top left) | Reorder handles appear on every row; no delete buttons; Edit becomes Done. With 0–1 subjects, Edit is disabled | | |
| C1.3 | Drag the last subject to the top, tap Done | The row stays at the top; reopening the Subjects sheet and relaunching the app keep the order | | |
| C1.4 | Open the subject picker in: lesson editor (new lesson), day-change editor (substitute / extra lesson), timetable quick add (tap an empty grid slot), Tasks → quick-add subject menu, task editor, exam editor | Every list shows the **same order** as the Subjects sheet (moved subject first) | | |
| C1.5 | Tasks tab → options menu → Subject filter (have tasks for ≥ 3 subjects) | Filter subjects follow the manual order; with several timetables, grouped in the timetables-list order | | |
| C1.6 | Subjects → **+**, create "Aaa test" | New subject appears at the **end** of the list (not alphabetically first), and at the end of every picker in C1.4 | | |
| C1.7 | Edit an existing subject (rename it), Save | Its position does not change | | |
| C1.8 | VoiceOver on, Subjects sheet: focus the 2nd row, swipe up/down (rotor Actions) | Actions "Move up" and "Move down" are offered; the first row offers only "Move down", the last only "Move up". Activating one moves the row immediately (check the new position by swiping through the list) | | |
| C1.9 | Repeat C1.8 in Slovak (or another non-English language) | Action names are translated ("Posunúť vyššie" / "Posunúť nižšie" in sk); footer translated | | |
| C1.10 | Dynamic Type at the largest accessibility size, Edit mode | Rows wrap, reorder handles stay reachable; the footer is readable | | |
| C1.11 | *(only once the share UI exists — not built yet; core-tested: `SubjectOrderShareBackupTests`)* Share the timetable (link or QR), import it on the same device | The imported timetable's subjects appear in the **same manual order** as the source | | |
| C1.12 | (optional, two devices or an older build) Reorder differently on two devices offline, then sync / exchange data | Both devices end with the same order (deterministic merge, DOMAIN_MODEL §3.3); a later full reorder on one device wins | | |
| C1.13 | *(only once the backup UI exists — not built yet; core-tested)* Export a backup, change the order, restore the backup (replace) | The order from the backup is restored | | |

Not testable on device yet: CloudKit sync, the share UI and the backup UI are not built, so C1.11–C1.13 wait for those
stages (the logic is covered by TimetableCore tests on Linux).
