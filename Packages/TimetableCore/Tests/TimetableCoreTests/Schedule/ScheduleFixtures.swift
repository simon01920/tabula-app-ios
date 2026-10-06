import Foundation
import Testing
@testable import TimetableCore

// Stage 2B test helpers. Names carry a `Schedule` prefix so they cannot collide with other stages' helpers in
// the shared `TimetableCoreTests` module. Generic helpers (`Fixture`, `TestRNG`, `FailureBudget`) come from
// Support/TestSupport.swift.

/// A small, mutable school used by the schedule tests.
///
/// Default bell schedule "Normal" (all Mon–Fri except Friday):
/// ```
/// P1 08:00–08:45 · B1 break 08:45–08:55 · P2 08:55–09:40 · B2 break 09:40–10:00 · P3 10:00–10:45
/// P4 10:55–11:40 · L lunch 11:40–12:20 · P5 12:20–13:05 · P6 13:15–14:00
/// ```
/// "Short" (Friday via `perWeekday`, same period IDs, no breaks):
/// `P1 08:00–08:30 · P2 08:40–09:10 · P3 09:20–09:50 · P4 10:00–10:30 · P5 10:40–11:10 · P6 11:20–11:50`.
struct ScheduleWorld {
    var ids = SequentialIDGenerator(namespace: 0x2B)
    var timetable: Timetable
    var subjects: [Subject] = []
    var bellSchedules: [BellSchedule] = []
    var lessons: [Lesson] = []
    var terms: [Term] = []
    var breaks: [CalendarBreak] = []
    var overrides: [ScheduleOverride] = []
    var context: CalendarContext

    /// Lesson periods 1…6 (index 0 = P1).
    var p: [Period.ID] = []
    var break1: Period.ID
    var break2: Period.ID
    var lunch: Period.ID
    var normalID: BellSchedule.ID
    var shortID: BellSchedule.ID
    /// Subject with defaults: room "101", building "A", teacher "Novák", notes "Calculator".
    var math: Subject.ID
    /// Subject without defaults.
    var physics: Subject.ID
    /// Subject with default room "201".
    var english: Subject.ID

    static let baseMillis: Int64 = 1_759_744_800_000

    init(rotation: RotationScheme = .none, enabledDays: Set<Weekday> = Weekday.workweek,
         zone: String = "Europe/Bratislava", firstWeekday: Weekday = .monday, freeForm: Bool = false) {
        var ids = SequentialIDGenerator(namespace: 0x2B)
        let ttID: Timetable.ID = ids.next()
        normalID = ids.next()
        shortID = ids.next()
        p = (0..<6).map { _ in ids.next() }
        break1 = ids.next()
        break2 = ids.next()
        lunch = ids.next()
        math = ids.next()
        physics = ids.next()
        english = ids.next()
        let structure: TimeStructure = freeForm ? .freeForm(defaultDurationMinutes: 90)
            : .bellSchedule(defaultID: normalID, perWeekday: [.friday: shortID])
        timetable = Timetable(id: ttID, meta: Self.meta(), name: "School", enabledDays: enabledDays, rotation: rotation,
                              timeStructure: structure)
        context = CalendarContext(timeZone: Fixture.zone(zone), firstWeekday: firstWeekday)
        let t = Fixture.time
        let normal = [
            Period(id: p[0], start: t("08:00"), end: t("08:45")),
            Period(id: break1, start: t("08:45"), end: t("08:55"), kind: .breakTime),
            Period(id: p[1], start: t("08:55"), end: t("09:40")),
            Period(id: break2, start: t("09:40"), end: t("10:00"), kind: .breakTime),
            Period(id: p[2], label: "3rd", start: t("10:00"), end: t("10:45")),
            Period(id: p[3], start: t("10:55"), end: t("11:40")),
            Period(id: lunch, start: t("11:40"), end: t("12:20"), kind: .lunch),
            Period(id: p[4], start: t("12:20"), end: t("13:05")),
            Period(id: p[5], start: t("13:15"), end: t("14:00")),
        ]
        let lessonPeriodIDs = p
        let short = [("08:00", "08:30"), ("08:40", "09:10"), ("09:20", "09:50"), ("10:00", "10:30"),
                     ("10:40", "11:10"), ("11:20", "11:50")].enumerated().map { index, pair in
            Period(id: lessonPeriodIDs[index], start: t(pair.0), end: t(pair.1))
        }
        if !freeForm {
            bellSchedules = [
                BellSchedule(id: normalID, meta: Self.meta(), timetableID: ttID, name: "Normal", periods: normal.shuffledDeterministically()),
                BellSchedule(id: shortID, meta: Self.meta(), timetableID: ttID, name: "Short", periods: short),
            ]
        }
        subjects = [
            Subject(id: math, meta: Self.meta(), timetableID: ttID, name: "Math", shortName: "MAT",
                    color: ColorValue(hex: "#E53935")!, defaultRoom: "101", defaultBuilding: "A",
                    defaultTeacher: "Novák", notes: "Calculator"),
            Subject(id: physics, meta: Self.meta(), timetableID: ttID, name: "Physics", color: ColorValue(hex: "#1E88E5")!),
            Subject(id: english, meta: Self.meta(), timetableID: ttID, name: "English", color: ColorValue(hex: "#43A047")!,
                    defaultRoom: "201"),
        ]
        self.ids = ids
    }

