# SHARE_FORMAT — share link / QR / short-code wire format (format version 1)

Status: written in Phase 1 Stage 2D (2026-10-07). Product behaviour: `docs/specs/SHARING.md`. Persisted schema:
`docs/specs/DOMAIN_MODEL.md` (the share format is **separate** from it).
Source of truth: `Packages/TimetableCore/Sources/TimetableCore/Share/` and `Sources/CZlib/`.
`ShareFormatDocTests` fails if a localisation key or a limit in this file drifts from the code.

Contents: 1 Overview · 2 Pipeline and envelope · 3 What is shared · 4 Payload v1 (DTOs, short keys) · 5 Limits and text
policy · 6 Compression (system zlib) · 7 Validation and errors · 8 Links and short codes · 9 Localisation keys ·
10 Versioning rules · 11 Decisions and open questions.

---

## 1. Overview

```
TabulaDatabase ──ShareExport──▶ SharePayloadV1 ──ShareCodec.encode──▶ "1.<base64url>" ──▶ ShareLink (/t#… or /c/CODE)
                                                                                                │
TabulaDatabase ◀─inserted(into:)─ ShareImportedTimetable ◀─materialize─ SharePayloadV1 ◀─decode─┘   (preview in between)
```

| API | Purpose |
|---|---|
| `ShareExport.makePayload(from:timetableID:includeTasks:)` → `ShareExportResult` | builds + validates a payload; returns `warnings` (shortened/cleaned text, skipped lessons, dropped values) |
| `ShareExport.encode(from:timetableID:includeTasks:)` | the same, plus `ShareCodec.encode` |
| `ShareCodec.encode(_:)` → `ShareEnvelope` | `text`, `jsonByteCount`, `compressedByteCount`, `route` (`.inline` / `.shortCode`) |
| `ShareCodec.decode(_:)` / `ShareImport.decode(_:)` | envelope → validated `SharePayloadV1` (typed `throws(ShareError)`) |
| `ShareImport.preview(_:)` (payload or envelope) → `SharePreview` | name, emoji, rotation, counts, `includesTasks`, `warnings` |
| `ShareImport.materialize(_:ids:clock:now:sortIndex:)` → `ShareImportedTimetable` | new entities, fresh IDs + `EntityMeta` |
| `ShareImportedTimetable.inserted(into:)` | appends to a database; never replaces; `.idCollision` if any new ID exists |
| `ShortCode.random(using:)`, `.normalize(_:)`, `.parse(_:)`, `.formatted` | 8-character codes |
| `ShareLink.parse(_:configuration:)`, `.urlString(configuration:)`, `.url(configuration:)` | strict link handling |
| `ShareConfiguration(domain:)`, `.default`, `.defaultDomain` = `tabula.simondev.sk` (placeholder) | link domain |

Everything is deterministic: no `Date()`, `UUID()` or randomness inside core (IDs, clock and RNG are injected).

## 2. Pipeline and envelope

Encode: payload → validate → canonical JSON (`TabulaJSON.makeEncoder()`: sorted keys, compact, slashes unescaped,
UTF-8) → raw DEFLATE (§6) → base64url without padding → prefix `"1."`.

```
envelope = envelope-version "." base64url-no-padding
envelope-version = "1"          ; 1–3 ASCII digits, no leading zero
```

Decode (input is hostile; every step has a bound and a typed error):

