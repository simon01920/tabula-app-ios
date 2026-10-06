# Phase 1 gate report — TimetableCore

Status: **DRAFT — Stage 2 running** · Plan: `docs/specs/PHASE1_PLAN.md` · Schema reference: `docs/specs/DOMAIN_MODEL.md`

## Stages
| Stage | Owner | Branch / commit | Tests | Status |
|---|---|---|---|---|
| 1 Model foundation | core-domain-engineer | `4237def` (ff-merged to main) | 142 in 30 suites, independently re-run by the orchestrator | merged |
| 2B Schedule engine | core-domain-engineer | — | — | running |
| 2C Reminder planner | notifications-engineer | `9843b24` (ff-merged) | 226 total (84 new), independently re-run | merged |
| 2D Share codec | core-domain-engineer | — | — | running |
| 2E Sync + repository | sync-storage-engineer | — | — | running |

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

**Integration to-do:**
- Add `ReminderL10n.allKeys` (42) to DOMAIN_MODEL Appendix A and `DomainModelDocTests`.
- Do the same for the keys from 2B, 2D and 2E.

## Decisions needed from the human (collected so far)
- Attachment quotas, free vs Pro (placeholders: 100 MB / 2,000 MB).
- Are the **time-block** and **Agenda** views Free or Pro? PRODUCT.md doesn't say. Currently ungated (free).
- D6/D7 from Phase 0 (implemented as defaults above).
