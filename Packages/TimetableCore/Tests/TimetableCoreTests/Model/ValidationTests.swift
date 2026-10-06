import Foundation
import Testing
@testable import TimetableCore

@Suite("TabulaDatabase.validate()")
struct ValidationTests {
    private let base = Fixture.fullDatabase()

    private func issues(_ db: TabulaDatabase, _ code: ValidationIssue.Code) -> [ValidationIssue] {
        db.validate().filter { $0.code == code }
    }

    private func index<T: SyncEntity>(_ items: [T], where predicate: (T) -> Bool) -> Int {
        guard let index = items.firstIndex(where: predicate) else { fatalError("fixture changed") }
        return index
    }

    private var school: Timetable { base.timetables[0] }
    private var college: Timetable { base.timetables[1] }
    private var mondayLesson: Int { index(base.lessons) { $0.occurrence.day == .weekday(.monday) } }

    // MARK: Baseline

    @Test func fixtureIsClean() {
        #expect(base.validate().isEmpty, "\(base.validate())")
        #expect(base.isValid)
    }

    @Test func deterministicOrderAndMessages() {
        var db = base
        db.lessons[mondayLesson].subjectID = Subject.ID(uuidString: "00000000-0000-4000-8000-0000000000AA")!
        db.terms[0].range = LocalDateRange(start: Fixture.date("2027-01-01"), end: Fixture.date("2026-01-01"))
        var shuffled = db
        var rng = TestRNG(seed: 3)
        shuffled.lessons.shuffle(using: &rng)
        shuffled.timetables.shuffle(using: &rng)
        #expect(db.validate() == shuffled.validate())
        let issue = db.validate().first { $0.code == .danglingReference }!
        #expect(issue.message.key == "validation.danglingReference")
        #expect(issue.message.args == [.text(LocalizedText(key: "entityType.lesson")), .string("subjectID"), .string("")])
        #expect(issue.description.contains("danglingReference lesson"))
        #expect(ValidationIssue.Severity.info < .warning && ValidationIssue.Severity.warning < .error)
    }

    // MARK: One test per issue code

    @Test func unsupportedSchemaVersion() {
        var db = base
        db.schemaVersion = 2
        let found = issues(db, .unsupportedSchemaVersion)
        #expect(found.count == 1 && found[0].severity == .error && found[0].value == "2")
    }

    @Test func duplicateID() {
        var db = base
        db.lessons.append(db.lessons[0])                                   // same entity twice
        var clash = db.subjects[0]
        clash.id = db.lessons[1].id.retyped()                              // UUID reused across types
        db.subjects.append(clash)
        let taskIndex = index(db.tasks) { !$0.subtasks.isEmpty }
        db.tasks[taskIndex].subtasks[1].id = db.tasks[taskIndex].subtasks[0].id  // child clash
        db.bellSchedules[0].periods[1].id = db.bellSchedules[0].periods[0].id   // period clash
        let found = issues(db, .duplicateID)
        #expect(found.count == 4)
        #expect(found.allSatisfy { $0.severity == .error })
        #expect(found.contains { $0.entityType == .task && $0.childID != nil })
        #expect(found.contains { $0.entityType == .bellSchedule && $0.field == "periods" })
        // Subjects are listed before lessons, so the later lesson is the one reported for the cross-type clash.
        #expect(found.contains { $0.entityType == .lesson && $0.entityID == db.lessons[1].id.uuid })
        #expect(found.contains { $0.entityType == .lesson && $0.entityID == db.lessons[0].id.uuid })
    }