| Step | Check | Error |
|---|---|---|
| 1 | non-empty | `malformedEnvelope` |
| 2 | ≤ `maxEnvelopeBytes` bytes | `envelopeTooLarge(byteCount:)` |
| 3 | a `.` exists | `malformedEnvelope` |
| 4 | prefix is 1–3 digits without leading zero; `1` → continue, `>1` → `newerVersion(n)`, `0` or anything else → `unsupportedVersion` | |
| 5 | body non-empty, canonical base64url (alphabet `A–Z a–z 0–9 - _`, no `=`, length ≢ 1 mod 4, zero padding bits) | `malformedEnvelope` / `invalidBase64` |
| 6 | raw INFLATE, streaming, abort as soon as output > `maxJSONBytes`; no trailing bytes after the final block | `decompressedTooLarge` / `decompressionFailed` |
| 7 | well-formed UTF-8 (no overlongs, surrogates, > U+10FFFF) | `invalidUTF8` |
| 8 | JSON nesting depth ≤ `maxJSONDepth` (scanned before `JSONDecoder`) | `malformedPayload(path: "")` |
| 9 | JSON object with integer `v`; `v == 1` → continue; `v > 1` → `newerVersion(v)`; `v < 1` → `unsupportedVersion` (checked before any other key, so a newer payload of unknown shape still says "update the app") | `malformedPayload(path:)` |
| 10 | typed decoding (§4) | `malformedPayload(path:)`, `duplicate`, `invalidValue` |
| 11 | `SharePayloadV1.validate()` (§7) | validation errors |

Route: `compressedByteCount ≤ inlineCompressedBytes` → `.inline`, else `.shortCode`. 2048 compressed bytes → 2731
base64url chars → an inline link of ≈ 2.76 KB, below the 2953-byte capacity of a QR code (byte mode, level L).

Measured sizes (Linux zlib, `ShareCodecTests.sizeBudgetRoutesSecondaryInlineAndUniversityToShortCode`):

| Fixture | JSON | DEFLATE | envelope | route |
|---|---|---|---|---|
| secondary school (14 subjects, 2 bell schedules, 32 lessons, 2 terms, 6 holidays) | 4063 B | 1405 B | 1876 chars | inline (link 1905 chars) |
| secondary + tasks (3 tasks, 1 exam) | 4535 B | 1619 B | 2161 chars | inline (link 2190 chars) |
| university (45 courses, 360 lessons, 12 breaks) | 56 387 B | 7642 B | 10 192 chars | short code |
| university + tasks (150 tasks, 40 exams) | 82 389 B | 11 832 B | 15 778 chars | short code |

## 3. What is shared

| Shared | Not shared (v1) |
|---|---|
| the live timetable: name, emoji, enabled days, rotation, time structure, field visibility, default view, density, palette pack | IDs and sync metadata (`meta`, `fieldClocks`), the timetable's `sortIndex` |
| its live subjects, bell schedules, terms, lessons | schedule overrides (one-off, date-specific, usually personal; may come in a later `v`) |
| live breaks of the timetable **and global breaks** (imported as breaks of the new timetable — never global) | reminder rules, settings |
| with "Include tasks": live, **open** tasks and exams of the timetable (by `timetableID`, or with none but linked to one of its subjects) | completed tasks/exams, completion state, attachments, reminder overrides |

Canonical order (determinism): every collection sorted by its source entity ID; periods by (start, end, ID); period keys
numbered by first appearance in that order; subtask titles by (sortIndex, ID). Permuting any array of the database
yields a byte-identical envelope (tested).

Export never fails silently: text is cleaned/shortened, lists shortened, lessons with a missing subject or period
skipped, malformed vocabulary/symbol/emoji values and unknown palette keys dropped — each counted in `warnings`.
A collection over its limit is refused (`tooMany`), as is an envelope over 64 KB (`envelopeTooLarge`).

## 4. Payload v1 (DTOs and short keys)

Entities reference each other by **index** into the payload arrays; periods by a payload-wide **period key**. The
payload therefore contains no UUIDs (smaller, and incoming IDs can never be reused). Omitted on encode: `nil`
optionals, empty optional lists, and default values (noted below). Sets are ascending arrays; a repeated element is
rejected (`duplicate`). Unknown keys are ignored. Dates `"yyyy-MM-dd"`, times `"HH:mm"`, colours `"#RRGGBB[AA]"`,
weekdays ISO 1…7 — as in DOMAIN_MODEL §1. "a/z" always means start/end.

### 4.1 Root `SharePayloadV1`

