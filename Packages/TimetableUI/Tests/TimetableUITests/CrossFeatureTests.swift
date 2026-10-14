// Phase 3 C1: lesson badges (LessonWorkIndex matching rule), the Today work state, the task prefill from a lesson and
// the cross-feature seed scenarios.
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let zone = TimeZone(identifier: "Europe/Bratislava")!
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private let meta = EntityMeta.untouchedSingleton

private func occurrence(_ subject: SubjectSummary, on day: LocalDate, _ start: LocalTime, _ end: LocalTime,
                        status: ResolvedLesson.Status = .scheduled, lessonID: Lesson.ID = Lesson.ID(UUID()),
                        oneOff: ScheduleOverride.ID? = nil) -> ResolvedLesson {
    let id = oneOff.map(OccurrenceID.oneOff) ?? OccurrenceID.lesson(lessonID, on: day)
    let source: ResolvedLesson.Source = oneOff.map { .oneOff($0) } ?? .lesson(lessonID)
    return ResolvedLesson(id: id, source: source, timetableID: Timetable.ID(UUID()), date: day, subject: subject,
                          startTime: start, endTime: end, start: Date(), end: Date(), status: status)
}

private func subject(_ name: String) -> SubjectSummary {
    SubjectSummary(id: Subject.ID(UUID()), name: name, color: PalettePack.classic.colors[0].value)
}

private func task(_ title: String, subject: SubjectSummary?, due: TaskDue?, link: LessonLink? = nil,
                  completed: Bool = false, priority: TaskPriority = .normal) -> TaskItem {
    TaskItem(id: TaskItem.ID(UUID()), meta: meta, title: title, subjectID: subject?.id, due: due, linkedLesson: link,
             priority: priority, completedAt: completed ? Date(timeIntervalSince1970: 0) : nil)
}

@Suite("Lesson badges (LessonWorkIndex)")
struct LessonWorkIndexTests {
    private let day = date(2026, 10, 13)
    private let maths = subject("Matematika")
    private let physics = subject("Fyzika")

    @Test func unlinkedTaskCountsOnceOnTheFirstLessonOfItsSubject() {
        let first = occurrence(maths, on: day, time(8), time(8, 45))
        let second = occurrence(maths, on: day, time(11), time(11, 45))
        let homework = task("Worksheet", subject: maths, due: .date(day))
        let index = LessonWorkIndex.make(lessons: [second, first], tasks: [homework], exams: [])
        #expect(index[first.id].openTaskIDs == [homework.id])
        #expect(index.badges(for: second.id) == nil)
        #expect(index.byOccurrence.values.reduce(0) { $0 + $1.openTaskIDs.count } == 1)
    }

    @Test func aCancelledFirstLessonPassesTheTaskToTheNextOne() {
        let cancelled = occurrence(maths, on: day, time(8), time(8, 45), status: .cancelled)
        let held = occurrence(maths, on: day, time(11), time(11, 45))
        let homework = task("Worksheet", subject: maths, due: .dateTime(day, time(7)))
        let index = LessonWorkIndex.make(lessons: [cancelled, held], tasks: [homework], exams: [])
        #expect(index[held.id].openTaskIDs == [homework.id])
        // Every occurrence cancelled: the first one keeps it (the user still sees the homework).
        let only = LessonWorkIndex.make(lessons: [cancelled], tasks: [homework], exams: [])
        #expect(only[cancelled.id].openTaskIDs == [homework.id])
    }

    @Test func aLinkedTaskBelongsToItsOccurrenceOnly() {
        let lessonID = Lesson.ID(UUID())
        let first = occurrence(maths, on: day, time(8), time(8, 45))
        let linked = occurrence(maths, on: day, time(11), time(11, 45), lessonID: lessonID)
        let homework = task("Proof", subject: maths, due: .date(day), link: LessonLink(lessonID: lessonID, date: day))
        let index = LessonWorkIndex.make(lessons: [first, linked], tasks: [homework], exams: [])
        #expect(index[linked.id].openTaskIDs == [homework.id])
        #expect(index[first.id].openTaskIDs.isEmpty)
    }

