// UX overhaul stage U5b (editors): week rotation mapping (H8/D9), the field rule for editors (F06/D10), the bell
// schedule rows / usage / regeneration (R6), the occasional bell schedules and the day-change move (M15/M20).
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let now = Date(timeIntervalSince1970: 1_791_879_600)

private func apply(_ mutation: DatabaseMutation, to database: TabulaDatabase) throws -> TabulaDatabase {
    var clock = HybridLogicalClock(node: 0xB5)
    clock.receive(database.latestTimestamp, now: now)
    return try mutation.apply(to: database, clock: &clock, now: now)
}

private func errors(_ database: TabulaDatabase) -> [ValidationIssue] {
    database.validate().filter { $0.severity == .error }
}

private func time(_ hour: Int, _ minute: Int = 0) -> LocalTime { LocalTime(hour: hour, minute: minute)! }

@Suite("U5b week rotation (H8/D9)")
struct CycleWeekSelectionTests {
    private let scenario = SampleScenarios.secondary()
    private static let today = LocalDate(year: 2027, month: 2, day: 10)!

    @Test func styleDependsOnTheCycleLength() {
        #expect(CycleWeekSelection.style(length: 1) == nil)
        #expect(CycleWeekSelection.style(length: 2) == .segmented)
        #expect(CycleWeekSelection.style(length: 4) == .list)
        #expect(CycleWeekSelection.segments(length: 2) == [.everyWeek, .week(1), .week(2)])
    }

    /// Stored value -> draft -> control: nil, [1], [2] and [1, 2] (old builds could store "both weeks").
    @Test func storedWeeksMapToTheSegment() {
        #expect(CycleWeekSelection.segment(of: [], length: 2) == .everyWeek)
        #expect(CycleWeekSelection.segment(of: [1], length: 2) == .week(1))
        #expect(CycleWeekSelection.segment(of: [2], length: 2) == .week(2))
        #expect(CycleWeekSelection.segment(of: [1, 2], length: 2) == .everyWeek)
        #expect(CycleWeekSelection.segment(of: [3], length: 2) == .everyWeek)   // outside the cycle: every week
    }

    /// Control -> draft -> stored value, through `LessonDraft.makeLesson`, for every segment.
    @Test func segmentsRoundTripThroughTheModel() throws {
        let timetable = scenario.timetable
        guard case .weekCycle(let cycle) = timetable.rotation, cycle.length == 2 else {
            Issue.record("expected a two-week cycle"); return
        }
        let lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        for segment in CycleWeekSelection.segments(length: 2) {
            var draft = LessonDraft(lesson: lesson, timetable: timetable, today: Self.today)
            draft.cycleWeeks = CycleWeekSelection.weeks(for: segment)
            let made = try #require(draft.makeLesson(in: timetable))
            switch segment {
            case .everyWeek: #expect(made.occurrence.cycleWeeks == nil)
            case .week(let week): #expect(made.occurrence.cycleWeeks == [week])
            }
            // And back: the stored lesson opens on the same segment.
            let reopened = LessonDraft(lesson: made, timetable: timetable, today: Self.today)
            #expect(CycleWeekSelection.segment(of: reopened.cycleWeeks, length: 2) == segment)
        }
    }

    @Test func listStartsOnEveryWeekAndNeverHasTwoMeanings() {
        let length = 4
        var weeks = CycleWeekSelection.selectingEveryWeek()
        #expect(CycleWeekSelection.isEveryWeek(weeks, length: length))
        #expect(!CycleWeekSelection.isChecked(1, in: weeks, length: length))
        weeks = CycleWeekSelection.toggling(2, in: weeks, length: length)
        #expect(weeks == [2])
        weeks = CycleWeekSelection.toggling(4, in: weeks, length: length)
        #expect(weeks == [2, 4])
        #expect(CycleWeekSelection.isChecked(4, in: weeks, length: length))
        // Unchecking every week returns to "Every week" (not to an empty "no week" state).
        weeks = CycleWeekSelection.toggling(2, in: weeks, length: length)
        weeks = CycleWeekSelection.toggling(4, in: weeks, length: length)
        #expect(weeks.isEmpty && CycleWeekSelection.isEveryWeek(weeks, length: length))
        // Checking all weeks is the same as every week, and is shown so.
        for week in 1...length where week != 3 { weeks = CycleWeekSelection.toggling(week, in: weeks, length: length) }
        #expect(weeks == [1, 2, 4])
        weeks = CycleWeekSelection.toggling(3, in: weeks, length: length)
        #expect(weeks.isEmpty)
        #expect(CycleWeekSelection.toggling(9, in: [1], length: length) == [1])   // not a week of the cycle
    }