| Key | Swift | Type | Notes |
|---|---|---|---|
| `v` | (`SharePayloadV1.version`) | Int | `1` |
| `t` | `timetable` | ShareTimetable | required |
| `s` | `subjects` | [ShareSubject] | omitted when empty |
| `b` | `bellSchedules` | [ShareBellSchedule] | omitted when empty |
| `l` | `lessons` | [ShareLesson] | omitted when empty |
| `r` | `terms` | [ShareTerm] | omitted when empty |
| `h` | `breaks` | [ShareBreak] | omitted when empty |
| `k` | `tasks` | [ShareTask] | present (possibly `[]`) **iff** `includesTasks` |
| `x` | `exams` | [ShareExam] | present (possibly `[]`) **iff** `includesTasks` |

### 4.2 `ShareTimetable` (`t`)

`n` name · `e` emoji? · `d` enabled weekdays (set) · `ro` rotation (omitted for none) · `ts` time structure ·
`fv` visible lesson fields (set of `LessonField`, omitted when empty) · `dv` default view (`TimetableViewKind`) ·
`de` density (`compact`/`comfortable`) · `pp` palette pack?

Rotation `ro` (closed union):
- `{"k":"w","n":2,"a":{…},"lb":["A","B"]}` week cycle; `n` length 2…6; `lb` labels?
  - anchor `{"k":"iso","p":"strict"|"continuous","o":0}` (`o` offset in 0..<length; export normalises mod length)
  - anchor `{"k":"ref","d":"2026-09-01","w":1}` (`w` cycle week 1…length)
- `{"k":"d","n":6,"d":"2026-09-01","i":1,"sd":[1,2,3,4,5],"sb":true,"lb":[…]}` day cycle; `n` 2…10, `d` anchor
  date, `i` anchor index 1…n, `sd` school days (non-empty set), `sb` skips breaks.
- `{"k":"n"}` none (accepted; never written).

Time structure `ts` (closed union): `{"k":"b","d":0,"w":{"5":1}}` (default bell-schedule index, per-weekday indices
keyed `"1"`…`"7"`, `w` omitted when empty) or `{"k":"f","m":90}` (free form, default minutes 1…1439).

### 4.3 `ShareSubject` (`s[i]`)

`n` name · `sn` short name? · `c` colour · colour name: `ck` palette colour key (known keys only; an unknown but
well-formed key is a warning and dropped on import) **or** `cl` literal text · symbol: `se` emoji **or** `si` SF Symbol
name (`a–z 0–9 .`) · `r` default room? · `bd` default building? · `te` default teacher? · `no` notes?

### 4.4 `ShareBellSchedule` (`b[i]`) and `SharePeriod`

Schedule: `n` name · `p` periods. Period: `k` key (0 ≤ key < 800, unique within the schedule; equal keys in different
schedules are the same period, mirroring the persisted period-ID convention) · `l` label? · `a` start · `z` end
(end > start) · `t` kind (`PeriodKind`, omitted when `lesson`).

### 4.5 `ShareLesson` (`l[i]`)

| Key | Meaning |
|---|---|
| `s` | subject index |
| `w` **or** `c` | weekday 1…7 (rotation none/week cycle) **or** cycle day 1…n (day cycle only) |
| `cw` | cycle weeks (set, 1…length of the week cycle, or 1…6 without one); omitted = every week |
| `p` (+ `n`) **or** `a` + `z` | period key (+ span 1…`maxSpan`, omitted when 1) **or** start/end times (end > start) |
| `vt` **or** `vr` | validity: term indices (set; `[]` allowed) **or** `{"a":date,"z":date}`; both omitted = always |
| `r`, `bd`, `te` | room, building, teacher? |
| `ty` | lesson type? (`LessonType`) |
| `no` | notes? |
| `br` | bring list (omitted when empty) |

### 4.6 `ShareTerm` (`r[i]`), `ShareBreak` (`h[i]`)

Term: `n` name, `a`, `z` (inclusive). Break: `n`, `a`, `z`, `t` kind (`BreakKind`, omitted when `holiday`).

### 4.7 `ShareTask` (`k[i]`), `ShareExam` (`x[i]`)