    @Test func danglingReference() {
        var ids = SequentialIDGenerator(namespace: 0xBAD)
        var db = base
        let missing: Subject.ID = ids.next()
        db.lessons[mondayLesson].subjectID = missing
        db.settings.activeTimetableID = ids.next()
        db.tasks[0].linkedLesson = LessonLink(lessonID: ids.next(), date: Fixture.date("2026-10-07"))
        let overrideIndex = index(db.overrides) { if case .cancelLesson = $0.change { return true } else { return false } }
        db.overrides[overrideIndex].change = .cancelLesson(ids.next())
        let thursday = index(db.lessons) { $0.occurrence.day == .weekday(.thursday) }
        let ghostPeriod: Period.ID = ids.next()
        db.lessons[thursday].slot = .period(ghostPeriod, span: 1)
        db.timetables[0].timeStructure = .bellSchedule(defaultID: ids.next(), perWeekday: [:])
        let found = issues(db, .danglingReference)
        #expect(found.allSatisfy { $0.severity == .error })
        #expect(found.contains { $0.entityType == .lesson && $0.field == "subjectID" && $0.relatedID == missing.uuid })
        #expect(found.contains { $0.entityType == .settings && $0.field == "activeTimetableID" })
        #expect(found.contains { $0.entityType == .task && $0.field == "linkedLesson" })
        #expect(found.contains { $0.entityType == .scheduleOverride && $0.field == "change" })
        #expect(found.contains { $0.entityType == .lesson && $0.field == "slot" && $0.relatedID == ghostPeriod.uuid })
        #expect(found.contains { $0.entityType == .timetable && $0.field == "timeStructure" })
        #expect(!db.isValid)
    }

    @Test func referencesDeletedEntity() {
        var db = base
        let subjectIndex = index(db.subjects) { $0.name == "Matematika" }
        db.subjects[subjectIndex].meta.isDeleted = true
        let found = issues(db, .referencesDeletedEntity)
        // Lessons, the homework and the exam all point at the deleted subject.
        #expect(found.count >= 3 && found.allSatisfy { $0.severity == .warning && $0.field == "subjectID" })
        #expect(Set(found.map(\.entityType)) == [.lesson, .task, .exam])
        #expect(db.isValid)   // warnings only
    }

    @Test func deletedEntitiesAreNotValidated() {
        var db = base
        db.lessons[mondayLesson].subjectID = Subject.ID(uuidString: "00000000-0000-4000-8000-0000000000AB")!
        db.lessons[mondayLesson].meta.isDeleted = true
        #expect(issues(db, .danglingReference).isEmpty)
    }

    @Test func crossTimetableReference() {
        var db = base
        let algebra = db.subjects.first { $0.timetableID == college.id }!
        db.lessons[mondayLesson].subjectID = algebra.id
        let found = issues(db, .crossTimetableReference)
        #expect(found.count == 1 && found[0].severity == .warning && found[0].relatedID == algebra.id.uuid)
    }

    @Test func invalidTimeRange() {
        var db = base
        db.bellSchedules[0].periods[0].end = db.bellSchedules[0].periods[0].start
        let wednesday = index(db.lessons) { $0.occurrence.day == .weekday(.wednesday) }
        db.lessons[wednesday].slot = .time(start: Fixture.time("12:00"), end: Fixture.time("11:00"))
        let examIndex = index(db.exams) { $0.start != nil }
        db.exams[examIndex].end = Fixture.time("07:00")
        db.reminderRules[0].quietHours = QuietHours(start: Fixture.time("22:00"), end: Fixture.time("22:00"))
        db.settings.globalQuietHours = QuietHours(start: Fixture.time("06:00"), end: Fixture.time("06:00"))
        let found = issues(db, .invalidTimeRange)
        #expect(found.filter { $0.severity == .error }.count == 3)
        #expect(found.filter { $0.severity == .warning }.count == 2)
        #expect(found.contains { $0.entityType == .bellSchedule && $0.childID != nil })
    }

    @Test func invalidDateRange() {
        var db = base
        let inverted = LocalDateRange(start: Fixture.date("2027-01-01"), end: Fixture.date("2026-01-01"))
        db.terms[0].range = inverted
        db.breaks[0].range = inverted
        let friday = index(db.lessons) { $0.occurrence.day == .weekday(.friday) }
        db.lessons[friday].validity = .range(inverted)
        let found = issues(db, .invalidDateRange)
        #expect(found.count == 3 && found.allSatisfy { $0.severity == .error })
    }

    @Test func overlappingPeriods() {
        var db = base
        let first = db.bellSchedules[0].periods[0]
        let second = index2(db.bellSchedules[0].periods) { $0.start == Fixture.time("08:55") }
        db.bellSchedules[0].periods[second].start = Fixture.time("08:30")
        let found = issues(db, .overlappingPeriods)
        // 08:30–09:40 overlaps 08:00–08:45 and the 08:45–08:55 break.
        #expect(found.count == 2 && found.allSatisfy { $0.severity == .warning })
        #expect(found.contains { $0.relatedID == first.id.uuid })
        #expect(db.isValid)
    }

