# Phase 1 plan — TimetableCore (pure Swift, Linux-tested)

Status: approved to start by the human (2026-10-06, "go directly to phase 1 and finish it"). Owner: orchestrator.
Scope per ROADMAP: models with sync metadata, rotation/override resolver, grid, conflicts, onboarding presets, reminder planner, share codec, `Entitlements` protocol; exhaustive Linux tests.
**Schema freeze:** after the Phase 1 gate, changes to the persisted schema need human approval (CLAUDE.md). So this phase pays extra attention to forward compatibility.

## 0. Ground rules for every Phase 1 agent
- Package: `Packages/TimetableCore`, module `TimetableCore` (+ an internal C shim target `CZlib` for the share codec). Swift 6 language mode, strict concurrency, `import Foundation` only (swift-corelibs-foundation on Linux). No UIKit/SwiftUI/Vision/etc. No package dependencies.
- Tests: Swift Testing (`import Testing`), run in WSL with `bash scripts/core-test.sh` (or the worktree equivalent with your own ext4 scratch path). Every public function has tests; time logic gets edge-case and property-style tests.
- **Determinism:** no `Date()`, `UUID()`, `Calendar.current`, `TimeZone.current`, `Locale.current` or random numbers inside core logic. Inject them (`now: Date`, `IDGenerator`, `CalendarContext`, `RandomNumberGenerator`).
- **No user-facing strings in core.** Return localisation keys + arguments (`LocalizedText(key:args:)`); user-entered text is data.
- **Value types:** `public struct`/`enum`, `Codable, Hashable, Sendable`; actors only where state must be shared (repositories). No singletons.
- **Forward compatibility of persisted enums:** vocabularies that may grow (lesson type, attachment kind, exam kind, view kind, reminder target, override change, reminder offset) must not break decoding of the whole database when an unknown value appears. Use open string-backed structs (`struct LessonType: RawRepresentable, Codable, Hashable { static let lecture … }`) or a custom `Codable` with an `.unknown(JSONValue)` case that round-trips.
- **All JSON through `TabulaJSON.makeEncoder()/makeDecoder()`** (sorted keys, `Date` as milliseconds since 1970, no pretty print in production; pretty in tests/backups).
- Folder ownership is exclusive per agent (see §9). Need a change in someone else's folder? Write it in your report; do not edit it.
- Report: files, test count, evidence (command + output tail), open questions, anything that deviates from this plan.

## 1. Calendar primitives (`Sources/TimetableCore/Calendar/`, Stage 1)
- `LocalDate {year, month, day}`: validated, Comparable, Codable as `"yyyy-MM-dd"`. Pure arithmetic (days-from-civil), so `adding(days:)`, `weekday` and `isoWeek` (`ISOWeek {year, week}`) don't need `Calendar`.
- `LocalTime {minuteOfDay: 0..<1440}`: Codable `"HH:mm"`. Lessons never span midnight; the validator reports it if one does.
- `Weekday`: ISO numbering, `monday = 1 … sunday = 7`. Foundation conversion helpers (Foundation: sunday = 1).
- `LocalDateRange {start, end}` (inclusive), `contains`, `days`.
- `CalendarContext {timeZone, firstWeekday}`, building a Gregorian `Calendar` internally.
  - `date(_ d: LocalDate, _ t: LocalTime) -> Date`. **DST policy:** a nonexistent local time (spring-forward gap) shifts forward by the gap length; an ambiguous one (fall-back) takes the **earlier** instant.
  - `local(from: Date) -> (LocalDate, LocalTime)`.
  - `startOfWeek(containing:)` honouring `firstWeekday`.
- `TimeZoneMode`: `.followDevice` (default; school times are wall-clock times) or `.fixed(identifier)`.
- Required tests: DST spring/fall in Europe/Bratislava and America/New_York; a 23 h and a 25 h day; week start Mon/Sun/Sat; midnight rollover; leap years (2028-02-29); ISO 53-week years (2026, 2032); time-zone change between scheduling and firing.