Task: `n` title · `t` kind (`TaskKind`, omitted when `homework`) · `s` subject index? · `dd` due date? + `dt` due
time? (`dt` requires `dd`) · `ll` `{"l":lessonIndex,"d":date}`? · `pr` priority (closed `TaskPriority`, omitted when
`normal`) · `no` notes? · `rp` `{"f":frequency,"i":interval (omitted when 1),"w":[weekdays],"u":until?}` · `st`
subtask titles in display order.

Exam: `n` title · `t` kind (`ExamKind`, omitted when `written`) · `s` subject index? · `d` date · `a` start? · `z`
end? (end > start when both) · `r` room? · `bd` building? · `tp` topics · `no` notes?

Example (the golden test `ShareCodecTests.goldenCanonicalJSON`, abridged):
```json
{"b":[{"n":"Normal","p":[{"a":"08:00","k":0,"z":"08:45"},{"a":"08:55","k":1,"z":"09:40"}]}],
 "l":[{"p":0,"s":0,"w":1},{"br":["Ruler"],"cw":[2],"n":2,"p":1,"r":"101","s":0,"vt":[0],"w":2}],
 "s":[{"c":"#E53935","ck":"palette.classic.color.red","n":"Math","se":"➗"}],
 "t":{"d":[1,2],"de":"comfortable","dv":"grid","fv":["room","teacher"],"n":"Mini",
      "ro":{"a":{"k":"iso","o":1,"p":"strict"},"k":"w","lb":["A","B"],"n":2},"ts":{"d":0,"k":"b"}},"v":1}
```

## 5. Limits and text policy

All in `ShareLimits`. Import rejects anything over a limit; export shortens text/lists and refuses whole collections.

### 5.1 Transport

| Constant | Value | Meaning |
|---|---|---|
| `inlineCompressedBytes` | 2048 | inline link / QR budget (compressed bytes) |
| `maxEnvelopeBytes` | 65536 | envelope string |
| `maxJSONBytes` | 1048576 | decompressed JSON (zip-bomb guard) |
| `maxJSONDepth` | 16 | JSON nesting (v1 needs 5) |

`maxLinkBytes` = envelope + 512 (links).

### 5.2 Counts and values

| Constant | Value | Applies to |
|---|---|---|
| `maxSubjects` | 200 | `s` |
| `maxLessons` | 2000 | `l` |
| `maxBellSchedules` | 20 | `b` |
| `maxPeriodsPerSchedule` | 40 | `b[i].p` |
| `maxTerms` | 20 | `r` |
| `maxBreaks` | 200 | `h` |
| `maxTasks` | 1000 | `k` |
| `maxExams` | 1000 | `x` |
| `maxBringListItems` | 50 | `l[i].br` |
| `maxSubtasks` | 50 | `k[i].st` |
| `maxTopics` | 50 | `x[i].tp` |
| `maxSpan` | 40 | `l[i].n` |
| `maxRepeatInterval` | 365 | `k[i].rp.i` |

