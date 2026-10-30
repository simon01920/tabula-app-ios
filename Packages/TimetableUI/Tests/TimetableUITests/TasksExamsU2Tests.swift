import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4U U2: the grouped Tasks list, the quick-entry defaults, the exam "When" mapping and the exam actions by date.

private let zone = TimeZone(identifier: "Europe/Bratislava")!
private let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
// Tuesday 13 Oct 2026, 10:20. The calendar week (Monday first) ends on Sunday 18 Oct.
private let today = date(2026, 10, 13)
private let now = LocalDateTime(date: today, time: time(10, 20))
private let lastDay = date(2026, 10, 18)
private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: zone),
    lookup: EnglishCatalog.lookup)

private func task(_ title: String, due: TaskDue? = nil, kind: TaskKind = .homework, completed: Date? = nil,
                  subject: Subject.ID? = nil) -> TaskItem {
    TaskItem(id: TaskItem.ID(UUID()), meta: EditorEntities.placeholderMeta, title: title, kind: kind, subjectID: subject,
             due: due, completedAt: completed)
}

private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

@Suite("Grouped task list")
struct TaskSectionTests {
    private func section(_ due: TaskDue?, at moment: LocalDateTime = now, last: LocalDate = lastDay) -> TaskSection? {
        TaskListModel.section(of: task("t", due: due), now: moment, lastDayOfWeek: last)
    }

    @Test func everyOpenTaskLandsInExactlyOneSection() {
        #expect(section(.date(date(2026, 10, 12))) == .overdue)
        #expect(section(.dateTime(today, time(8))) == .overdue)          // overdue today: the time has passed
        #expect(section(.dateTime(today, time(23, 59))) == .today)
        #expect(section(.date(today)) == .today)
        #expect(section(.date(date(2026, 10, 14))) == .tomorrow)
        #expect(section(.date(date(2026, 10, 15))) == .thisWeek)
        #expect(section(.date(lastDay)) == .thisWeek)                    // the last day of the week is still this week
        #expect(section(.date(date(2026, 10, 19))) == .later)
        #expect(section(nil) == .noDate)
        #expect(section(.unknown(.null)) == .noDate)
        #expect(TaskListModel.section(of: task("done", due: .date(today), completed: Date()), now: now, lastDayOfWeek: lastDay) == nil)
        var deleted = task("gone", due: .date(today))
        deleted.meta.isDeleted = true
        #expect(TaskListModel.section(of: deleted, now: now, lastDayOfWeek: lastDay) == nil)
    }

    @Test func tomorrowIsThisWeekOnlyBeforeTheWeekEnds() {
        // On the last day of the week, tomorrow is next week: it is "Tomorrow", and the day after is "Later".
        let sunday = LocalDateTime(date: lastDay, time: time(9))
        #expect(section(.date(date(2026, 10, 19)), at: sunday) == .tomorrow)
        #expect(section(.date(date(2026, 10, 20)), at: sunday) == .later)
        #expect(TaskListModel.lastDayOfWeek(containing: today, context: context) == lastDay)
        let sundayFirst = CalendarContext(timeZone: zone, firstWeekday: .sunday)
        #expect(TaskListModel.lastDayOfWeek(containing: today, context: sundayFirst) == date(2026, 10, 17))
    }

    @Test func midnightRolloverAndDSTMoveTasksByCalendarDay() {
        // 25 Oct 2026: clocks go back at 03:00 (a 25-hour day). A task due Mon 26 Oct is "Tomorrow" at 00:30 CEST on the
        // 25th and "Today" at 23:30 CET, i.e. 00:30 on the 26th: the section follows the wall-clock date.
        let due = TaskDue.date(date(2026, 10, 26))
        let before = context.local(from: instant("2026-10-24T22:30:00Z"))
        let lateOn25th = context.local(from: instant("2026-10-25T22:30:00Z"))
        let after = context.local(from: instant("2026-10-25T23:30:00Z"))
        #expect(before.date == date(2026, 10, 25) && lateOn25th.date == date(2026, 10, 25) && after.date == date(2026, 10, 26))
        #expect(section(due, at: before, last: date(2026, 10, 25)) == .tomorrow)
        #expect(section(due, at: lateOn25th, last: date(2026, 10, 25)) == .tomorrow)
        #expect(section(due, at: after, last: date(2026, 11, 1)) == .today)
        // Spring forward (29 Mar 2026): the same holds across the 23-hour day.
        let springDue = TaskDue.date(date(2026, 3, 30))
        let evening = context.local(from: instant("2026-03-29T21:30:00Z"))   // 23:30 CEST on the 29th
        #expect(section(springDue, at: evening, last: date(2026, 3, 29)) == .tomorrow)
    }