## 2. Model + schema (`Model/`, `Support/`, Stage 1)
- `EntityID<Entity>`: a phantom-typed UUID, Codable as a plain UUID string; each entity has `typealias ID = EntityID<Self>`.
- `HLCTimestamp {physicalMillis: Int64, logical: UInt32, node: UInt64}`: Comparable (lexicographic), Codable as a fixed-width string so string order equals time order. Data type only; the clock algorithm is Stage 2E.
- `EntityMeta {createdAt: HLCTimestamp, updatedAt: HLCTimestamp, isDeleted: Bool, fieldClocks: [String: HLCTimestamp]}`. An empty `fieldClocks` means every field is at `updatedAt`.
  - **Superseded (Stage 3, 2026-10-07):** a missing field clock means `createdAt`, not `updatedAt`; canonical `fieldClocks` omit entries equal to `createdAt`; the `AppSettings` singleton starts at `createdAt = HLCTimestamp.zero` (DOMAIN_MODEL §2.2, B9).
- `protocol SyncEntity: Identifiable, Codable, Hashable, Sendable { var meta: EntityMeta { get set }; static var entityType: EntityType { get } }`.
- `JSONValue` (Codable enum) in `Support/`. It is used for unknown-case preservation and by Stage 2E for field diffs.
- **Entities** (all `SyncEntity`):
  - `Timetable`:
    - `name`, `emoji?`, `enabledDays: Set<Weekday>`, `rotation: RotationScheme`, `timeStructure`.
    - `timeStructure` is `.bellSchedule(defaultID, perWeekday: [Weekday: BellSchedule.ID])` or `.freeForm(defaultDurationMinutes)`.
    - `fieldVisibility: FieldVisibility`, `defaultView: TimetableViewKind` (open), `density`, `palettePackID?`, `sortIndex`.
    - **Superseded (pre-freeze, 2026-10-08):** `Timetable` also persists `rotationWeekStart: Weekday` (rotation arithmetic never uses the device week start); `density` is an open vocabulary (DOMAIN_MODEL §3.2, §4.3, §5).
  - `Subject`: `timetableID`, `name`, `shortName?`, `color: ColorValue`, `colorName?` (accessibility label key or user text), `symbol?` (emoji or SF Symbol name), `defaultRoom?`, `defaultBuilding?`, `defaultTeacher?`, `notes?`.
  - `BellSchedule`: `timetableID`, `name`, `periods: [Period]`.
    - `Period {id, label, start: LocalTime, end: LocalTime, kind: .lesson|.break|.lunch}`.
    - The whole `periods` array is one field for merge purposes.
  - `Lesson`:
    - `timetableID`, `subjectID`, `occurrence: LessonOccurrenceRule`.
    - `slot`: `.period(Period.ID, span: Int)` or `.time(start, end)`.
    - `validity`: `.always`, `.terms(Set<Term.ID>)` or `.range(LocalDateRange)`.
    - **Superseded (pre-freeze):** `validity` is an open union with `.unknown(JSONValue)`; such a lesson is never shown (DOMAIN_MODEL §3.5, §5).
    - Optional fields: `room`, `building`, `teacher`, `lessonType: LessonType?` (open), `notes`, `bringList: [String]`.
    - Nil or empty means "inherit the subject default, else absent". The field-visibility rule is applied by the UI, never by storing placeholders.
  - `LessonOccurrenceRule {day: DayKey, cycleWeeks: Set<Int>?}`. `DayKey` is `.weekday(Weekday)` or `.cycleDay(Int)` (1-based). `cycleWeeks == nil` means every week.
  - `Term`: `timetableID`, `name`, `range`.
  - `CalendarBreak`: `timetableID?` (nil means all timetables), `name`, `range`, `kind` (open: `holiday`, `vacation`, `examPeriod`, `noSchool`).
  - `ScheduleOverride`: `timetableID`, `date`, `change: OverrideChange`. The cases are:
    - `.cancelLesson(Lesson.ID)`, `.modifyLesson(Lesson.ID, LessonPatch)`, `.addLesson(OneOffLesson)`, `.cancelDay(note?)`, `.useBellSchedule(BellSchedule.ID)`, `.followDay(DayKey)`
    - `.unknown(JSONValue)` (round-trips)
  - `TaskItem` (deliberately not named `Task`):
    - `title`, `kind` (open: `homework`, `assignment`, `todo`), `subjectID?`, `timetableID?`.
    - `due: TaskDue?` (`.date(LocalDate)` or `.dateTime(LocalDate, LocalTime)`), `linkedLesson: (Lesson.ID, LocalDate)?`.
    - `priority` (`low`, `normal`, `high`, `urgent`), `notes`, `repeat: RepeatRule?`, `completedAt: Date?`.
    - **Superseded (pre-freeze):** `due` (`TaskDue`) is an open union with `.unknown(JSONValue)` (task treated as undated); the property is named `repeatRule`, and its next-occurrence semantics and derived IDs are normative in DOMAIN_MODEL §3.9.
    - Child collections `subtasks: [Subtask]` and `attachments: [AttachmentRef]`. Children carry their own `id` and `meta`, for set-merge.
    - `reminderOverride: ReminderOverride?`.
  - `Exam`: `timetableID?`, `subjectID?`, `title`, `kind` (open), `date`, `start?`, `end?`, `room?`, `building?`, `topics`, `reminderOverride?`, `completedAt?`.
  - `ReminderRule`:
    - `target` (open: `homework`, `assignment`, `exam`, `lesson`, `packTonight`, `todo`), `offsets: [ReminderOffset]`.
    - `ReminderOffset` is `.minutesBefore(n)`, `.daysBefore(n, at: LocalTime)` or `.unknown`.
    - `followUp`: `.afterMinutes(n)` or `.nextMorning(at:)`; fires only if the item is not completed.
    - `tier: DeliveryTier` (`standard`, `timeSensitive`, `alarm`), `quietHours: QuietHours?`, `isEnabled`, `origin` (`preset` or `user`).
    - **Superseded (pre-freeze):** `FollowUp` is an open union (`.unknown` plans no follow-up) and `DeliveryTier` an open vocabulary (unknown → planned as `standard`) (DOMAIN_MODEL §5).
  - `AppSettings` (a single entity):
    - `profile: UserProfile`, `onboardingCompletedAt?`, `activeTimetableID?`.
    - `weekStartOverride: Weekday?`, `hourCycle` (`auto`, `h12`, `h24`), `timeZoneMode`, `appearance`, `palettePackID`.
    - `globalQuietHours?`, `timeSensitivePolicy`, `alarmPolicy`, `syncEnabled = true`.
    - **Superseded (pre-freeze):** `UserProfile`, `HourCycle` and `Appearance` are open vocabularies (unknown → `.other` presets / `.auto`) (DOMAIN_MODEL §5).
