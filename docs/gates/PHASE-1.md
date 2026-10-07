# Phase 1 gate report — TimetableCore

Date: 2026-10-08 · Status: **STOPPED AT GATE: awaiting human approval.** Approving this gate **freezes the persisted schema** (CLAUDE.md: later changes need your approval).
Plan: `docs/specs/PHASE1_PLAN.md` · Schema reference: `docs/specs/DOMAIN_MODEL.md` · Share wire format: `docs/specs/SHARE_FORMAT.md`

## 1. Done
| Part | What it gives the app | Tests (new) |
|---|---|---|
| Stage 1 model foundation | Calendar primitives with an explicit DST policy; schema v1 (12 entity types, sync metadata, open vocabularies, deterministic JSON); validation; colour contrast (WCAG) + 4 palette packs; onboarding presets per profile; the Free/Pro table as data; `EntitlementsProvider` | 142 |
| 2B schedule engine | Week cycles (odd/even, N-week), day cycles (A/B…) counted over school days and breaks; terms, holidays, overrides (cancel/modify/add/cancelDay/followDay/bell swap); subject defaults; conflicts; now & next; grid and time-block layouts | 92 |
| 2C reminder planner | Rules → prioritised plan within the 64-notification cap; Time Sensitive and alarm policies; quiet hours; follow-ups; pack-tonight; stable IDs plus diffing for the iOS adapter | 84 |
| 2D share codec | Versioned JSON → DEFLATE (system zlib) → base64url; inline link vs 8-char short code; strict validation and limits; import preview and materialise with fresh IDs | 66 |
| 2E sync + storage | Hybrid logical clock; field-level merge with tombstones and child set-merge; unknown-field preservation; file repository (atomic, backup, recovery, read-only on newer schema, migrations); backup archive with SHA-256 | 74 |
| 3 integration + pre-freeze fixes | `createdAt` field-clock default (file 8.9 → 4.8 MB); hostile-number hardening (8 crash paths); validation gaps; all vocabularies open; `rotationWeekStart` persisted; repeat-task semantics; 192 l10n keys in the catalog + docs; macOS `swift test` in CI | 41 |

