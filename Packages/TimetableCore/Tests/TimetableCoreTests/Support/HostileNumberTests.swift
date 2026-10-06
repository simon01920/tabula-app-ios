import Foundation
import Testing
@testable import TimetableCore

/// Stage 3: hostile numbers in persisted data (backups, sync records, hand-edited files) must be rejected with a
/// `DecodingError` or tolerated — never trap. `TabulaJSON.makeDecoder()` used to trap on `1e300` through an
/// unchecked `Int64(value.rounded())`.
@Suite("Hostile numbers")
struct HostileNumberTests {
    private struct Box: Codable, Equatable { var at: Date }

    /// Literals that must be rejected wherever an instant is expected.
    static let invalidInstantLiterals = [
        "1e300", "-1e300", "1.7976931348623157e308", "-1.7976931348623157e308", "1e309", "-1e309",
        "9223372036854775807", "-9223372036854775808", "9223372036854775808", "-9223372036854775809",
        "18446744073709551616", "1e19", "-1e19", "4.5e15", "253402214400000", "-62135510400001",
        "253402214399999.6", "-62135510400000.6", #""NaN""#, #""Infinity""#, #""-Infinity""#, #""1791280800000""#,
        "true", "[]", "{}",
    ]

    /// Literals that are valid instants, with the milliseconds they decode to.
    static let validInstantLiterals: [(String, Int64)] = [
        ("0", 0), ("-0", 0), ("1e-300", 0), ("0.4", 0), ("0.5", 1), ("1791280800000.4", 1_791_280_800_000),
        ("1.7912808e12", 1_791_280_800_000), ("-62135510400000", -62_135_510_400_000),
        ("253402214399999", 253_402_214_399_999), ("253402214399999.4", 253_402_214_399_999),
    ]