    @Test func groupsAreOrderedSortedAndFiltered() {
        let maths = Subject.ID(UUID())
        let list = [
            task("later", due: .date(date(2026, 11, 2))), task("none"), task("late-today", due: .date(today), subject: maths),
            task("mon", due: .date(date(2026, 10, 12))), task("tomorrow", due: .date(date(2026, 10, 14)), kind: .todo),
            task("week-b", due: .date(date(2026, 10, 16))), task("week-a", due: .date(date(2026, 10, 15))),
            task("done", completed: Date()),
        ]
        let groups = TaskListModel.sections(of: list, now: now, lastDayOfWeek: lastDay)
        #expect(groups.map(\.section) == [.overdue, .today, .tomorrow, .thisWeek, .later, .noDate])
        #expect(groups[3].tasks.map(\.title) == ["week-a", "week-b"])
        #expect(TaskListModel.sections(of: list, now: now, lastDayOfWeek: lastDay, subjectFilter: maths).map(\.section) == [.today])
        #expect(TaskListModel.sections(of: list, now: now, lastDayOfWeek: lastDay, kindFilter: .todo).map(\.section) == [.tomorrow])
        #expect(TaskListModel.sections(of: [], now: now, lastDayOfWeek: lastDay).isEmpty)
        #expect(TaskListModel.completedTasks(of: list, now: now).map(\.title) == ["done"])
        #expect(TaskListModel.completedTasks(of: list, now: now, kindFilter: .todo).isEmpty)
    }

    @Test func segmentsMapToAnchors() {
        let groups = TaskListModel.sections(of: [task("o", due: .date(date(2026, 10, 12))), task("l", due: .date(date(2026, 11, 2)))],
                                            now: now, lastDayOfWeek: lastDay)
        #expect(TaskListModel.anchor(for: .overdue, in: groups) == .section(.overdue))
        #expect(TaskListModel.anchor(for: .today, in: groups) == nil)               // empty: stay at the top
        #expect(TaskListModel.anchor(for: .upcoming, in: groups) == .section(.later))
        #expect(TaskListModel.anchor(for: .completed, in: groups) == .completed)
    }

    @Test func dueLabelIsHiddenWhenItEqualsTheSection() {
        let todayPlain = TaskDueDescription.make(due: .date(today), today: today)
        let todayTimed = TaskDueDescription.make(due: .dateTime(today, time(23, 30)), today: today)
        let tomorrow = TaskDueDescription.make(due: .date(date(2026, 10, 14)), today: today)
        let overdue = TaskDueDescription.make(due: .date(date(2026, 10, 11)), today: today)
        #expect(todayPlain?.line(in: .today) == nil)
        #expect(todayTimed?.line(in: .today) == .timeOnly(time(23, 30)))
        #expect(tomorrow?.line(in: .tomorrow) == nil)
        #expect(todayPlain?.line(in: .overdue) == .full(todayPlain!))      // overdue today keeps "Today, 8:00"
        #expect(overdue?.line(in: .overdue) == .full(overdue!))
        #expect(tomorrow?.line(in: nil) == .full(tomorrow!))
    }

    @Test func repeatIsOneLine() {
        let weekly = TaskRepeatSummary(rule: RepeatRule(frequency: .weekly, interval: 1, weekdays: [.tuesday]))
        #expect(weekly?.line(renderer: renderer) == "Weekly on Tuesday")
        let biweekly = TaskRepeatSummary(rule: RepeatRule(frequency: .weekly, interval: 2, weekdays: [.wednesday, .monday],
                                                          until: date(2027, 1, 31)))
        #expect(biweekly?.line(renderer: renderer) == "Every 2 weeks on Monday and Wednesday")
        #expect(biweekly?.untilText(renderer: renderer) == "Until 31 Jan 2027")
        #expect(TaskRepeatSummary(rule: RepeatRule(frequency: .daily))?.line(renderer: renderer) == "Every day")
        #expect(TaskRepeatSummary(rule: RepeatRule(frequency: .weekly, interval: 3))?.line(renderer: renderer) == "Every 3 weeks")
    }
}

@Suite("Quick entry")
struct TaskQuickEntryTests {
    private let maths = Subject.ID(UUID())
    private let timetable = Timetable.ID(UUID())
    private let next = NextLesson(date: date(2026, 10, 16), startTime: time(9), lessonID: Lesson.ID(UUID()))

