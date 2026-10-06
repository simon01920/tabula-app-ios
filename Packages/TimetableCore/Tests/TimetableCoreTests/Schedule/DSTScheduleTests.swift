import Foundation
import Testing
@testable import TimetableCore

/// DST, time zones and midnight through the resolver. Instants follow the Stage 1 DST policy
/// (`CalendarContext.date`): a nonexistent local time moves forward by the gap; an ambiguous one takes the
/// earlier instant. Wall-clock times never change.
@Suite("ScheduleResolver — DST and time zones")
struct DSTScheduleTests {
    private func utc(_ date: String, _ time: String, seconds: Int = 0) -> Date { Fixture.utc(date, time, seconds: seconds) }
    private let t = Fixture.time

    private func everyDayWorld(_ zone: String) -> ScheduleWorld {
        ScheduleWorld(enabledDays: Set(Weekday.allCases), zone: zone)
    }

    private func times(_ entry: ResolvedLesson?) -> (Date, Date)? { entry.map { ($0.start, $0.end) } }

    @Test func bratislavaSpringForwardGap() {
        var world = everyDayWorld("Europe/Bratislava")
        let across = world.lesson(world.math, .weekday(.sunday), .time(start: t("01:30"), end: t("03:30")))
        let inside = world.lesson(world.physics, .weekday(.sunday), .time(start: t("02:15"), end: t("02:45")))
        let fromGap = world.lesson(world.english, .weekday(.sunday), .time(start: t("02:30"), end: t("04:00")))
        let morning = world.lesson(world.math, .weekday(.sunday), .time(start: t("08:00"), end: t("08:45")))
        let day = world.day("2026-03-29")
        #expect(day.entries.count == 4, "lessons in the gap are kept; wall-clock times are unchanged")
        #expect(times(day.entry(across))! == (utc("2026-03-29", "00:30"), utc("2026-03-29", "01:30"))) // 01:30 CET → 03:30 CEST
        #expect(times(day.entry(inside))! == (utc("2026-03-29", "01:15"), utc("2026-03-29", "01:45"))) // shifted +1 h
        #expect(times(day.entry(fromGap))! == (utc("2026-03-29", "01:30"), utc("2026-03-29", "02:00")))
        #expect(times(day.entry(morning))! == (utc("2026-03-29", "06:00"), utc("2026-03-29", "06:45")))
        #expect(day.entry(inside).map { "\($0.startTime)-\($0.endTime)" } == "02:15-02:45")
        for entry in day.entries {
            #expect(entry.start == world.context.date(entry.date, entry.startTime))
            #expect(entry.end == world.context.date(entry.date, entry.endTime))
        }
        // In progress across the gap: remaining time is real elapsed time.
        let now = world.resolver.nowAndNext(at: utc("2026-03-29", "00:45")) // 01:45 CET
        #expect(now.current?.id == day.entry(across)?.id && now.remaining == 45 * 60 && now.state == .inLesson)
    }

    @Test func bratislavaFallBackOverlap() {
        var world = everyDayWorld("Europe/Bratislava")
        let ambiguousStart = world.lesson(world.math, .weekday(.sunday), .time(start: t("02:30"), end: t("03:30")))
        let ambiguousEnd = world.lesson(world.physics, .weekday(.sunday), .time(start: t("01:00"), end: t("02:00")))
        let day = world.day("2026-10-25")
        #expect(times(day.entry(ambiguousStart))! == (utc("2026-10-25", "00:30"), utc("2026-10-25", "02:30"))) // 2 h of real time
        #expect(times(day.entry(ambiguousEnd))! == (utc("2026-10-24", "23:00"), utc("2026-10-25", "00:00")))
        #expect(day.entry(ambiguousStart)!.interval.duration == 7200)
    }

    @Test func newYorkTransitions() {
        var world = everyDayWorld("America/New_York")
        let zeroLength = world.lesson(world.math, .weekday(.sunday), .time(start: t("02:30"), end: t("03:30")))
        let short = world.lesson(world.physics, .weekday(.sunday), .time(start: t("01:30"), end: t("03:00")))
        world.lesson(world.english, .weekday(.sunday), .time(start: t("08:00"), end: t("08:45")))
        let spring = world.day("2026-03-08")
        #expect(times(spring.entry(zeroLength))! == (utc("2026-03-08", "07:30"), utc("2026-03-08", "07:30")))
        #expect(times(spring.entry(short))! == (utc("2026-03-08", "06:30"), utc("2026-03-08", "07:00")))
        #expect(spring.entries.last?.start == utc("2026-03-08", "12:00"))
        // A zero-length occurrence is never "current" but is found by interval queries.
        let resolver = world.resolver
        #expect(resolver.nowAndNext(at: utc("2026-03-08", "07:30")).current == nil)
        let window = DateInterval(start: utc("2026-03-08", "07:00"), end: utc("2026-03-08", "08:00"))
        #expect(resolver.occurrences(in: window).map(\.id) == [spring.entry(zeroLength)!.id])
        let fall = world.day("2026-11-01")
        let overlap = fall.entries.first { "\($0.startTime)" == "01:30" }!
        #expect(overlap.start == utc("2026-11-01", "05:30") && overlap.end == utc("2026-11-01", "08:00")) // 01:30 EDT → 03:00 EST
        #expect(overlap.interval.duration == 150 * 60, "90 wall-clock minutes + the repeated hour")
    }