    static func meta(_ millis: Int64 = baseMillis) -> EntityMeta {
        .created(at: HLCTimestamp(physicalMillis: millis, logical: 0, node: 0xC0FFEE))
    }

    static func meta(updatedAt millis: Int64) -> EntityMeta {
        EntityMeta(createdAt: HLCTimestamp(physicalMillis: baseMillis, logical: 0, node: 0xC0FFEE),
                   updatedAt: HLCTimestamp(physicalMillis: millis, logical: 0, node: 0xC0FFEE))
    }

    // MARK: Builders

    @discardableResult
    mutating func lesson(_ subject: Subject.ID, _ day: DayKey, _ slot: LessonSlot, weeks: Set<Int>? = nil,
                         validity: LessonValidity = .always, room: String? = nil, building: String? = nil,
                         teacher: String? = nil, lessonType: LessonType? = nil, notes: String? = nil,
                         bringList: [String] = []) -> Lesson.ID {
        let id: Lesson.ID = ids.next()
        lessons.append(Lesson(id: id, meta: Self.meta(), timetableID: timetable.id, subjectID: subject,
                              occurrence: LessonOccurrenceRule(day: day, cycleWeeks: weeks), slot: slot, validity: validity,
                              room: room, building: building, teacher: teacher, lessonType: lessonType, notes: notes,
                              bringList: bringList))
        return id
    }

    /// A lesson in lesson period `number` (1-based) on `weekday`.
    @discardableResult
    mutating func lesson(_ subject: Subject.ID, _ weekday: Weekday, period number: Int, span: Int = 1,
                         weeks: Set<Int>? = nil, validity: LessonValidity = .always, room: String? = nil,
                         teacher: String? = nil, bringList: [String] = []) -> Lesson.ID {
        lesson(subject, .weekday(weekday), .period(p[number - 1], span: span), weeks: weeks, validity: validity,
               room: room, teacher: teacher, bringList: bringList)
    }

    @discardableResult
    mutating func override(_ date: String, _ change: OverrideChange,
                           updatedAt millis: Int64 = ScheduleWorld.baseMillis) -> ScheduleOverride.ID {
        let id: ScheduleOverride.ID = ids.next()
        overrides.append(ScheduleOverride(id: id, meta: Self.meta(updatedAt: millis), timetableID: timetable.id,
                                          date: Fixture.date(date), change: change))
        return id
    }

    @discardableResult
    mutating func holiday(_ start: String, _ end: String, ownTimetable: Bool = false,
                          kind: BreakKind = .holiday) -> CalendarBreak.ID {
        let id: CalendarBreak.ID = ids.next()
        breaks.append(CalendarBreak(id: id, meta: Self.meta(), timetableID: ownTimetable ? timetable.id : nil, name: "Break",
                                    range: LocalDateRange(start: Fixture.date(start), end: Fixture.date(end)), kind: kind))
        return id
    }

