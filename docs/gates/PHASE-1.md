# Phase 1 gate report — TimetableCore

Status: **DRAFT — Stage 3 integration running** · Plan: `docs/specs/PHASE1_PLAN.md` · Schema reference: `docs/specs/DOMAIN_MODEL.md`

## Stages
| Stage | Owner | Branch / commit | Tests | Status |
|---|---|---|---|---|
| 1 Model foundation | core-domain-engineer | `4237def` (ff-merged to main) | 142 in 30 suites, independently re-run by the orchestrator | merged |
| 2B Schedule engine | core-domain-engineer | merged `a3c60bb` | 318 on main after merge (92 new), independently re-run | merged |
| 2C Reminder planner | notifications-engineer | `9843b24` (ff-merged) | 226 total (84 new), independently re-run | merged |
| 2D Share codec | core-domain-engineer | merged `61e78bc` | 384 on main after merge (66 new), independently re-run | merged |
| 2E Sync + repository | sync-storage-engineer | merged `085bfbf` | 458 on main after merge (74 new), independently re-run | merged |
| 3 Integration | core-domain-engineer | main | — | running |

## Orchestrator decisions taken during Phase 1 (reviewable)
1. Stage 1 deviations accepted:
   - dates encoded as integer milliseconds;
   - `LocalDateTime` struct;
   - fixed singleton UUID for `AppSettings`;
   - more vocabularies made open;
   - `followDay.cycleWeek`, `isoWeekParity.offset`, `Exam.notes`, `[String]` topics;
   - `repeatRule` naming;
   - "Other" profile falls back to the secondary bell template.
2. Period mapping across bell-schedule variants: match by `Period.ID`, else the same ordinal among lesson periods, else omit with a warning.
3. `ISOWeekParityPolicy.continuous` defined as: parity fixed by the ISO week at the school-year start (1 Sept), then strict alternation within the school year. The default for new timetables is `.strict`.
4. `useBellSchedule` override marks lessons whose times change as `.modified`.
5. Forward compatibility: unknown JSON keys are preserved through re-saves (collection-level side table). This is done before the schema freeze.
6. Reminder planner defaults follow the Phase 0 recommendations D6/D7 (Time Sensitive lead ≤ 60 min; alarms only from user rules), as policies in `AppSettings`.

7. Reminder IDs (2C): `rem.` + FNV-1a 64 of source + rule + offset + **wall-clock** time. Offsets in "days before at hh:mm" use the local fire time; "minutes before" use the item's local time, so IDs survive DST and time-zone changes. This supersedes PHASE1_PLAN §5's "fire instant".
8. Planner defaults (2C):
   - Time Sensitive is kept at exactly 60 min lead, measured after the quiet-hours shift.
   - Alarm gate order: follow-ups never ring, then preset rules, then policy, then device capability. Anything that fails the gate falls back to Time Sensitive.
   - Global quiet hours don't move alarms.
   - Date-only items anchor at 08:00, fixed for now. Making it user-configurable later would be a schema change.
   - Pack-tonight shows counts and the first subject only on the lock screen (privacy).

9. Schedule engine (2B):
   - **Week parity:** `.strict` is the default and is isolated in `WeekParity.defaultPolicy(for:regionCode:)`. `.continuous` assigns the whole week containing 1 Sept to the new school year. Sun/Sat week starts use the ISO week of the week's middle day.
   - **`followDay`:**
     - It keeps the actual date's bell schedule; stack `useBellSchedule` for the followed day's times.
     - It works on disabled weekdays and during breaks (make-up Saturdays).
     - It never shifts the rotation.
   - **Override replay order:** `meta.updatedAt`, then ID.
     - A later `modifyLesson` revives a cancelled lesson.
     - `cancelDay` beats lesson-level changes; added one-off lessons survive it.
   - **Period mapping:** a span running past the last period is shortened and flagged, not dropped.
   - **Performance:** 5 years × 40 lessons resolves in 0.07 s (release) / 0.5 s (debug).
   - **Known gaps:**
     - A zone with two DST changes within 5 days would break the fast path; no such zone exists.
     - A day schedule with more periods than the default shows the extra lessons as "unplaced" in the grid.
     - Validation doesn't yet check `followDay.cycleWeek` against the cycle length, or day-cycle school days against enabled days. The resolver tolerates both.

10. Share codec (2D):
   - Payload size: typical secondary school 1.4 KB (inline link); university with 360 lessons 7.6 KB (short code).
   - Fuzz: 5,200 hostile inputs, no crash.
   - The payload contains no UUIDs; entities are referenced by index.
   - Completed tasks/exams and schedule overrides are **not shared** in v1.
   - Global breaks become breaks of the imported timetable.
   - `CZlib` is a system library, not a package dependency.
   - iOS cross-compile verified (release); a debug-link quirk was seen under xtool.

11. Sync + storage (2E):
   - **Merge:** field-level last-writer-wins; children set-merged; tombstone rule "newest delete ≥ newest liveness → deleted".
   - **Proofs:** 600-seed algebraic properties; 150/40-seed convergence across replicas.
   - **Unknown fields** preserved at the root, on entities, settings and children; not inside embedded value objects.
   - **Hashing:** pure-Swift SHA-256 (FIPS vectors) to avoid a dependency.
12. **Pre-freeze schema change (orchestrator):**
   - A missing field clock now means `createdAt` (was `updatedAt`), so the stamper writes clocks only for keys that changed.
   - Why: with the old rule, per-field clocks doubled the saved file (8.9 MB vs 4.4 MB for 5k tasks + 2k lessons), and load+save sat at 0.91 s against the 1 s budget.
   - The `AppSettings` singleton gets a zero `createdAt`, so untouched defaults never beat a real edit from another device.

**Integration to-do:**
- Add `ReminderL10n.allKeys` (42) to DOMAIN_MODEL Appendix A and `DomainModelDocTests`.
- Do the same for 2B's 18 keys (`schedule.warning.*` and `schedule.change.*`) and the keys from 2D/2E.
- Add validation for the two gaps above.
- **Fix the crash:** `TabulaJSON.makeDecoder()` traps on out-of-range numeric dates (e.g. `1e300`) through an unchecked `Int64(...)`. A hostile backup could crash the app. Range-check it and throw.
- Add 2D's 27 keys (`share.error.*`, `share.warning.*`).

## Decisions needed from the human (collected so far)
- Attachment quotas, free vs Pro (placeholders: 100 MB / 2,000 MB).
- Are the **time-block** and **Agenda** views Free or Pro? PRODUCT.md doesn't say. Currently ungated (free).
- D6/D7 from Phase 0 (implemented as defaults above).
- Should sharing include **completed** tasks/exams? Currently not.