    @Test func listSelectionRoundTripsThroughTheModel() throws {
        var timetable = scenario.timetable
        timetable.rotation = .weekCycle(WeekCycle(length: 3, anchor: .referenceWeek(date: Self.today, cycleWeek: 1)))
        let lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        var draft = LessonDraft(lesson: lesson, timetable: timetable, today: Self.today)
        draft.cycleWeeks = CycleWeekSelection.toggling(3, in: draft.cycleWeeks, length: 3)
        draft.cycleWeeks = CycleWeekSelection.toggling(1, in: draft.cycleWeeks, length: 3)
        let made = try #require(draft.makeLesson(in: timetable))
        #expect(made.occurrence.cycleWeeks == [1, 3])
        let reopened = LessonDraft(lesson: made, timetable: timetable, today: Self.today)
        #expect(CycleWeekSelection.isChecked(1, in: reopened.cycleWeeks, length: 3))
        #expect(!CycleWeekSelection.isChecked(2, in: reopened.cycleWeeks, length: 3))
    }

    @Test func weekNamesAreFullPhrasesNotConcatenations() {
        #expect(CycleWeekSelection.name(of: 1, labels: ["A", "B"]) == .named("A"))
        #expect(CycleWeekSelection.name(of: 2, labels: ["Nepárny", "Párny"]) == .verbatim("Párny"))
        #expect(CycleWeekSelection.name(of: 2, labels: nil) == .numbered(2))
        #expect(CycleWeekSelection.name(of: 2, labels: ["A", " "]) == .numbered(2))
    }
}

@Suite("U5b field rule in editors (F06/D10)")
struct EditorFieldRuleD10Tests {
    private let scenario = SampleScenarios.secondary()
    private static let today = LocalDate(year: 2027, month: 2, day: 10)!

    @Test func editorsOfferEveryFieldWhateverTheDisplaySetting() {
        #expect(EditorFieldPolicy.editorFields == LessonField.knownValues)
        #expect(!EditorFieldPolicy.moreDetailsStartsExpanded(texts: ["", "  "], lessonType: nil, bringList: [" "]))
        #expect(EditorFieldPolicy.moreDetailsStartsExpanded(texts: ["", "301"], lessonType: nil, bringList: []))
        #expect(EditorFieldPolicy.moreDetailsStartsExpanded(texts: [], lessonType: .lecture, bringList: []))
        #expect(EditorFieldPolicy.moreDetailsStartsExpanded(texts: [], lessonType: nil, bringList: ["kit"]))
    }

    /// Astra F06 acceptance: hide Room in summaries, edit the lesson's room, show Room again: the new value is there.
    @Test func hiddenFieldIsStillEditedAndKept() throws {
        var timetable = scenario.timetable
        timetable.fieldVisibility = FieldVisibility([.notes])          // room, teacher … hidden in summaries
        var lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        lesson.teacher = "Mgr. X"
        var draft = LessonDraft(lesson: lesson, timetable: timetable, today: Self.today)
        #expect(draft.teacher == "Mgr. X")                              // the hidden value is loaded for editing
        draft.room = "  301 "
        let made = try #require(draft.makeLesson(in: timetable))
        #expect(made.room == "301")
        #expect(made.teacher == "Mgr. X")                               // untouched hidden value is kept
        timetable.fieldVisibility = .all                                // show Room again
        #expect(LessonDraft(lesson: made, timetable: timetable, today: Self.today).room == "301")
        let stored = try apply(.upsert(made), to: scenario.database)
        #expect(errors(stored).isEmpty)
    }

