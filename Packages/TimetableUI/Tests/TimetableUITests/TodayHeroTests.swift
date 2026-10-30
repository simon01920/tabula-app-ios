import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4U U3: the Today hero moments (Opus R1), the minutes-only countdown (H2), "rest of today" (H3.2 / F14), the bring
// list, the subtitle (L2) and the next-exam rules, against the deterministic secondary scenario (Tue 2026-10-13, bell
// 8:00–8:45, 8:55–9:40, 10:00–10:45, 10:55–11:40, …; autumn holidays Thu 29 – Fri 30 Oct).

private let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func instant(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> Date { context.date(day, time(h, m)) }
private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: SampleScenarios.timeZone),
    lookup: EnglishCatalog.lookup)
private let today = SampleScenarios.today
private let scenario = SampleScenarios.secondary()
private let visibility = scenario.database.timetables[0].fieldVisibility
private let text = TodayHeroText(renderer: renderer, visibility: visibility)

private func state(at now: Date, database: TabulaDatabase = scenario.database) throws -> TodayState {
    let resolver = try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id, context: context))
    return TodayState.make(now: now, resolver: resolver, database: database)
}

@Suite("Today hero (U3)")
struct TodayHeroTests {
    @Test func stateRoutesShowTheirMoment() throws {
        let clocks = SampleScenarios.todayMomentClocks
        #expect(try state(at: SampleScenarios.referenceNow).header.moment == .inLesson)
        #expect(try state(at: clocks.beforeSchool).header.moment == .beforeSchool)
        #expect(try state(at: clocks.breakTime).header.moment == .breakTime)
        #expect(try state(at: clocks.afterSchool).header.moment == .afterSchool)
        let holiday = try state(at: clocks.holiday)
        #expect(holiday.header.moment == .dayOff)
        #expect(holiday.holidayEnd == date(2026, 10, 30))
        let off = text.dayOff(holiday.header, holidayEnd: holiday.holidayEnd, today: holiday.date)
        #expect(off.title == "Jesenné prázdniny" && off.detail == "until Fri 30 Oct")
        #expect(try state(at: instant(date(2026, 10, 17), 11)).header.moment == .dayOff)   // Saturday
    }

    @Test func inLessonTexts() throws {
        let now = SampleScenarios.referenceNow   // 10:20 in the 10:00–10:45 lesson
        let hero = try state(at: now)
        guard case let .current(lesson, next) = hero.header else {
            Issue.record("expected a lesson, got \(hero.header)")
            return
        }
        #expect(text.until(lesson.endTime) == "until 10:45")
        #expect(text.left(until: lesson.end, now: now) == "25 min left")
        let following = try #require(next)
        #expect(text.line(following, today: today).hasPrefix("10:55 · \(following.subject.name)"))
        let spoken = text.accessibilityLabel(hero, now: now, bring: [])
        #expect(spoken.hasPrefix("Now, \(lesson.subject.name)"))
        #expect(spoken.contains("25 min left, ends at 10:45, Next, 10:55 · "))
        #expect(TodayHeroText.bringItems(hero, visibility: visibility).isEmpty)
    }

    @Test func breakAndBeforeSchool() throws {
        let breakState = try state(at: instant(today, 8, 53))
        guard case let .upcoming(next, isFirst) = breakState.header else {
            Issue.record("expected upcoming, got \(breakState.header)")
            return
        }
        #expect(!isFirst && next.startTime == time(8, 55))
        #expect(text.startsIn(next.start, now: instant(today, 8, 53)) == "in 2 min")
        // The exact end of a lesson is already the break (half-open lessons, as the widgets).
        #expect(try state(at: instant(today, 8, 45)).header.moment == .breakTime)

        let early = try state(at: instant(today, 6, 30))
        #expect(early.header.moment == .beforeSchool)
        #expect(text.startsIn(early.header.next!.start, now: instant(today, 6, 30)) == "in 1 h 30 min")
    }