    @Test func aDanglingLinkFallsBackToTheSubjectRule() {
        let first = occurrence(maths, on: day, time(8), time(8, 45))
        let gone = LessonLink(lessonID: Lesson.ID(UUID()), date: day)
        let homework = task("Proof", subject: maths, due: .date(day), link: gone)
        #expect(LessonWorkIndex.make(lessons: [first], tasks: [homework], exams: [])[first.id].openTaskIDs == [homework.id])
    }

    @Test func completedTombstonedUndatedAndOtherSubjectsDoNotCount() {
        let lesson = occurrence(maths, on: day, time(8), time(8, 45))
        let done = task("Done", subject: maths, due: .date(day), completed: true)
        var deleted = task("Deleted", subject: maths, due: .date(day))
        deleted.meta.isDeleted = true
        let undated = task("Someday", subject: maths, due: nil)
        let unknown = task("Newer", subject: maths, due: .unknown(.string("x")))
        let noSubject = task("Pack", subject: nil, due: .date(day))
        let otherSubject = task("Physics", subject: physics, due: .date(day))
        let otherDay = task("Tomorrow", subject: maths, due: .date(day.adding(days: 1)))
        let index = LessonWorkIndex.make(lessons: [lesson],
                                         tasks: [done, deleted, undated, unknown, noSubject, otherSubject, otherDay],
                                         exams: [])
        #expect(index[lesson.id].openTaskIDs.isEmpty)
        #expect(index[lesson.id].completedTaskIDs == [done.id])
        #expect(index.badges(for: lesson.id) == nil)   // a completed task alone shows no badge
    }

    @Test func openTasksAreOrderedLikeTheTasksTab() {
        let lesson = occurrence(maths, on: day, time(8), time(8, 45))
        let low = task("B low", subject: maths, due: .date(day))
        let high = task("A high", subject: maths, due: .date(day), priority: .high)
        let timed = task("C timed", subject: maths, due: .dateTime(day, time(7)))
        let index = LessonWorkIndex.make(lessons: [lesson], tasks: [low, high, timed], exams: [])
        #expect(index[lesson.id].openTaskIDs == [timed.id, high.id, low.id])
        #expect(index.badges(for: lesson.id) == LessonBadges(openTasks: 3, hasExam: false))
    }

    @Test func examsGoToTheLessonContainingTheirStartElseTheAnchor() {
        let first = occurrence(maths, on: day, time(8), time(8, 45))
        let second = occurrence(maths, on: day, time(10), time(10, 45))
        let atTen = Exam(id: Exam.ID(UUID()), meta: meta, subjectID: maths.id, title: "Test", date: day, start: time(10, 5))
        let noTime = Exam(id: Exam.ID(UUID()), meta: meta, subjectID: maths.id, title: "Oral", date: day)
        let index = LessonWorkIndex.make(lessons: [first, second], tasks: [], exams: [atTen, noTime])
        #expect(index[second.id].examIDs == [atTen.id])
        #expect(index[first.id].examIDs == [noTime.id])
        #expect(index.badges(for: second.id) == LessonBadges(openTasks: 0, hasExam: true))
        // A completed exam still marks its lesson (it is an event on that date).
        var done = atTen
        done.completedAt = Date(timeIntervalSince1970: 0)
        #expect(LessonWorkIndex.make(lessons: [second], tasks: [], exams: [done]).badges(for: second.id)?.hasExam == true)
    }

    @Test func oneOffLessonsMatchBySubjectButNotByLink() {
        let oneOff = occurrence(maths, on: day, time(14), time(14, 45), oneOff: ScheduleOverride.ID(UUID()))
        let homework = task("For the extra lesson", subject: maths, due: .date(day))
        #expect(LessonWorkIndex.make(lessons: [oneOff], tasks: [homework], exams: [])[oneOff.id].openTaskIDs == [homework.id])
    }