    @Test func changingVisibilityNeverChangesStoredValues() throws {
        let lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        var hidden = scenario.timetable
        hidden.fieldVisibility = FieldVisibility()
        var shown = scenario.timetable
        shown.fieldVisibility = .all
        let a = try #require(LessonDraft(lesson: lesson, timetable: hidden, today: Self.today).makeLesson(in: hidden))
        let b = try #require(LessonDraft(lesson: lesson, timetable: shown, today: Self.today).makeLesson(in: shown))
        #expect(a == b)
    }

    /// Nested "New Subject" from the lesson editor: selecting the new subject keeps the rest of the draft and fills
    /// only empty fields with the subject's defaults.
    @Test func subjectCreatedFromTheLessonEditorKeepsTheDraft() throws {
        var timetable = scenario.timetable
        timetable.fieldVisibility = FieldVisibility()                   // D10: defaults apply anyway
        let period = SlotDraft.lessonPeriods(of: scenario.regularBell)[3]
        var draft = LessonDraft(newIn: timetable,
                                context: NewLessonContext(day: .weekday(.thursday), slot: .period(period.id, span: 1)),
                                schedule: scenario.regularBell, subject: nil, firstWeekday: .monday,
                                id: Lesson.ID(UUID()), today: Self.today)
        draft.room = "Lab 2"
        draft.notes = "Bring goggles"
        var subject = try #require(scenario.database.subjects.first)
        subject.id = Subject.ID(UUID())
        subject.defaultRoom = "B12"
        subject.defaultTeacher = "Ing. Y"
        draft.subjectID = subject.id
        draft.applySubjectDefaults(subject)
        #expect(draft.room == "Lab 2")                                  // typed value wins
        #expect(draft.teacher == "Ing. Y")                              // empty field gets the default
        #expect(draft.notes == "Bring goggles")
        #expect(draft.day == .weekday(.thursday) && draft.slot.periodID == period.id)
        #expect(draft.hasOptionalDetails)
    }
}

@Suite("U5b bell schedule editor (C1/R6)")
struct BellScheduleU5bTests {
    private let scenario = SampleScenarios.secondary()

    private func draft() -> BellSetDraft {
        BellSetDraft(timetable: scenario.timetable, schedules: scenario.database.bellSchedules,
                     defaultScheduleName: "Regular", ids: { BellSchedule.ID(UUID()) })
    }

    @Test func occasionalSchedulesAreLoadedAndKept() throws {
        let draft = draft()
        let short = try #require(draft.entry(scenario.shortBell.id))   // used by a day change, no weekday
        #expect(short.weekdays.isEmpty && !short.isNew)
        let stored = try draft.mutations(for: scenario.timetable).reduce(scenario.database) { try apply($1, to: $0) }
        #expect(errors(stored).isEmpty)
        #expect(stored.bellSchedules.first { $0.id == scenario.shortBell.id }?.isDeleted == false)
        let timetable = try #require(stored.timetables.first { $0.id == scenario.timetable.id })
        #expect(timetable.timeStructure == scenario.timetable.timeStructure)
    }

