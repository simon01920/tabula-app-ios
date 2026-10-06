# DOMAIN_MODEL — persisted schema reference (schema version 1)

Status: written in Phase 1 Stage 1 (2026-10-06). **This is the document the post-Phase-1 schema freeze refers to.**
After the Phase 1 gate, any change to what is described in §§1–6 needs human approval (CLAUDE.md).
Source of truth for the code: `Packages/TimetableCore/Sources/TimetableCore/{Calendar,Model,Support,Theme}`.
`DomainModelDocTests` fails if a localisation key or a union kind used by the code is missing from this file.

Contents: 1 Encoding conventions · 2 Root and sync metadata · 3 Entities · 4 Embedded value types ·
5 Vocabularies · 6 Invariants and validation · 7 Forward compatibility · 8 Not persisted · 9 Calendar semantics ·
Appendix A localisation keys · Appendix B decisions and open questions.

---

## 1. Encoding conventions

All persisted JSON goes through `TabulaJSON.makeEncoder()` / `makeDecoder()`.

| Rule | Detail |
|---|---|
| Text | UTF-8. Object keys sorted (`.sortedKeys`), slashes not escaped, compact. `pretty: true` (indentation) only for tests and human-readable backups; both decode identically. |
| Determinism | The same logical database always produces the same bytes. Entity arrays are written sorted by `id`. `TaskItem.subtasks` / `.attachments` are written sorted by (`sortIndex`, `id`). Every `Set` is written as an ascending array. `decode(encode(x)) == x.canonicalized()` and `encode(decode(bytes)) == bytes` for canonical input. |
| Optionals | `nil` optional fields are **omitted** (no `null`). Empty arrays are written (`"bringList":[]`). |
| Instant (`Date`) | **Integer** milliseconds since 1970-01-01T00:00:00Z, rounded to the nearest ms (`1791280800000`). Decoding also accepts a fractional number (rounded). Integers keep decode→encode byte-stable. |
| `LocalDate` | `"yyyy-MM-dd"`, years 0001–9999, strict (zero-padded, valid day). Proleptic Gregorian. |
| `LocalTime` | `"HH:mm"`, 00:00–23:59, 24-hour. No seconds, no 24:00. |
| `LocalDateRange` | `{"end":"yyyy-MM-dd","start":"yyyy-MM-dd"}`, **inclusive** both ends. `end < start` decodes (empty range) and is reported by validation. |
| `Weekday` | Integer, **ISO numbering**: Monday `1` … Sunday `7`. (Foundation's Sunday = 1 is never persisted.) |
| `EntityID<T>` | Uppercase UUID string `"000000F1-0000-4000-8000-000000000001"`; decoding accepts lowercase. Ordering = UUID byte order. |
| `HLCTimestamp` | Fixed-width string `PPPPPPPPPPPPPPP-LLLLLLLLLL-NNNNNNNNNNNNNNNN`: 15 decimal digits physical ms, 10 decimal digits logical counter (UInt32), 16 lowercase hex digits node (UInt64). Byte order of the strings equals timestamp order. Example `"001759744800000-0000000000-0000000000c0ffee"`. |
| `ColorValue` | `"#RRGGBB"` when opaque, else `"#RRGGBBAA"`; uppercase on encode, case-insensitive on decode. 8-bit sRGB channels. |
| Tagged unions | An object with a string `"kind"` discriminator plus named payload keys, e.g. `{"kind":"period","periodID":"…","span":1}`. **Closed** unions reject an unknown kind (decoding error); **open** unions (`OverrideChange`, `ReminderOffset`) preserve it (§7). |
| Open vocabularies | Plain strings (`"lecture"`). Any string decodes and round-trips (§5). |
| Closed enums | Plain strings (`"timeSensitive"`); unknown values are a decoding error. |
| Dictionaries | Only `[String: …]` objects are persisted (`fieldClocks`, `perWeekday` keyed by ISO weekday number strings `"1"`…`"7"`). |

---

## 2. Root and sync metadata

### 2.1 `TabulaDatabase` (root object)

| Key | Type | Notes |
|---|---|---|
| `schemaVersion` | Int | `1` for data written by this version (`TabulaDatabase.currentSchemaVersion` = `TimetableCoreInfo.schemaVersion`). Decoding never rejects other values; the repository decides (migration / read-only). |
| `settings` | `AppSettings` | Required. The singleton. |
| `timetables` | [`Timetable`] | Each array is optional on decode (missing → empty) and always written. |
| `subjects` | [`Subject`] | |
| `bellSchedules` | [`BellSchedule`] | |
| `lessons` | [`Lesson`] | |
| `terms` | [`Term`] | |
| `breaks` | [`CalendarBreak`] | |
| `overrides` | [`ScheduleOverride`] | |
| `tasks` | [`TaskItem`] | |
| `exams` | [`Exam`] | |
| `reminderRules` | [`ReminderRule`] | |

Tombstoned entities (`meta.isDeleted == true`) stay in their array until a future garbage collection; every
consumer must skip them.

### 2.2 `EntityMeta` (key `meta` on every entity and child)

```json
"meta": {
  "createdAt": "001759744800000-0000000000-0000000000c0ffee",
  "fieldClocks": { "hourCycle": "001759744900000-0000000000-0000000000c0ffee" },
  "isDeleted": false,
  "updatedAt": "001759744900000-0000000000-0000000000c0ffee"
}
```

| Key | Type | Invariant |
|---|---|---|
| `createdAt` | HLCTimestamp | ≤ `updatedAt`. |
| `updatedAt` | HLCTimestamp | Latest change to any field; ≥ every `fieldClocks` value. |
| `isDeleted` | Bool | Tombstone. |
| `fieldClocks` | {String: HLCTimestamp} | Keyed by the field's **JSON key** (top-level fields of the entity, e.g. `"room"`, `"periods"`). **Empty map or missing key = the field is at `updatedAt`.** Always written (possibly `{}`). |

Merge granularity (implemented by Stage 2E): field-level last-writer-wins by `fieldClocks`, ties broken by the
HLC node. `BellSchedule.periods` is **one** field. `TaskItem.subtasks` and `TaskItem.attachments` are set-merged
by child `id`, each child carrying its own `meta`.

### 2.3 Entity types (sync record types)

`EntityType` raw values are stable record-type names: `timetable`, `subject`, `bellSchedule`, `lesson`, `term`,
`calendarBreak`, `scheduleOverride`, `task`, `exam`, `reminderRule`, `settings`.
Every top-level entity conforms to `SyncEntity` (`id: EntityID<Self>`, `meta`, `static entityType`). Children
(`Subtask`, `AttachmentRef`) conform to `ChildEntity` (`id`, `meta`).

---

## 3. Entities

Field tables list the JSON key (= Swift property name), the type, and whether it may be absent ("opt").
Every entity also has `id` (its typed `EntityID`) and `meta` (§2.2); they are not repeated below.
User text is stored verbatim; it is data, never a localisation key, unless the type is `TextValue`.

### 3.1 `AppSettings` (`settings`)

Exactly one instance, always with id **`7AB01A00-5E77-4000-8000-000000000001`** (`AppSettings.singletonID`), so
that settings created independently on two devices merge field by field. It is never tombstoned.

| Key | Type | Opt | Default / notes |
|---|---|---|---|
| `profile` | `UserProfile` | | `elementary` · `secondary` · `university` · `other` |
| `onboardingCompletedAt` | instant | opt | absent = onboarding not finished |
| `activeTimetableID` | Timetable.ID | opt | timetable shown at launch |
| `weekStartOverride` | Weekday | opt | absent = locale's first weekday |
| `hourCycle` | `HourCycle` | | `auto` · `h12` · `h24` |
| `timeZoneMode` | `TimeZoneMode` | | `{"kind":"followDevice"}` (default) or `{"kind":"fixed","identifier":"Europe/Bratislava"}` |
| `appearance` | `Appearance` | | `auto` · `light` · `dark` |
| `palettePackID` | `PalettePackID` | | default `"classic"` |
| `globalQuietHours` | `QuietHours` | opt | |
| `timeSensitivePolicy` | `{"isEnabled":Bool,"maxLeadMinutes":Int}` | | defaults `true`, `60` (decision D6) |
| `alarmPolicy` | `{"allowsPresetRules":Bool,"isEnabled":Bool}` | | defaults `false`, `false` (decision D7: alarms only from user rules) |
| `syncEnabled` | Bool | | default `true` |

### 3.2 `Timetable` (`timetable`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `name` | String | | user text |
| `emoji` | String | opt | |
| `enabledDays` | [Weekday] | | ascending set, e.g. `[1,2,3,4,5]`; should be non-empty |
| `rotation` | `RotationScheme` | | §4.3 |
| `timeStructure` | `TimeStructure` | | `{"kind":"bellSchedule","defaultID":"…","perWeekday":{"5":"…"}}` or `{"kind":"freeForm","defaultDurationMinutes":90}` (1…1439) |
| `fieldVisibility` | [`LessonField`] | | ascending set of enabled optional fields, e.g. `["notes","room","teacher"]` |
| `defaultView` | `TimetableViewKind` | | |
| `density` | `Density` | | `compact` · `comfortable` |
| `palettePackID` | `PalettePackID` | opt | absent = `settings.palettePackID` |
| `sortIndex` | Int | | ascending display order |

`perWeekday` maps an ISO weekday number (as a string key) to a bell schedule of the same timetable that applies
on that weekday instead of `defaultID` (e.g. a short Friday). Overrides (`useBellSchedule`) take precedence.

### 3.3 `Subject` (`subject`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `timetableID` | Timetable.ID | | owner |
| `name` | String | | user text |
| `shortName` | String | opt | for tight grid cells |
| `color` | ColorValue | | opaque recommended; text colour via `ColorValue.preferredTextColor` |
| `colorName` | `TextValue` | opt | `{"kind":"key","value":"palette.classic.color.red"}` (follows app language) or `{"kind":"literal","value":"Brick"}` (user text) |
| `symbol` | `SubjectSymbol` | opt | `{"kind":"emoji","value":"📐"}` or `{"kind":"systemImage","value":"function"}` |
| `defaultRoom`, `defaultBuilding`, `defaultTeacher` | String | opt | inherited by lessons whose own value is nil/empty |
| `notes` | String | opt | |

### 3.4 `BellSchedule` (`bellSchedule`) and `Period`

| Key | Type | Notes |
|---|---|---|
| `timetableID` | Timetable.ID | owner |
| `name` | String | user text |
| `periods` | [`Period`] | one merge field; ascending by start; must not overlap |

`Period` (embedded, not an entity): `{"end":"08:45","id":"…","kind":"lesson","label":"1","start":"08:00"}`

| Key | Type | Opt | Notes |
|---|---|---|---|
| `id` | Period.ID | | unique **within** the schedule (see convention below) |
| `label` | String | opt | user label; absent → UI numbers lesson periods 1, 2, … |
| `start`, `end` | LocalTime | | `end > start` (no period spans midnight) |
| `kind` | `PeriodKind` | | `lesson` · `break` · `lunch` (open) |

**Period-ID convention:** a variant schedule of the same timetable (short day, exam day) is created by copying
the default schedule *including its period IDs*, then changing times. Lessons reference `Period.ID`, so "period 3"
lands in period 3 of whichever schedule applies on a date. Period IDs are therefore shared across a timetable's
schedules and unique only within one schedule.

### 3.5 `Lesson` (`lesson`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `timetableID` | Timetable.ID | | owner |
| `subjectID` | Subject.ID | | same timetable |
| `occurrence` | `LessonOccurrenceRule` | | `{"cycleWeeks":[1,3],"day":{"kind":"weekday","weekday":1}}`; `cycleWeeks` omitted = every week |
| `slot` | `LessonSlot` | | `{"kind":"period","periodID":"…","span":2}` or `{"kind":"time","end":"09:30","start":"08:00"}` |
| `validity` | `LessonValidity` | | `{"kind":"always"}`, `{"kind":"terms","termIDs":[…]}` (ascending), `{"kind":"range","range":{…}}` |
| `room`, `building`, `teacher` | String | opt | nil/empty → subject default, else absent |
| `lessonType` | `LessonType` | opt | open |
| `notes` | String | opt | |
| `bringList` | [String] | | user order; feeds "pack tonight" |

- `span` ≥ 1 counts consecutive **lesson-kind** periods starting at `periodID` in the applicable schedule; the
  occurrence runs from the first period's start to the last one's end, including break periods in between.
- `.time` slots: `end > start`; lessons never span midnight.
- `DayKey` `weekday` is used with rotation `none`/`weekCycle`; `cycleDay` (1-based) only with `dayCycle`.
- Field rule: values are never placeholders. Visibility (`Timetable.fieldVisibility`) is applied by the UI only.

Example:
```json
{
  "bringList": ["Goggles", "Notebook"],
  "id": "000000F1-0000-4000-8000-00000000000D",
  "lessonType": "lab",
  "meta": {…},
  "occurrence": { "day": { "kind": "weekday", "weekday": 1 } },
  "room": "Lab 2",
  "slot": { "kind": "period", "periodID": "000000F1-0000-4000-8000-000000000005", "span": 1 },
  "subjectID": "000000F1-0000-4000-8000-00000000000A",
  "timetableID": "000000F1-0000-4000-8000-000000000001",
  "validity": { "kind": "terms", "termIDs": ["000000F1-0000-4000-8000-00000000000C"] }
}
```

### 3.6 `Term` (`term`)

`timetableID` (Timetable.ID), `name` (String), `range` (LocalDateRange, inclusive, `start ≤ end`).

### 3.7 `CalendarBreak` (`calendarBreak`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `timetableID` | Timetable.ID | opt | absent = applies to every timetable |
| `name` | String | | user text |
| `range` | LocalDateRange | | inclusive |
| `kind` | `BreakKind` | | `holiday` · `vacation` · `examPeriod` · `noSchool` (open) |

### 3.8 `ScheduleOverride` (`scheduleOverride`)

`timetableID` (Timetable.ID), `date` (LocalDate), `change` (`OverrideChange`, **open** union):

| `kind` | Payload | Meaning |
|---|---|---|
| `"cancelLesson"` | `lessonID` | the lesson's occurrence on `date` does not take place |
| `"modifyLesson"` | `lessonID`, `patch` (`LessonPatch`) | one-occurrence change |
| `"addLesson"` | `lesson` (`OneOffLesson`) | extra lesson on `date` only; its occurrence ID derives from the override ID |
| `"cancelDay"` | `note`? | no lessons that day |
| `"useBellSchedule"` | `bellScheduleID` | use another schedule of the timetable that day |
| `"followDay"` | `day` (DayKey), `cycleWeek`? | the date runs another day's lessons; `cycleWeek` (1-based) picks the week of a week cycle, absent = the date's own cycle week |
| anything else | preserved verbatim | `.unknown(JSONValue)`: ignored by the resolver, re-encoded unchanged |

Several overrides may target one date; Stage 2B applies `followDay`, then `useBellSchedule`, then
`cancelDay`/`cancelLesson`/`modifyLesson`/`addLesson`.

`LessonPatch` (all keys optional; absent = keep the effective value): `subjectID`, `slot`, `room`, `building`,
`teacher`, `lessonType`, `notes`, `bringList`. A present value replaces the effective value (after subject
defaults); an **empty** string/array clears the field for that occurrence (no fallback to the subject default).
Example: `{"kind":"modifyLesson","lessonID":"…","patch":{"room":"204","teacher":""}}`.

`OneOffLesson`: `subjectID`, `slot`, `room`?, `building`?, `teacher`?, `lessonType`?, `notes`?, `bringList` — same
rules as `Lesson`.

### 3.9 `TaskItem` (`task`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `title` | String | | user text |
| `kind` | `TaskKind` | | `homework` · `assignment` · `todo` (open) |
| `subjectID` | Subject.ID | opt | |
| `timetableID` | Timetable.ID | opt | |
| `due` | `TaskDue` | opt | `{"date":"2026-10-08","kind":"date"}` or `{"date":"2026-10-08","kind":"dateTime","time":"08:00"}` |
| `linkedLesson` | `{"date":…,"lessonID":…}` | opt | one occurrence of a recurring lesson |
| `priority` | `TaskPriority` | | `low` < `normal` < `high` < `urgent` |
| `notes` | String | opt | |
| `repeatRule` | `RepeatRule` | opt | `{"frequency":"weekly","interval":1,"until":"2027-01-31","weekdays":[1,3]}`; `interval` ≥ 1; `weekdays` empty = weekday of the due date; `until` optional |
| `completedAt` | instant | opt | absent = open |
| `subtasks` | [`Subtask`] | | children, written sorted by (`sortIndex`, `id`) |
| `attachments` | [`AttachmentRef`] | | children, written sorted by (`sortIndex`, `id`) |
| `reminderOverride` | `ReminderOverride` | opt | absent = follow matching rules |

`Subtask` (child): `id`, `meta`, `title`, `completedAt`?, `sortIndex`.
`AttachmentRef` (child): `id`, `meta`, `kind` (`AttachmentKind`: `photo` · `file` · `link` · `voiceNote`, open),
`title`?, `fileName`? (inside the attachments container), `url`? (links; never opened automatically),
`contentType`? (UTI string), `byteCount`? (Int64), `sortIndex`. The bytes are **not** in the database.

`ReminderOverride`: `{"followUp":{"kind":"inherit"},"isEnabled":true,"offsets":[…],"tier":"timeSensitive"}`.
`isEnabled: false` = no reminders for the item; `offsets`/`tier` absent = inherit from the rule;
`followUp` is `{"kind":"inherit"}`, `{"kind":"none"}` or `{"kind":"custom","followUp":{…FollowUp…}}`.

### 3.10 `Exam` (`exam`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `timetableID` | Timetable.ID | opt | |
| `subjectID` | Subject.ID | opt | |
| `title` | String | | |
| `kind` | `ExamKind` | | `written` · `oral` · `test` · `quiz` · `practical` · `midterm` · `final` (open) |
| `date` | LocalDate | | |
| `start`, `end` | LocalTime | opt | `end > start` when both are present |
| `room`, `building` | String | opt | |
| `topics` | [String] | | user order |
| `notes` | String | opt | |
| `reminderOverride` | `ReminderOverride` | opt | |
| `completedAt` | instant | opt | |

### 3.11 `ReminderRule` (`reminderRule`)

| Key | Type | Opt | Notes |
|---|---|---|---|
| `target` | `ReminderTarget` | | `homework` · `assignment` · `exam` · `lesson` · `packTonight` · `todo` (open) |
| `offsets` | [`ReminderOffset`] | | should be non-empty |
| `followUp` | `FollowUp` | opt | fires only if the item is still incomplete |
| `tier` | `DeliveryTier` | | `standard` < `timeSensitive` < `alarm` |
| `quietHours` | `QuietHours` | opt | in addition to `settings.globalQuietHours` |
| `isEnabled` | Bool | | |
| `origin` | `RuleOrigin` | | `preset` · `user`; the UI sets `user` when the user edits a rule. Presets never use `alarm`. |

`ReminderOffset` (**open** union): `{"kind":"minutesBefore","minutes":15}` (≥ 0, before the due/start instant) ·
`{"at":"19:00","days":1,"kind":"daysBefore"}` (wall-clock `at` on the day `days` ≥ 0 calendar days before; "morning
of" = `days: 0`) · anything else preserved as `.unknown`.
`FollowUp` (closed): `{"kind":"afterMinutes","minutes":120}` (> 0) · `{"at":"07:00","kind":"nextMorning"}`.
`QuietHours`: `{"end":"07:00","start":"22:00"}`; `[start, end)`; `end < start` spans midnight; `start == end` is empty.

---

## 4. Embedded value types

### 4.1 Calendar values
`LocalDate`, `LocalTime`, `LocalDateRange`, `Weekday` — §1. `LocalDateTime` and `ISOWeek` are never persisted.

### 4.2 `TimeZoneMode`
`{"kind":"followDevice"}` or `{"identifier":"Asia/Tokyo","kind":"fixed"}` (IANA identifier; an unknown identifier
falls back to the device zone and is reported by validation).

### 4.3 Rotation

`RotationScheme` (closed): `{"kind":"none"}` · `{"kind":"weekCycle","weekCycle":{…}}` · `{"kind":"dayCycle","dayCycle":{…}}`.

`WeekCycle`: `{"anchor":{…},"labels":["A","B"],"length":2}` — `length` 2…6; `labels` optional, exactly `length`
entries (user text).

`WeekCycleAnchor` (closed):
- `{"kind":"isoWeekParity","offset":0,"policy":"strict"}` — cycle week from the ISO week number; `offset` shifts the
  mapping (swap A/B; missing on decode = 0); `policy` is `ISOWeekParityPolicy`: `strict` (use the ISO number
  literally — W53 and the next W01 are both odd) or `continuous` (keep alternating across the year boundary). The
  mapping function is Stage 2B (PHASE1_PLAN §4, §10).
- `{"cycleWeek":1,"date":"2026-09-01","kind":"referenceWeek"}` — the week containing `date` (weeks start on the
  user's first weekday) is cycle week `cycleWeek` (1…length); counting is continuous in both directions.

`DayCycle`: `{"anchorDate":"2026-09-01","anchorIndex":1,"labels":[…],"length":6,"schoolDays":[1,2,3,4,5],"skipsBreaks":true}`
— `length` 2…10; `anchorIndex` 1…length is the cycle day of `anchorDate`; the cycle advances only on `schoolDays`
(ascending set, non-empty) and, with `skipsBreaks`, not on days inside a `CalendarBreak`.

`DayKey` (closed): `{"kind":"weekday","weekday":1}` · `{"index":3,"kind":"cycleDay"}`.

---

## 5. Vocabularies

**Open** (string-backed structs, `OpenVocabulary`; any string decodes, unknown values round-trip, `isKnown == false`):

| Type | Known values |
|---|---|
| `LessonType` | `lecture`, `seminar`, `lab`, `tutorial` |
| `LessonField` | `room`, `building`, `teacher`, `lessonType`, `notes`, `bringList` |
| `TimetableViewKind` | `grid`, `timeBlocks`, `day`, `tiles`, `agenda` |
| `PeriodKind` | `lesson`, `break`, `lunch` |
| `BreakKind` | `holiday`, `vacation`, `examPeriod`, `noSchool` |
| `TaskKind` | `homework`, `assignment`, `todo` |
| `ExamKind` | `written`, `oral`, `test`, `quiz`, `practical`, `midterm`, `final` |
| `AttachmentKind` | `photo`, `file`, `link`, `voiceNote` |
| `ReminderTarget` | `homework`, `assignment`, `exam`, `lesson`, `packTonight`, `todo` |
| `RepeatFrequency` | `daily`, `weekly`, `monthly` |
| `PalettePackID` | `classic`, `ocean`, `sunset`, `pastel` |

**Open unions:** `OverrideChange`, `ReminderOffset` (unknown `kind`, a missing `kind`, or a non-object value is
preserved as `.unknown(JSONValue)`; a *known* kind with a malformed payload is a decoding error).

**Closed** (Swift enums; an unknown value fails decoding of the whole database):
`UserProfile` (`elementary`, `secondary`, `university`, `other`), `HourCycle` (`auto`, `h12`, `h24`),
`Appearance` (`auto`, `light`, `dark`), `Density` (`compact`, `comfortable`), `TaskPriority` (`low`, `normal`,
`high`, `urgent`), `DeliveryTier` (`standard`, `timeSensitive`, `alarm`), `RuleOrigin` (`preset`, `user`),
`ISOWeekParityPolicy` (`strict`, `continuous`), `Weekday` (1…7), and the closed unions `RotationScheme`,
`WeekCycleAnchor`, `DayKey`, `TimeStructure`, `LessonSlot`, `LessonValidity`, `TaskDue`, `FollowUp`,
`FollowUpOverride` (`"inherit"`, `"none"`, `"custom"`), `SubjectSymbol`, `TextValue` (`"key"`, `"literal"`),
`TimeZoneMode`.

---

## 6. Invariants and validation

`TabulaDatabase.validate() -> [ValidationIssue]` never mutates or rejects data. It is deterministic (same input →
same issues in the same order). Tombstoned entities are skipped except for duplicate-ID and metadata checks.
**"Passes validation" = no issue with severity `error`.**

`ValidationIssue`: `severity` (`info` < `warning` < `error`), `code`, `entityType`, `entityID`, `childID`?
(subtask/attachment/period), `field`? (JSON key path, e.g. `"slot"`, `"rotation.anchorIndex"`), `relatedID`?
(missing/deleted/overlapping counterpart), `value`? (offending value as text), `message` (`LocalizedText`
`validation.<code>` with three arguments: entity-type name key, field, value).

| Code | Severity | Checked |
|---|---|---|
| `unsupportedSchemaVersion` | error | `schemaVersion != 1` |
| `duplicateID` | error | a UUID used twice across all top-level entities (incl. settings); child IDs within a task; period IDs within a schedule |
| `danglingReference` | error | every reference: subject/lesson/term/bell-schedule/timetable IDs, `activeTimetableID`, `linkedLesson`, override targets, `LessonSlot.period` must exist in a schedule of the lesson's timetable |
| `referencesDeletedEntity` | warning | a live entity references a tombstone |
| `crossTimetableReference` | warning | lesson→subject, lesson→term, override→lesson/schedule/subject, timetable→bell schedule in a different timetable |
| `invalidTimeRange` | error / warning | period, `.time` slot or exam `end ≤ start` (error); quiet hours `start == end` (warning) |
| `invalidDateRange` | error | term, break or `validity.range` with `end < start` |
| `overlappingPeriods` | warning | two valid periods of one schedule overlap |
| `invalidValue` | error / warning | errors: rotation length/anchor/anchorIndex/schoolDays out of range, `cycleDay` key without a matching day cycle, `weekday` key in a day-cycle timetable, `cycleWeeks` outside 1…length, `span < 1`, free-form duration outside 1…1439, `repeatRule.interval < 1`, negative offsets, `afterMinutes ≤ 0`, negative `maxLeadMinutes`, deleted settings. Warnings: labels count ≠ length, empty `enabledDays`/`cycleWeeks`/`validity.terms`/`offsets`, `cycleWeeks` without a week cycle, lesson on a disabled weekday, period slot in a free-form timetable, slot on a non-lesson period, `span` running past the last lesson period of the default schedule, preset rule with `alarm` tier, settings ID ≠ singleton, unknown fixed time zone, `updatedAt < createdAt`, a field clock after `updatedAt` |
| `unknownValue` | info | an open-vocabulary value or open-union kind this version does not know |
| `emptyScheduleDay` | info | an enabled weekday (or a cycle day of a day cycle) with no live lesson |

Further invariants not expressible in validation: `AppSettings.id` is the singleton; IDs are never reused after
deletion; `LocalTime` never exceeds 23:59 (no lesson spans midnight).

---

## 7. Forward-compatibility rules

1. **Open vocabularies / open unions** may gain values without a schema bump. Older versions keep and re-encode
   unknown values unchanged (tested byte-for-byte: `unknownValuesSurviveDecodeAndReencode`), plan/resolve nothing
   for them and report them as `unknownValue` (info).
2. **Closed enums / closed unions**: adding a case is a schema change → bump `schemaVersion` (older apps then open the
   file read-only, Stage 2E).
3. **Unknown object keys are ignored on decode and dropped on re-encode.** Adding an optional field without a bump
   is therefore only acceptable if losing it when an *older* version re-saves is acceptable; otherwise bump the
   version. The sync layer should upload only changed fields so that an older device does not erase a newer
   device's fields in CloudKit (open question B4).
4. Renaming a key or a raw value, changing a type, or changing the meaning of a value is always a breaking change.
5. Decoding tolerates: missing root arrays (→ empty), missing `WeekCycleAnchor.offset` (→ 0), lowercase UUIDs,
   lowercase hex colours, fractional millisecond instants.
6. `TabulaDatabase` decoding accepts any `schemaVersion`; migrations operate on `JSONValue` before typed decoding
   (Stage 2E).

---

## 8. Not persisted (derived or configuration data)

- **Schedule results** (`Model/ScheduleTypes.swift`): `ResolvedLesson`, `ResolvedLesson.Status`, `Source`,
  `SubjectSummary`, `DaySchedule`, `Conflict`, `NowNext`. They are `Codable` for widget/watch snapshots, which are a
  separate, separately versioned format. `OccurrenceID` is derived but **its format is frozen**, because notification
  identifiers derive from it: `"lesson:<LESSON-UUID>:<yyyy-MM-dd>"` and `"override:<OVERRIDE-UUID>"`.
- `CalendarContext`, `LocalDateTime`, `ISOWeek`, `CalendarContext.Resolution`.
- `ValidationIssue`, `LocalizedText`/`LocalizedArgument` (Codable for logs/snapshots only).
- Presets and theme data: `ProfilePreset`, `ReminderRulePreset`, `BellScheduleTemplate`, `OnboardingAnswers`,
  `SampleData`, `PalettePack`/`PaletteColor` (only `PalettePackID` and `ColorValue`s are persisted).
- Entitlements: `ProFeature`, `Tier`, `Limit`, `FeaturePolicy`, `EntitlementsProvider` (StoreKit state lives in the
  app; the Free/Pro table is code data in `FeaturePolicy.standard`).
- Attachment bytes (App Group files / CloudKit assets).
- Display names of vocabulary values and enums — the UI owns those catalog keys.

---

## 9. Calendar semantics (normative for every stage)

- Lesson, period, exam and reminder times are **wall-clock** times in the `CalendarContext` time zone
  (`settings.timeZoneMode` resolved against the device zone). A zone change moves instants; reminders must be re-planned.
- **DST policy** (`CalendarContext.date(_:_:)`): a nonexistent local time (spring-forward gap) is shifted forward by
  the gap length (Bratislava 2026-03-29 02:30 → 03:30 CEST); an ambiguous one (fall-back) takes the **earlier**
  instant (Bratislava 2026-10-25 02:30 → 00:30 UTC). `CalendarContext.resolve` exposes the classification.
- Days can last 23 h or 25 h (`dayInterval`); a skipped midnight starts the day at the first existing minute.
- Week start is `settings.weekStartOverride ?? locale first weekday`; `startOfWeek` is pure arithmetic.
- `LocalDate` arithmetic is pure integer math (proleptic Gregorian); ISO weeks follow ISO 8601 (53-week years 2020,
  2026, 2032, 2037).
- Instant arithmetic uses `Int64` seconds (Apple Watch arm64_32 has a 32-bit `Int`).
- Core never reads `Date()`, `UUID()`, `Calendar.current`, `TimeZone.current` or `Locale.current`: inject `now`,
  an `IDGenerator` (`SystemIDGenerator` / `SequentialIDGenerator`) and a `TimestampClock`.

---

## Appendix A — localisation keys introduced by TimetableCore (Stage 1)

Core returns only keys; the UI resolves them in String Catalogs. English source text below is a suggestion with
translator context. Argument placeholders are positional.

### A.1 Entity type names (nested argument of validation messages)

| Key | English | Context |
|---|---|---|
| `entityType.timetable` | timetable | noun, lower case, used inside sentences |
| `entityType.subject` | subject | " |
| `entityType.bellSchedule` | bell schedule | " |
| `entityType.lesson` | lesson | " |
| `entityType.term` | term | school term / semester |
| `entityType.calendarBreak` | holiday | a break/holiday date range |
| `entityType.scheduleOverride` | schedule change | a one-off change to one day |
| `entityType.task` | task | homework/assignment/to-do |
| `entityType.exam` | exam | " |
| `entityType.reminderRule` | reminder rule | " |
| `entityType.settings` | settings | " |

### A.2 Validation messages — args: (1) entity type name (key from A.1), (2) field (technical), (3) value

| Key | English |
|---|---|
| `validation.unsupportedSchemaVersion` | This data was created by a different version of the app. |
| `validation.duplicateID` | A %1$@ appears twice. |
| `validation.danglingReference` | A %1$@ refers to something that no longer exists. |
| `validation.referencesDeletedEntity` | A %1$@ refers to something that was deleted. |
| `validation.crossTimetableReference` | A %1$@ refers to something from another timetable. |
| `validation.invalidTimeRange` | A %1$@ ends before it starts. |
| `validation.invalidDateRange` | A %1$@ has an end date before its start date. |
| `validation.overlappingPeriods` | Two periods of a bell schedule overlap. |
| `validation.invalidValue` | A %1$@ has a value that is out of range. |
| `validation.unknownValue` | A %1$@ uses something from a newer app version. |
| `validation.emptyScheduleDay` | A school day has no lessons yet. |

### A.3 Schedule conflicts — arg (1) number of affected lessons (plural variations)

| Key | English |
|---|---|
| `conflict.overlap` | %lld lessons overlap. |
| `conflict.periodNotInSchedule` | A lesson's period doesn't exist in today's bell schedule. |
| `conflict.spanExceedsSchedule` | A lesson runs past the last period of the day. |
| `conflict.missingSubject` | A lesson's subject is missing. |
| `conflict.invalidTimeRange` | A lesson ends before it starts. |

### A.4 Terminology (profile presets)

| Key | English | Context |
|---|---|---|
| `terminology.lesson` | Lesson | school profiles |
| `terminology.classLecture` | Class | university profile ("class/lecture"); choose the natural word per language |

### A.5 Palette packs and colour names (accessibility names of subject colours)

| Pack key | English | Colour keys (English in parentheses) |
|---|---|---|
| `palette.classic.name` | Classic | `palette.classic.color.red` (Red), `palette.classic.color.orange` (Orange), `palette.classic.color.yellow` (Yellow), `palette.classic.color.green` (Green), `palette.classic.color.teal` (Teal), `palette.classic.color.cyan` (Cyan), `palette.classic.color.blue` (Blue), `palette.classic.color.indigo` (Indigo), `palette.classic.color.purple` (Purple), `palette.classic.color.pink` (Pink), `palette.classic.color.brown` (Brown), `palette.classic.color.gray` (Grey) |
| `palette.ocean.name` | Ocean | `palette.ocean.color.abyss` (Abyss), `palette.ocean.color.navy` (Navy), `palette.ocean.color.harbor` (Harbour), `palette.ocean.color.deepSea` (Deep sea), `palette.ocean.color.lagoon` (Lagoon), `palette.ocean.color.teal` (Teal), `palette.ocean.color.seafoam` (Seafoam), `palette.ocean.color.aqua` (Aqua), `palette.ocean.color.sky` (Sky), `palette.ocean.color.mist` (Mist), `palette.ocean.color.sand` (Sand), `palette.ocean.color.coral` (Coral) |
| `palette.sunset.name` | Sunset | `palette.sunset.color.crimson` (Crimson), `palette.sunset.color.rust` (Rust), `palette.sunset.color.ember` (Ember), `palette.sunset.color.tangerine` (Tangerine), `palette.sunset.color.amber` (Amber), `palette.sunset.color.gold` (Gold), `palette.sunset.color.peach` (Peach), `palette.sunset.color.rose` (Rose), `palette.sunset.color.magenta` (Magenta), `palette.sunset.color.plum` (Plum), `palette.sunset.color.violet` (Violet), `palette.sunset.color.dusk` (Dusk) |
| `palette.pastel.name` | Pastel | `palette.pastel.color.pink` (Pink), `palette.pastel.color.peach` (Peach), `palette.pastel.color.lemon` (Lemon), `palette.pastel.color.mint` (Mint), `palette.pastel.color.aqua` (Aqua), `palette.pastel.color.periwinkle` (Periwinkle), `palette.pastel.color.lavender` (Lavender), `palette.pastel.color.lilac` (Lilac), `palette.pastel.color.sage` (Sage), `palette.pastel.color.sky` (Sky), `palette.pastel.color.blush` (Blush), `palette.pastel.color.linen` (Linen) |

### A.6 Sample data (resolved once into user text when the user picks "Use sample data")

| Key | English | Context |
|---|---|---|
| `sample.subject.mathematics` | Mathematics | school subject |
| `sample.subject.nativeLanguage` | English | the country's main language as a school subject (sk: Slovenčina, de: Deutsch, …) |
| `sample.subject.foreignLanguage` | French | a typical first foreign language for the locale (sk/cs/pl/…: English) |
| `sample.subject.science` | Science | primary-school subject |
| `sample.subject.art` | Art | |
| `sample.subject.music` | Music | |
| `sample.subject.physicalEducation` | PE | physical education |
| `sample.subject.physics` | Physics | |
| `sample.subject.chemistry` | Chemistry | |
| `sample.subject.biology` | Biology | |
| `sample.subject.history` | History | |
| `sample.subject.geography` | Geography | |
| `sample.subject.informatics` | Computer Science | |
| `sample.subject.calculus` | Calculus | university course |
| `sample.subject.linearAlgebra` | Linear Algebra | university course |
| `sample.subject.programming` | Programming | university course |
| `sample.subject.databases` | Databases | university course |
| `sample.subject.statistics` | Statistics | university course |
| `sample.subject.academicWriting` | Academic Writing | university course |
| `sample.task.homework` | Exercises on page 42 | sample homework title |
| `sample.exam.title` | Unit test | sample exam title |
| `sample.bring.sportsKit` | Sports kit | bring-list item for PE |

Total: 103 keys (11 + 11 + 5 + 2 + 52 + 22).

---

## Appendix B — decisions and open questions (Stage 1)

Decisions taken in Stage 1 (safer option where the plan was silent or ambiguous):

- B1 Instants are integer milliseconds (not `.millisecondsSince1970` doubles) for byte-stable round trips.
- B2 `AppSettings` uses a fixed singleton ID so two devices' settings merge instead of duplicating.
- B3 `PeriodKind`, `LessonField`, `RepeatFrequency`, `PalettePackID` are open vocabularies (the plan listed a
  closed `.lesson|.break|.lunch`); unknown values round-trip.
- B4 Unknown object keys are not preserved (§7.3). Open: should entities carry an "unknown fields" bag, or should the
  sync layer only ever upload changed fields? Needs a decision before the freeze.
- B5 `OverrideChange.followDay` has an optional `cycleWeek`; `WeekCycleAnchor.isoWeekParity` has an `offset`
  (A/B swap). Both are additive to the plan.
- B6 Period-ID convention for variant bell schedules (§3.4) and `span` counting lesson periods only (§3.5).
- B7 `ISOWeekParityPolicy.continuous` needs a precise reference definition from Stage 2B (what the alternation is
  anchored to across years); the human's learning-mode contribution (PHASE1_PLAN §10) decides the default.
- B8 Free/Pro attachment quotas (100 MB / 2 000 MB) are placeholders; the human decides. PRODUCT.md's Free list names
  "grid/day/tile views" but does not assign week time-blocks or Agenda to either tier — currently ungated.