- `FieldVisibility`: `Set<LessonField>`, where `LessonField` is `room`, `building`, `teacher`, `lessonType`, `notes`, `bringList`.
- **Schema root `TabulaDatabase`:** `schemaVersion: Int` (`current = 1`), with one array per entity type plus `settings`. Encoding is deterministic: arrays sorted by `id`, keys sorted.
  - Also `func validate() -> [ValidationIssue]`. It checks dangling references, end ≤ start, overlapping periods within a bell schedule, duplicate IDs, and enabled days with zero lessons (info level).
  - **Superseded (pre-freeze):** validation messages use neutral phrasing without arguments; the entity type name is a separate label (`ValidationIssue.entityTypeName`), never inserted into a sentence (DOMAIN_MODEL §6, Appendix A.2).
- Also write `docs/specs/DOMAIN_MODEL.md`: the schema reference (every type, field, encoding and invariant). This is the document the schema freeze refers to.

## 3. Theme, presets, entitlements (Stage 1)
- `Theme/`: `ColorValue` (sRGB + alpha, Codable as `"#RRGGBB[AA]"`), WCAG 2.x relative luminance, `contrastRatio`, `preferredTextColor(on:)` (black or white with the higher ratio), `meetsAA(normal/large)`. Palette packs as data (Classic, Ocean, Sunset, Pastel; ~12 named colours each; names as l10n keys). Test that every pack colour has a text colour with ≥ 4.5:1.
- `Presets/`: `ProfilePreset.for(UserProfile)` per the PRODUCT.md table (time structure, fields, rotation prompt level, default view, exam prominence, terminology key, default reminder rules; **no preset ever uses the `alarm` tier**). `BellScheduleTemplate(firstStart, lessonMinutes, breakMinutes: [Int], count)`. `OnboardingAnswers → OnboardingBuilder.makeInitialDatabase(answers, idGenerator, clock, now)`. `SampleData.make(profile:…)` with subject names as l10n keys.
- `Entitlements/`:
  - `ProFeature` cases: `unlimitedTimetables`, `largeWidgets`, `lockScreenWidgets`, `liveActivity`, `watchApp`, `loudAlarms`, `aiImport`, `exports`, `themePacks`, `extraAttachmentCapacity`, `statistics`.
  - `Tier`: `free` or `pro`. `FeaturePolicy` is data, with limits such as `maxTimetables(free) = 1` and an attachment quota.
  - `protocol EntitlementsProvider: Sendable { var tier: Tier { get }; func isAllowed(_: ProFeature) -> Bool; func limit(_: Limit) -> Int? }`.
  - Implementations `PolicyEntitlements(tier:policy:)` and `AllAccessEntitlements` (development).
  - The Free/Pro split mirrors PRODUCT.md and is a human decision, so it lives in one data table.