    @Test func newScheduleWithoutWeekdaysIsStoredAndCanBeAssigned() throws {
        var draft = draft()
        let id = BellSchedule.ID(UUID())
        draft.addSchedule(copying: draft.defaultEntry.id, name: "Exam day", id: id)
        #expect(draft.entry(id)?.periods.map(\.id) == draft.defaultEntry.periods.map(\.id))
        let stored = try draft.mutations(for: scenario.timetable).reduce(scenario.database) { try apply($1, to: $0) }
        #expect(stored.bellSchedules.contains { $0.id == id && !$0.isDeleted })
        let timetable = try #require(stored.timetables.first { $0.id == scenario.timetable.id })
        #expect(timetable.timeStructure.bellScheduleID(for: .monday) == scenario.regularBell.id)
        // Assigning a weekday makes it a weekday variant; removing the weekday keeps the schedule.
        var next = BellSetDraft(timetable: timetable, schedules: stored.bellSchedules, defaultScheduleName: "x",
                                ids: { BellSchedule.ID(UUID()) })
        next.assign([.friday], to: id)
        let assigned = try next.mutations(for: timetable).reduce(stored) { try apply($1, to: $0) }
        let withFriday = try #require(assigned.timetables.first { $0.id == timetable.id })
        #expect(withFriday.timeStructure.bellScheduleID(for: .friday) == id)
        var again = BellSetDraft(timetable: withFriday, schedules: assigned.bellSchedules, defaultScheduleName: "x",
                                 ids: { BellSchedule.ID(UUID()) })
        again.assign([], to: id)
        let unassigned = try again.mutations(for: withFriday).reduce(assigned) { try apply($1, to: $0) }
        #expect(unassigned.bellSchedules.contains { $0.id == id && !$0.isDeleted })
        #expect(errors(unassigned).isEmpty)
    }

    @Test func blankScheduleNameBlocksSaving() {
        var draft = draft()
        draft.rename(draft.defaultEntry.id, to: "  ")
        #expect(draft.hasBlankName && draft.hasBlockingIssues)
    }

    @Test func rowsNumberLessonsAndComputeBreaks() {
        let p1 = Period(id: Period.ID(UUID()), start: time(8), end: time(8, 45))
        let p2 = Period(id: Period.ID(UUID()), start: time(8, 55), end: time(9, 40))
        let lunch = Period(id: Period.ID(UUID()), start: time(9, 40), end: time(10, 10), kind: .lunch)
        let p3 = Period(id: Period.ID(UUID()), start: time(10, 30), end: time(11, 15))
        let entry = BellSetDraft.Entry(id: BellSchedule.ID(UUID()), name: "x", periods: [p3, lunch, p1, p2],
                                       weekdays: [], isNew: true)
        let rows = BellSetDraft.rows(of: entry)
        #expect(rows.map(\.id) == [p1.id, p2.id, lunch.id, p3.id])
        #expect(rows.map(\.ordinal) == [1, 2, nil, 3])
        #expect(rows.map(\.gapAfterMinutes) == [10, nil, 20, nil])
    }

    @Test func usageCountsLessonsAndDayChanges() throws {
        let usage = BellSetDraft.periodUsage(lessons: scenario.database.lessons, overrides: scenario.database.overrides,
                                             timetableID: scenario.timetable.id)
        let locked = BellSetDraft.lockedPeriods(lessons: scenario.database.lessons, timetableID: scenario.timetable.id)
        #expect(locked.isSubset(of: Set(usage.keys)))
        #expect(usage.values.reduce(0, +) >= locked.count)
        let schedules = BellSetDraft.scheduleUsage(overrides: scenario.database.overrides, timetableID: scenario.timetable.id)
        #expect(schedules[scenario.shortBell.id] == 1)
        #expect(schedules[scenario.regularBell.id] == nil)
    }

    @Test func regenerationReadsTheScheduleAndKeepsPeriodIDs() throws {
        var draft = draft()
        let before = BellSetDraft.rows(of: draft.defaultEntry).filter { $0.ordinal != nil }.map(\.period)
        var regeneration = BellRegeneration(entry: draft.defaultEntry)
        #expect(regeneration.firstStart == before[0].start)
        #expect(regeneration.lessonMinutes == before[0].end.minuteOfDay - before[0].start.minuteOfDay)
        #expect(regeneration.lessonCount == before.count)
        #expect(regeneration.preview.map(\.start) == before.map(\.start))   // the sample was generated the same way
        regeneration.lessonMinutes = 40
        regeneration.lessonCount = before.count + 1
        var fresh: [Period.ID] = []
        draft.regenerate(draft.defaultEntry.id, with: regeneration, inUse: [], newID: {
            let id = Period.ID(UUID()); fresh.append(id); return id
        })
        let after = BellSetDraft.rows(of: draft.defaultEntry).map(\.period)
        #expect(after.count == before.count + 1 && fresh.count == 1)
        #expect(Array(after.prefix(before.count)).map(\.id) == before.map(\.id))   // lessons keep their periods
        #expect(after.allSatisfy { $0.end.minuteOfDay - $0.start.minuteOfDay == 40 })
        let stored = try draft.mutations(for: scenario.timetable).reduce(scenario.database) { try apply($1, to: $0) }
        #expect(errors(stored).isEmpty)
    }

