import Foundation
import Testing
@testable import TimetableCore

@Suite("Schedule result types")
struct ScheduleTypesTests {
    private let lessonID = Lesson.ID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let overrideID = ScheduleOverride.ID(uuidString: "00000000-0000-4000-8000-000000000002")!

    @Test func occurrenceIDsAreDeterministic() throws {
        let a = OccurrenceID.lesson(lessonID, on: Fixture.date("2026-10-06"))
        #expect(a.rawValue == "lesson:00000000-0000-4000-8000-000000000001:2026-10-06")
        #expect(a == OccurrenceID.lesson(Lesson.ID(uuidString: "00000000-0000-4000-8000-000000000001")!, on: Fixture.date("2026-10-06")))
        #expect(a != OccurrenceID.lesson(lessonID, on: Fixture.date("2026-10-07")))
        #expect(OccurrenceID.oneOff(overrideID).rawValue == "override:00000000-0000-4000-8000-000000000002")
        #expect(try Fixture.json(a) == "\"lesson:00000000-0000-4000-8000-000000000001:2026-10-06\"")
        #expect(try Fixture.roundTrip(a) == a)
        #expect(OccurrenceID.lesson(lessonID, on: Fixture.date("2026-10-06")) < OccurrenceID.lesson(lessonID, on: Fixture.date("2026-10-07")))
    }

    private func resolved(status: ResolvedLesson.Status = .scheduled) -> ResolvedLesson {
        let db = Fixture.fullDatabase()
        let context = CalendarContext(timeZone: Fixture.zone("Europe/Bratislava"), firstWeekday: .monday)
        let date = Fixture.date("2026-10-06")
        return ResolvedLesson(
            id: .lesson(lessonID, on: date), source: .lesson(lessonID), timetableID: db.timetables[0].id, date: date,
            subject: SubjectSummary(db.subjects[0]), startTime: Fixture.time("08:00"), endTime: Fixture.time("08:45"),
            start: context.date(date, Fixture.time("08:00")), end: context.date(date, Fixture.time("08:45")),
            periodID: db.bellSchedules[0].periods[0].id, periodLabel: "1", periodNumber: 1, periodSpan: 1,
            room: "101", building: "A", teacher: "Novák", lessonType: .lab, notes: nil, bringList: ["Goggles"],
            status: status, appliedOverrideIDs: [overrideID])
    }

    @Test func resolvedLessonCodableAndInterval() throws {
        let lesson = resolved(status: .modified)
        #expect(try Fixture.roundTrip(lesson) == lesson)
        #expect(lesson.interval.duration == 45 * 60)
        #expect(lesson.subject.name == "Matematika" && lesson.subject.shortName == "MAT")
        #expect(ResolvedLesson.Status.allCases == [.scheduled, .modified, .added, .cancelled])
    }

    @Test func conflictsSortOccurrencesAndLocalise() throws {
        let b = OccurrenceID.lesson(lessonID, on: Fixture.date("2026-10-07"))
        let a = OccurrenceID.oneOff(overrideID)
        let conflict = Conflict(kind: .overlap, date: Fixture.date("2026-10-07"), occurrenceIDs: [b, a])
        #expect(conflict.occurrenceIDs == [b, a].sorted())
        #expect(conflict.message == LocalizedText(key: "conflict.overlap", args: [.integer(2)]))
        #expect(try Fixture.roundTrip(conflict) == conflict)
        #expect(Set(Conflict.Kind.allCases.map(\.l10nKey)).count == Conflict.Kind.allCases.count)
    }

    @Test func dayScheduleAndNowNextCodable() throws {
        let lesson = resolved()
        let day = DaySchedule(date: lesson.date, timetableID: lesson.timetableID, dayKey: .weekday(.tuesday), cycleWeek: 2,
                              cycleLabel: "B", isSchoolDay: true, bellScheduleID: Fixture.fullDatabase().bellSchedules[0].id,
                              entries: [lesson], conflicts: [])
        #expect(try Fixture.roundTrip(day) == day)
        let nowNext = NowNext(at: lesson.start + 600, current: lesson, remaining: 35 * 60, next: nil, untilNext: nil, state: .inLesson)
        #expect(try Fixture.roundTrip(nowNext) == nowNext)
        let holiday = NowNext(at: lesson.start, state: .inBreak(Fixture.fullDatabase().breaks[0].id))
        #expect(try Fixture.roundTrip(holiday) == holiday)
    }
}
