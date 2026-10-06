import Foundation
import Testing
@testable import TimetableCore

@Suite("ScheduleResolver — now & next")
struct NowNextTests {
    /// Tuesday: P1 Math 08:00–08:45, P2 Physics 08:55–09:40, P5 English 12:20–13:05. Wednesday: P1 Math.
    private func world() -> (world: ScheduleWorld, math: Lesson.ID, physics: Lesson.ID, english: Lesson.ID, wednesday: Lesson.ID) {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        let physics = world.lesson(world.physics, .tuesday, period: 2)
        let english = world.lesson(world.english, .tuesday, period: 5)
        let wednesday = world.lesson(world.math, .wednesday, period: 1)
        return (world, math, physics, english, wednesday)
    }

    @Test func boundariesAreHalfOpen() {
        let (w, math, physics, english, wednesday) = world()
        let resolver = w.resolver
        let atStart = resolver.nowAndNext(at: w.instant("2026-10-06", "08:00"))
        #expect(atStart.state == .inLesson && atStart.current?.source == .lesson(math))
        #expect(atStart.remaining == 45 * 60 && atStart.next?.source == .lesson(physics) && atStart.untilNext == 55 * 60)
        #expect(atStart.at == w.instant("2026-10-06", "08:00"))

        let before = resolver.nowAndNext(at: w.instant("2026-10-06", "07:59", seconds: 59))
        #expect(before.state == .beforeFirstLesson && before.current == nil && before.remaining == nil)
        #expect(before.next?.source == .lesson(math) && before.untilNext == 1)

        let atEnd = resolver.nowAndNext(at: w.instant("2026-10-06", "08:45"))
        #expect(atEnd.state == .betweenLessons && atEnd.current == nil && atEnd.next?.source == .lesson(physics) && atEnd.untilNext == 600)

        let lastSecond = resolver.nowAndNext(at: w.instant("2026-10-06", "08:44", seconds: 59))
        #expect(lastSecond.current?.source == .lesson(math) && lastSecond.remaining == 1)

        let inBreak = resolver.nowAndNext(at: w.instant("2026-10-06", "08:50"))
        #expect(inBreak.state == .betweenLessons && inBreak.untilNext == 300)

        let freePeriods = resolver.nowAndNext(at: w.instant("2026-10-06", "10:00"))
        #expect(freePeriods.state == .betweenLessons && freePeriods.next?.source == .lesson(english))
        #expect(freePeriods.untilNext == TimeInterval(140 * 60))

        let afterLast = resolver.nowAndNext(at: w.instant("2026-10-06", "13:05"))
        #expect(afterLast.state == .afterLastLesson && afterLast.next?.source == .lesson(wednesday))
        #expect(afterLast.next?.date == Fixture.date("2026-10-07") && afterLast.untilNext == (18 * 60 + 55) * 60)
    }

    @Test func weekendsHolidaysAndCancellations() {
        let fixture = world()
        var w = fixture.world
        let math = fixture.math, physics = fixture.physics
        let autumn = w.holiday("2026-10-26", "2026-10-30")
        let weekend = w.resolver.nowAndNext(at: w.instant("2026-10-10", "12:00"))
        #expect(weekend.state == .noLessonsToday && weekend.next?.source == .lesson(math))
        #expect(weekend.next?.date == Fixture.date("2026-10-13"))

        let holiday = w.resolver.nowAndNext(at: w.instant("2026-10-27", "10:00"))
        #expect(holiday.state == .inBreak(autumn) && holiday.current == nil)
        #expect(holiday.next?.date == Fixture.date("2026-11-03") && holiday.untilNext == (6 * 24 + 22) * 3600)

        // Across the DST change of 25 October: the countdown is real elapsed time.
        let friday = w.resolver.nowAndNext(at: w.instant("2026-10-23", "13:30"))
        #expect(friday.state == .noLessonsToday && friday.next?.date == Fixture.date("2026-11-03"))
        #expect(friday.untilNext == w.instant("2026-11-03", "08:00").timeIntervalSince(w.instant("2026-10-23", "13:30")))
        #expect(friday.untilNext == TimeInterval((10 * 24 + 18) * 3600 + 30 * 60 + 3600), "one extra hour from the fall-back")

        w.override("2026-10-06", .cancelLesson(math))
        let cancelled = w.resolver.nowAndNext(at: w.instant("2026-10-06", "08:10"))
        #expect(cancelled.current == nil && cancelled.state == .beforeFirstLesson && cancelled.next?.source == .lesson(physics))

        w.override("2026-10-13", .cancelDay(note: nil))
        let cancelledDay = w.resolver.nowAndNext(at: w.instant("2026-10-13", "09:00"))
        #expect(cancelledDay.state == .noLessonsToday && cancelledDay.next?.date == Fixture.date("2026-10-14"))

        // An added lesson during the holidays is a real lesson.
        let camp = w.override("2026-10-28", .addLesson(OneOffLesson(subjectID: w.english,
                                                                    slot: .time(start: Fixture.time("09:00"), end: Fixture.time("12:00")))))
        let duringCamp = w.resolver.nowAndNext(at: w.instant("2026-10-28", "10:00"))
        #expect(duringCamp.state == .inLesson && duringCamp.current?.id == .oneOff(camp))
        #expect(w.resolver.nowAndNext(at: w.instant("2026-10-28", "13:00")).state == .afterLastLesson)
    }

    @Test func horizonAndMidnight() {
        let (w, math, _, _, wednesday) = world()
        let resolver = w.resolver
        #expect(resolver.nowAndNext(at: w.instant("2026-10-06", "13:30"), horizonDays: 0).next == nil)
        #expect(resolver.nowAndNext(at: w.instant("2026-10-06", "13:30"), horizonDays: 1).next?.source == .lesson(wednesday))
        #expect(resolver.nowAndNext(at: w.instant("2026-10-08", "13:30"), horizonDays: 4).next == nil) // Thu → Mon
        let midnight = resolver.nowAndNext(at: w.instant("2026-10-06", "00:00"))
        #expect(midnight.state == .beforeFirstLesson && midnight.next?.source == .lesson(math) && midnight.untilNext == 8 * 3600)
        let lastMondaySecond = resolver.nowAndNext(at: w.instant("2026-10-05", "23:59", seconds: 59))
        #expect(lastMondaySecond.state == .noLessonsToday && lastMondaySecond.untilNext == 8 * 3600 + 1)
    }

    @Test func overlappingLessonsPreferTheLatestStart() {
        let fixture = world()
        var w = fixture.world
        let math = fixture.math, physics = fixture.physics
        let overlap = w.override("2026-10-06", .addLesson(OneOffLesson(subjectID: w.english,
                                                                       slot: .time(start: Fixture.time("08:30"), end: Fixture.time("09:00")))))
        let now = w.resolver.nowAndNext(at: w.instant("2026-10-06", "08:35"))
        #expect(now.current?.id == .oneOff(overlap) && now.remaining == 25 * 60 && now.next?.source == .lesson(physics))
        let earlier = w.resolver.nowAndNext(at: w.instant("2026-10-06", "08:20"))
        #expect(earlier.current?.source == .lesson(math) && earlier.next?.id == .oneOff(overlap))
        #expect(w.day("2026-10-06").conflicts.map(\.kind) == [.overlap])
    }
}