    @Test func lastLessonEndingAndMidnight() throws {
        let last = try #require(try state(at: SampleScenarios.referenceNow).items.compactMap { item -> ResolvedLesson? in
            if case let .lesson(lesson, _, _) = item, lesson.status != .cancelled { return lesson }
            return nil
        }.last)
        let ending = try state(at: last.end.addingTimeInterval(-20))
        #expect(ending.header.moment == .inLesson)
        #expect(text.left(until: last.end, now: last.end.addingTimeInterval(-20)) == "1 min left")
        let over = try state(at: last.end)
        #expect(over.header.moment == .afterSchool && over.header.next?.date == date(2026, 10, 14))
        #expect(over.remainingItems.isEmpty && !over.earlierItems.isEmpty)

        let beforeMidnight = try state(at: instant(today, 23, 59))
        #expect(beforeMidnight.date == today && beforeMidnight.header.moment == .afterSchool)
        #expect(text.line(beforeMidnight.header.next!, today: today).hasPrefix("Tomorrow, 8:00 · "))
        let midnight = try state(at: instant(date(2026, 10, 14), 0))
        #expect(midnight.date == date(2026, 10, 14) && midnight.header.moment == .beforeSchool)
        #expect(midnight.earlierItems.isEmpty && midnight.upcomingItems.isEmpty)
    }

    @Test func daylightSavingTimeEnded() throws {
        // Sun 2026-10-25 03:00 CEST → 02:00 CET. Monday's wall-clock bell must not shift by an hour.
        let monday = date(2026, 10, 26)
        let early = try state(at: instant(monday, 7, 20))
        #expect(early.header.moment == .beforeSchool && early.header.next?.startTime == time(8))
        #expect(text.startsIn(early.header.next!.start, now: instant(monday, 7, 20)) == "in 40 min")
        let lesson = try state(at: instant(monday, 10, 20))
        guard case let .current(current, _) = lesson.header else {
            Issue.record("expected a lesson, got \(lesson.header)")
            return
        }
        #expect(text.left(until: current.end, now: instant(monday, 10, 20)) == "25 min left")
        // Saturday evening before the change: Monday's first lesson is 34 h away in real time (the extra hour).
        let saturday = try state(at: instant(date(2026, 10, 24), 23))
        let next = try #require(saturday.header.next)
        #expect(next.date == monday)
        #expect(next.start.timeIntervalSince(instant(date(2026, 10, 24), 23)) == 34 * 3600)
    }

    @Test func minutesLeftRoundsUp() {
        let end = Date(timeIntervalSince1970: 100_000)
        #expect(TodayHeroText.minutesLeft(until: end, now: end.addingTimeInterval(-25 * 60)) == 25)
        #expect(TodayHeroText.minutesLeft(until: end, now: end.addingTimeInterval(-(24 * 60 + 1))) == 25)
        #expect(TodayHeroText.minutesLeft(until: end, now: end.addingTimeInterval(-20)) == 1)
        #expect(TodayHeroText.minutesLeft(until: end, now: end) == 0)
        #expect(TodayHeroText.minutesLeft(until: end, now: end.addingTimeInterval(30)) == 0)
        #expect(text.left(until: end, now: end.addingTimeInterval(-(65 * 60))) == "1 h 5 min left")
        #expect(text.left(until: end, now: end.addingTimeInterval(-(60 * 60))) == "1 h left")
    }

    @Test func restOfTodayExcludesTheCurrentAndPastLessons() throws {
        let now = SampleScenarios.referenceNow
        let hero = try state(at: now)
        guard case let .current(current, _) = hero.header else {
            Issue.record("expected a lesson, got \(hero.header)")
            return
        }
        let lessons = hero.items.filter { $0.timing != nil }
        #expect(!hero.remainingItems.contains { $0.id == current.id.rawValue })
        #expect(!hero.earlierItems.contains { $0.id == current.id.rawValue })
        #expect(hero.remainingItems.allSatisfy { item in
            if case let .lesson(lesson, _, _) = item { return lesson.start > now }
            return false
        })
        #expect(hero.earlierItems.count == 2 && hero.remainingItems.count == lessons.count - 3)
    }

    @Test func bringListMergesVisibleItemsOnce() throws {
        var lessons = try state(at: SampleScenarios.referenceNow).items.compactMap { item -> ResolvedLesson? in
            if case let .lesson(lesson, _, _) = item { return lesson }
            return nil
        }
        lessons[0].bringList = ["Atlas", " ruler "]
        lessons[1].bringList = ["atlas", "Sports kit", ""]
        lessons[2].bringList = ["Cancelled item"]
        lessons[2].status = .cancelled
        let items = lessons.prefix(3).map { TodayItem.lesson($0, reasons: [], timing: .upcoming) }
        #expect(TodayState.bringList(items, visibility: .all) == ["Atlas", "ruler", "Sports kit"])
        #expect(TodayState.bringList(items, visibility: FieldVisibility([.room])).isEmpty)
        #expect(text.bring(["Atlas", "ruler"]) == "What to bring: Atlas and ruler")
        #expect(text.bring([]) == nil)
    }

    @Test func subtitleHasNoYearAndAFullRotationPhrase() throws {
        let subtitle = text.subtitle(try state(at: SampleScenarios.referenceNow))
        #expect(subtitle == "Tue 13 Oct · Week B")
        #expect(!subtitle.contains("2026"))
    }

    @Test func nextExamIsTheEarliestOpenOneWithinTheHorizon() throws {
        let now = LocalDateTime(date: today, time: time(10, 20))
        let work = TodayWork.make(database: scenario.database, now: now, context: scenario.context)
        let exam = try #require(work.nextExam)
        #expect(text.examWhen(exam) == "Thu 22 Oct · in 9 days")
        // Completing it moves Today to the next open exam, still within 14 days.
        var database = scenario.database
        let index = database.exams.firstIndex { $0.id == exam.id }!
        database.exams[index].completedAt = SampleScenarios.referenceNow
        let after = TodayWork.make(database: database, now: now, context: scenario.context)
        #expect(after.nextExam.map { $0.id != exam.id && $0.daysUntil >= 9 && $0.daysUntil <= TodayWork.examHorizonDays } == true)
        #expect(text.overdue(3) == "3 overdue tasks")   // the test catalog has the "other" forms only
    }
}
