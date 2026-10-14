// The work part of the Today tab (Phase 3 C1, PHASE3_PLAN §0.10): the "Due today" tasks with an overdue count, and
// the next exam when it is close. Pure, Linux-tested; `TodayRootView` renders it below the Now & Next header.
//
// Rules (same classification as the Tasks tab, `TaskListModel`, so the numbers always agree):
//   - Due today  = the Tasks tab's Today segment (open, due today, not yet past a due time), sorted by due.
//   - Overdue    = the Tasks tab's Overdue count (the chip opens that segment).
//   - Next exam  = the Exams tab's featured exam (`ExamListModel.next`) when it is at most `examHorizonDays` away.
//   - The section is absent when there is nothing due today and nothing overdue; the card is absent without an exam.
import Foundation
import TimetableCore

public struct TodayWork: Equatable, Sendable {
    /// How far ahead (whole days) the next exam is shown on Today.
    public static let examHorizonDays = 14

    /// Open tasks due today, in the Tasks tab's order.
    public var dueToday: [TaskItem]
    /// Open tasks whose due date (or due time today) has passed.
    public var overdueCount: Int
    /// The next upcoming exam within the horizon.
    public var nextExam: ExamRow?

    public init(dueToday: [TaskItem], overdueCount: Int, nextExam: ExamRow?) {
        self.dueToday = dueToday
        self.overdueCount = overdueCount
        self.nextExam = nextExam
    }

    /// `true` when the "Due today" section has something to show.
    public var showsTasks: Bool { !dueToday.isEmpty || overdueCount > 0 }

    /// Builds the state at `now` (wall clock in the user's calendar context).
    public static func make(database: TabulaDatabase, now: LocalDateTime, context: CalendarContext) -> TodayWork {
        let tasks = database.tasks.filter { !$0.isDeleted }
        let counts = TaskListModel.counts(of: tasks, now: now)
        let due = TaskListModel.tasks(in: .today, from: tasks, now: now, sort: .due)
        let next = ExamListModel.make(database: database, today: now.date, context: context).next
        let exam = next.flatMap { $0.daysUntil <= examHorizonDays ? $0 : nil }
        return TodayWork(dueToday: due, overdueCount: counts.overdue, nextExam: exam)
    }
}