    private func index2(_ periods: [Period], where predicate: (Period) -> Bool) -> Int {
        guard let index = periods.firstIndex(where: predicate) else { fatalError("fixture changed") }
        return index
    }

    @Test func invalidValue() {
        var db = base
        // Timetable rotation out of range.
        db.timetables[0].rotation = .weekCycle(WeekCycle(length: 7, anchor: .referenceWeek(date: Fixture.date("2026-09-01"), cycleWeek: 9)))
        db.timetables[1].rotation = .dayCycle(DayCycle(length: 2, anchorDate: Fixture.date("2026-09-01"), anchorIndex: 0,
                                                       schoolDays: [], labels: ["A"]))
        // Lesson keys inconsistent with the rotation, bad span.
        let tuesday = index(db.lessons) { $0.occurrence.day == .weekday(.tuesday) }
        db.lessons[tuesday].occurrence = LessonOccurrenceRule(day: .cycleDay(1))
        let thursday = index(db.lessons) { $0.occurrence.day == .weekday(.thursday) }
        db.lessons[thursday].slot = .period(db.bellSchedules[0].periods[0].id, span: 0)
        // Task / rule values.
        db.tasks[0].repeatRule?.interval = 0
        db.reminderRules[0].offsets = [.minutesBefore(-5)]
        db.reminderRules[1].followUp = .afterMinutes(0)
        db.reminderRules[2].tier = .alarm   // preset rule with alarm tier
        // Settings.
        db.settings.id = AppSettings.ID(uuidString: "00000000-0000-4000-8000-0000000000CC")!
        db.settings.timeZoneMode = .fixed(identifier: "Nowhere/Nothing")
        db.settings.meta.updatedAt = HLCTimestamp.zero   // before createdAt

        let found = issues(db, .invalidValue)
        func has(_ type: EntityType, _ field: String, _ severity: ValidationIssue.Severity) -> Bool {
            found.contains { $0.entityType == type && $0.field == field && $0.severity == severity }
        }
        #expect(has(.timetable, "rotation", .error))
        #expect(has(.timetable, "rotation.anchor", .error))
        #expect(has(.timetable, "rotation.anchorIndex", .error))
        #expect(has(.timetable, "rotation.schoolDays", .error))
        #expect(has(.timetable, "rotation.labels", .warning))
        #expect(has(.lesson, "occurrence", .error))
        #expect(has(.lesson, "slot", .error))
        #expect(has(.task, "repeatRule", .error))
        #expect(has(.reminderRule, "offsets", .error))
        #expect(has(.reminderRule, "followUp", .error))
        #expect(has(.reminderRule, "tier", .warning))
        #expect(has(.settings, "id", .warning))
        #expect(has(.settings, "timeZoneMode", .warning))
        #expect(has(.settings, "meta.updatedAt", .warning))
    }