    @Test func badgeTextsAndVoiceOverPhrases() {
        let renderer = LocalizedTextRenderer(
            formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .auto, timeZone: zone),
            lookup: EnglishCatalog.lookup)
        let badges = LessonBadges(openTasks: 2, hasExam: true)
        #expect(badges.tasksText(renderer: renderer) == "2 tasks")
        #expect(badges.examText(renderer: renderer) == "Exam")
        #expect(badges.accessibilityParts(renderer: renderer) == ["2 open tasks", "exam on this day"])
        #expect(LessonBadges(openTasks: 0, hasExam: true).tasksText(renderer: renderer) == nil)
        #expect(LessonBadges(openTasks: 0, hasExam: false).isEmpty)
        let lesson = occurrence(maths, on: day, time(8), time(8, 45))
        let sentence = LessonAccessibilityLabel.make(lesson: lesson, visibility: FieldVisibility(), reasons: [],
                                                     badges: badges, renderer: renderer)
        #expect(sentence == "Matematika, 8:00 to 8:45, 2 open tasks, exam on this day")
        #expect(LessonAccessibilityLabel.make(lesson: lesson, visibility: FieldVisibility(), reasons: [],
                                              renderer: renderer) == "Matematika, 8:00 to 8:45")
    }
}

@Suite("Cross-feature seed scenarios")
struct CrossFeatureSeedTests {
    private let scenario = SampleScenarios.secondary()

    private func index(days: [LocalDate]) throws -> (LessonWorkIndex, [ResolvedLesson]) {
        let resolver = try #require(ScheduleResolver(database: scenario.database, timetableID: scenario.timetable.id,
                                                     context: scenario.context))
        let lessons = days.flatMap { resolver.day($0).entries }
        return (LessonWorkIndex.make(lessons: lessons, tasks: scenario.database.tasks, exams: scenario.database.exams),
                lessons)
    }

    private func badges(_ index: LessonWorkIndex, _ lessons: [ResolvedLesson]) -> [String: LessonBadges] {
        var result: [String: LessonBadges] = [:]
        for lesson in lessons {
            if let badges = index.badges(for: lesson.id) {
                result["\(lesson.date.weekday.rawValue)-\(lesson.subject.shortName ?? "")"] = badges
            }
        }
        return result
    }

    @Test func referenceWeekBadges() throws {
        let monday = date(2026, 10, 12)
        let (index, lessons) = try index(days: (0..<5).map { monday.adding(days: $0) })
        #expect(badges(index, lessons) == [
            "1-FYZ": LessonBadges(openTasks: 1, hasExam: false),   // overdue lab report (due Mon)
            "1-DEJ": LessonBadges(openTasks: 0, hasExam: true),    // past History test
            "2-NEJ": LessonBadges(openTasks: 1, hasExam: false),   // due today, 2/5 subtasks, repeats
            "3-ANJ": LessonBadges(openTasks: 1, hasExam: false),
            "4-MAT": LessonBadges(openTasks: 1, hasExam: false),
        ])
        // The completed Biology task is listed for the lesson but not counted.
        let biology = try #require(lessons.first { $0.date == SampleScenarios.today && $0.subject.shortName == "BIO" })
        #expect(index[biology.id].completedTaskIDs.count == 1)
    }

    @Test func nextWeekHasTheLinkedAssignmentAndTheChemistryExam() throws {
        let monday = date(2026, 10, 19)
        let (index, lessons) = try index(days: (0..<5).map { monday.adding(days: $0) })
        #expect(badges(index, lessons) == [
            "1-SJL": LessonBadges(openTasks: 1, hasExam: false),   // essay due Mon 8:00
            "3-INF": LessonBadges(openTasks: 1, hasExam: false),   // linked to Wednesday's double period
            "4-CHE": LessonBadges(openTasks: 0, hasExam: true),
        ])
    }

    @Test func seedShapes() throws {
        let tasks = scenario.database.tasks
        let now = LocalDateTime(date: SampleScenarios.today, time: time(10, 20))
        let counts = TaskListModel.counts(of: tasks, now: now)
        #expect(counts == TaskSegmentCounts(today: 1, upcoming: 4, overdue: 1, completed: 2))
        let repeating = try #require(tasks.first { $0.repeatRule != nil })
        #expect(repeating.subtasks.count == 5 && repeating.subtasks.filter { $0.completedAt != nil }.count == 2)
        #expect(tasks.contains { $0.linkedLesson != nil && $0.priority == .high && $0.kind == .assignment })
        let history = ExamListModel.make(database: scenario.database, today: SampleScenarios.today,
                                         context: scenario.context).history
        #expect(history.map { $0.subject?.shortName } == ["DEJ"])

        let university = SampleScenarios.university()
        let context = CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
        let list = ExamListModel.make(database: university, today: SampleScenarios.today, context: context)
        let period = try #require(list.periods.first)
        #expect(!period.isDerived && period.examCount == 2)
        #expect(university.breaks.filter { $0.kind == .examPeriod }.count == 1)
    }
}

