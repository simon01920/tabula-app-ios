import Foundation
import Testing
@testable import TimetableCore

@Suite("ScheduleResolver — days")
struct ScheduleResolverTests {
    private let d = Fixture.date

    @Test func periodLessonsUseBellTimesAndInstants() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        let physics = world.lesson(world.physics, .tuesday, period: 3)
        let english = world.lesson(world.english, .weekday(.tuesday), .time(start: Fixture.time("14:30"), end: Fixture.time("15:15")))
        let day = world.day("2026-10-06")
        #expect(day.dayKey == .weekday(.tuesday) && day.isSchoolDay && day.cycleWeek == nil && day.cycleLabel == nil)
        #expect(day.bellScheduleID == world.normalID && day.termID == nil && day.activeBreakID == nil)
        #expect(day.scheduleTimes == ["08:00-08:45", "10:00-10:45", "14:30-15:15"])
        #expect(day.entries.map(\.source) == [.lesson(math), .lesson(physics), .lesson(english)])
        let first = day.entries[0]
        #expect(first.id == .lesson(math, on: d("2026-10-06")))
        #expect(first.start == Fixture.utc("2026-10-06", "06:00") && first.end == Fixture.utc("2026-10-06", "06:45")) // CEST
        #expect(first.periodID == world.p[0] && first.periodNumber == 1 && first.periodSpan == 1 && first.periodLabel == nil)
        #expect(first.status == .scheduled && first.appliedOverrideIDs.isEmpty && first.subject.name == "Math")
        #expect(day.entries[1].periodLabel == "3rd" && day.entries[1].periodNumber == 3)
        #expect(day.entries[2].periodID == nil && day.entries[2].periodNumber == nil && day.entries[2].periodSpan == nil)
        #expect(day.conflicts.isEmpty)
    }

    @Test func spanCoversInnerBreaksAndIsTruncatedAtTheEnd() {
        var world = ScheduleWorld()
        world.lesson(world.math, .wednesday, period: 1, span: 2)
        world.lesson(world.physics, .wednesday, period: 4, span: 2)
        let english = world.lesson(world.english, .wednesday, period: 6, span: 3)
        let resolution = world.resolution("2026-10-07")
        let day = resolution.schedule
        #expect(day.scheduleTimes == ["08:00-09:40", "10:55-13:05", "13:15-14:00"])
        #expect(day.entries.map(\.periodSpan) == [2, 2, 1])
        let occurrence = OccurrenceID.lesson(english, on: d("2026-10-07"))
        #expect(day.conflicts == [Conflict(kind: .spanExceedsSchedule, date: d("2026-10-07"), occurrenceIDs: [occurrence])])
        #expect(resolution.warnings.map(\.kind) == [.spanExceedsSchedule])
        #expect(resolution.warnings[0].occurrenceID == occurrence && resolution.warnings[0].periodID == world.p[5])
    }

    @Test func weekendsAndDisabledDaysHaveNoLessons() {
        var world = ScheduleWorld()
        world.lesson(world.math, .saturday, period: 1)
        let saturday = world.resolution("2026-10-10")
        #expect(!saturday.schedule.isSchoolDay && saturday.schedule.dayKey == nil && saturday.schedule.entries.isEmpty)
        #expect(saturday.naturalDayKey == nil)
        world.timetable.enabledDays.insert(.saturday)
        #expect(world.day("2026-10-10").scheduleTimes == ["08:00-08:45"])
        world.timetable.enabledDays = []
        #expect(!world.day("2026-10-06").isSchoolDay)
    }

    @Test func perWeekdayScheduleIsTheRegularFridaySchedule() {
        var world = ScheduleWorld()
        world.lesson(world.math, .friday, period: 3)
        let resolution = world.resolution("2026-10-09")
        #expect(resolution.schedule.bellScheduleID == world.shortID)
        #expect(resolution.schedule.scheduleTimes == ["09:20-09:50"])
        #expect(resolution.schedule.entries[0].status == .scheduled && resolution.changes.isEmpty && resolution.warnings.isEmpty)
    }

    @Test func breaksRemoveRegularLessonsUnlessIgnored() {
        var world = ScheduleWorld()
        world.lesson(world.math, .tuesday, period: 1)
        let autumn = world.holiday("2026-10-26", "2026-10-30")
        let foreign = CalendarBreak(id: world.ids.next(), meta: ScheduleWorld.meta(), timetableID: world.ids.next(),
                                    name: "Other", range: LocalDateRange(day: d("2026-11-03")))
        world.breaks.append(foreign)
        let inBreak = world.day("2026-10-27")
        #expect(!inBreak.isSchoolDay && inBreak.dayKey == nil && inBreak.entries.isEmpty && inBreak.activeBreakID == autumn)
        let regular = world.day("2026-10-27", options: .regular)
        #expect(regular.isSchoolDay && regular.scheduleTimes == ["08:00-08:45"] && regular.activeBreakID == autumn)
        #expect(world.day("2026-11-03").isSchoolDay, "another timetable's break does not apply")
        let ownBreak = world.holiday("2026-11-10", "2026-11-10", ownTimetable: true)
        #expect(world.day("2026-11-10").activeBreakID == ownBreak)
        // A tombstoned break is ignored.
        world.breaks[0].meta.isDeleted = true
        #expect(world.day("2026-10-27").isSchoolDay)
    }

    @Test func termsAndValidityRestrictLessons() {
        var world = ScheduleWorld()
        let winter = world.term("2026-09-01", "2027-01-31")
        let summer = world.term("2027-02-01", "2027-06-30")
        let gone = world.term("2026-09-01", "2027-06-30")
        world.terms[2].meta.isDeleted = true
        let a = world.lesson(world.math, .tuesday, period: 1, validity: .terms([winter]))
        let b = world.lesson(world.physics, .tuesday, period: 2,
                             validity: .range(LocalDateRange(start: d("2026-10-01"), end: d("2026-10-31"))))
        let c = world.lesson(world.english, .tuesday, period: 3, validity: .terms([gone]))
        let e = world.lesson(world.english, .tuesday, period: 4, validity: .terms([summer, winter]))
        #expect(world.day("2026-10-06").entries.map(\.source) == [.lesson(a), .lesson(b), .lesson(e)])
        #expect(world.day("2026-10-06").termID == winter)
        #expect(world.day("2026-11-03").entries.map(\.source) == [.lesson(a), .lesson(e)])
        #expect(world.day("2027-02-02").entries.map(\.source) == [.lesson(e)])
        #expect(world.day("2027-02-02").termID == summer)
        #expect(world.day("2027-07-06").entries.isEmpty && world.day("2027-07-06").termID == nil)
        #expect(world.day("2027-07-06", options: .allLessons).entries.map(\.source) == [.lesson(a), .lesson(b), .lesson(c), .lesson(e)])
    }

    @Test func cycleWeeksFollowTheWeekCycle() {
        var world = ScheduleWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0),
                                                                 labels: ["A", "B"])))
        let weekA = world.lesson(world.math, .monday, period: 1, weeks: [1])
        let weekB = world.lesson(world.physics, .monday, period: 1, weeks: [2])
        let every = world.lesson(world.english, .monday, period: 2)
        world.lesson(world.english, .monday, period: 3, weeks: [])
        let odd = world.day("2026-10-05") // W41
        #expect(odd.cycleWeek == 1 && odd.cycleLabel == "A" && odd.entries.map(\.source) == [.lesson(weekA), .lesson(every)])
        let even = world.day("2026-10-12") // W42
        #expect(even.cycleWeek == 2 && even.cycleLabel == "B" && even.entries.map(\.source) == [.lesson(weekB), .lesson(every)])
        #expect(world.day("2026-10-10").cycleWeek == 1 && world.day("2026-10-10").cycleLabel == "A", "weekends keep the week")
        // Without a week cycle `cycleWeeks` is ignored, so A and B both appear (and overlap).
        world.timetable.rotation = .none
        let flat = world.day("2026-10-05")
        #expect(flat.entries.count == 4 && flat.cycleWeek == nil)
        #expect(flat.conflicts.map(\.kind) == [.overlap])
    }

    @Test func effectiveFieldsFollowTheFieldRule() {
        var world = ScheduleWorld()
        world.lesson(world.math, .weekday(.tuesday), .period(world.p[0], span: 1), lessonType: .lab, bringList: ["Ruler", " ", ""])
        world.lesson(world.math, .weekday(.tuesday), .period(world.p[1], span: 1), room: "  ", lessonType: LessonType(rawValue: ""))
        world.lesson(world.math, .weekday(.tuesday), .period(world.p[2], span: 1), room: "Lab", teacher: "Kováč", notes: "Bring tablet")
        world.lesson(world.physics, .weekday(.tuesday), .period(world.p[3], span: 1))
        let entries = world.day("2026-10-06").entries
        #expect(entries[0].room == "101" && entries[0].building == "A" && entries[0].teacher == "Novák")
        #expect(entries[0].notes == nil, "subject notes are not lesson notes")
        #expect(entries[0].lessonType == .lab && entries[0].bringList == ["Ruler"])
        #expect(entries[1].room == "101" && entries[1].lessonType == nil)
        #expect(entries[2].room == "Lab" && entries[2].teacher == "Kováč" && entries[2].notes == "Bring tablet")
        #expect(entries[3].room == nil && entries[3].building == nil && entries[3].teacher == nil && entries[3].bringList.isEmpty)
        #expect(entries[0].subject == SubjectSummary(world.subjects[0]))
    }

    @Test func singleFieldRule() {
        #expect(EffectiveFields.resolve(own: "A", subjectDefault: "B", patch: nil) == "A")
        #expect(EffectiveFields.resolve(own: nil, subjectDefault: "B", patch: nil) == "B")
        #expect(EffectiveFields.resolve(own: " \n", subjectDefault: "B", patch: nil) == "B")
        #expect(EffectiveFields.resolve(own: nil, subjectDefault: " ", patch: nil) == nil)
        #expect(EffectiveFields.resolve(own: "A", subjectDefault: "B", patch: "C") == "C")
        #expect(EffectiveFields.resolve(own: "A", subjectDefault: "B", patch: "") == nil, "empty patch clears, no fallback")
        #expect(EffectiveFields.resolve(own: nil, subjectDefault: "B", patch: "   ") == nil)
        #expect(EffectiveFields.resolve(own: " A ", subjectDefault: nil, patch: nil) == " A ", "values are verbatim")
        #expect(EffectiveFields.isBlank("") && EffectiveFields.isBlank(" \t\n") && !EffectiveFields.isBlank("x"))
    }

    @Test func missingAndDeletedEntitiesAreReportedNotFatal() {
        var world = ScheduleWorld()
        let orphan = world.lesson(world.physics, .tuesday, period: 1)
        world.subjects[1].meta.isDeleted = true
        let deleted = world.lesson(world.math, .tuesday, period: 2)
        world.lessons[1].meta.isDeleted = true
        world.lesson(world.math, .tuesday, period: 3)
        let resolution = world.resolution("2026-10-06")
        let occurrence = OccurrenceID.lesson(orphan, on: d("2026-10-06"))
        #expect(resolution.schedule.scheduleTimes == ["10:00-10:45"])
        #expect(!resolution.schedule.entries.contains { $0.source == .lesson(deleted) })
        #expect(resolution.schedule.conflicts == [Conflict(kind: .missingSubject, date: d("2026-10-06"), occurrenceIDs: [occurrence])])
        #expect(resolution.warnings == [ResolutionWarning(kind: .missingSubject, date: d("2026-10-06"), occurrenceID: occurrence,
                                                          lessonID: orphan, subjectID: world.physics)])
    }

    @Test func missingBellScheduleAndFreeFormPeriods() {
        var world = ScheduleWorld()
        let lesson = world.lesson(world.math, .tuesday, period: 1)
        world.lesson(world.math, .weekday(.tuesday), .time(start: Fixture.time("15:00"), end: Fixture.time("15:45")))
        world.bellSchedules[0].meta.isDeleted = true // the default "Normal"
        let resolution = world.resolution("2026-10-06")
        let occurrence = OccurrenceID.lesson(lesson, on: d("2026-10-06"))
        #expect(resolution.schedule.scheduleTimes == ["15:00-15:45"] && resolution.schedule.bellScheduleID == nil)
        #expect(resolution.warnings.map(\.kind) == [.missingBellSchedule, .periodNotInSchedule])
        #expect(resolution.warnings[0].bellScheduleID == world.normalID)
        #expect(resolution.schedule.conflicts == [Conflict(kind: .periodNotInSchedule, date: d("2026-10-06"), occurrenceIDs: [occurrence])])
        #expect(world.resolution("2026-10-10").warnings.isEmpty, "no warning on days without lessons")

        var freeForm = ScheduleWorld(freeForm: true)
        freeForm.lesson(freeForm.math, .tuesday, period: 1)
        freeForm.lesson(freeForm.math, .weekday(.tuesday), .time(start: Fixture.time("09:00"), end: Fixture.time("10:30")))
        let free = freeForm.resolution("2026-10-06")
        #expect(free.schedule.scheduleTimes == ["09:00-10:30"] && free.warnings.map(\.kind) == [.periodNotInSchedule])
        #expect(free.schedule.conflicts.map(\.kind) == [.periodNotInSchedule])

        var invalid = ScheduleWorld()
        invalid.lesson(invalid.math, .weekday(.tuesday), .time(start: Fixture.time("10:00"), end: Fixture.time("09:00")))
        let bad = invalid.resolution("2026-10-06")
        #expect(bad.schedule.entries.isEmpty && bad.warnings.map(\.kind) == [.invalidTimeRange])
        #expect(bad.schedule.conflicts.map(\.kind) == [.invalidTimeRange])
    }

    @Test func dayCycleTimetables() {
        var world = ScheduleWorld(rotation: .dayCycle(DayCycle(length: 2, anchorDate: d("2026-09-01"), labels: ["A", "B"])),
                                  enabledDays: [.monday, .tuesday, .wednesday, .thursday])
        let dayA = world.lesson(world.math, .cycleDay(1), .period(world.p[0], span: 1))
        let dayB = world.lesson(world.physics, .cycleDay(2), .period(world.p[0], span: 1))
        world.lesson(world.english, .weekday(.monday), .period(world.p[1], span: 1)) // wrong key kind: never runs
        #expect(world.day("2026-09-01").entries.map(\.source) == [.lesson(dayA)])
        #expect(world.day("2026-09-02").entries.map(\.source) == [.lesson(dayB)])
        let october6 = world.day("2026-10-06") // 26th school day → cycle day 2
        #expect(october6.dayKey == .cycleDay(2) && october6.cycleLabel == "B" && october6.cycleWeek == nil)
        #expect(october6.entries.map(\.source) == [.lesson(dayB)])
        // Friday advances the cycle (schoolDays Mon–Fri) but is not an enabled day of this timetable.
        let friday = world.resolution("2026-10-09")
        #expect(!friday.schedule.isSchoolDay && friday.schedule.entries.isEmpty && friday.naturalDayKey == nil)
        #expect(world.resolver.rotation.cycleDay(on: d("2026-10-09")) != nil)
    }

    @Test func fullDatabaseIntegration() throws {
        let db = Fixture.fullDatabase()
        let context = CalendarContext(timeZone: Fixture.zone("Europe/Bratislava"), firstWeekday: .monday)
        let school = try #require(ScheduleResolver(database: db, timetableID: db.timetables[0].id, context: context))
        let college = try #require(ScheduleResolver(database: db, timetableID: db.timetables[1].id, context: context))
        let lessons = db.lessons
        let overrides = db.overrides

        let monday = school.day(d("2026-10-12"))
        #expect(monday.cycleWeek == 2 && monday.cycleLabel == "B" && monday.isSchoolDay)
        #expect(monday.entries.map(\.status) == [.cancelled] && monday.entries[0].appliedOverrideIDs == [overrides[0].id])

        let tuesday = school.resolution(for: d("2026-10-13"))
        let patched = try #require(tuesday.schedule.entries.first)
        #expect(patched.source == .lesson(lessons[1].id) && patched.status == .modified)
        #expect(patched.room == "204" && patched.teacher == nil && patched.building == "A" && patched.bringList.isEmpty)
        #expect(tuesday.reasons(for: patched.id) == [.roomChanged, .teacherChanged])

        let wednesday = school.day(d("2026-10-14"))
        #expect(wednesday.scheduleTimes == ["10:00-10:45", "12:00-12:45"])
        #expect(wednesday.entries[0].status == .added && wednesday.entries[0].room == "Aula")
        #expect(wednesday.entries[0].id == .oneOff(overrides[2].id))

        let thursday = school.day(d("2026-10-15"))
        #expect(!thursday.isSchoolDay && thursday.cancellingOverrideID == overrides[3].id)
        #expect(thursday.scheduleTimes == ["08:00-09:40"] && thursday.entries[0].status == .cancelled)

        let shortMonday = school.resolution(for: d("2026-10-19"))
        #expect(shortMonday.schedule.scheduleTimes == ["08:00-08:30"] && shortMonday.schedule.entries[0].status == .modified)
        #expect(shortMonday.reasons(for: shortMonday.schedule.entries[0].id) == [.timeChanged])
        #expect(shortMonday.bellScheduleOverrideID == overrides[5].id)

        let following = school.resolution(for: d("2026-10-21"))
        #expect(following.schedule.dayKey == .weekday(.friday) && following.naturalDayKey == .weekday(.wednesday))
        #expect(following.schedule.cycleWeek == 2 && following.schedule.cycleLabel == "B")
        #expect(following.schedule.entries.map(\.source) == [.lesson(lessons[4].id)])
        #expect(following.schedule.scheduleTimes == ["08:00-08:45"], "Wednesday keeps its own bell schedule")
        #expect(following.schedule.entries[0].status == .scheduled && following.followDayOverrideID == overrides[6].id)

        #expect(school.day(d("2027-01-15")).entries.isEmpty && school.day(d("2027-01-15")).activeBreakID == db.breaks[1].id)
        #expect(school.day(d("2026-12-24")).activeBreakID == db.breaks[0].id)

        #expect(college.day(d("2026-09-02")).scheduleTimes == ["09:00-10:30"])
        let collegeThursday = college.day(d("2026-10-22"))
        #expect(collegeThursday.isSchoolDay && collegeThursday.dayKey == .cycleDay(2))
        #expect(collegeThursday.scheduleTimes == ["11:00-12:30"])

        #expect(ScheduleResolver(database: db, timetableID: Timetable.ID(uuidString: "00000000-0000-4000-8000-0000000000FF")!,
                                 context: context) == nil)
        var deleted = db
        deleted.timetables[0].meta.isDeleted = true
        #expect(ScheduleResolver(database: deleted, timetableID: db.timetables[0].id, context: context) == nil)
        #expect(ScheduleResolver.all(database: db, context: context).map(\.timetable.id) == [db.timetables[0].id, db.timetables[1].id])
        #expect(ScheduleResolver.all(database: deleted, context: context).map(\.timetable.id) == [db.timetables[1].id])
    }

    @Test func resultsAreDeterministicAndCodable() throws {
        var world = ScheduleWorld()
        world.lesson(world.math, .tuesday, period: 1, span: 2)
        world.lesson(world.physics, .tuesday, period: 2)
        world.override("2026-10-06", .addLesson(OneOffLesson(subjectID: world.english, slot: .period(world.p[4], span: 1))))
        let first = world.resolution("2026-10-06")
        #expect(first == world.resolution("2026-10-06"))
        #expect(try Fixture.roundTrip(first) == first)
        let range = LocalDateRange(start: d("2026-10-01"), end: d("2026-10-31"))
        let days = world.resolver.days(in: range)
        #expect(days.count == 31 && days.map(\.date) == Array(range.days))
        #expect(world.resolver.days(in: LocalDateRange(start: d("2026-10-02"), end: d("2026-10-01"))).isEmpty)
        // Input order does not matter.
        var reversed = world
        reversed.lessons.reverse()
        reversed.subjects.reverse()
        reversed.bellSchedules.reverse()
        #expect(reversed.resolution("2026-10-06") == first)
    }

    @Test func occurrencesInAnInterval() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        let physics = world.lesson(world.physics, .tuesday, period: 2)
        let english = world.lesson(world.english, .wednesday, period: 1)
        world.override("2026-10-06", .cancelLesson(physics))
        let resolver = world.resolver
        let twoDays = DateInterval(start: world.instant("2026-10-06", "00:00"), end: world.instant("2026-10-08", "00:00"))
        #expect(resolver.occurrences(in: twoDays).map(\.source) == [.lesson(math), .lesson(english)])
        #expect(resolver.occurrences(in: twoDays, includeCancelled: true).map(\.source) == [.lesson(math), .lesson(physics), .lesson(english)])
        let instant = world.instant("2026-10-06", "08:30")
        #expect(resolver.occurrences(in: DateInterval(start: instant, duration: 0)).map(\.source) == [.lesson(math)])
        let gap = DateInterval(start: world.instant("2026-10-06", "08:45"), end: world.instant("2026-10-06", "08:55"))
        #expect(resolver.occurrences(in: gap, includeCancelled: true).isEmpty, "half-open on both sides")
        let overlapStart = DateInterval(start: world.instant("2026-10-06", "08:44"), end: world.instant("2026-10-06", "08:56"))
        #expect(resolver.occurrences(in: overlapStart, includeCancelled: true).map(\.source) == [.lesson(math), .lesson(physics)])
        #expect(resolver.occurrences(in: twoDays, options: .regular).count == 3)
    }

    @Test func nextSchoolDay() {
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 1, bringList: ["Gym bag"])
        world.holiday("2026-10-26", "2026-10-30")
        let resolver = world.resolver
        #expect(resolver.nextSchoolDay(after: d("2026-10-09"))?.date == d("2026-10-12"))
        #expect(resolver.nextSchoolDay(after: d("2026-10-09"))?.entries.first?.bringList == ["Gym bag"])
        #expect(resolver.nextSchoolDay(after: d("2026-10-23"))?.date == d("2026-11-02"))
        #expect(resolver.nextSchoolDay(after: d("2026-10-23"), horizonDays: 5) == nil)
        #expect(resolver.nextSchoolDay(after: d("2026-10-23"), horizonDays: 0) == nil)
    }
}