    private func draft(subject: Subject.ID?, lesson: NextLesson?) -> TaskDraft {
        TaskQuickEntry.initialDraft(id: TaskItem.ID(UUID()), today: today, timetableID: timetable, subjectID: subject, nextLesson: lesson)
    }

    @Test func homeworkWithASubjectDefaultsToTheNextLesson() {
        let made = draft(subject: maths, lesson: next)
        #expect(made.kind == .homework && made.dueMode == .nextLesson && made.nextLesson == next)
        #expect(TaskQuickEntry.choice(of: made, today: today) == .nextLesson)
        #expect(made.canSave == false && made.issues == [.titleEmpty])      // Add stays disabled without a title
        var titled = made
        titled.title = "  Ex. 4  "
        let task = titled.makeTask(now: Date())
        #expect(task?.title == "Ex. 4" && task?.due == .date(date(2026, 10, 16)) && task?.linkedLesson?.lessonID == next.lessonID)
    }

    @Test func withoutASubjectItIsATodoDueTomorrow() {
        let made = draft(subject: nil, lesson: next)                        // a lesson without a subject is ignored
        #expect(made.kind == .todo && made.dueMode == .date && made.dueDate == date(2026, 10, 14))
        #expect(TaskQuickEntry.choice(of: made, today: today) == .tomorrow)
        #expect(TaskQuickEntry.options(nextLesson: nil) == [.tomorrow, .date])
        #expect(TaskQuickEntry.options(nextLesson: next) == [.nextLesson, .tomorrow, .date])
    }

    @Test func untouchedTypeAndDueFollowTheSubject() {
        var made = draft(subject: nil, lesson: nil)
        made.quickChooseSubject(maths, nextLesson: next, today: today, followKind: true, followDue: true)
        #expect(made.kind == .homework && made.dueMode == .nextLesson && made.nextLesson == next)
        made.quickChooseSubject(nil, nextLesson: nil, today: today, followKind: true, followDue: true)
        #expect(made.kind == .todo && made.subjectID == nil && made.dueMode == .date && made.dueDate == date(2026, 10, 14))
    }

    @Test func chosenTypeAndDueAreKept() {
        var made = draft(subject: maths, lesson: next)
        made.quickChooseKind(.assignment, nextLesson: next, today: today, followDue: false)
        #expect(made.kind == .assignment && made.dueMode == .nextLesson)    // the user chose the due: it stays
        made.quickChooseKind(.todo, nextLesson: next, today: today, followDue: true)
        #expect(made.dueMode == .date && made.dueDate == date(2026, 10, 14))
        made.quickApply(.date, nextLesson: next, today: today)
        made.dueDate = date(2026, 10, 30)
        #expect(TaskQuickEntry.choice(of: made, today: today) == .date)
        // A chosen "next lesson" follows a new subject; when that subject has none it falls back to tomorrow.
        var follow = draft(subject: maths, lesson: next)
        follow.quickChooseSubject(Subject.ID(UUID()), nextLesson: nil, today: today, followKind: false, followDue: false)
        #expect(follow.dueMode == .date && follow.dueDate == date(2026, 10, 14))
        #expect(TaskQuickEntry.kinds == [.homework, .todo, .assignment])
    }
}

@Suite("Exam When and actions")
struct ExamWhenTests {
    private static func lessonFixture(_ name: String, _ start: LocalTime, _ end: LocalTime,
                                      status: ResolvedLesson.Status = .scheduled) -> ResolvedLesson {
        let subject = SubjectSummary(id: Subject.ID(UUID()), name: name, color: .white)
        let lessonID = Lesson.ID(UUID())
        let day = date(2026, 10, 20)
        let startInstant = context.date(day, start)
        let endInstant = context.date(day, end)
        return ResolvedLesson(id: .lesson(lessonID, on: day), source: .lesson(lessonID), timetableID: Timetable.ID(UUID()), date: day,
                              subject: subject, startTime: start, endTime: end, start: startInstant, end: endInstant, status: status)
    }

    // Stored, not computed: every access of a computed one would mint new random ids.
    private let choices = ExamLessonChoice.choices(from: [
        Self.lessonFixture("B", time(9, 55), time(10, 40)), Self.lessonFixture("A", time(8), time(8, 45)),
        Self.lessonFixture("C", time(11), time(11, 45), status: .cancelled),
    ])

    @Test func choicesSkipCancelledLessonsAndSortByStart() {
        #expect(choices.map(\.subject.name) == ["A", "B"])
    }