Rotation labels: at most 10. Dates: years 1970…2199 (keeps calendar arithmetic far from `LocalDate`'s 1…9999 edges).

### 5.3 Strings (length in Unicode scalars)

| Constant | Value | Applies to |
|---|---|---|
| `maxNameLength` | 100 | names, short names, rooms, buildings, teachers, period/rotation labels, titles, literal colour names, palette keys |
| `maxNotesLength` | 4000 | notes (multi-line) |
| `maxListItemLength` | 100 | bring-list items, subtask titles, topics |
| `maxEmojiLength` | 16 | timetable emoji, subject emoji (non-empty) |
| `maxSystemImageLength` | 100 | SF Symbol names (`a–z 0–9 .`) |
| `maxVocabularyLength` | 40 | open-vocabulary raw values (`A–Z a–z 0–9 _ . -`, non-empty) |

Scalars (not grapheme clusters) are counted because grapheme segmentation differs between OS/Unicode versions, and it
caps "Zalgo" text (one grapheme with thousands of combining marks). Export shortens without splitting a grapheme.

Forbidden scalars (import: `invalidCharacters`; export: removed, line breaks in single-line text → space, CR LF / CR /
U+2028 / U+2029 in notes → LF): C0 controls U+0000–U+001F (notes may contain TAB and LF), DEL and C1 U+007F–U+009F,
U+2028/U+2029, bidi embeddings/overrides U+202A–U+202E and isolates U+2066–U+2069 (spoofing), U+FFF9–U+FFFB,
noncharacters U+FDD0–U+FDEF and U+xxFFFE/U+xxFFFF. Allowed: everything else, including RLM/LRM marks, ZWJ emoji
sequences and RTL scripts.

**Text is data.** Shared strings are never interpreted: not as format strings, markup, URLs or catalog keys. The only
key-valued field (`ck`) is accepted only from the known palette colour keys.

## 6. Compression (system zlib)

Raw DEFLATE (RFC 1951; window bits −15, no zlib/gzip framing), level 9, memLevel 8, default strategy. Inflate streams in
16 KB chunks and stops as soon as the output would exceed `maxJSONBytes`; trailing bytes after the final block,
truncation, a preset-dictionary request or any zlib error is `decompressionFailed`.

**Why system zlib, not a package (dependency justification):** zlib is part of the OS on every target (Apple SDKs ship
`usr/include/zlib.h` + `libz.tbd`; Ubuntu `zlib1g-dev`), zlib licence (permissive), maintained for 30 years, no
package dependency. Foundation's `NSData.compressed(using:)` is Apple-only (not in swift-corelibs-foundation), and a
hand-written DEFLATE encoder is far more than 50 lines.

Wiring: `Sources/CZlib/module.modulemap` (`module CZlib [system] { header "CZlib.h"; link "z" }`) and `CZlib.h`
(includes `<zlib.h>` and wraps `deflateInit2`/`inflateInit2` — macros Swift cannot call — and the `next_in` const
differences in static inline functions). `Package.swift`: `.systemLibrary(name: "CZlib", path: "Sources/CZlib",
pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])])`, `TimetableCore` depends on it. Verified: Linux tests (WSL) and
the iOS cross-build `XCODE_EXTRA_PLATFORM_FOLDERS=…/darwin.artifactbundle/Developer/Platforms swift build
--package-path Packages/TimetableCore --swift-sdk arm64-apple-ios -c release` (links against the SDK's zlib symbols).

Compressed bytes are deterministic per zlib build; Linux and Apple zlib may emit different, equally valid streams.
Golden tests therefore pin the canonical JSON, not the compressed bytes.

## 7. Validation and errors

`SharePayloadV1.validate() throws(ShareError) -> [ShareWarning]` runs on decode, before encode, in `preview` and in
`materialize`. Fixed order (counts → timetable → subjects → bell schedules → terms → breaks → lessons → tasks → exams;
array order within), so the same payload always yields the same error. Invariant (tested, incl. fuzzing): **every
accepted payload materializes into a database with no `error`-severity `TabulaDatabase.validate()` issue.**

| `ShareError` | Raised for |
|---|---|
| `invalidLink`, `invalidShortCode` | §8 |
| `malformedEnvelope`, `unsupportedVersion`, `newerVersion(n)`, `envelopeTooLarge`, `invalidBase64`, `decompressionFailed`, `decompressedTooLarge`, `invalidUTF8` | §2 |
| `malformedPayload(path:)` | JSON syntax, depth, wrong types, missing required keys, unknown kind of a closed union, closed enum value unknown, violated "exactly one of" groups (`w`/`c`, `p`/`a`+`z`, `vt`/`vr`, `ck`/`cl`, `se`/`si`, `dt` without `dd`) |
| `tooMany(collection, count:)` | §5.2 count limits |
| `stringTooLong(path:length:)`, `invalidCharacters(path:)` | §5.3 |
| `invalidValue(path:)` | rotation length/anchor/offset/index/school days, labels > 10, day key vs rotation, cycle weeks out of range, span, period key, free-form minutes, repeat interval, dates outside 1970…2199, malformed emoji/symbol/palette key/vocabulary value, non-canonical weekday keys in `ts.w`, tasks present without `includesTasks` |
| `danglingReference(path:)` | subject/term/bell-schedule/lesson index, period key not in any schedule |
| `duplicate(path:)` | period key twice in a schedule; repeated element in any set |
| `invalidTimeRange(path:)` | period, time slot, exam: end ≤ start |
| `invalidDateRange(path:)` | term, break, validity range: end < start |
| `timetableNotFound`, `compressionFailed` | export |
| `idCollision` | `inserted(into:)` |

Paths are wire paths for diagnostics (`l[3].cw`), never shown to users. Open vocabularies (`LessonType`,
`LessonField`, `TimetableViewKind`, `PeriodKind`, `BreakKind`, `TaskKind`, `ExamKind`, `RepeatFrequency`,
`PalettePackID`) accept unknown well-formed values, keep them unchanged and report `ShareWarning.unknownValue` once per
distinct value.

| `ShareWarning` | When |
|---|---|
| `unknownValue(field:value:)` | import: open-vocabulary value from a newer app (kept) |
| `unknownColorName(subjectIndex:)` | import: `ck` not a known palette colour (dropped on import, colour kept) |
| `overlappingPeriods(scheduleIndex:)` | import: two periods of a schedule overlap |
| `lessonsOnDisabledDays(count:)` | import: weekday lessons on days the timetable does not show |
| `noLessons` | import: empty timetable |
| `textShortened`, `charactersRemoved`, `listsShortened`, `skippedLessons`, `valuesDropped` (`count:`) | export |

## 8. Links and short codes

`ShareLink`: `.inline(envelope:)` ↔ `https://<domain>/t#<envelope>` (the fragment never reaches a server) and
`.shortCode(ShortCode)` ↔ `https://<domain>/c/<CODE>`. Domain from `ShareConfiguration` (default placeholder
`tabula.simondev.sk`; `init?(domain:)` accepts lowercase-able ASCII DNS names with ≥ 2 labels only).

`parse` is strict and treats the text as untrusted: surrounding whitespace trimmed; only printable ASCII; total ≤
`maxLinkBytes`; scheme `https` (any case); host exactly the configured domain (any case) — no user info, port, trailing
dot, percent-encoding or IDN look-alikes; path exactly `/t` with a non-empty fragment of `A–Z a–z 0–9 . _ -`, or exactly
`/c/` + canonical code with no fragment. A query string is ignored (messengers append tracking parameters). The
envelope is only syntax-checked; `ShareCodec.decode` does the rest.

`ShortCode`: 8 characters from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (31 symbols, no 0/O/1/I/L; 31⁸ ≈ 8.5 × 10¹¹).
`random(using:)` draws each character by rejection sampling on 64-bit outputs of the injected generator (draws ≥
2⁶⁴ − 16 are discarded, so there is no modulo bias) — own code, so seeded sequences do not depend on the standard
library's algorithm. `normalize(_:)` drops Unicode whitespace and dashes (`-`, U+2010…U+2015, U+2212), uppercases
ASCII letters and validates (input ≤ 64 scalars; non-ASCII letters, `0 O 1 I L` → `nil`). `formatted` = `ABCD-EFGH`.
The share service must reject a code collision on upload (SHARING.md).

## 9. Localisation keys (String Catalog)

Core returns keys only (`ShareError.message`, `ShareWarning.message`); English is a suggestion for the catalog.

| Key | Args | English |
|---|---|---|
| `share.error.invalidLink` | — | This isn't a Tabula share link. |
| `share.error.invalidCode` | — | Check the code: it has 8 letters and digits. |
| `share.error.damaged` | — | This shared timetable is damaged or incomplete. |
| `share.error.unsupportedVersion` | — | This share format isn't supported. |
| `share.error.newerVersion` | — | This timetable was shared from a newer version of Tabula. Update the app to open it. |
| `share.error.tooLarge` | — | This timetable is too large to share. Remove some notes or tasks and try again. |
| `share.error.invalidContent` | — | This shared timetable contains invalid data and can't be imported. |
| `share.error.timetableNotFound` | — | This timetable no longer exists. |
| `share.error.failed` | — | Something went wrong. Try again. |
| `share.error.tooMany.subjects` | count, limit | This timetable has %1$lld subjects; at most %2$lld can be shared. |
| `share.error.tooMany.lessons` | count, limit | This timetable has %1$lld lessons; at most %2$lld can be shared. |
| `share.error.tooMany.bellSchedules` | count, limit | This timetable has %1$lld bell schedules; at most %2$lld can be shared. |
| `share.error.tooMany.periods` | count, limit | A bell schedule has %1$lld periods; at most %2$lld can be shared. |
| `share.error.tooMany.terms` | count, limit | This timetable has %1$lld terms; at most %2$lld can be shared. |
| `share.error.tooMany.breaks` | count, limit | This timetable has %1$lld holidays; at most %2$lld can be shared. |
| `share.error.tooMany.tasks` | count, limit | There are %1$lld tasks; at most %2$lld can be shared. Share without tasks? |
| `share.error.tooMany.exams` | count, limit | There are %1$lld exams; at most %2$lld can be shared. Share without tasks? |
| `share.warning.unknownValue` | value (verbatim) | Some details come from a newer version of Tabula and are kept as they are. |
| `share.warning.unknownColorName` | — | Some colour names aren't available in this version. |
| `share.warning.overlappingPeriods` | — | Two periods of a bell schedule overlap. |
| `share.warning.lessonsOnDisabledDays` | count | %lld lessons are on days this timetable doesn't show. |
| `share.warning.noLessons` | — | This timetable has no lessons yet. |
| `share.warning.textShortened` | count | %lld texts were shortened to fit. |
| `share.warning.charactersRemoved` | count | Special characters were removed from %lld texts. |
| `share.warning.listsShortened` | count | %lld lists were shortened to fit. |
| `share.warning.skippedLessons` | count | %lld lessons without a subject or period were left out. |
| `share.warning.valuesDropped` | count | %lld details that can't be shared were left out. |

Count arguments need plural variations. Total: 27 keys (17 errors + 10 warnings).

## 10. Versioning rules

- **Envelope version** (`"1."`): the transport (DEFLATE + base64url). A new compression/encoding bumps it. Old apps
  show `newerVersion` ("update the app") for a higher number.
- **Payload version** (`v`): the JSON shape. Within `v` = 1 it is allowed to add **optional** keys (old apps ignore
  them) and new open-vocabulary values (old apps keep them and warn). Bump `v` for anything else: renamed keys, changed
  meaning, new cases of a closed union (rotation, time structure, slot, validity, anchors) or closed enum (density,
  priority, parity policy), tightened rules, overrides or other new collections whose loss would matter.
- Apps keep decoding every older `v` they ever wrote (add `SharePayloadV2` + a converter, never edit V1 in place).
- `ShareCodecTests.goldenCanonicalJSON` pins the v1 wire format; changing it is a format change.

## 11. Decisions and open questions (Stage 2D)

- D2D-1 References are payload indices / period keys, not UUIDs: ~2–3× smaller (UUIDs are incompressible) and import
  cannot reuse incoming IDs by construction.
- D2D-2 Import is strict (reject), export is lenient (clean + warn); export validates its own output, so whatever we
  send, we can receive.
- D2D-3 Envelope prefix > 1 → `newerVersion` (the brief said "unknown prefix → unsupportedVersion"; a higher number is
  clearly a newer app, so the user gets the actionable "update the app"); non-numeric/0 → `unsupportedVersion`.
- D2D-4 Completed tasks/exams are not shared (personal history; keeps links small). Open: should the user be able to
  include them?
- D2D-5 Global breaks are shared and imported as breaks of the new timetable (never global), so an import cannot change
  the recipient's other timetables.
- D2D-6 Dates limited to 1970…2199 and ISO-parity offsets to 0..<length in the wire format (defence for Stage 2B
  arithmetic). Export normalises offsets modulo the length.
- Open: overrides in a later `v`; whether the Worker should re-validate payloads with the same rules (port of §5/§7);
  App Attest for uploads (SHARING.md).
