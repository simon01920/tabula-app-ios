import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 3 B1: Tasks tab logic (segments, sorting, row model, draft, next lesson, quick add).

private let zone = SampleScenarios.timeZone
private let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private let today = date(2026, 10, 13)
private let now = LocalDateTime(date: today, time: time(10, 20))
private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: zone),
    lookup: EnglishCatalog.lookup)

private func task(_ title: String, due: TaskDue? = nil, priority: TaskPriority = .normal, completed: Date? = nil,
                  subject: Subject.ID? = nil, subtasks: [Subtask] = [], repeatRule: RepeatRule? = nil) -> TaskItem {
    TaskItem(id: TaskItem.ID(UUID()), meta: EditorEntities.placeholderMeta, title: title, subjectID: subject, due: due, priority: priority,
             repeatRule: repeatRule, completedAt: completed, subtasks: subtasks)
}

@Suite("Task list model")
struct TaskListModelTests {
    @Test func classifiesIntoDisjointSegments() {
        #expect(TaskListModel.segment(of: task("a", due: .date(date(2026, 10, 12))), now: now) == .overdue)
        #expect(TaskListModel.segment(of: task("a", due: .date(today)), now: now) == .today)
        #expect(TaskListModel.segment(of: task("a", due: .dateTime(today, time(8))), now: now) == .overdue)
        #expect(TaskListModel.segment(of: task("a", due: .dateTime(today, time(23, 59))), now: now) == .today)
        #expect(TaskListModel.segment(of: task("a", due: .date(date(2026, 10, 14))), now: now) == .upcoming)
        #expect(TaskListModel.segment(of: task("a"), now: now) == .upcoming)
        #expect(TaskListModel.segment(of: task("a", due: .unknown(.null)), now: now) == .upcoming)
        #expect(TaskListModel.segment(of: task("a", due: .date(date(2026, 10, 1)), completed: Date()), now: now) == .completed)
    }

    @Test func tombstonesAreSkippedAndCountsFollowTheFilter() {
        let maths = Subject.ID(UUID())
        var deleted = task("gone", due: .date(today))
        deleted.meta.isDeleted = true
        let list = [task("a", due: .date(today), subject: maths), task("b", due: .date(today)), deleted,
                    task("c", due: .date(date(2026, 10, 1))), task("d", completed: Date())]
        let all = TaskListModel.counts(of: list, now: now)
        #expect(all == TaskSegmentCounts(today: 2, upcoming: 0, overdue: 1, completed: 1))
        #expect(all.open == 3 && all.total == 4 && all[.overdue] == 1)
        #expect(TaskListModel.counts(of: list, now: now, subjectFilter: maths) == TaskSegmentCounts(today: 1))
    }

    @Test func sortsByDueOrPriorityWithUndatedLast() {
        let early = task("early", due: .date(date(2026, 10, 14)), priority: .low)
        let late = task("late", due: .date(date(2026, 10, 20)), priority: .urgent)
        let undated = task("undated", priority: .high)
        let list = [undated, late, early]
        let byDue = TaskListModel.tasks(in: .upcoming, from: list, now: now, sort: .due).map(\.title)
        #expect(byDue == ["early", "late", "undated"])
        let byPriority = TaskListModel.tasks(in: .upcoming, from: list, now: now, sort: .priority).map(\.title)
        #expect(byPriority == ["late", "undated", "early"])
    }

    @Test func completedAreNewestFirstAndFilterSubjectsAreUsedOnly() {
        let old = task("old", completed: Date(timeIntervalSince1970: 100))
        let new = task("new", completed: Date(timeIntervalSince1970: 200))
        #expect(TaskListModel.tasks(in: .completed, from: [old, new], now: now).map(\.title) == ["new", "old"])
        let used = Subject(id: Subject.ID(UUID()), meta: EditorEntities.placeholderMeta, timetableID: Timetable.ID(UUID()),
                           name: "Maths", color: .white)
        let unused = Subject(id: Subject.ID(UUID()), meta: EditorEntities.placeholderMeta, timetableID: used.timetableID,
                             name: "Art", color: .white)
        let linked = task("x", subject: used.id)
        #expect(TaskListModel.filterSubjects(tasks: [linked], subjects: [unused, used], timetableOrder: [used.timetableID],
                                             locale: Locale(identifier: "en_US")).map(\.name) == ["Maths"])
    }
}