## 4. Schedule engine (`Schedule/`, Stage 2B)
- Result types (defined by Stage 1 in `Model/ScheduleTypes.swift`, so Stage 2C can depend on them):
  - `ResolvedLesson`: an occurrence ID that is deterministic per lesson and date; source; effective fields after subject defaults and patches; start/end as both local times and instants; period label; status (`scheduled`, `modified`, `added`, `cancelled`).
  - `DaySchedule`: date, day key, cycle label, `isSchoolDay`, active break, entries, conflicts.
  - `Conflict`.
- `RotationResolver`, which turns a date into a `DayKey` and a cycle week:
  - `RotationScheme`:
    - `.none`
    - `.weekCycle(WeekCycle {length 2…6, anchor: .isoWeekParity(policy) | .referenceWeek(LocalDate, cycleWeek), labels?})`
    - `.dayCycle(DayCycle {length 2…10, anchorDate, anchorIndex, schoolDays, skipsBreaks, labels?})`
  - **ISO 53-week years:** `ISOWeekParityPolicy` is `.strict` or `.continuous`. The function that maps an ISO week to a cycle week is isolated so the human can review it (learning-mode contribution, §10).
  - **Superseded (pre-freeze):** both policies and the week boundaries (`Timetable.rotationWeekStart`, never the device week start) are now normative in DOMAIN_MODEL §4.3.
  - Day cycles count only school days (enabled weekdays, not in a break if `skipsBreaks`). This must be O(1) or O(breaks) per query, not a day-by-day loop over years.
- `ScheduleResolver.day(_:in:)` and `days(in range)`:
  - Applies terms, validity, breaks, overrides (followDay, then useBellSchedule, then cancel/modify/add), bell schedules (including per-weekday overrides) and subject defaults.
  - Sorted output; conflicts detected per day.
  - `nowAndNext(at: Date)` returns the current lesson, remaining seconds, the next lesson, and the gap/break state.
  - `occurrences(in: DateInterval)` serves widgets and the planner.
