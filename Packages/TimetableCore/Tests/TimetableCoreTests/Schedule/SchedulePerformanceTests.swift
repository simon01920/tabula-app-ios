import Foundation
import Testing
@testable import TimetableCore

/// Performance sanity: resolving five years of days for a 40-lesson timetable must take under a second in a
/// release build (`swift test -c release`; measured ~0.07 s).
@Suite("Schedule performance")
struct SchedulePerformanceTests {
    /// Same pattern as `SyncPerformanceTests`: unoptimised (debug) test builds run in parallel with the whole suite
    /// and get a generous bound so a loaded machine does not flake (~0.3 s alone, up to ~1 s under load); the
    /// 1 s budget is asserted in release builds.
    #if DEBUG
    static let budget = Duration.seconds(5)
    #else
    static let budget = Duration.seconds(1)
    #endif

    private static func fortyLessonWorld(rotation: RotationScheme) -> ScheduleWorld {
        var world = ScheduleWorld(rotation: rotation)
        let subjects = [world.math, world.physics, world.english]
        for weekday in Weekday.workweek.sorted() {
            for period in 1...6 {
                world.lesson(subjects[(period + weekday.rawValue) % 3], weekday, period: period,
                             weeks: period == 6 ? [2] : nil)
            }
            world.lesson(world.math, .weekday(weekday), .time(start: Fixture.time("14:30"), end: Fixture.time("15:15")))
            world.lesson(world.physics, .weekday(weekday), .time(start: Fixture.time("15:30"), end: Fixture.time("16:15")))
        }
        // Day-cycle variant: give lessons cycle-day keys instead.
        if case .dayCycle(let cycle) = rotation {
            for index in world.lessons.indices {
                world.lessons[index].occurrence = LessonOccurrenceRule(day: .cycleDay(index % cycle.length + 1))
            }
        }
        var start = Fixture.date("2026-09-01")
        for _ in 0..<30 { // 30 breaks over five years
            world.holiday(start.adding(days: 50).isoString, start.adding(days: 56).isoString)
            start = start.adding(days: 61)
        }
        for offset in stride(from: 3, to: 1800, by: 37) { // ~50 overrides
            world.override(Fixture.date("2026-09-01").adding(days: offset).isoString, .useBellSchedule(world.shortID))
        }
        return world
    }

    private static func measure(_ world: ScheduleWorld) -> (Duration, Int) {
        let resolver = world.resolver
        let range = LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2031-08-31"))
        var entries = 0
        let duration = ContinuousClock().measure {
            entries = resolver.days(in: range).reduce(0) { $0 + $1.entries.count }
        }
        return (duration, entries)
    }

    @Test func fiveYearsOfAFortyLessonWeekCycleTimetable() {
        let world = Self.fortyLessonWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .continuous, offset: 0))))
        #expect(world.lessons.count == 40)
        let (duration, entries) = Self.measure(world)
        print("[perf] week cycle: 1826 days, \(entries) occurrences in \(duration)")
        #expect(entries > 7_000) // 40 lessons per week ≈ 8 per school day, minus breaks
        #expect(duration < Self.budget)
    }

    @Test func fiveYearsOfAFortyLessonDayCycleTimetable() {
        let world = Self.fortyLessonWorld(rotation: .dayCycle(DayCycle(length: 6, anchorDate: Fixture.date("2026-09-01"))))
        let (duration, entries) = Self.measure(world)
        print("[perf] day cycle (30 breaks): 1826 days, \(entries) occurrences in \(duration)")
        #expect(entries > 6_000)
        #expect(duration < Self.budget)
    }

    @Test func widgetQueriesAreCheap() {
        let world = Self.fortyLessonWorld(rotation: .none)
        let resolver = world.resolver
        let now = world.instant("2026-10-06", "10:10")
        var count = 0
        let duration = ContinuousClock().measure {
            for minute in 0..<100 {
                count += resolver.nowAndNext(at: now.addingTimeInterval(TimeInterval(minute * 600))).current == nil ? 0 : 1
            }
            count += resolver.occurrences(in: DateInterval(start: now, duration: 14 * 86_400)).count
        }
        print("[perf] 100 × nowAndNext + 14-day occurrences in \(duration)")
        #expect(count > 0 && duration < Self.budget)
    }
}
