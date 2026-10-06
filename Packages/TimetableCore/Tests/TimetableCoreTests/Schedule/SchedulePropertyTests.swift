import Foundation
import Testing
@testable import TimetableCore

/// Seeded property tests over ten years (2026-01-01 … 2035-12-31, which includes the 53-week ISO years 2026
/// and 2032). Every failure message names the seed so a run can be reproduced.
@Suite("Schedule properties (10 years)")
struct SchedulePropertyTests {
    private static let start = Fixture.date("2026-01-01")
    private static let end = Fixture.date("2035-12-31")
    private static var tenYears: LocalDateRange { LocalDateRange(start: start, end: end) }
    private static let totalDays = start.days(to: end) + 1

    private static func randomRotation(_ rng: inout TestRNG) -> RotationScheme {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0:
            return .none
        case 1:
            let length = Int.random(in: 2...6, using: &rng)
            let anchor: WeekCycleAnchor = Bool.random(using: &rng)
                ? .isoWeekParity(policy: Bool.random(using: &rng) ? .strict : .continuous, offset: Int.random(in: -3...3, using: &rng))
                : .referenceWeek(date: ScheduleOracle.randomDate(&rng, from: start, days: totalDays),
                                 cycleWeek: Int.random(in: 1...length, using: &rng))
            return .weekCycle(WeekCycle(length: length, anchor: anchor))
        default:
            return .dayCycle(DayCycle(length: Int.random(in: 2...10, using: &rng),
                                      anchorDate: ScheduleOracle.randomDate(&rng, from: start, days: totalDays),
                                      anchorIndex: Int.random(in: 1...10, using: &rng),
                                      schoolDays: ScheduleOracle.randomWeekdays(&rng), skipsBreaks: Bool.random(using: &rng)))
        }
    }

    private static func randomWorld(_ rng: inout TestRNG, breaks: Int) -> ScheduleWorld {
        var world = ScheduleWorld(rotation: randomRotation(&rng), enabledDays: ScheduleOracle.randomWeekdays(&rng),
                                  firstWeekday: Weekday.allCases.randomElement(using: &rng)!)
        for range in ScheduleOracle.randomBreaks(&rng, count: breaks, from: start, days: totalDays) {
            world.holiday(range.start.isoString, range.end.isoString)
        }
        return world
    }

    @Test(arguments: [UInt64(0xA1), 0xB2, 0xC3, 0xD4, 0xE5, 0xF6])
    func everySchoolDayGetsExactlyOneDayKey(seed: UInt64) {
        var rng = TestRNG(seed: seed)
        let world = Self.randomWorld(&rng, breaks: 12)
        let resolver = world.resolver
        let breaks = world.breaks.map(\.range)
        var failures = FailureBudget()
        for date in Self.tenYears.days {
            let day = resolver.day(date)
            let inBreak = breaks.contains { $0.contains(date) }
            let enabled = world.timetable.enabledDays.contains(date.weekday)
            let expectedKey: DayKey?
            switch world.timetable.rotation {
            case .none, .weekCycle:
                expectedKey = enabled && !inBreak ? .weekday(date.weekday) : nil
            case .dayCycle(let cycle):
                let counted = ScheduleOracle.advances(cycle, breaks: breaks, date)
                expectedKey = enabled && !inBreak && counted ? resolver.rotation.cycleDay(on: date).map(DayKey.cycleDay) : nil
                if enabled && !inBreak && counted, case .cycleDay(let index)? = day.dayKey, !(1...cycle.length).contains(index) {
                    failures.record("seed \(seed) \(date): cycle day \(index) out of range")
                }
            }
            if day.dayKey != expectedKey || day.isSchoolDay != (expectedKey != nil) {
                if !failures.record("seed \(seed) \(date): key \(String(describing: day.dayKey)) expected \(String(describing: expectedKey))") { break }
            }
            if case .weekCycle(let cycle) = world.timetable.rotation, !(1...cycle.length).contains(day.cycleWeek ?? 0) {
                failures.record("seed \(seed) \(date): cycle week \(String(describing: day.cycleWeek))")
            }
        }
        #expect(failures.count == 0)
    }

    @Test(arguments: [UInt64(1), 2, 3, 4, 5, 6, 7, 8])
    func dayCyclesAdvanceByOnePerSchoolDay(seed: UInt64) {
        var rng = TestRNG(seed: seed)
        let cycle = DayCycle(length: Int.random(in: 2...10, using: &rng),
                             anchorDate: ScheduleOracle.randomDate(&rng, from: Self.start, days: Self.totalDays),
                             anchorIndex: Int.random(in: 1...10, using: &rng), schoolDays: ScheduleOracle.randomWeekdays(&rng),
                             skipsBreaks: seed % 2 == 1)
        let breaks = ScheduleOracle.randomBreaks(&rng, count: 15, from: Self.start, days: Self.totalDays)
        let rotation = RotationResolver(scheme: .dayCycle(cycle), firstWeekday: .monday, breaks: breaks)
        var failures = FailureBudget()
        var previous: Int?
        var anchorSeen = false
        for date in Self.tenYears.days {
            let index = rotation.cycleDay(on: date)
            let counted = ScheduleOracle.advances(cycle, breaks: breaks, date)
            if counted != (index != nil) { failures.record("seed \(seed) \(date): counted \(counted) index \(String(describing: index))") }
            guard let index else { continue }
            if let previous, index != previous % cycle.length + 1 {
                failures.record("seed \(seed) \(date): \(previous) → \(index)")
            }
            if !anchorSeen && date >= cycle.anchorDate {
                anchorSeen = true
                if index != (cycle.anchorIndex - 1) % cycle.length + 1 { failures.record("seed \(seed): anchor day \(date) is \(index)") }
            }
            previous = index
        }
        // Closed-form counting equals day-by-day counting on random ranges, in both directions.
        for _ in 0..<200 {
            let a = ScheduleOracle.randomDate(&rng, from: Self.start, days: Self.totalDays)
            let b = a.adding(days: Int.random(in: -30...900, using: &rng))
            #expect(rotation.countedDays(from: a, through: b) == ScheduleOracle.countedDays(cycle, breaks: breaks, from: a, through: b))
        }
        #expect(failures.count == 0)
    }

    @Test(arguments: [Weekday.monday, .sunday, .saturday])
    func weekCyclesAdvanceOncePerWeek(firstWeekday: Weekday) {
        var rng = TestRNG(seed: UInt64(firstWeekday.rawValue))
        var failures = FailureBudget()
        for length in 2...6 {
            let reference = RotationResolver(scheme: .weekCycle(WeekCycle(length: length, anchor: .referenceWeek(
                date: ScheduleOracle.randomDate(&rng, from: Self.start, days: Self.totalDays), cycleWeek: Int.random(in: 1...length, using: &rng)))),
                firstWeekday: firstWeekday)
            let strict = RotationResolver(scheme: .weekCycle(WeekCycle(length: length, anchor: .isoWeekParity(policy: .strict, offset: 1))),
                                          firstWeekday: firstWeekday)
            let continuous = RotationResolver(scheme: .weekCycle(WeekCycle(length: length, anchor: .isoWeekParity(policy: .continuous, offset: 0))),
                                              firstWeekday: firstWeekday)
            var weekStart = reference.startOfWeek(containing: Self.start)
            while weekStart < Self.end {
                let next = weekStart.adding(days: 7)
                for rotation in [reference, strict, continuous] {
                    let days = Set((0..<7).map { rotation.cycleWeek(on: weekStart.adding(days: $0)) })
                    if days.count != 1 { failures.record("\(firstWeekday) \(weekStart): mixed weeks \(days)") }
                }
                let advances = { (rotation: RotationResolver) in rotation.cycleWeek(on: next)! == rotation.cycleWeek(on: weekStart)! % length + 1 }
                if !advances(reference) { failures.record("reference \(length) \(weekStart)") }
                let representative = WeekParity.representativeISOWeek(containing: next, firstWeekday: firstWeekday)
                if representative.week != 1 && !advances(strict) { failures.record("strict \(length) \(weekStart)") }
                let previousRepresentative = WeekParity.representativeISOWeek(containing: weekStart, firstWeekday: firstWeekday)
                if WeekParity.schoolYearStartWeek(for: representative) == WeekParity.schoolYearStartWeek(for: previousRepresentative),
                   !advances(continuous) {
                    failures.record("continuous \(length) \(weekStart)")
                }
                weekStart = next
            }
        }
        #expect(failures.count == 0)
    }

    @Test(arguments: [UInt64(0x51), 0x52, 0x53])
    func lessonsAppearExactlyWhenRotationValidityAndBreaksAllow(seed: UInt64) {
        var rng = TestRNG(seed: seed)
        var world = Self.randomWorld(&rng, breaks: 8)
        world.timetable.enabledDays = Set(Weekday.allCases) // guarantees real lessons whatever the random rotation
        var termIDs: [Term.ID] = []
        for _ in 0..<4 {
            let first = ScheduleOracle.randomDate(&rng, from: Self.start, days: Self.totalDays)
            termIDs.append(world.term(first.isoString, first.adding(days: Int.random(in: 30...300, using: &rng)).isoString))
        }
        world.terms[3].meta.isDeleted = true
        var cycleLength = 1
        var dayKeys: [DayKey] = Weekday.allCases.map(DayKey.weekday)
        switch world.timetable.rotation {
        case .weekCycle(let cycle): cycleLength = cycle.length
        case .dayCycle(let cycle): dayKeys = (1...cycle.length).map(DayKey.cycleDay)
        case .none: break
        }
        for _ in 0..<30 {
            let validity: LessonValidity
            switch Int.random(in: 0..<3, using: &rng) {
            case 0: validity = .always
            case 1:
                let first = ScheduleOracle.randomDate(&rng, from: Self.start, days: Self.totalDays)
                validity = .range(LocalDateRange(start: first, end: first.adding(days: Int.random(in: -10...400, using: &rng))))
            default: validity = .terms(Set(termIDs.filter { _ in Bool.random(using: &rng) }))
            }
            let weeks: Set<Int>? = Bool.random(using: &rng) ? nil : Set((1...cycleLength).filter { _ in Bool.random(using: &rng) })
            let startMinute = Int.random(in: 420...1000, using: &rng)
            let slot: LessonSlot = Bool.random(using: &rng)
                ? .time(start: LocalTime(minuteOfDay: startMinute)!, end: LocalTime(minuteOfDay: startMinute + Int.random(in: 30...120, using: &rng))!)
                : .period(world.p[Int.random(in: 0..<6, using: &rng)], span: Int.random(in: 1...2, using: &rng))
            world.lesson([world.math, world.physics, world.english].randomElement(using: &rng)!, dayKeys.randomElement(using: &rng)!,
                         slot, weeks: weeks, validity: validity)
        }
        let resolver = world.resolver
        let liveTerms = world.terms.filter { !$0.isDeleted }
        func valid(_ validity: LessonValidity, _ date: LocalDate) -> Bool {
            switch validity {
            case .always: return true
            case .range(let range): return range.contains(date)
            case .terms(let ids): return liveTerms.contains { ids.contains($0.id) && $0.range.contains(date) }
            }
        }
        var failures = FailureBudget()
        var seen = 0
        for date in Self.tenYears.days {
            let day = resolver.day(date)
            let expected: Set<Lesson.ID>
            if let key = day.dayKey {
                expected = Set(world.lessons.filter { lesson in
                    guard lesson.occurrence.day == key, valid(lesson.validity, date) else { return false }
                    if case .weekCycle = world.timetable.rotation, let weeks = lesson.occurrence.cycleWeeks {
                        return weeks.contains(day.cycleWeek ?? -1)
                    }
                    return true
                }.map(\.id))
            } else {
                expected = []
            }
            let actual = Set(day.entries.compactMap { entry -> Lesson.ID? in
                if case .lesson(let id) = entry.source { return id }
                return nil
            })
            seen += actual.count
            if actual != expected {
                if !failures.record("seed \(seed) \(date): \(actual.count) entries, expected \(expected.count)") { break }
            }
            for entry in day.entries {
                guard case .lesson(let id) = entry.source, let lesson = world.lessons.first(where: { $0.id == id }) else { continue }
                if !valid(lesson.validity, date) { failures.record("seed \(seed) \(date): lesson outside validity") }
                if entry.start != world.context.date(date, entry.startTime) || entry.id != .lesson(id, on: date) {
                    failures.record("seed \(seed) \(date): instant or ID mismatch")
                }
            }
            if day.entries != day.entries.sorted(by: ScheduleResolver.wallClockOrder) { failures.record("seed \(seed) \(date): unsorted") }
        }
        #expect(seen > 1000, "the random timetable must produce real lessons (\(seen))")
        #expect(failures.count == 0)
    }

    @Test(arguments: [UInt64(0x77), 0x78])
    func overrideOrderInTheDatabaseDoesNotMatter(seed: UInt64) {
        var rng = TestRNG(seed: seed)
        var world = ScheduleWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0))))
        var lessonIDs: [Lesson.ID] = []
        for weekday in Weekday.workweek.sorted() {
            for period in 1...4 {
                lessonIDs.append(world.lesson([world.math, world.physics, world.english][period % 3], weekday, period: period,
                                              weeks: period == 4 ? [2] : nil))
            }
        }
        let october = (0..<31).map { Fixture.date("2026-10-01").adding(days: $0) }
        for index in 0..<120 {
            let date = october.randomElement(using: &rng)!.isoString
            let lesson = lessonIDs.randomElement(using: &rng)!
            let change: OverrideChange
            switch Int.random(in: 0..<7, using: &rng) {
            case 0: change = .cancelLesson(lesson)
            case 1: change = .modifyLesson(lesson, LessonPatch(room: "R\(index)", teacher: Bool.random(using: &rng) ? "" : nil))
            case 2: change = .addLesson(OneOffLesson(subjectID: world.physics, slot: .period(world.p[Int.random(in: 0..<6, using: &rng)], span: 1)))
            case 3: change = .cancelDay(note: nil)
            case 4: change = .useBellSchedule(Bool.random(using: &rng) ? world.shortID : world.normalID)
            case 5: change = .followDay(.weekday(Weekday.workweek.randomElement(using: &rng)!), cycleWeek: Bool.random(using: &rng) ? 2 : nil)
            default: change = .modifyLesson(lesson, LessonPatch(slot: .period(world.p[5], span: 1)))
            }
            world.override(date, change, updatedAt: ScheduleWorld.baseMillis + Int64(Int.random(in: 0..<5, using: &rng)) * 1000)
        }
        var shuffled = world
        shuffled.overrides.shuffle(using: &rng)
        shuffled.lessons.shuffle(using: &rng)
        let range = LocalDateRange(start: october[0], end: october[30])
        let a = range.days.map { world.resolver.resolution(for: $0) }
        let b = range.days.map { shuffled.resolver.resolution(for: $0) }
        #expect(a == b)
        #expect(a.contains { !$0.warnings.isEmpty } && a.contains { $0.schedule.entries.contains { $0.status == .modified } })
        for resolution in a {
            let ids = resolution.schedule.entries.map(\.id)
            #expect(Set(ids).count == ids.count, "occurrence IDs are unique per day")
        }
    }
}