    private func box(_ literal: String) -> Data { Data(#"{"at":\#(literal)}"#.utf8) }

    @Test func decoderRejectsOutOfRangeAndNonNumericInstants() throws {
        let decoder = TabulaJSON.makeDecoder()
        for literal in Self.invalidInstantLiterals {
            #expect(throws: DecodingError.self, "\(literal)") { try decoder.decode(Box.self, from: box(literal)) }
        }
        for (literal, millis) in Self.validInstantLiterals {
            let decoded = try decoder.decode(Box.self, from: box(literal))
            #expect(TabulaJSON.checkedMilliseconds(from: decoded.at) == millis, "\(literal)")
        }
    }

    @Test func boundsAreInclusiveAndByteStable() throws {
        for millis in [TabulaJSON.millisecondsRange.lowerBound, TabulaJSON.millisecondsRange.upperBound, 0, -1, 1] {
            let data = box(String(millis))
            let decoded = try TabulaJSON.makeDecoder().decode(Box.self, from: data)
            #expect(try TabulaJSON.makeEncoder().encode(decoded) == data)
        }
        // The bounds keep every persisted instant inside years 1…9999 in every time zone.
        let lower = TabulaJSON.date(fromMilliseconds: TabulaJSON.millisecondsRange.lowerBound)
        let upper = TabulaJSON.date(fromMilliseconds: TabulaJSON.millisecondsRange.upperBound)
        for zone in ["Pacific/Kiritimati", "Etc/GMT+12", "UTC"] {
            let context = CalendarContext(timeZone: Fixture.zone(zone), firstWeekday: .monday)
            #expect(context.localDate(of: lower) >= .earliest && context.localDate(of: lower) <= Fixture.date("0001-01-03"))
            #expect(context.localDate(of: upper) <= .latest && context.localDate(of: upper) >= Fixture.date("9999-12-29"))
        }
    }

    @Test func encoderRefusesWhatTheDecoderWouldReject() {
        let unpersistable = [Date(timeIntervalSince1970: 1e300), Date(timeIntervalSince1970: -1e300),
                             Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity),
                             Date(timeIntervalSince1970: -.infinity), .distantPast,
                             TabulaJSON.date(fromMilliseconds: TabulaJSON.millisecondsRange.upperBound + 1)]
        // Note: values are checked through Bools, never through `#expect` on a `Date` — FoundationEssentials'
        // `Date.description` itself traps for such instants, and a failing expectation would describe it.
        for date in unpersistable {
            let seconds = date.timeIntervalSince1970
            var threwEncodingError = false
            do { _ = try TabulaJSON.makeEncoder().encode(Box(at: date)) } catch is EncodingError { threwEncodingError = true } catch {}
            #expect(threwEncodingError, "encode \(seconds)")
            let unchecked = TabulaJSON.checkedMilliseconds(from: date) == nil
            #expect(unchecked, "checked \(seconds)")
            let clamped = TabulaJSON.millisecondsRange.contains(TabulaJSON.milliseconds(from: date))
            #expect(clamped, "clamped, total: \(seconds)")
        }
        #expect(TabulaJSON.milliseconds(from: Date(timeIntervalSince1970: 1e300)) == TabulaJSON.millisecondsRange.upperBound)
        #expect(TabulaJSON.milliseconds(from: Date(timeIntervalSince1970: -1e300)) == TabulaJSON.millisecondsRange.lowerBound)
        #expect((try? TabulaJSON.makeEncoder().encode(Box(at: .distantFuture))) != nil, "year 4001 is fine")
    }

    // MARK: Every instant field of the database, via TabulaDatabase.decode and backup import

    /// The fixture with every optional instant set, so every `Date` path appears in the JSON.
    static func databaseWithEveryInstant() -> TabulaDatabase {
        var db = Fixture.fullDatabase()
        db.settings.onboardingCompletedAt = Fixture.now
        db.tasks[0].completedAt = Fixture.now
        if db.tasks[0].subtasks.isEmpty {
            db.tasks[0].subtasks = [Subtask(id: SyncFixture.id(1, namespace: 0x77), meta: Fixture.meta(), title: "s")]
        }
        db.tasks[0].subtasks[0].completedAt = Fixture.now
        db.exams[0].completedAt = Fixture.now
        return db
    }

    /// JSON paths (object keys / array indices) of every instant in `tree`.
    static func instantPaths(in tree: JSONValue, prefix: [SyncJSONPatch.Step] = []) -> [[SyncJSONPatch.Step]] {
        switch tree {
        case .object(let members):
            return members.keys.sorted().flatMap { key -> [[SyncJSONPatch.Step]] in
                let path = prefix + [.key(key)]
                if ["completedAt", "onboardingCompletedAt"].contains(key), case .integer = members[key] { return [path] }
                return instantPaths(in: members[key] ?? .null, prefix: path)
            }
        case .array(let items):
            return items.indices.flatMap { instantPaths(in: items[$0], prefix: prefix + [.index($0)]) }
        default:
            return []
        }
    }

    /// The database JSON with the instant at `path` replaced by the raw `literal`.
    static func patched(_ tree: JSONValue, at path: [SyncJSONPatch.Step], literal: String) -> Data {
        let marker = "__tabula_hostile_number__"
        let text = String(decoding: SyncJSONParser.serialize(SyncJSONPatch.set(tree, path, .string(marker))), as: UTF8.self)
        return Data(text.replacingOccurrences(of: "\"\(marker)\"", with: literal).utf8)
    }

    /// A backup archive file whose database part is `database` (manifest consistent with it).
    static func archive(database: Data, createdAt: String = "1791280800000") -> Data {
        let manifest = #"{"createdAt":\#(createdAt),"databaseByteCount":\#(database.count),"entityCounts":{},"#
            + #""format":"tabula.backup","formatVersion":1,"schemaVersion":1,"sha256":"\#(TabulaSHA256.hexDigest(database))"}"#
        return Data((BackupArchive.magicLine + "\n" + manifest + "\n").utf8) + database
    }

    @Test func everyInstantPathRejectsHostileNumbersThroughDecodeAndBackupImport() throws {
        let db = Self.databaseWithEveryInstant()
        let tree = try SyncJSONParser.parse(db.encoded())
        let paths = Self.instantPaths(in: tree)
        let keys = Set(paths.compactMap { path -> String? in
            guard case .key(let key)? = path.last else { return nil }
            return key
        })
        #expect(keys == ["completedAt", "onboardingCompletedAt"])
        #expect(paths.count >= 4, "settings, task, subtask and exam instants: \(paths.count)")
        // Sanity: re-inserting the original value round-trips through both entry points.
        guard case .integer(let original)? = SyncJSONPatch.get(tree, paths[0]) else {
            Issue.record("no instant at \(paths[0])")
            return
        }
        #expect(try TabulaDatabase.decode(from: Self.patched(tree, at: paths[0], literal: String(original))) == db.canonicalized())
        #expect(try BackupArchive.decode(from: Self.archive(database: db.encoded())).database() == db.canonicalized())

        var checked = 0
        for path in paths {
            for literal in Self.invalidInstantLiterals {
                let data = Self.patched(tree, at: path, literal: literal)
                #expect(throws: (any Error).self, "\(path) = \(literal)") { try TabulaDatabase.decode(from: data) }
                let file = Self.archive(database: data)
                #expect(throws: BackupArchiveError.self, "backup \(path) = \(literal)") {
                    try BackupArchive.decode(from: file).database()
                }
                checked += 1
            }
            for (literal, _) in Self.validInstantLiterals {
                let decoded = try TabulaDatabase.decode(from: Self.patched(tree, at: path, literal: literal))
                #expect(try TabulaDatabase.decode(from: decoded.encoded()) == decoded, "re-encodes: \(literal)")
            }
        }
        #expect(checked == paths.count * Self.invalidInstantLiterals.count)

        // The manifest's own instant.
        for literal in Self.invalidInstantLiterals {
            #expect(throws: BackupArchiveError.self, "manifest createdAt = \(literal)") {
                try BackupArchive.decode(from: Self.archive(database: db.encoded(), createdAt: literal))
            }
        }
    }

    // MARK: Hostile integers reaching the engines

    /// Extreme integers and dates that decode fine (validation reports most of them) must not trap
    /// validation, the schedule resolver, the grid or the reminder planner.
    @Test func extremeValuesNeverTrapTheEngines() throws {
        let extremes = [Int.max, Int.min, Int.max - 1, Int.min + 1, 0, -1, 4_000_000]
        for (index, value) in extremes.enumerated() {
            var db = Fixture.fullDatabase()
            let school = db.timetables[0].id, college = db.timetables[1].id
            db.timetables[0].rotation = .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: index % 2 == 0 ? .strict : .continuous, offset: value)))
            db.timetables[1].rotation = .dayCycle(DayCycle(length: max(1, value), anchorDate: index % 2 == 0 ? .earliest : .latest,
                                                           anchorIndex: value, schoolDays: [.monday, .wednesday]))
            if let first = db.lessons.firstIndex(where: { $0.timetableID == school }),
               case .period(let periodID, _) = db.lessons[first].slot {
                db.lessons[first].slot = .period(periodID, span: value)
                db.lessons[first].occurrence.cycleWeeks = [value]
            }
            if let follow = db.overrides.firstIndex(where: { if case .followDay = $0.change { return true } else { return false } }) {
                db.overrides[follow].change = .followDay(.weekday(.friday), cycleWeek: value)
            }
            db.settings.timeSensitivePolicy.maxLeadMinutes = value
            db.settings.globalQuietHours = QuietHours(start: Fixture.time("22:00"), end: Fixture.time("07:00"))
            for rule in db.reminderRules.indices {
                db.reminderRules[rule].isEnabled = true
                db.reminderRules[rule].offsets = [.minutesBefore(value), .daysBefore(value, at: Fixture.time("19:00")),
                                                  .minutesBefore(15)]
                db.reminderRules[rule].followUp = index % 2 == 0 ? .afterMinutes(value) : .nextMorning(at: Fixture.time("07:00"))
            }
            db.tasks[0].due = .date(index % 2 == 0 ? .latest : .earliest)
            db.tasks[0].completedAt = nil
            db.exams[0].date = index % 2 == 0 ? .latest : .earliest
            db.exams[0].start = Fixture.time("23:59")
            db.exams[0].completedAt = nil

            _ = db.validate()
            let context = CalendarContext(timeZone: Fixture.zone("Pacific/Kiritimati"), firstWeekday: .sunday)
            for timetable in [school, college] {
                let resolver = try #require(ScheduleResolver(database: db, timetableID: timetable, context: context))
                for date in [LocalDate.earliest, .latest, Fixture.date("2026-10-21"), Fixture.date("2026-10-22")] {
                    _ = resolver.day(date)
                    _ = GridLayout.make(days: [resolver.day(date)], resolver: resolver)
                }
                _ = resolver.rotation.startOfWeek(withCycleWeek: 2, onOrAfter: .latest)
            }
            let plan = ReminderPlanner.plan(PlannerInput(
                now: Fixture.now, context: context, settings: db.settings, rules: db.reminderRules, tasks: db.tasks,
                exams: db.exams, lessons: [], packTonight: [], budget: .iOSDefault, alarmSoftLimit: 10, horizonDays: 14,
                canScheduleAlarms: true))
            #expect(plan.notifications.allSatisfy { $0.fireDate > Fixture.now })
        }
        // Instants far outside years 1…9999 saturate instead of trapping.
        let context = CalendarContext(timeZone: Fixture.zone("UTC"), firstWeekday: .monday)
        #expect(context.local(from: Date(timeIntervalSince1970: 1e300)).date == .latest)
        #expect(context.local(from: Date(timeIntervalSince1970: -1e300)).date == .earliest)
        #expect(context.local(from: Date(timeIntervalSince1970: .nan)).date == .latest)
        #expect(LocalDate.latest.adding(days: 1) == .latest && LocalDate.earliest.adding(days: Int.min) == .earliest)
        #expect(LocalDate.latest.addingIfValid(days: 1) == nil && LocalDate.earliest.addingIfValid(days: Int.max) == nil)
        #expect(Fixture.date("2026-10-07").addingIfValid(days: -1) == Fixture.date("2026-10-06"))
    }

    /// A hostile `minutesBefore`/`daysBefore` offset is dropped as `invalidOffset`, not planned at an instant
    /// outside the calendar.
    @Test func unrepresentableOffsetsAreDroppedAsInvalid() {
        let rule = PlannerFixture.rule(1, .homework, [.minutesBefore(Int.max), .daysBefore(Int.max, at: Fixture.time("19:00")),
                                                     .daysBefore(4_000_000, at: Fixture.time("19:00"))])
        let task = PlannerFixture.task(1, due: .dateTime(Fixture.date("2026-10-08"), Fixture.time("08:00")))
        let plan = ReminderPlanner.plan(PlannerFixture.input(rules: [rule], tasks: [task]))
        #expect(plan.notifications.isEmpty && plan.alarms.isEmpty)
        #expect(plan.dropped.count == 3 && plan.dropped.allSatisfy { $0.reason == .invalidOffset })
    }

    /// A clock that received a hostile maximal timestamp saturates instead of trapping.
    @Test func hybridLogicalClockSaturatesAtTheEndOfTime() {
        var clock = HybridLogicalClock(node: 1)
        let end = HLCTimestamp(physicalMillis: HLCTimestamp.maxPhysicalMillis, logical: UInt32.max, node: 99)
        let received = clock.receive(end, now: Fixture.now)
        #expect(received.physicalMillis == HLCTimestamp.maxPhysicalMillis && received.logical == UInt32.max)
        #expect(clock.tick(now: Fixture.now) == received)
    }
}