    @discardableResult
    mutating func term(_ start: String, _ end: String) -> Term.ID {
        let id: Term.ID = ids.next()
        terms.append(Term(id: id, meta: Self.meta(), timetableID: timetable.id, name: "Term",
                          range: LocalDateRange(start: Fixture.date(start), end: Fixture.date(end))))
        return id
    }

    @discardableResult
    mutating func bellSchedule(_ periods: [Period]) -> BellSchedule.ID {
        let id: BellSchedule.ID = ids.next()
        bellSchedules.append(BellSchedule(id: id, meta: Self.meta(), timetableID: timetable.id, name: "Variant", periods: periods))
        return id
    }

    func period(_ id: Period.ID, _ start: String, _ end: String, kind: PeriodKind = .lesson) -> Period {
        Period(id: id, start: Fixture.time(start), end: Fixture.time(end), kind: kind)
    }

    var resolver: ScheduleResolver {
        ScheduleResolver(timetable: timetable, subjects: subjects, bellSchedules: bellSchedules, lessons: lessons,
                         terms: terms, breaks: breaks, overrides: overrides, context: context)
    }

    func resolver(context: CalendarContext) -> ScheduleResolver {
        ScheduleResolver(timetable: timetable, subjects: subjects, bellSchedules: bellSchedules, lessons: lessons,
                         terms: terms, breaks: breaks, overrides: overrides, context: context)
    }

    // MARK: Date helpers

    func day(_ date: String, options: ResolutionOptions = .actual) -> DaySchedule {
        resolver.day(Fixture.date(date), options: options)
    }

    func resolution(_ date: String, options: ResolutionOptions = .actual) -> DayResolution {
        resolver.resolution(for: Fixture.date(date), options: options)
    }

    /// The instant of wall-clock `date` `time` in this world's context.
    func instant(_ date: String, _ time: String, seconds: Int = 0) -> Date {
        context.date(Fixture.date(date), Fixture.time(time)).addingTimeInterval(TimeInterval(seconds))
    }
}

extension Array {
    /// A fixed permutation (reversal of the second half) so tests prove the engine sorts its inputs.
    func shuffledDeterministically() -> [Element] {
        let middle = count / 2
        return Array(self[middle...].reversed()) + Array(self[..<middle])
    }
}

/// Short accessors for entry assertions.
extension DaySchedule {
    var scheduleTimes: [String] { entries.map { "\($0.startTime)-\($0.endTime)" } }
    func entry(_ lessonID: Lesson.ID) -> ResolvedLesson? {
        entries.first { $0.source == .lesson(lessonID) }
    }
    func entry(oneOff overrideID: ScheduleOverride.ID) -> ResolvedLesson? {
        entries.first { $0.source == .oneOff(overrideID) }
    }
}

/// Brute-force oracles for the property tests.
enum ScheduleOracle {
    /// Day-by-day count of the dates in `start…end` that advance a day cycle.
    static func countedDays(_ cycle: DayCycle, breaks: [LocalDateRange], from start: LocalDate, through end: LocalDate) -> Int {
        guard start <= end else { return 0 }
        return LocalDateRange(start: start, end: end).days.filter { advances(cycle, breaks: breaks, $0) }.count
    }

    static func advances(_ cycle: DayCycle, breaks: [LocalDateRange], _ date: LocalDate) -> Bool {
        cycle.schoolDays.contains(date.weekday) && !(cycle.skipsBreaks && breaks.contains { $0.contains(date) })
    }

    static func randomWeekdays(_ rng: inout TestRNG) -> Set<Weekday> {
        var days = Set(Weekday.allCases.filter { _ in Int.random(in: 0..<10, using: &rng) < 6 })
        if days.isEmpty { days.insert(Weekday.allCases.randomElement(using: &rng)!) }
        return days
    }

    static func randomDate(_ rng: inout TestRNG, from start: LocalDate, days: Int) -> LocalDate {
        start.adding(days: Int.random(in: 0..<days, using: &rng))
    }

    static func randomBreaks(_ rng: inout TestRNG, count: Int, from start: LocalDate, days: Int) -> [LocalDateRange] {
        (0..<count).map { _ in
            let first = randomDate(&rng, from: start, days: days)
            return LocalDateRange(start: first, end: first.adding(days: Int.random(in: 0...20, using: &rng)))
        }
    }
}