    @Test func weeklyLessonsKeepWallClockTimeAcrossDST() {
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 1)
        #expect(world.day("2026-03-23").entries[0].start == utc("2026-03-23", "07:00")) // CET
        #expect(world.day("2026-03-30").entries[0].start == utc("2026-03-30", "06:00")) // CEST
        #expect(world.day("2026-10-19").entries[0].start == utc("2026-10-19", "06:00"))
        #expect(world.day("2026-10-26").entries[0].start == utc("2026-10-26", "07:00"))
        var newYork = ScheduleWorld(zone: "America/New_York")
        newYork.lesson(newYork.math, .monday, period: 1)
        #expect(newYork.day("2026-03-02").entries[0].start == utc("2026-03-02", "13:00")) // EST
        #expect(newYork.day("2026-03-09").entries[0].start == utc("2026-03-09", "12:00")) // EDT
        // Week cycles and day cycles are calendar arithmetic, unaffected by 23/25-hour days.
        let rotation = RotationResolver(scheme: .weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: Fixture.date("2026-03-23"), cycleWeek: 1))),
                                        firstWeekday: .monday)
        #expect(rotation.cycleWeek(on: Fixture.date("2026-03-29")) == 1 && rotation.cycleWeek(on: Fixture.date("2026-03-30")) == 2)
    }

    @Test func timeZoneChangeMovesInstantsNotWallClock() {
        var world = ScheduleWorld()
        world.lesson(world.math, .tuesday, period: 1)
        let bratislava = world.day("2026-10-06").entries[0]
        let newYork = world.resolver(context: CalendarContext(timeZone: Fixture.zone("America/New_York"), firstWeekday: .monday))
            .day(Fixture.date("2026-10-06")).entries[0]
        #expect(bratislava.startTime == newYork.startTime && bratislava.id == newYork.id)
        #expect(newYork.start.timeIntervalSince(bratislava.start) == 6 * 3600)
        #expect(newYork.start == utc("2026-10-06", "12:00"))
    }

    @Test(arguments: ["Europe/Bratislava", "America/New_York", "America/Sao_Paulo", "Australia/Lord_Howe", "Asia/Kathmandu", "UTC"])
    func dayClockFastPathEqualsCalendarContext(zone: String) {
        let context = CalendarContext(timeZone: Fixture.zone(zone), firstWeekday: .monday)
        var failures = FailureBudget()
        for date in LocalDateRange(start: Fixture.date("2026-01-01"), end: Fixture.date("2027-12-31")).days {
            let clock = DayClock(context: context, date: date)
            for minute in stride(from: 0, to: 1440, by: 15) {
                let time = LocalTime(minuteOfDay: minute)!
                if clock.instant(time) != context.date(date, time) { failures.record("\(zone) \(date) \(time)") }
            }
        }
        #expect(failures.count == 0)
    }

    @Test func skippedMidnightAndDayBoundaries() {
        // São Paulo 2018-11-04: 00:00 did not exist (clocks jumped to 01:00, UTC−2).
        var world = everyDayWorld("America/Sao_Paulo")
        world.lesson(world.math, .weekday(.sunday), .time(start: t("00:00"), end: t("00:45")))
        world.lesson(world.physics, .weekday(.saturday), .time(start: t("23:00"), end: t("23:59")))
        let sunday = world.day("2018-11-04")
        #expect(times(sunday.entries.first)! == (utc("2018-11-04", "03:00"), utc("2018-11-04", "03:45")))
        let interval = world.context.dayInterval(Fixture.date("2018-11-04"))
        #expect(world.resolver.occurrences(in: interval).map(\.date) == [Fixture.date("2018-11-04")])
        // 23:00–23:59 on Saturday ends one minute before the (skipped) midnight.
        let saturday = world.day("2018-11-03").entries[0]
        #expect(saturday.end == utc("2018-11-04", "02:59"))
        let lastSecond = world.resolver.nowAndNext(at: utc("2018-11-04", "02:59", seconds: 59))
        #expect(lastSecond.state == .afterLastLesson && lastSecond.next?.date == Fixture.date("2018-11-04"))
        #expect(lastSecond.untilNext == 1)
    }
}