@Suite("Today work and the lesson task prefill")
struct TodayWorkTests {
    private let scenario = SampleScenarios.secondary()

    @Test func referenceMorning() {
        let now = LocalDateTime(date: SampleScenarios.today, time: time(10, 20))
        let work = TodayWork.make(database: scenario.database, now: now, context: scenario.context)
        #expect(work.dueToday.map(\.title) == ["Nemčina – Lektion 3"])
        #expect(work.overdueCount == 1)
        #expect(work.showsTasks)
        #expect(work.nextExam?.subject?.shortName == "CHE")
        #expect(work.nextExam?.daysUntil == 9)
    }

    @Test func examHorizonAndEmptyState() {
        // 2026-10-02: the chemistry test is 20 days away (beyond the 14-day horizon); nothing due that day.
        let now = LocalDateTime(date: date(2026, 10, 2), time: time(9))
        var database = scenario.database
        database.tasks = []
        database.exams = database.exams.filter { $0.title.hasPrefix("Písomka – organická") }   // only the Oct 22 test
        let work = TodayWork.make(database: database, now: now, context: scenario.context)
        #expect(work.nextExam == nil)
        #expect(!work.showsTasks)
        // On the 8th it is exactly 14 days away and shows.
        let close = TodayWork.make(database: database, now: LocalDateTime(date: date(2026, 10, 8), time: time(9)),
                                   context: scenario.context)
        #expect(close.nextExam?.daysUntil == 14)
    }

    @Test func prefillFromALessonLinksTheOccurrence() throws {
        let resolver = try #require(ScheduleResolver(database: scenario.database, timetableID: scenario.timetable.id,
                                                     context: scenario.context))
        let lesson = try #require(resolver.day(date(2026, 10, 21)).entries.first { $0.subject.shortName == "INF" })
        let prefill = TaskPrefill(lesson: lesson)
        var draft = prefill.draft(newWithID: TaskItem.ID(UUID()), today: SampleScenarios.today,
                                  timetableID: lesson.timetableID)
        #expect(draft.dueMode == .nextLesson)
        #expect(draft.effectiveDueDate == date(2026, 10, 21))
        #expect(draft.kind == .homework)
        #expect(!draft.canSave)   // the title is still empty
        draft.title = "Read chapter 4"
        let made = try #require(draft.makeTask(now: Date(timeIntervalSince1970: 0)))
        #expect(made.subjectID == lesson.subject.id)
        #expect(made.due == .date(date(2026, 10, 21)))
        #expect(made.linkedLesson?.date == date(2026, 10, 21))
        if case .lesson(let id) = lesson.source { #expect(made.linkedLesson?.lessonID == id) }
        // The new task then shows on exactly that occurrence.
        let index = LessonWorkIndex.make(lessons: resolver.day(date(2026, 10, 21)).entries,
                                         tasks: scenario.database.tasks + [made], exams: [])
        #expect(index[lesson.id].openTaskIDs.contains(made.id))
    }

    @Test func prefillFromAOneOffLessonHasNoLink() throws {
        let resolver = try #require(ScheduleResolver(database: scenario.database, timetableID: scenario.timetable.id,
                                                     context: scenario.context))
        let added = try #require(resolver.day(scenario.overrideDate).entries.first { $0.status == .added })
        var draft = TaskPrefill(lesson: added).draft(newWithID: TaskItem.ID(UUID()), today: SampleScenarios.today,
                                                     timetableID: added.timetableID)
        draft.title = "Bring the project"
        let made = try #require(draft.makeTask(now: Date(timeIntervalSince1970: 0)))
        #expect(made.linkedLesson == nil)
        #expect(made.due == .date(scenario.overrideDate))
    }

    @Test func taskEditorContextIsNotATimetableEditorTarget() {
        let prefill = TaskPrefill(subjectID: Subject.ID(UUID()), date: date(2026, 10, 13), startTime: nil, lessonID: nil)
        #expect(EditorLaunchTarget(EditorContext(timetableID: Timetable.ID(UUID()), target: .newTask(prefill))) == nil)
        #expect(EditorContext.RouteID.newTask == "tasks.editor-new")
    }
}