    @Test func invalidValueForCycleWeeksSpanAndDisabledDay() {
        var db = base
        let tuesday = index(db.lessons) { $0.occurrence.day == .weekday(.tuesday) }
        db.lessons[tuesday].occurrence.cycleWeeks = [3]
        let thursday = index(db.lessons) { $0.occurrence.day == .weekday(.thursday) }
        db.lessons[thursday].slot = .period(db.bellSchedules[0].periods[0].id, span: 4)   // only 3 lesson periods
        db.timetables[0].enabledDays.remove(.friday)
        #expect(issues(db, .cycleWeekOutOfRange).contains {
            $0.field == "occurrence.cycleWeeks" && $0.severity == .error && $0.value == "3"
        })
        let found = issues(db, .invalidValue)
        #expect(found.contains { $0.field == "slot" && $0.severity == .warning && $0.value == "4" })
        #expect(found.contains { $0.field == "occurrence" && $0.severity == .warning && $0.value == "5" })
    }

    /// Stage 3: `followDay.cycleWeek` outside the week cycle (0, length + 1) is an error with its own code; within
    /// range it is clean; on a timetable without a week cycle it stays an `invalidValue` warning (ignored).
    @Test func followDayCycleWeekOutOfRange() {
        let follow = index(base.overrides) { $0.change == .followDay(.weekday(.friday), cycleWeek: 2) }
        #expect(issues(base, .cycleWeekOutOfRange).isEmpty)
        for week in [0, 3, -1, Int.max] {
            var db = base
            db.overrides[follow].change = .followDay(.weekday(.friday), cycleWeek: week)
            let found = issues(db, .cycleWeekOutOfRange)
            #expect(found.count == 1, "week (week)")
            #expect(found.first?.severity == .error && found.first?.field == "change.cycleWeek")
            #expect(found.first?.entityType == .scheduleOverride && found.first?.value == String(week))
            #expect(!db.isValid)
        }
        var db = base
        db.timetables[0].rotation = .weekCycle(WeekCycle(length: 4, anchor: .isoWeekParity(policy: .strict, offset: 0)))
        db.overrides[follow].change = .followDay(.weekday(.friday), cycleWeek: 4)
        #expect(issues(db, .cycleWeekOutOfRange).isEmpty, "4 is inside a 4-week cycle")
        db.timetables[0].rotation = .none
        db.lessons = db.lessons.map { lesson in
            var copy = lesson
            copy.occurrence.cycleWeeks = nil
            return copy
        }
        #expect(issues(db, .cycleWeekOutOfRange).isEmpty)
        #expect(issues(db, .invalidValue).contains { $0.field == "change.cycleWeek" && $0.severity == .warning })
    }

    /// Stage 3: a day cycle whose school days differ from the shown weekdays — one warning per weekday, in both
    /// directions; matching sets (the fixture) are clean.
    @Test func schoolDaysMismatch() {
        let collegeIndex = index(base.timetables) { $0.id == college.id }
        #expect(issues(base, .schoolDaysMismatch).isEmpty)
        var db = base
        db.timetables[collegeIndex].enabledDays = [.monday, .tuesday, .wednesday]
        db.timetables[collegeIndex].rotation = .dayCycle(DayCycle(
            length: 2, anchorDate: Fixture.date("2026-09-01"), anchorIndex: 1,
            schoolDays: [.monday, .wednesday, .saturday], skipsBreaks: true, labels: ["A", "B"]))
        let found = issues(db, .schoolDaysMismatch)
        #expect(found.count == 2 && found.allSatisfy { $0.severity == .warning && $0.entityID == college.id.uuid })
        #expect(found.contains { $0.field == "rotation.schoolDays" && $0.value == "6" }, "Saturday advances the cycle unseen")
        #expect(found.contains { $0.field == "enabledDays" && $0.value == "2" }, "Tuesday is shown but never a cycle day")
        #expect(db.isValid)
        // Week-cycle timetables have no school days; empty sets are reported by `invalidValue` only.
        db.timetables[collegeIndex].rotation = .dayCycle(DayCycle(length: 2, anchorDate: Fixture.date("2026-09-01"),
                                                                  anchorIndex: 1, schoolDays: []))
        #expect(issues(db, .schoolDaysMismatch).isEmpty)
    }

    @Test func unknownValue() {
        var db = base
        db.breaks[0].kind = BreakKind(rawValue: "strike")
        db.settings.palettePackID = PalettePackID(rawValue: "neon")
        db.exams[0].kind = ExamKind(rawValue: "viva")
        let found = issues(db, .unknownValue)
        #expect(found.count == 3 && found.allSatisfy { $0.severity == .info })
        #expect(Set(found.compactMap(\.value)) == ["strike", "neon", "viva"])
        #expect(db.isValid)
    }

    @Test func emptyScheduleDay() {
        var db = base
        db.lessons.removeAll { $0.occurrence.day == .weekday(.friday) || $0.occurrence.day == .cycleDay(2) }
        let found = issues(db, .emptyScheduleDay)
        #expect(found.count == 2 && found.allSatisfy { $0.severity == .info })
        #expect(found.contains { $0.entityID == school.id.uuid && $0.field == "enabledDays" && $0.value == "5" })
        #expect(found.contains { $0.entityID == college.id.uuid && $0.field == "rotation" && $0.value == "2" })
    }
}