    @Test func regenerationNeverDropsAPeriodInUse() throws {
        var draft = draft()
        let lessons = BellSetDraft.rows(of: draft.defaultEntry).filter { $0.ordinal != nil }.map(\.period)
        let used: Set<Period.ID> = [lessons[4].id]
        #expect(BellRegeneration.minimumCount(of: draft.defaultEntry, inUse: used) == 5)
        var regeneration = BellRegeneration(entry: draft.defaultEntry)
        regeneration.lessonCount = 3                                          // below the minimum: kept anyway
        draft.regenerate(draft.defaultEntry.id, with: regeneration, inUse: used, newID: { Period.ID(UUID()) })
        #expect(draft.defaultEntry.periods.contains { $0.id == lessons[4].id })
        #expect(!draft.defaultEntry.periods.contains { $0.id == lessons[5].id })
    }
}

@Suite("U5b day change (M15/M20, D10)")
struct DayChangeU5bTests {
    private let scenario = SampleScenarios.secondary()

    private func draft(lessonID: Lesson.ID) -> DayChangeDraft {
        DayChangeDraft(timetable: scenario.timetable, date: scenario.overrideDate, lessonID: lessonID,
                       schedule: scenario.regularBell, id: ScheduleOverride.ID(UUID()))
    }

    @Test func moveSubstituteAndNoteBuildOnePatch() throws {
        let lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        var draft = draft(lessonID: lesson.id)
        #expect(draft.issues == [.nothingChanged])
        draft.setMoves(true, lessonSlot: lesson.slot)
        #expect(draft.movedSlot == SlotDraft(slot: lesson.slot))
        let later = SlotDraft.lessonPeriods(of: scenario.regularBell)[6]
        draft.movedSlot.periodID = later.id
        draft.teacher = " Mgr. Novák "                                    // D10: offered whatever the display setting
        draft.lessonNote = "Gym"
        let override = try #require(draft.makeOverride())
        #expect(override.change == .modifyLesson(lesson.id, LessonPatch(slot: .period(later.id, span: 1),
                                                                         teacher: "Mgr. Novák", notes: "Gym")))
        let stored = try apply(.upsert(override), to: scenario.database)
        #expect(errors(stored).isEmpty)
    }

    @Test func invalidMovedTimesBlockAndOtherLessonResetsTheMove() throws {
        let lesson = try #require(scenario.database.lessons.first { !$0.isDeleted })
        var draft = draft(lessonID: lesson.id)
        draft.setMoves(true, lessonSlot: .time(start: time(9), end: time(9, 45)))
        draft.movedSlot.end = draft.movedSlot.start
        #expect(draft.slotIssues == [.endBeforeStart] && !draft.canSave)
        let other = try #require(scenario.database.lessons.first { !$0.isDeleted && $0.id != lesson.id })
        draft.selectLesson(other.id)
        #expect(!draft.moves && draft.slotIssues.isEmpty)
    }

    @Test func extraLessonKeepsEveryOfferedField() throws {
        var draft = draft(lessonID: scenario.database.lessons[0].id)
        draft.kind = .extraLesson
        draft.extraSubjectID = scenario.database.subjects[0].id
        draft.extraBuilding = " B "
        draft.extraNotes = "Project"
        let override = try #require(draft.makeOverride())
        guard case .addLesson(let oneOff) = override.change else { Issue.record("addLesson"); return }
        #expect(oneOff.building == "B" && oneOff.notes == "Project" && oneOff.room == nil)
    }
}