- `GridLayout`: for the classic periods × days grid, a week projection (which cycle week to show) with cells, spans and empty slots.
- `TimeBlockLayout`: proportional layout returning fractional positions; day range from the earliest and latest lesson, or user bounds.
- Tests:
  - Property tests over 10 years of dates: every school day gets exactly one day key; cycles advance by one per school day; no lesson appears outside its validity window.
  - All §1 edge cases through the resolver.
  - Overrides stacking on one date.
  - Conflicts.

## 5. Reminder planner (`Reminders/`, Stage 2C — notifications-engineer)
- Input:
  - `PlannerInput`: `now`, `CalendarContext`, settings, rules, tasks, exams.
  - `lessons: [ResolvedLesson]` (pre-resolved by the caller over the horizon).
  - `packTonight` sources (the next school day's bring lists).
  - `NotificationBudget(maxPending: 64, reserved: 4)`, `alarmSoftLimit`, `horizonDays` (default 14).
- Output `ReminderPlan`:
  - `notifications: [PlannedNotification]` and `alarms: [PlannedAlarm]`.
  - `dropped` (never silently: a count plus items) and `isSaturated`.
  - `nextReplanDate`.
- `PlannedNotification`:
  - `id`: a deterministic stable hash of source + rule + offset + fire instant, so re-planning can diff.
    **Superseded (Stage 2C, decision 7):** the hash uses the offset's **wall-clock** time (local fire time for "days before at hh:mm", the item's local time for "minutes before") instead of the fire instant, so IDs survive DST and time-zone changes.
  - `fireDate`, `requestedTier`, `effectiveTier`.
  - Content as l10n keys + args, `threadID`, `categoryID` (actions: mark done, snooze), `sourceRef`, `isFollowUp`.
- Policies:
  - **Time Sensitive downgrade:** lead time > `timeSensitivePolicy.maxLeadMinutes` (default 60, per Apple HIG; decision D6 pending) means standard.
  - **Alarms only from user-created rules** (`origin == .user`; decision D7 pending).
  - Quiet hours: move to the end of quiet hours unless that is after the due time; then drop, with a reason.
  - Completed items get nothing. Follow-ups are planned only for incomplete items and cancelled by re-planning.
- Priority when over budget: soonest first, then the higher tier. Everything beyond the budget goes to `dropped` with a saturation flag.
- Tests: the 64 cap with 100+ tasks; DST transitions in offsets ("1 day before at 19:00" across a DST weekend); quiet hours spanning midnight; follow-ups; ID stability across re-plans; time-zone change.

## 6. Share codec (`Share/`, `Sources/CZlib/`, Stage 2D)
- Share DTOs, separate from persistence models:
  - `SharePayloadV1`: `v`, timetable, subjects, bell schedules, lessons, terms, breaks; optional tasks + exams when "Include tasks" is on.
  - No meta or field clocks; IDs remapped on import.
  - Short keys allowed; deterministic JSON.
- Pipeline: JSON, then raw DEFLATE (system zlib via the `CZlib` module map: Linux `zlib1g-dev`, Apple SDK `libz`), then base64url without padding. The envelope string is prefixed with its format version.
- Limits:
  - Inline-link budget: ≤ 2048 compressed bytes, else short code.
  - Max encoded size 64 KB; max decompressed size 1 MB (zip-bomb guard).
  - Count and string-length caps.
  - Strict validation: references, enum vocabularies, version (`.newerVersion` maps to an "update the app" error).
- `ShareImport.preview(_:)` returns name, counts, includes-tasks and warnings. `materialize(_, idGenerator, clock, now)` returns new entities with fresh IDs and metadata. It never overwrites anything.
- `ShortCode`:
  - 8 characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0/O/1/I/L), generated with an injected RNG.
  - `normalize(_:)` uppercases and strips spaces and dashes, then validates.