    @Test func modesMapOntoTheExistingFields() throws {
        var draft = ExamDraft(newOn: today, timetableID: nil)
        #expect(draft.timeMode == .allDay && !draft.hasStart)
        draft.setTimeMode(.custom, choices: choices)
        #expect(draft.timeMode == .custom && draft.hasStart)
        draft.setTimeMode(.lesson, choices: choices)
        #expect(draft.timeMode == .lesson && draft.start == time(8) && draft.end == time(8, 45) && draft.hasEnd)
        #expect(draft.subjectID == choices[0].subject.id)                    // an exam without a subject takes the lesson's
        draft.title = "Maths"
        let lessonExam = try #require(draft.makeExam())
        #expect(lessonExam.start == time(8) && lessonExam.end == time(8, 45))
        draft.chooseLesson(choices[1])
        #expect(draft.start == time(9, 55) && draft.end == time(10, 40) && draft.subjectID == choices[0].subject.id)
        draft.setTimeMode(.allDay, choices: choices)
        let allDay = try #require(draft.makeExam())
        #expect(allDay.start == nil && allDay.end == nil && !draft.hasEnd)
    }

    @Test func lessonModeIsOnlyOfferedWithLessons() {
        var draft = ExamDraft(newOn: today, timetableID: nil)
        #expect(draft.availableTimeModes(choices: []) == [.custom, .allDay])
        #expect(draft.availableTimeModes(choices: choices) == [.lesson, .custom, .allDay])
        draft.setTimeMode(.lesson, choices: [])                              // nothing to take times from: unchanged
        #expect(draft.timeMode == .allDay)
        draft.chooseLesson(choices[0])
        #expect(draft.availableTimeModes(choices: []).contains(.lesson))     // never vanishes under the user
    }

    @Test func aStoredExamOpensOnTheLessonItMatchesAndAChangedDateFallsBackToCustom() {
        var exam = Exam(id: Exam.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "T", date: date(2026, 10, 20))
        exam.start = time(9, 55)
        exam.end = time(10, 40)
        var draft = ExamDraft(exam: exam)
        #expect(draft.timeMode == .custom)
        draft.syncTimeMode(choices: choices)
        #expect(draft.timeMode == .lesson && draft.chosenLessonID == choices[1].id)
        draft.syncTimeMode(choices: [])                                      // the date changed to a day without that lesson
        #expect(draft.timeMode == .custom && draft.start == time(9, 55) && draft.end == time(10, 40))
        var plain = ExamDraft(exam: Exam(id: Exam.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "T", date: date(2026, 10, 20)))
        plain.syncTimeMode(choices: choices)
        #expect(plain.timeMode == .allDay)
    }

    @Test func doneActionDependsOnTheExamDate() {
        let exam = date(2026, 10, 20)
        #expect(ExamCompletionAction(examDate: exam, today: date(2026, 10, 19)) == .moveToHistory)
        #expect(ExamCompletionAction(examDate: exam, today: exam) == .takenIt)
        #expect(ExamCompletionAction(examDate: exam, today: date(2026, 10, 21)) == .takenIt)
        #expect(ExamCompletionAction.takenIt.isPrimaryButton && !ExamCompletionAction.moveToHistory.isPrimaryButton)
        #expect(ExamCompletionAction.allKeys == [ExamCompletionAction.takenIt.l10nKey, ExamCompletionAction.moveToHistory.l10nKey])
    }

    @Test func relativeTimeIsOnlyShownWithinTwoWeeks() {
        func row(_ days: Int) -> ExamRow {
            ExamRow(exam: Exam(id: Exam.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "T", date: today.adding(days: days)),
                    subject: nil, today: today)
        }
        #expect(row(14).showsRelativeTime && !row(15).showsRelativeTime && !row(91).showsRelativeTime)
        #expect(row(0).showsRelativeTime && row(-3).showsRelativeTime && !row(-40).showsRelativeTime)
        #expect(ExamUrgency.later.emphasisSymbolName == nil && ExamUrgency.thisWeek.emphasisSymbolName == nil)
        #expect(ExamUrgency.tomorrow.emphasisSymbolName != nil && ExamUrgency.soon.emphasisSymbolName != nil)
    }

    @Test func roomBuildingAndNotesAreSavedWhateverTheVisibilitySays() {
        var exam = Exam(id: Exam.ID(UUID()), meta: EditorEntities.placeholderMeta, title: "T", date: today)
        exam.room = "A1"
        var draft = ExamDraft(exam: exam)
        draft.building = " Main "
        draft.notes = "Bring ID"
        let saved = draft.makeExam()
        #expect(saved?.room == "A1" && saved?.building == "Main" && saved?.notes == "Bring ID")
    }
}