@Suite("Task row model")
struct TaskRowModelTests {
    @Test func dueDescriptions() {
        func make(_ due: TaskDue?) -> TaskDueDescription? { TaskDueDescription.make(due: due, today: today) }
        #expect(make(nil) == nil)
        #expect(make(.unknown(.null)) == nil)
        #expect(make(.date(today))?.kind == .today)
        #expect(make(.dateTime(date(2026, 10, 14), time(8)))?.catalogKey == "tasks.due.tomorrowAt")
        #expect(make(.date(date(2026, 10, 16)))?.kind == .inDays(3))
        #expect(make(.date(date(2026, 10, 30)))?.kind == .onDate(date(2026, 10, 30)))
        let overdue = make(.dateTime(date(2026, 10, 10), time(8)))
        #expect(overdue?.kind == .overdueDays(3) && overdue?.time == nil && overdue?.catalogKey == "tasks.due.overdueDays")
        #expect(make(.dateTime(today, time(8, 5)))?.text(renderer: renderer) == "Today, 8:05")
        #expect(make(.date(date(2026, 10, 14)))?.text(renderer: renderer) == "Tomorrow")
    }

    @Test func absentFieldsAndBadges() {
        let plain = TaskRowModel(task: task("plain"), subjects: [:], now: now)
        #expect(plain.subject == nil && plain.due == nil && !plain.showsPriorityBadge && plain.subtasksTotal == 0)
        #expect(plain.attachmentCount == 0 && !plain.repeats && !plain.isOverdue)
        let sub = Subtask(id: Subtask.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "s", completedAt: Date())
        let open = Subtask(id: Subtask.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "t")
        var dead = Subtask(id: Subtask.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "dead")
        dead.meta.isDeleted = true
        let busy = TaskRowModel(task: task("busy", due: .date(date(2026, 10, 12)), priority: .urgent,
                                           subtasks: [sub, open, dead], repeatRule: RepeatRule(frequency: .daily)),
                                subjects: [:], now: now)
        #expect(busy.subtasksDone == 1 && busy.subtasksTotal == 2 && busy.repeats && busy.isOverdue)
        #expect(busy.priorityBadgeKey == "tasks.priority.urgent")
    }

    @Test func oneSentenceAccessibilityLabel() {
        let row = TaskRowModel(task: task("Essay", due: .date(date(2026, 10, 14)), priority: .high), subjects: [:], now: now)
        #expect(row.accessibilityLabel(renderer: renderer) == "Essay, due Tomorrow, high priority")
        let late = TaskRowModel(task: task("Late", due: .date(date(2026, 10, 10))), subjects: [:], now: now)
        #expect(late.accessibilityLabel(renderer: renderer) == "Late, 3 days overdue")
        let done = TaskRowModel(task: task("Done", completed: Date()), subjects: [:], now: now)
        #expect(done.accessibilityLabel(renderer: renderer) == "Done, completed")
    }

    @Test func everyKeyIsInTheCatalog() {
        let missing = TaskL10nKeys.allKeys.filter { EnglishCatalog.values[$0] == nil }
        #expect(missing.isEmpty, "Missing: \(missing)")
        #expect(TaskL10nKeys.kind(TaskKind(rawValue: "fromTheFuture")) == nil)
    }
}

@Suite("Task draft")
struct TaskDraftTests {
    private func newDraft(subject: Subject.ID? = nil, nextLesson: NextLesson? = nil) -> TaskDraft {
        TaskDraft(newWithID: TaskItem.ID(UUID()), today: today, timetableID: nil, subjectID: subject, nextLesson: nextLesson)
    }

    @Test func newDraftDefaultsToTomorrowAndNeedsATitle() {
        var draft = newDraft()
        #expect(draft.isNew && draft.dueMode == .date && draft.dueDate == date(2026, 10, 14) && draft.kind == .todo)
        #expect(draft.issues == [.titleEmpty] && !draft.canSave && draft.makeTask(now: Date()) == nil)
        draft.title = "  Read chapter 3  "
        #expect(draft.canSave)
        let made = draft.makeTask(now: Date())
        #expect(made?.title == "Read chapter 3" && made?.due == .date(date(2026, 10, 14)) && made?.notes == nil)
    }

