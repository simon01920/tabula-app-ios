import Foundation
import Testing
@testable import TimetableCore

@Suite("ScheduleResolver — overrides")
struct OverrideStackingTests {
    private let d = Fixture.date
    private static let t0 = ScheduleWorld.baseMillis

    @Test func cancelLessonKeepsTheOccurrenceStruckThrough() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        let physics = world.lesson(world.physics, .tuesday, period: 2)
        let cancel = world.override("2026-10-06", .cancelLesson(math))
        let day = world.day("2026-10-06")
        #expect(day.isSchoolDay && day.entries.map(\.status) == [.cancelled, .scheduled])
        #expect(day.entry(math)?.appliedOverrideIDs == [cancel] && day.entry(physics)?.appliedOverrideIDs == [])
        #expect(day.entry(math)?.id == .lesson(math, on: d("2026-10-06")))
        #expect(world.day("2026-10-13").entries.map(\.status) == [.scheduled, .scheduled], "one date only")
    }

    @Test func modifyLessonPatchesFieldsAndReportsReasons() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1, teacher: "Kováč")
        let patch = LessonPatch(room: "305", building: "B", teacher: "", lessonType: .seminar, notes: "Test today",
                                bringList: ["Calculator", " "])
        let modify = world.override("2026-10-06", .modifyLesson(math, patch))
        let resolution = world.resolution("2026-10-06")
        let entry = resolution.schedule.entries[0]
        #expect(entry.status == .modified && entry.appliedOverrideIDs == [modify] && entry.id == .lesson(math, on: d("2026-10-06")))
        #expect(entry.room == "305" && entry.building == "B" && entry.teacher == nil, "empty patch value clears, no subject fallback")
        #expect(entry.lessonType == .seminar && entry.notes == "Test today" && entry.bringList == ["Calculator"])
        #expect(resolution.reasons(for: entry.id) == [.roomChanged, .buildingChanged, .teacherChanged, .lessonTypeChanged,
                                                      .notesChanged, .bringListChanged])
        #expect(resolution.changes.count == 1)
    }

    @Test func aPatchThatChangesNothingKeepsScheduled() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        let modify = world.override("2026-10-06", .modifyLesson(math, LessonPatch(slot: .period(world.p[0], span: 1), room: "101")))
        let resolution = world.resolution("2026-10-06")
        #expect(resolution.schedule.entries[0].status == .scheduled && resolution.changes.isEmpty)
        #expect(resolution.schedule.entries[0].appliedOverrideIDs == [modify])
    }

    @Test func laterPatchesWinFieldByField() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        // Inserted newest first: the engine must order by updatedAt, not by array order.
        let newer = world.override("2026-10-06", .modifyLesson(math, LessonPatch(room: "A1", teacher: "T1")), updatedAt: Self.t0 + 2000)
        let older = world.override("2026-10-06", .modifyLesson(math, LessonPatch(room: "B1", notes: "N")), updatedAt: Self.t0 + 1000)
        let entry = world.day("2026-10-06").entries[0]
        #expect(entry.room == "A1" && entry.teacher == "T1" && entry.notes == "N")
        #expect(entry.appliedOverrideIDs == [newer, older].sorted())
    }

    @Test func cancelAndModifyReplayInUpdatedAtOrder() {
        var revived = ScheduleWorld()
        let lesson = revived.lesson(revived.math, .tuesday, period: 1)
        revived.override("2026-10-06", .cancelLesson(lesson), updatedAt: Self.t0 + 1000)
        revived.override("2026-10-06", .modifyLesson(lesson, LessonPatch(room: "9")), updatedAt: Self.t0 + 2000)
        #expect(revived.day("2026-10-06").entries[0].status == .modified, "a later modify revives an earlier cancel")

        var cancelled = ScheduleWorld()
        let other = cancelled.lesson(cancelled.math, .tuesday, period: 1)
        cancelled.override("2026-10-06", .cancelLesson(other), updatedAt: Self.t0 + 2000)
        cancelled.override("2026-10-06", .modifyLesson(other, LessonPatch(room: "9")), updatedAt: Self.t0 + 1000)
        let resolution = cancelled.resolution("2026-10-06")
        let entry = resolution.schedule.entries[0]
        #expect(entry.status == .cancelled && entry.room == "9")
        #expect(resolution.reasons(for: entry.id) == [.roomChanged], "reasons are kept for a cancelled, patched occurrence")
        #expect(resolution.schedule.conflicts.isEmpty)
    }

    @Test func cancelDayCancelsRegularLessonsButNotAddedOnes() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        let physics = world.lesson(world.physics, .tuesday, period: 2)
        let first = world.override("2026-10-06", .cancelDay(note: "Sports day"), updatedAt: Self.t0 + 1000)
        let second = world.override("2026-10-06", .cancelDay(note: nil), updatedAt: Self.t0 + 3000)
        world.override("2026-10-06", .modifyLesson(physics, LessonPatch(room: "Gym")), updatedAt: Self.t0 + 5000)
        let event = world.override("2026-10-06", .addLesson(OneOffLesson(
            subjectID: world.english, slot: .time(start: Fixture.time("08:00"), end: Fixture.time("12:00")), notes: "Sports day")))
        let day = world.day("2026-10-06")
        #expect(!day.isSchoolDay && day.cancellingOverrideID == second && day.dayKey == .weekday(.tuesday))
        #expect(day.entry(math)?.status == .cancelled && day.entry(physics)?.status == .cancelled, "cancelDay wins over a later modify")
        #expect(day.entry(math)?.appliedOverrideIDs == [first, second].sorted())
        #expect(day.entry(oneOff: event)?.status == .added && day.entry(oneOff: event)?.room == "201")
        #expect(day.entry(oneOff: event)?.appliedOverrideIDs == [event] && day.entry(oneOff: event)?.id == .oneOff(event))
        #expect(day.conflicts.isEmpty, "cancelled occurrences do not overlap the added event")
    }

    @Test func useBellScheduleMovesPeriodLessonsOnly() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .monday, period: 2)
        let club = world.lesson(world.physics, .weekday(.monday), .time(start: Fixture.time("15:00"), end: Fixture.time("16:00")))
        let use = world.override("2026-10-05", .useBellSchedule(world.shortID))
        let resolution = world.resolution("2026-10-05")
        #expect(resolution.schedule.bellScheduleID == world.shortID && resolution.bellScheduleOverrideID == use)
        let moved = resolution.schedule.entry(math)!
        #expect("\(moved.startTime)-\(moved.endTime)" == "08:40-09:10" && moved.status == .modified)
        #expect(moved.appliedOverrideIDs == [use] && resolution.reasons(for: moved.id) == [.timeChanged])
        let kept = resolution.schedule.entry(club)!
        #expect(kept.status == .scheduled && kept.appliedOverrideIDs.isEmpty)
    }

    @Test func useBellScheduleWithIdenticalTimesKeepsScheduled() {
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 3)
        let copy = world.bellSchedule(world.bellSchedules[0].periods)
        let use = world.override("2026-10-05", .useBellSchedule(copy))
        let entry = world.day("2026-10-05").entries[0]
        #expect(entry.status == .scheduled && entry.appliedOverrideIDs == [use])
    }

    @Test func aMissingBellScheduleOverrideFallsBackToTheNaturalOne() {
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 1)
        let missing: BellSchedule.ID = world.ids.next()
        let use = world.override("2026-10-05", .useBellSchedule(missing))
        let resolution = world.resolution("2026-10-05")
        #expect(resolution.schedule.bellScheduleID == world.normalID && resolution.bellScheduleOverrideID == nil)
        #expect(resolution.schedule.scheduleTimes == ["08:00-08:45"] && resolution.schedule.entries[0].status == .scheduled)
        #expect(resolution.warnings == [ResolutionWarning(kind: .missingBellSchedule, date: d("2026-10-05"), overrideID: use,
                                                          bellScheduleID: missing)])
    }

    @Test func followDayRunsAnotherDaysLessonsWithTheDatesBells() {
        var world = ScheduleWorld()
        world.lesson(world.math, .wednesday, period: 1)
        let friday = world.lesson(world.physics, .friday, period: 3)
        let follow = world.override("2026-10-07", .followDay(.weekday(.friday), cycleWeek: nil))
        let resolution = world.resolution("2026-10-07")
        let day = resolution.schedule
        #expect(day.dayKey == .weekday(.friday) && resolution.naturalDayKey == .weekday(.wednesday))
        #expect(resolution.followDayOverrideID == follow && day.bellScheduleID == world.normalID)
        #expect(day.entries.map(\.source) == [.lesson(friday)] && day.scheduleTimes == ["10:00-10:45"])
        #expect(day.entries[0].status == .scheduled && day.entries[0].appliedOverrideIDs == [follow])
        #expect(day.entries[0].id == .lesson(friday, on: d("2026-10-07")))
        // Stacking useBellSchedule gives the followed day's times as well.
        let use = world.override("2026-10-07", .useBellSchedule(world.shortID))
        let stacked = world.resolution("2026-10-07")
        #expect(stacked.schedule.scheduleTimes == ["09:20-09:50"] && stacked.schedule.entries[0].status == .modified)
        #expect(stacked.schedule.entries[0].appliedOverrideIDs == [follow, use].sorted())
    }

    @Test func followDayPicksTheCycleWeek() {
        var world = ScheduleWorld(rotation: .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0),
                                                                 labels: ["A", "B"])))
        let weekA = world.lesson(world.math, .monday, period: 1, weeks: [1])
        let weekB = world.lesson(world.physics, .monday, period: 1, weeks: [2])
        world.override("2026-10-05", .followDay(.weekday(.monday), cycleWeek: 2))
        let resolution = world.resolution("2026-10-05")
        #expect(resolution.schedule.cycleWeek == 2 && resolution.schedule.cycleLabel == "B" && resolution.naturalCycleWeek == 1)
        #expect(resolution.schedule.entries.map(\.source) == [.lesson(weekB)])
        world.override("2026-10-19", .followDay(.weekday(.monday), cycleWeek: 5)) // out of range → own week
        #expect(world.day("2026-10-19").entries.map(\.source) == [.lesson(weekA)])
        #expect(world.day("2026-10-19").cycleWeek == 1)
    }

    @Test func followDayMakesMakeUpDaysEvenInBreaks() {
        var world = ScheduleWorld()
        let monday = world.lesson(world.math, .monday, period: 1)
        world.override("2026-10-10", .followDay(.weekday(.monday), cycleWeek: nil)) // Saturday
        let saturday = world.day("2026-10-10")
        #expect(saturday.isSchoolDay && saturday.entries.map(\.source) == [.lesson(monday)])
        let autumn = world.holiday("2026-10-26", "2026-10-30")
        world.override("2026-10-28", .followDay(.weekday(.monday), cycleWeek: nil))
        let inBreak = world.day("2026-10-28")
        #expect(inBreak.isSchoolDay && inBreak.activeBreakID == autumn && inBreak.entries.count == 1)
    }

    @Test func theLatestFollowDayWins() {
        var world = ScheduleWorld()
        world.lesson(world.math, .monday, period: 1)
        let friday = world.lesson(world.physics, .friday, period: 1)
        let late = world.override("2026-10-07", .followDay(.weekday(.friday), cycleWeek: nil), updatedAt: Self.t0 + 2000)
        let early = world.override("2026-10-07", .followDay(.weekday(.monday), cycleWeek: nil), updatedAt: Self.t0 + 1000)
        let resolution = world.resolution("2026-10-07")
        #expect(resolution.schedule.entries.map(\.source) == [.lesson(friday)] && resolution.followDayOverrideID == late)
        #expect(resolution.warnings == [ResolutionWarning(kind: .supersededOverride, date: d("2026-10-07"), overrideID: early,
                                                          supersededByID: late)])
        // Equal timestamps: the larger ID wins (deterministic).
        var tie = ScheduleWorld()
        tie.lesson(tie.math, .monday, period: 1)
        tie.lesson(tie.physics, .friday, period: 1)
        let a = tie.override("2026-10-07", .followDay(.weekday(.friday), cycleWeek: nil))
        let b = tie.override("2026-10-07", .followDay(.weekday(.monday), cycleWeek: nil))
        #expect(tie.resolution("2026-10-07").followDayOverrideID == max(a, b))
        // Same rule for bell schedules.
        let bellLate = world.override("2026-10-08", .useBellSchedule(world.shortID), updatedAt: Self.t0 + 9000)
        world.override("2026-10-08", .useBellSchedule(world.normalID), updatedAt: Self.t0 + 8000)
        #expect(world.resolution("2026-10-08").bellScheduleOverrideID == bellLate)
    }

    @Test func mismatchedUnknownAndStrayOverridesAreReported() {
        var world = ScheduleWorld()
        let monday = world.lesson(world.math, .monday, period: 1)
        world.lesson(world.math, .tuesday, period: 1)
        let mismatch = world.override("2026-10-07", .followDay(.cycleDay(1), cycleWeek: nil))
        let unknown = world.override("2026-10-06", .unknown(.object(["kind": .string("swapRooms")])))
        let stray = world.override("2026-10-06", .cancelLesson(monday))
        let wednesday = world.resolution("2026-10-07")
        #expect(wednesday.schedule.entries.isEmpty && wednesday.schedule.isSchoolDay)
        #expect(wednesday.warnings == [ResolutionWarning(kind: .followDayKindMismatch, date: d("2026-10-07"), overrideID: mismatch)])
        let tuesday = world.resolution("2026-10-06")
        #expect(tuesday.schedule.entries.map(\.status) == [.scheduled])
        #expect(tuesday.warnings == [
            ResolutionWarning(kind: .unknownOverride, date: d("2026-10-06"), overrideID: unknown),
            ResolutionWarning(kind: .overrideTargetNotScheduled, date: d("2026-10-06"), lessonID: monday, overrideID: stray),
        ])
        #expect(tuesday.warnings.map(\.message.key) == ["schedule.warning.unknownOverride", "schedule.warning.overrideTargetNotScheduled"])
    }

    @Test func patchedSlotAndSubstituteSubject() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        world.override("2026-10-06", .modifyLesson(math, LessonPatch(subjectID: world.english, slot: .period(world.p[4], span: 1))))
        let resolution = world.resolution("2026-10-06")
        let entry = resolution.schedule.entries[0]
        #expect(entry.subject.id == world.english && "\(entry.startTime)" == "12:20" && entry.periodNumber == 5)
        #expect(entry.room == "201" && entry.teacher == nil && entry.building == nil, "the substitute subject's defaults apply")
        #expect(resolution.reasons(for: entry.id) == [.timeChanged, .subjectChanged, .roomChanged, .buildingChanged, .teacherChanged])

        var missing = ScheduleWorld()
        let lesson = missing.lesson(missing.math, .tuesday, period: 1)
        let ghost: Subject.ID = missing.ids.next()
        missing.override("2026-10-06", .modifyLesson(lesson, LessonPatch(subjectID: ghost, room: "7")))
        let fallback = missing.resolution("2026-10-06")
        let kept = fallback.schedule.entries[0]
        #expect(kept.subject.id == missing.math && kept.room == "7" && kept.status == .modified)
        #expect(fallback.schedule.conflicts.map(\.kind) == [.missingSubject])
        #expect(fallback.warnings.map(\.kind) == [.missingSubject] && fallback.warnings[0].subjectID == ghost)
    }

    @Test func oneOffLessonsUseTheEffectiveSchedule() {
        var world = ScheduleWorld()
        let use = world.override("2026-10-05", .useBellSchedule(world.shortID))
        let extra = world.override("2026-10-05", .addLesson(OneOffLesson(subjectID: world.physics, slot: .period(world.p[1], span: 2),
                                                                          room: "Aula", bringList: ["Lab coat"])))
        let ghost: Subject.ID = world.ids.next()
        let broken = world.override("2026-10-05", .addLesson(OneOffLesson(subjectID: ghost, slot: .period(world.p[0], span: 1))))
        let resolution = world.resolution("2026-10-05")
        let entry = resolution.schedule.entry(oneOff: extra)!
        #expect("\(entry.startTime)-\(entry.endTime)" == "08:40-09:50" && entry.periodSpan == 2 && entry.status == .added)
        #expect(entry.appliedOverrideIDs == [use, extra].sorted() && entry.bringList == ["Lab coat"] && entry.room == "Aula")
        #expect(resolution.schedule.entry(oneOff: broken) == nil)
        #expect(resolution.schedule.conflicts == [Conflict(kind: .missingSubject, date: d("2026-10-05"), occurrenceIDs: [.oneOff(broken)])])
        // An added lesson on a weekend appears, but the day stays a non-school day.
        let saturdayEvent = world.override("2026-10-10", .addLesson(OneOffLesson(subjectID: world.math,
                                                                                 slot: .time(start: Fixture.time("09:00"), end: Fixture.time("11:00")))))
        let saturday = world.day("2026-10-10")
        #expect(!saturday.isSchoolDay && saturday.entries.map(\.id) == [.oneOff(saturdayEvent)])
    }

    @Test func regularOptionsAndForeignOrDeletedOverridesAreIgnored() {
        var world = ScheduleWorld()
        let math = world.lesson(world.math, .tuesday, period: 1)
        world.override("2026-10-06", .cancelDay(note: nil))
        #expect(world.day("2026-10-06", options: .regular).entries.map(\.status) == [.scheduled])
        #expect(world.day("2026-10-06", options: .regular).isSchoolDay)
        world.overrides[0].meta.isDeleted = true
        #expect(world.day("2026-10-06").isSchoolDay)
        world.overrides.append(ScheduleOverride(id: world.ids.next(), meta: ScheduleWorld.meta(), timetableID: world.ids.next(),
                                                date: d("2026-10-06"), change: .cancelLesson(math)))
        #expect(world.day("2026-10-06").entries.map(\.status) == [.scheduled], "another timetable's override")
    }

    @Test func fullStackOnOneDate() {
        var world = ScheduleWorld()
        world.lesson(world.math, .wednesday, period: 1) // replaced by Friday's lessons
        let fri1 = world.lesson(world.math, .friday, period: 1)
        let fri2 = world.lesson(world.physics, .friday, period: 2)
        let fri3 = world.lesson(world.english, .friday, period: 3)
        let follow = world.override("2026-10-07", .followDay(.weekday(.friday), cycleWeek: nil))
        let use = world.override("2026-10-07", .useBellSchedule(world.shortID))
        let cancel = world.override("2026-10-07", .cancelLesson(fri2))
        let modify = world.override("2026-10-07", .modifyLesson(fri3, LessonPatch(room: "Library")))
        let add = world.override("2026-10-07", .addLesson(OneOffLesson(subjectID: world.physics, slot: .period(world.p[3], span: 1))))
        let resolution = world.resolution("2026-10-07")
        let day = resolution.schedule
        #expect(day.dayKey == .weekday(.friday) && day.bellScheduleID == world.shortID && day.isSchoolDay)
        #expect(day.scheduleTimes == ["08:00-08:30", "08:40-09:10", "09:20-09:50", "10:00-10:30"])
        #expect(day.entries.map(\.status) == [.modified, .cancelled, .modified, .added])
        #expect(day.entry(fri1)?.appliedOverrideIDs == [follow, use].sorted())
        #expect(day.entry(fri2)?.appliedOverrideIDs == [follow, use, cancel].sorted())
        #expect(day.entry(fri3)?.appliedOverrideIDs == [follow, use, modify].sorted() && day.entry(fri3)?.room == "Library")
        #expect(day.entry(oneOff: add)?.appliedOverrideIDs == [use, add].sorted())
        #expect(resolution.reasons(for: .lesson(fri3, on: d("2026-10-07"))) == [.timeChanged, .roomChanged])
        #expect(resolution.warnings.isEmpty && day.conflicts.isEmpty)
    }
}
