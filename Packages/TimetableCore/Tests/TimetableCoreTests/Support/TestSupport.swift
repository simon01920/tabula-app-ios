import Foundation
import Testing
@testable import TimetableCore

// Shared test helpers (Stage 1). Later stages: reuse these instead of redefining them — every test file
// compiles into the same `TimetableCoreTests` module, so duplicate type names would collide.

/// Deterministic SplitMix64 random number generator for property-style tests.
struct TestRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A minimal monotonic HLC-style clock for tests (the real clock is Stage 2E's `HybridLogicalClock`).
struct TestClock: TimestampClock {
    var node: UInt64 = 0xC0FFEE
    private(set) var last = HLCTimestamp.zero

    init(node: UInt64 = 0xC0FFEE) { self.node = node }

    mutating func tick(now: Date) -> HLCTimestamp {
        let physical = max(TabulaJSON.milliseconds(from: now), last.physicalMillis)
        let logical: UInt32 = physical == last.physicalMillis ? last.logical + 1 : 0
        last = HLCTimestamp(physicalMillis: physical, logical: logical, node: node)
        return last
    }
}

/// Literal helpers and fixtures.
enum Fixture {
    /// `LocalDate` from `"yyyy-MM-dd"` (traps on typos).
    static func date(_ string: String) -> LocalDate {
        guard let value = LocalDate(string) else { fatalError("bad date literal \(string)") }
        return value
    }

    /// `LocalTime` from `"HH:mm"` (traps on typos).
    static func time(_ string: String) -> LocalTime {
        guard let value = LocalTime(string) else { fatalError("bad time literal \(string)") }
        return value
    }

    /// The UTC instant of a wall-clock `date` `time` (+ `seconds`), computed with pure arithmetic.
    static func utc(_ date: String, _ time: String, seconds: Int = 0) -> Date {
        let days = Fixture.date(date).daysSinceEpoch
        return Date(timeIntervalSince1970: TimeInterval(Int64(days) * 86_400 + Int64(Fixture.time(time).minuteOfDay) * 60
                                                         + Int64(seconds)))
    }

    /// A time zone that must exist in the platform's tz data.
    static func zone(_ identifier: String) -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else { fatalError("missing time zone \(identifier)") }
        return zone
    }

    /// Fixed "now" used across tests: 2026-10-06T10:00:00Z.
    static let now = Fixture.utc("2026-10-06", "10:00")

    /// Compact canonical JSON of `value`.
    static func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try TabulaJSON.makeEncoder().encode(value), as: UTF8.self)
    }

    /// Decodes `json` with the canonical decoder.
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try TabulaJSON.makeDecoder().decode(type, from: Data(json.utf8))
    }

    /// Encode → decode with the canonical coders.
    static func roundTrip<T: Codable>(_ value: T) throws -> T {
        try TabulaJSON.makeDecoder().decode(T.self, from: TabulaJSON.makeEncoder().encode(value))
    }

    static func meta(_ millis: Int64 = 1_759_744_800_000, logical: UInt32 = 0) -> EntityMeta {
        .created(at: HLCTimestamp(physicalMillis: millis, logical: logical, node: 0xC0FFEE))
    }

    /// A database that uses every entity type and every union case at least once, and passes `validate()`
    /// without errors.
    static func fullDatabase() -> TabulaDatabase {
        var ids = SequentialIDGenerator(namespace: 0xF1)
        let tt: Timetable.ID = ids.next()
        let tt2: Timetable.ID = ids.next()
        let normal: BellSchedule.ID = ids.next()
        let short: BellSchedule.ID = ids.next()
        let p1: Period.ID = ids.next(), p2: Period.ID = ids.next(), p3: Period.ID = ids.next()
        let pBreak: Period.ID = ids.next()
        let math: Subject.ID = ids.next(), physics: Subject.ID = ids.next(), lecture: Subject.ID = ids.next()
        let winter: Term.ID = ids.next()
        let l1: Lesson.ID = ids.next(), l2: Lesson.ID = ids.next(), l3: Lesson.ID = ids.next()
        let l4: Lesson.ID = ids.next(), l5: Lesson.ID = ids.next(), l6: Lesson.ID = ids.next()

        let settings = AppSettings(
            meta: meta(), profile: .secondary, onboardingCompletedAt: Fixture.now, activeTimetableID: tt,
            weekStartOverride: .monday, hourCycle: .h24, timeZoneMode: .fixed(identifier: "Europe/Bratislava"),
            appearance: .dark, palettePackID: .ocean, globalQuietHours: QuietHours(start: time("22:00"), end: time("06:30")),
            timeSensitivePolicy: TimeSensitivePolicy(isEnabled: true, maxLeadMinutes: 45),
            alarmPolicy: AlarmPolicy(isEnabled: true, allowsPresetRules: false), syncEnabled: true)

        let school = Timetable(
            id: tt, meta: meta(), name: "Škola", emoji: "🏫", enabledDays: Weekday.workweek,
            rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0), labels: ["A", "B"])),
            timeStructure: .bellSchedule(defaultID: normal, perWeekday: [.friday: short]),
            fieldVisibility: FieldVisibility([.room, .teacher, .notes]), defaultView: .grid, density: .compact,
            palettePackID: .classic, sortIndex: 0)
        let college = Timetable(
            id: tt2, meta: meta(), name: "College", enabledDays: [.monday, .wednesday],
            rotation: .dayCycle(DayCycle(length: 2, anchorDate: date("2026-09-01"), anchorIndex: 1,
                                         schoolDays: [.monday, .wednesday], skipsBreaks: true, labels: ["A", "B"])),
            timeStructure: .freeForm(defaultDurationMinutes: 90), fieldVisibility: .all, defaultView: .timeBlocks,
            density: .comfortable, sortIndex: 1)

        let periods = [
            Period(id: p1, label: "1", start: time("08:00"), end: time("08:45")),
            Period(id: pBreak, start: time("08:45"), end: time("08:55"), kind: .breakTime),
            Period(id: p2, start: time("08:55"), end: time("09:40")),
            Period(id: p3, start: time("10:00"), end: time("10:45")),
        ]
        let shortPeriods = [
            Period(id: p1, start: time("08:00"), end: time("08:30")),
            Period(id: p2, start: time("08:40"), end: time("09:10")),
            Period(id: p3, start: time("09:20"), end: time("09:50")),
        ]
        let bells = [
            BellSchedule(id: normal, meta: meta(), timetableID: tt, name: "Normal", periods: periods),
            BellSchedule(id: short, meta: meta(), timetableID: tt, name: "Short Friday", periods: shortPeriods),
        ]
        let subjects = [
            Subject(id: math, meta: meta(), timetableID: tt, name: "Matematika", shortName: "MAT",
                    color: ColorValue(hex: "#E53935")!, colorName: .key("palette.classic.color.red"),
                    symbol: .emoji("➗"), defaultRoom: "101", defaultBuilding: "A", defaultTeacher: "Novák",
                    notes: "Calculator"),
            Subject(id: physics, meta: meta(), timetableID: tt, name: "Fyzika", color: ColorValue(hex: "#1E88E580")!,
                    colorName: .literal("Blue-ish"), symbol: .systemImage("atom")),
            Subject(id: lecture, meta: meta(), timetableID: tt2, name: "Algebra", color: .black),
        ]
        let winterTerm = Term(id: winter, meta: meta(), timetableID: tt, name: "Winter",
                              range: LocalDateRange(start: date("2026-09-01"), end: date("2027-01-31")))
        let lessons: [Lesson] = Weekday.workweek.sorted().map { day in
            let lessonID: Lesson.ID
            switch day {
            case .monday: lessonID = l1
            case .tuesday: lessonID = l2
            case .wednesday: lessonID = l3
            case .thursday: lessonID = l4
            default: lessonID = l5
            }
            return Lesson(id: lessonID, meta: meta(), timetableID: tt, subjectID: day == .monday ? physics : math,
                          occurrence: LessonOccurrenceRule(day: .weekday(day), cycleWeeks: day == .tuesday ? [2, 1] : nil),
                          slot: day == .wednesday ? .time(start: time("12:00"), end: time("12:45")) : .period(p1, span: day == .thursday ? 2 : 1),
                          validity: day == .monday ? .terms([winter]) : (day == .friday ? .range(LocalDateRange(start: date("2026-09-01"), end: date("2027-06-30"))) : .always),
                          room: day == .monday ? "Lab 2" : nil, building: nil, teacher: day == .tuesday ? "Kováč" : nil,
                          lessonType: day == .monday ? .lab : nil, notes: nil, bringList: day == .monday ? ["Goggles", "Notebook"] : [])
        } + [
            Lesson(id: l6, meta: meta(), timetableID: tt2, subjectID: lecture, occurrence: LessonOccurrenceRule(day: .cycleDay(1)),
                   slot: .time(start: time("09:00"), end: time("10:30")), lessonType: .lecture),
            Lesson(id: ids.next(), meta: meta(), timetableID: tt2, subjectID: lecture, occurrence: LessonOccurrenceRule(day: .cycleDay(2)),
                   slot: .time(start: time("11:00"), end: time("12:30")), lessonType: .seminar),
        ]
        let breaks = [
            CalendarBreak(id: ids.next(), meta: meta(), timetableID: nil, name: "Christmas",
                          range: LocalDateRange(start: date("2026-12-23"), end: date("2027-01-07")), kind: .vacation),
            CalendarBreak(id: ids.next(), meta: meta(), timetableID: tt, name: "Exams",
                          range: LocalDateRange(day: date("2027-01-15")), kind: .examPeriod),
        ]
        let overrides = [
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-12"), change: .cancelLesson(l1)),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-13"),
                             change: .modifyLesson(l2, LessonPatch(room: "204", teacher: "", bringList: []))),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-14"),
                             change: .addLesson(OneOffLesson(subjectID: physics, slot: .period(p3, span: 1), room: "Aula"))),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-15"), change: .cancelDay(note: "Sports day")),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-16"), change: .cancelDay(note: nil)),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-19"), change: .useBellSchedule(short)),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt, date: date("2026-10-21"),
                             change: .followDay(.weekday(.friday), cycleWeek: 2)),
            ScheduleOverride(id: ids.next(), meta: meta(), timetableID: tt2, date: date("2026-10-22"),
                             change: .followDay(.cycleDay(2), cycleWeek: nil)),
        ]
        let task = TaskItem(
            id: ids.next(), meta: meta(), title: "Úloha 3", kind: .homework, subjectID: math, timetableID: tt,
            due: .dateTime(date("2026-10-08"), time("08:00")), linkedLesson: LessonLink(lessonID: l3, date: date("2026-10-07")),
            priority: .high, notes: "p. 42", repeatRule: RepeatRule(frequency: .weekly, interval: 1, weekdays: [.wednesday, .monday], until: date("2027-01-31")),
            completedAt: nil,
            subtasks: [Subtask(id: ids.next(), meta: meta(), title: "Read", completedAt: Fixture.now, sortIndex: 1),
                       Subtask(id: ids.next(), meta: meta(), title: "Write", sortIndex: 0)],
            attachments: [AttachmentRef(id: ids.next(), meta: meta(), kind: .photo, title: "Board", fileName: "board.jpg",
                                        contentType: "public.jpeg", byteCount: 1_234_567, sortIndex: 0),
                          AttachmentRef(id: ids.next(), meta: meta(), kind: .link, url: "https://example.com/a?b=c", sortIndex: 1)],
            reminderOverride: ReminderOverride(isEnabled: true, offsets: [.minutesBefore(30)], tier: .timeSensitive,
                                               followUp: .custom(.afterMinutes(60))))
        let todo = TaskItem(id: ids.next(), meta: meta(), title: "Buy pens", kind: .todo, due: .date(date("2026-10-09")),
                            priority: .low, completedAt: Date(timeIntervalSince1970: 1_759_750_000.123),
                            reminderOverride: ReminderOverride(isEnabled: false, followUp: .none))
        let exams = [
            Exam(id: ids.next(), meta: meta(), timetableID: tt, subjectID: math, title: "Písomka", kind: .test,
                 date: date("2026-10-20"), start: time("08:00"), end: time("08:45"), room: "101", building: "A",
                 topics: ["Fractions", "Equations"], notes: "No calculator",
                 reminderOverride: ReminderOverride(followUp: .inherit), completedAt: nil),
            Exam(id: ids.next(), meta: meta(), title: "Driving theory", kind: .oral, date: date("2026-11-02")),
        ]
        let rules = [
            ReminderRule(id: ids.next(), meta: meta(), target: .homework,
                         offsets: [.daysBefore(1, at: time("17:00")), .daysBefore(0, at: time("07:00"))],
                         followUp: .nextMorning(at: time("07:00")), tier: .standard, quietHours: nil, isEnabled: true, origin: .preset),
            ReminderRule(id: ids.next(), meta: meta(), target: .exam, offsets: [.daysBefore(1, at: time("19:00"))],
                         followUp: .afterMinutes(120), tier: .alarm, quietHours: QuietHours(start: time("21:00"), end: time("07:00")),
                         isEnabled: true, origin: .user),
            ReminderRule(id: ids.next(), meta: meta(), target: .lesson, offsets: [.minutesBefore(5)], tier: .timeSensitive,
                         isEnabled: false, origin: .preset),
        ]
        return TabulaDatabase(settings: settings, timetables: [school, college], subjects: subjects, bellSchedules: bells,
                              lessons: lessons, terms: [winterTerm], breaks: breaks, overrides: overrides,
                              tasks: [task, todo], exams: exams, reminderRules: rules)
    }
}

/// Reads repository files (docs) from tests. Test files live two levels below `Tests/TimetableCoreTests`
/// (`Packages/TimetableCore/Tests/TimetableCoreTests/<dir>/<file>.swift`), so the repo root is six levels up.
enum RepositoryFile {
    static func url(_ relativePath: String, from filePath: String = #filePath) -> URL {
        var root = URL(fileURLWithPath: filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        return root.appendingPathComponent(relativePath)
    }

    static func text(_ relativePath: String, from filePath: String = #filePath) throws -> String {
        try String(contentsOf: url(relativePath, from: filePath), encoding: .utf8)
    }
}

/// `Issue.record` helper for collecting a bounded number of property-test failures.
struct FailureBudget {
    private(set) var count = 0
    let limit: Int

    init(limit: Int = 5) { self.limit = limit }

    /// Records `message` while under the limit; returns `false` once the budget is exhausted.
    @discardableResult
    mutating func record(_ message: String, sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        count += 1
        if count <= limit { Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation) }
        return count < limit
    }
}