    @Test func nextLessonDueNeedsASubjectAndAResolvedLesson() {
        var draft = newDraft()
        draft.title = "x"
        draft.setDueMode(.nextLesson)
        #expect(draft.issues == [.nextLessonNeedsSubject])
        draft.setSubject(Subject.ID(UUID()))
        #expect(draft.issues == [.nextLessonNotFound])
        let lessonID = Lesson.ID(UUID())
        draft.nextLesson = NextLesson(date: date(2026, 10, 15), startTime: time(8, 55), lessonID: lessonID)
        #expect(draft.issues.isEmpty)
        let made = draft.makeTask(now: Date())
        #expect(made?.due == .date(date(2026, 10, 15)) && made?.linkedLesson == LessonLink(lessonID: lessonID, date: date(2026, 10, 15)))
        // Changing the subject drops the resolved lesson again.
        draft.setSubject(Subject.ID(UUID()))
        #expect(draft.nextLesson == nil)
        // Switching to a plain date clears the link.
        draft.setDueMode(.date)
        #expect(draft.makeTask(now: Date())?.linkedLesson == nil)
    }

    @Test func repeatValidationAndRule() {
        var draft = newDraft()
        draft.title = "x"
        draft.setRepeatMode(.weekly)
        draft.toggleWeekday(.monday)
        draft.toggleWeekday(.wednesday)
        draft.repeatInterval = 2
        draft.hasUntil = true
        draft.until = date(2026, 10, 1)
        #expect(draft.issues == [.untilBeforeDue])
        draft.until = date(2027, 1, 31)
        #expect(draft.makeTask(now: Date())?.repeatRule
                == RepeatRule(frequency: .weekly, interval: 2, weekdays: [.monday, .wednesday], until: date(2027, 1, 31)))
        draft.setDueMode(.none)
        #expect(draft.issues == [.repeatNeedsDue])
        draft.setRepeatMode(.daily)
        #expect(draft.repeatWeekdays.count == 2)   // kept in the draft...
        draft.setDueMode(.date)
        draft.hasUntil = false
        #expect(draft.makeTask(now: Date())?.repeatRule == RepeatRule(frequency: .daily, interval: 2))   // ...but not stored
    }

    @Test func subtasksAddReorderDeleteAndTombstonesStayOut() {
        var draft = newDraft()
        draft.title = "x"
        let addedBlank = draft.addSubtask(title: "   ", id: Subtask.ID(UUID()))
        #expect(!addedBlank)
        for name in ["a", "b", "c"] { draft.addSubtask(title: name, id: Subtask.ID(UUID())) }
        draft.moveSubtasks(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(draft.subtasks.map(\.title) == ["b", "c", "a"])
        draft.moveSubtasks(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(draft.subtasks.map(\.title) == ["a", "b", "c"])
        draft.removeSubtasks(atOffsets: IndexSet(integer: 1))
        draft.subtasks[0].isDone = true
        let now = Date(timeIntervalSince1970: 1000)
        let made = draft.makeTask(now: now)
        #expect(made?.subtasks.map(\.title) == ["a", "c"] && made?.subtasks.map(\.sortIndex) == [0, 1])
        #expect(made?.subtasks[0].completedAt == now && made?.subtasks[1].completedAt == nil)
    }

    @Test func editingKeepsUnknownValuesAndExistingChildren() {
        var original = task("Old", due: .unknown(.string("future")), repeatRule: RepeatRule(frequency: RepeatFrequency(rawValue: "yearly")))
        original.notes = "n"
        let completed = Date(timeIntervalSince1970: 50)
        original.subtasks = [Subtask(id: Subtask.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "s", completedAt: completed)]
        var draft = TaskDraft(task: original, today: today)
        #expect(draft.dueMode == .none && draft.repeatMode == .none && draft.canSave)
        draft.title = "New"
        let made = draft.makeTask(now: Date())
        #expect(made?.due == original.due && made?.repeatRule == original.repeatRule && made?.title == "New")
        #expect(made?.subtasks.first?.completedAt == completed)   // completion instant of an untouched subtask is kept
        draft.setDueMode(.date)
        #expect(draft.makeTask(now: Date())?.due == .date(draft.dueDate))
    }

    @Test func existingNextLessonLinkRoundTrips() {
        let link = LessonLink(lessonID: Lesson.ID(UUID()), date: date(2026, 10, 15))
        var original = task("Linked", due: .date(date(2026, 10, 15)))
        original.linkedLesson = link
        let draft = TaskDraft(task: original, today: today)
        #expect(draft.dueMode == .nextLesson && draft.issues == [.nextLessonNeedsSubject])
        var subjectTask = original
        subjectTask.subjectID = Subject.ID(UUID())
        var withSubject = TaskDraft(task: subjectTask, today: today)
        #expect(withSubject.issues.isEmpty)
        withSubject.title = "Linked"
        #expect(withSubject.makeTask(now: Date())?.linkedLesson == link)
    }
}

@Suite("Next lesson and quick add")
struct TaskNextLessonTests {
    @Test func findsTheNextNonCancelledLessonOfASubject() throws {
        let database = SampleScenarios.secondary().database
        let resolver = try #require(ScheduleResolver(database: database, timetableID: database.timetables[0].id, context: context))
        let subject = try #require(database.subjects.first { $0.shortName == "MAT" } ?? database.subjects.first)
        let found = try #require(NextLessonResolver.find(subjectID: subject.id, resolver: resolver, now: SampleScenarios.referenceNow))
        #expect(found.date >= today && found.startTime != nil)
        let entries = resolver.day(found.date).entries.filter { $0.subject.id == subject.id && $0.status != .cancelled }
        #expect(entries.contains { $0.startTime == found.startTime })
        // Nothing earlier than `found` qualifies.
        for offset in 0..<max(0, today.days(to: found.date)) {
            let day = today.adding(days: offset)
            let early = resolver.day(day).entries.filter {
                $0.subject.id == subject.id && $0.status != .cancelled && $0.start > SampleScenarios.referenceNow
            }
            #expect(early.isEmpty)
        }
        #expect(NextLessonResolver.find(subjectID: Subject.ID(UUID()), resolver: resolver, now: SampleScenarios.referenceNow) == nil)
    }

    @Test func quickAddUsesTheLessonElseTomorrow() {
        let id = TaskItem.ID(UUID())
        #expect(TaskQuickAdd.makeTask(id: id, title: "  ", subject: nil, nextLesson: nil, today: today, fallbackTimetableID: nil) == nil)
        let plain = TaskQuickAdd.makeTask(id: id, title: " Buy pens ", subject: nil, nextLesson: nil, today: today,
                                          fallbackTimetableID: nil)
        #expect(plain?.title == "Buy pens" && plain?.due == .date(date(2026, 10, 14)) && plain?.kind == .todo)
        let subject = Subject(id: Subject.ID(UUID()), meta: EditorEntities.placeholderMeta, timetableID: Timetable.ID(UUID()),
                              name: "Maths", color: .white)
        let lessonID = Lesson.ID(UUID())
        let next = NextLesson(date: date(2026, 10, 16), startTime: time(9), lessonID: lessonID)
        let linked = TaskQuickAdd.makeTask(id: id, title: "Ex. 4", subject: subject, nextLesson: next, today: today,
                                           fallbackTimetableID: nil)
        #expect(linked?.due == .date(date(2026, 10, 16)) && linked?.linkedLesson?.lessonID == lessonID
                && linked?.kind == .homework && linked?.timetableID == subject.timetableID)
        // A lesson without a subject is ignored.
        #expect(TaskQuickAdd.makeTask(id: id, title: "x", subject: nil, nextLesson: next, today: today, fallbackTimetableID: nil)?.due
                == .date(date(2026, 10, 14)))
    }

    @Test func subtaskToggleAndRepeatSummary() {
        let sub = Subtask(id: Subtask.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "s")
        let base = task("t", subtasks: [sub])
        let at = Date(timeIntervalSince1970: 5)
        let done = TaskEdits.togglingSubtask(sub.id, in: base, now: at)
        #expect(done?.subtasks[0].completedAt == at)
        #expect(done.flatMap { TaskEdits.togglingSubtask(sub.id, in: $0, now: at) }?.subtasks[0].completedAt == nil)
        #expect(TaskEdits.togglingSubtask(Subtask.ID(UUID()), in: base, now: at) == nil)
        let summary = TaskRepeatSummary(rule: RepeatRule(frequency: .weekly, interval: 2, weekdays: [.wednesday, .monday],
                                                          until: date(2027, 1, 31)))
        #expect(summary?.lines(renderer: renderer) == ["Every 2 weeks", "On Mon and Wed", "Until 31 Jan 2027"])
        #expect(TaskRepeatSummary(rule: RepeatRule(frequency: RepeatFrequency(rawValue: "yearly"))) == nil)
        #expect(TaskRepeatSummary(rule: nil) == nil)
    }
}