## 2. Evidence
- **Linux (orchestrator re-run, 2026-10-08):** `bash scripts/validate.sh` → **ALL CHECKS PASSED**. That covers **499 core tests in 76 suites** (agent run after the last touches; orchestrator re-run at 497 before them), 9 TimetableUI tests, manifests, plists, path sync, the catalog and XcodeGen. 0 compiler warnings.
- **iOS app build (xtool, local):** `Build complete! (7.08 secs)`, iOS app + widget. **Watch type-check (arm64_32, watchOS 26):** OK.
- **Final CI** ([37700254831](https://github.com/simon01920/tabula-app-ios/actions/runs/37700254831), `266270d`):
  - **502 core tests in 77 suites pass on macOS** (Apple Foundation + Apple tz data) and on Linux.
  - ✓ XcodeGen iOS + watch build; ✓ xtool path.
  - The first macOS run found a **real stack-overflow crash** (hostile deeply-nested JSON in a backup → app crash on iPhone). It is fixed with a nesting cap of 64 and 512 KiB/256 KiB-stack regression tests (RISKS #44).
- **Earlier CI on the Phase 1 code** (run [37690335046](https://github.com/simon01920/tabula-app-ios/actions/runs/37690335046) at `1e36a06`): ✓ Linux tests, ✓ XcodeGen iOS+watch build, ✓ xtool path, ✓ simulator screenshots ([37690335073](https://github.com/simon01920/tabula-app-ios/actions/runs/37690335073)). The pre-freeze commits are pushed with this report, and their CI run is the final check.
- **Performance (release, 5,000 tasks + 2,000 lessons):** file 4.8 MB, load 0.27 s + save 0.31 s = **0.57 s** (budget 1 s). Resolving five years of a 40-lesson timetable: 0.07 s.
- **Robustness:** share-codec fuzzing (≥ 2,100 counted hostile inputs plus mutated links), hostile-number fuzzing of every date field, 600-seed merge algebra, and 150/40-seed multi-replica convergence. All green.
- **Independent QA (qa-reviewer):** gate review PASS WITH FIXES, fixes applied, then a delta re-review (see §6).

## 3. Not done / limits (honest)
- **Watch:** nothing runs on its 32-bit CPU yet; it is type-checked only. Core logic runs on both Linux and macOS.
- **Phase 2/3 items:**
  - **No UI** for any of this yet (Phase 2).
  - The **iOS notification/AlarmKit adapter** (Phase 3).
  - **CloudKit** transport (Phase 6).
  - **Share Worker** (Phase 7).
- **Known accepted limits:**
  - Lessons can't end exactly at 24:00.
  - Unknown keys *inside* embedded value objects are not preserved.
  - Schedule overrides and completed tasks are not shared in v1.
  - Date-only items remind relative to 08:00.

## 4. Orchestrator decisions taken in Phase 1 (please skim; all reversible until you approve the freeze)
1. **Data format:** integer-millisecond dates; a singleton UUID for settings; most vocabularies **open** (unknown values round-trip and degrade safely).
2. **Sync:** a field with no clock counts as written at `createdAt`; settings start at time zero; the merged `createdAt` is the later one.
3. **Odd/even weeks:** default `.strict` (ISO week number parity). `.continuous` = re-anchor at the week containing 1 September, then alternate. The rotation week start is stored per timetable, so all devices agree on A/B.
4. **Overrides:** replayed in edit order. A later modify revives a cancelled lesson; `cancelDay` wins over lesson changes; added one-off lessons survive it.
5. **Reminders:**
   - Time Sensitive is used only when the lead is ≤ 60 min, per Apple's HIG (Phase 0 D6).
   - Alarms come only from user rules (Phase 0 D7).
   - University lesson reminders are off by default, so the 64 cap isn't hit.
   - The lock screen shows counts, never bring-list text.
6. **Last closed vocabulary opened:** `ISOWeekParityPolicy` (unknown → `.strict`).
7. **Repeating tasks:** completing one creates its successor with an ID derived from the finished task, so two devices completing it don't duplicate it. Monthly repeats skip months without that day (31 Jan → 31 Mar).
8. **Sharing:** no UUIDs in payloads; IDs are remapped on import; completed tasks/exams and overrides are excluded.
9. **Dependencies:** none added. zlib is a system library; SHA-256 is our own ~150 lines.

## 5. Decisions needed from you
| # | Decision | Recommendation |
|---|---|---|
| **P1-1** | **Approve the schema freeze** (DOMAIN_MODEL v1) | Approve |
| P1-2 | Default odd/even policy `.strict` (ISO weeks) vs `.continuous` (from 1 Sept) for Slovak/Czech schools | See §7: your call, as the person who knows how your schools count |
| P1-3 | Attachment quotas, free vs Pro (placeholders 100 MB / 2,000 MB) | Keep the placeholders until Phase 10 |
| P1-4 | Time-block and Agenda views: Free or Pro? (PRODUCT.md silent; currently free) | Free (core promise: a usable timetable) |
| P1-5 | Free tier = 1 timetable: what happens on share-import or a second device's onboarding? | Allow viewing/importing; editing a second timetable prompts the paywall (Phase 10) |
| P1-6 | Share completed tasks/exams? | No (privacy, size) |
| P1-9 | Monthly repeats on the 31st: skip short months (current) or use the month's last day? The second needs a `RepeatRule.monthDay` field, **before** the freeze | Skip (current) |
| P1-7 | Tombstone garbage collection vs merging old backups | Defer to Phase 6 with a rule: keep tombstones ≥ 1 year |
| P1-8 | Phase 0 D6/D7 confirmation (Time Sensitive ≤ 60 min; alarms only at user-chosen times) | Confirm |

## 6. Risks (see `docs/RISKS.md`)
- **Debug-build performance tests are machine-load sensitive.** One run of a < 1 s debug assertion exceeded it; QA delta review comments below.
- **Core logic hasn't yet executed on Apple Foundation;** the new CI step closes this from the next run.
- **Pre-freeze changes landed late** (open vocabularies, `rotationWeekStart`). They are covered by tests, but the UI phase is the first real consumer.

**QA delta review: PASS.** All earlier items are closed. Its three minor follow-ups are applied (`6ef2f62`, `bd90ab7`):
- debug performance limits relaxed (the 1 s budget stays in release);
- `ISOWeekParityPolicy` opened;
- an unknown reminder tier now keeps its raw value and records `unknownTier`.

The QA reviewer also documented the successor-resurrection edge case (B14).

## 7. Your turn (learning mode, optional, ~5 lines)
`Packages/TimetableCore/Sources/TimetableCore/Schedule/WeekParity.swift:28`, `defaultPolicy(for:regionCode:)`, returns `.strict` for everyone. It decides how odd/even ("lichý/sudý", "nepárny/párny") weeks are counted for new timetables:
- **`.strict`:** week parity = the ISO week number's parity. Simple to explain ("week 41 is odd"), but 2026 has 53 weeks, so W53 and the next W01 are both odd: two "odd" weeks in a row around New Year.
- **`.continuous`:** anchors at the week containing 1 September and then strictly alternates. It never repeats inside a school year, but it can disagree with the printed week number after a 53-week year.

You know how Slovak schools and universities actually announce these weeks. If, for example, schools follow the calendar week number but universities run continuously, write the rule with a `switch profile` (and optionally `regionCode`). The tests pin both policies, so any choice stays safe.