- `ShareLink`: build/parse `https://<domain>/t#<payload>` and `/c/<code>`. The domain comes from a configuration value (placeholder `tabula.simondev.sk`).
- Tests:
  - Round-trip; determinism (same input gives the same bytes).
  - Size budget with a large university timetable.
  - Fuzz: random/truncated/oversized/bomb/invalid UTF-8/wrong version/dangling references.
  - Malicious strings are stored as data only.

## 7. Sync primitives + repository (`Sync/`, Stage 2E — sync-storage-engineer)
- `HybridLogicalClock` (`tick(now:)`, `receive(_:now:)`, a node ID from injected randomness).
- `MutationStamper.stamp(old:new:clock:now:)`: diffs top-level fields via `JSONValue` and advances `fieldClocks` and `updatedAt`.
  **Superseded detail (Stage 3):** only changed keys get clocks; unchanged fields stay at their clock (missing = `createdAt`), so no materialisation of every field is needed.
- `SyncMerge.merge(local:remote:)`:
  - Field-level last-writer-wins by field clocks, tie broken by node.
  - Tombstones: the later delete wins against an earlier edit, and the reverse; documented.
  - Child set-merge for `subtasks` and `attachments` by child ID.
- `TabulaDatabase` merge, for first sync, backup import and multi-device tests.
- `protocol TabulaRepository: Sendable { func load() async throws -> TabulaDatabase; func save(_:) async throws }`, with two implementations:
  - `InMemoryRepository` (actor).
  - `FileRepository` (actor, directory URL injected), which provides:
    - an atomic write (temp file + rename) and a last-good backup file;
    - corruption recovery from the backup, with a `RecoveryEvent`;
    - a migration chain on `JSONValue` (v1 = identity, scaffolding for v2);
    - read-only mode if the file's schema is newer than the app;
    - backup export/import (`BackupArchive` = manifest + database JSON).
- Tests: merge commutativity and idempotence (property tests), tombstones, children, a corrupted file, a newer-schema file, atomicity (an interrupted write leaves the last good state).

## 8. Integration (orchestrator, Stage 3)
Merge all worktree branches; one `scripts/core-test.sh` run green; `scripts/validate.sh` green; `qa-reviewer`; fixes; `docs/specs/DOMAIN_MODEL.md` final; gate report `docs/gates/PHASE-1.md`.

## 9. Stages, agents, folder ownership
| Stage | Agent | Folders (exclusive) | Depends on |
|---|---|---|---|
| 1 | core-domain-engineer | `Calendar/`, `Model/`, `Support/`, `Theme/`, `Presets/`, `Entitlements/`, their tests, `docs/specs/DOMAIN_MODEL.md` | Phase 0 skeleton |
| 2B | core-domain-engineer | `Schedule/` + tests | Stage 1 commit |
| 2C | notifications-engineer | `Reminders/` + tests | Stage 1 commit |
| 2D | core-domain-engineer | `Share/`, `Sources/CZlib/`, the `CZlib` target in `Packages/TimetableCore/Package.swift` + tests | Stage 1 commit |
| 2E | sync-storage-engineer | `Sync/` + tests | Stage 1 commit |
| — | env-ci-engineer (parallel, main tree) | everything outside `Packages/TimetableCore` | — |
Each Stage agent works in its own git worktree and commits on its branch; the orchestrator merges.

## 10. Learning-mode contribution for the human
`RotationResolver`'s mapping from ISO week to cycle week for odd/even weeks (≈ 5–10 lines) is a domain decision. Slovak and Czech schools differ: some use the ISO week-number parity, others count weeks from 1 September. The 53-week years (2026, 2032) are where the choice shows. Stage 2B ships both policies plus a default. The gate report invites the human to write or adjust the default-selection function.
