// Timeline planning for the *Homework* and *Next exam* widgets (PHASE4_PLAN §0.3, Stage B1), next to the Now & Next
// planner (WidgetTimelinePlanner.swift; the Today widget reuses that one, see `TodayPresenter`). Pure, Linux-tested; the
// widget extension's TimelineProvider only maps the result.
//
// Homework state at an instant = the snapshot's overdue list + its tasks due within 7 days, with "overdue" re-evaluated
// at the instant (a task due 16:00 is overdue from 16:01, the Tasks tab's rule: today with the time passed), sorted
// overdue first (oldest due date first), then due soonest (date / time, undated time last, then priority, title, id).
// Entries: `now`, every midnight of the covered days (relative texts change: "Tomorrow" → "Today") and one minute after
// each due time (the task turns overdue).
//
// Exam state at an instant = the snapshot's next exam relative to today: a later day (countdown in days), today (before
// the start: a live countdown; in progress; started without a known end; finished), or none. Entries: `now`, each
// midnight up to the exam day, the exam's start and its end. An exam whose date has passed is `.unavailable(.outdated)`
// (the next exam is unknown until the app writes again: never stale or invented data).
//
// Coverage (when the snapshot is "outdated"): the same range as Now & Next, i.e. through the snapshot's last covered
// day (or a week after the day it was written when there is no timetable). The reload rules are the Now & Next ones
// (`WidgetTimelinePlanner`): at most `maxEntries`, a cut timeline ends at its last midnight, reload ≤ 6 h after now.
import Foundation
import TimetableCore

/// One entry of a state-based widget timeline.
public struct WidgetStateEntry<State: Equatable & Sendable>: Equatable, Sendable {
    /// When the entry becomes current.
    public var date: Date
    /// The state from `date` until the next entry.
    public var state: State

    public init(date: Date, state: State) {
        self.date = date
        self.state = state
    }
}

/// A planned timeline of states.
public struct WidgetStatePlan<State: Equatable & Sendable>: Equatable, Sendable {
    /// Entries, ascending by date, the first at "now"; never empty.
    public var entries: [WidgetStateEntry<State>]
    /// When WidgetKit should ask for a new timeline.
    public var reloadDate: Date
    /// The calendar context the instants were computed in (`nil` without a snapshot).
    public var context: CalendarContext?
}

extension WidgetTimelinePlanner {
    /// The last day the snapshot covers: its last day, else a week after the day it was written.
    static func coverageLastDay(_ snapshot: WidgetSnapshot, context: CalendarContext) -> LocalDate {
        snapshot.lastDay ?? context.localDate(of: snapshot.generatedAt).adding(days: WidgetSnapshotBuilder.fallbackCoveredDays)
    }

    /// Shared tail of the state planners: `now` plus the future `boundaries` (≤ `maxEntries`, cut at the last midnight
    /// inside the kept range when cut), the reload date (≤ `maxReloadInterval`).
    static func assemble<State: Equatable & Sendable>(
        now: Date, boundaries: Set<Date>, midnights: Set<Date>, coverageEnd: Date, context: CalendarContext,
        state: (Date) -> State
    ) -> WidgetStatePlan<State> {
        let future = boundaries.union(midnights).filter { $0 > now }.sorted()
        var kept = Array(future.prefix(maxEntries - 1))
        let isCut = kept.count < future.count
        if isCut, let lastMidnight = kept.lastIndex(where: { midnights.contains($0) }) {
            kept = Array(kept[...lastMidnight])
        }
        let entries = ([now] + kept).map { WidgetStateEntry(date: $0, state: state($0)) }
        let natural = isCut ? (kept.last ?? now) : max(coverageEnd, now)
        return WidgetStatePlan(entries: entries, reloadDate: min(natural, now.addingTimeInterval(maxReloadInterval)),
                               context: context)
    }
}

// MARK: - Homework

/// What the Homework widget lists at one instant.
public struct HomeworkList: Equatable, Sendable {
    /// One open task.
    public struct Row: Equatable, Sendable, Identifiable {
        public var task: WidgetSnapshot.DueTask
        /// Past its due date / time at the instant.
        public var isOverdue: Bool
        public var id: UUID { task.id }
    }

    /// Overdue tasks first (oldest first), then by due date / time.
    public var rows: [Row]
    /// Every overdue task at the instant, listed or not.
    public var overdueTotal: Int
    /// Overdue tasks the snapshot did not list (cap `WidgetSnapshotBuilder.maxOverdueTasks`).
    public var unlistedOverdue: Int

    /// Open tasks known to the widget (overdue + due within a week), listed or not.
    public var knownTotal: Int { rows.count + unlistedOverdue }
    /// The true number of open tasks (the snapshot's `openTaskCount`, at least `knownTotal`).
    public var total: Int

}

/// The Homework widget's state.
public enum HomeworkState: Equatable, Sendable {
    case list(HomeworkList)
    case unavailable(NowNextState.Unavailable)
}

public enum HomeworkPlanner {
    /// The timeline from `now`.
    public static func plan(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone) -> WidgetStatePlan<HomeworkState> {
        guard let snapshot else {
            return WidgetStatePlan(entries: [WidgetStateEntry(date: now, state: .unavailable(.noSnapshot))],
                                   reloadDate: now.addingTimeInterval(WidgetTimelinePlanner.unavailableRetry), context: nil)
        }
        let context = WidgetTimelinePlanner.context(for: snapshot, deviceTimeZone: deviceTimeZone)
        if case .unavailable = state(snapshot: snapshot, at: now, context: context) {
            return WidgetStatePlan(entries: [WidgetStateEntry(date: now, state: state(snapshot: snapshot, at: now, context: context))],
                                   reloadDate: now.addingTimeInterval(WidgetTimelinePlanner.unavailableRetry), context: context)
        }
        let today = context.localDate(of: now)
        let last = WidgetTimelinePlanner.coverageLastDay(snapshot, context: context)
        var midnights: Set<Date> = []
        var date = today
        while date <= last {
            midnights.insert(context.startOfDay(date.adding(days: 1)))
            date = date.adding(days: 1)
        }
        var boundaries: Set<Date> = []
        for task in snapshot.tasks {
            guard let time = task.dueTime, task.dueDate >= today, task.dueDate <= last else { continue }
            boundaries.insert(context.date(task.dueDate, time).addingTimeInterval(60))   // overdue once the minute has passed
        }
        return WidgetTimelinePlanner.assemble(now: now, boundaries: boundaries, midnights: midnights,
                                              coverageEnd: context.startOfDay(last.adding(days: 1)), context: context) {
            state(snapshot: snapshot, at: $0, context: context)
        }
    }

    /// The state at `instant`.
    public static func state(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> HomeworkState {
        let local = context.local(from: instant)
        if local.date > WidgetTimelinePlanner.coverageLastDay(snapshot, context: context) { return .unavailable(.outdated) }
        func overdue(_ task: WidgetSnapshot.DueTask) -> Bool {
            if task.dueDate != local.date { return task.dueDate < local.date }
            if let time = task.dueTime { return time < local.time }
            return false
        }
        let listedOverdue = snapshot.overdueTasks
        let rows = (listedOverdue + snapshot.tasks).map { HomeworkList.Row(task: $0, isOverdue: overdue($0)) }
            .sorted(by: ordered)
        let newlyOverdue = snapshot.tasks.filter(overdue).count
        let unlisted = max(0, snapshot.overdueTaskCount - listedOverdue.count)
        return .list(HomeworkList(rows: rows, overdueTotal: snapshot.overdueTaskCount + newlyOverdue, unlistedOverdue: unlisted,
                                  total: max(snapshot.openTaskCount ?? 0, rows.count + unlisted)))
    }

    /// Overdue before open; then due date, due time (a task without a time after those with one), priority (highest
    /// first), title, id.
    static func ordered(_ lhs: HomeworkList.Row, _ rhs: HomeworkList.Row) -> Bool {
        if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
        let (l, r) = (lhs.task, rhs.task)
        if l.dueDate != r.dueDate { return l.dueDate < r.dueDate }
        switch (l.dueTime, r.dueTime) {
        case let (lt?, rt?) where lt != rt: return lt < rt
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if l.priority != r.priority { return l.priority > r.priority }
        if l.title != r.title { return l.title < r.title }
        return l.id.uuidString < r.id.uuidString
    }
}

// MARK: - Next exam

/// The Next exam widget's state.
public enum ExamState: Equatable, Sendable {
    /// Where the exam is today.
    public enum Phase: Equatable, Sendable {
        /// Before the start: a live countdown to `start`.
        case beforeStart(start: Date)
        /// No start time: "Today".
        case allDay
        /// Between the start and the end.
        case inProgress(start: Date, end: Date)
        /// After the start; the exam has no known end.
        case started(start: Date)
        /// After the end.
        case finished
    }

    /// The exam is on a later day.
    case upcoming(WidgetSnapshot.UpcomingExam, daysUntil: Int)
    /// The exam is today.
    case today(WidgetSnapshot.UpcomingExam, Phase)
    /// No upcoming exam.
    case none
    /// Nothing can be shown.
    case unavailable(NowNextState.Unavailable)
}

public enum ExamPlanner {
    /// The timeline from `now`.
    public static func plan(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone) -> WidgetStatePlan<ExamState> {
        guard let snapshot else {
            return WidgetStatePlan(entries: [WidgetStateEntry(date: now, state: .unavailable(.noSnapshot))],
                                   reloadDate: now.addingTimeInterval(WidgetTimelinePlanner.unavailableRetry), context: nil)
        }
        let context = WidgetTimelinePlanner.context(for: snapshot, deviceTimeZone: deviceTimeZone)
        let first = state(snapshot: snapshot, at: now, context: context)
        if case .unavailable = first {
            return WidgetStatePlan(entries: [WidgetStateEntry(date: now, state: first)],
                                   reloadDate: now.addingTimeInterval(WidgetTimelinePlanner.unavailableRetry), context: context)
        }
        let today = context.localDate(of: now)
        let exams = snapshot.upcomingExams.filter { $0.date >= today }
        let lastDay = exams.last.map { max($0.date, today) } ?? WidgetTimelinePlanner.coverageLastDay(snapshot, context: context)
        var midnights: Set<Date> = []
        var date = today
        // At most `maxEntries` midnights matter; do not walk months for a far exam.
        while date <= lastDay, midnights.count < WidgetTimelinePlanner.maxEntries {
            midnights.insert(context.startOfDay(date.adding(days: 1)))
            date = date.adding(days: 1)
        }
        var boundaries: Set<Date> = []
        for exam in exams {
            guard let startTime = exam.start else { continue }
            boundaries.insert(context.date(exam.date, startTime))
            if let endTime = exam.end, endTime > startTime { boundaries.insert(context.date(exam.date, endTime)) }
        }
        return WidgetTimelinePlanner.assemble(now: now, boundaries: boundaries, midnights: midnights,
                                              coverageEnd: context.startOfDay(lastDay.adding(days: 1)), context: context) {
            state(snapshot: snapshot, at: $0, context: context)
        }
    }

    /// The state at `instant`: the first listed exam that has not ended (an exam without a valid end lasts until
    /// midnight); a day's earlier exam hands over to the later one when it ends.
    public static func state(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> ExamState {
        let today = context.localDate(of: instant)
        let list = snapshot.upcomingExams
        func isOver(_ exam: WidgetSnapshot.UpcomingExam) -> Bool {
            if exam.date != today { return exam.date < today }
            guard let start = exam.start, let end = exam.end, end > start else { return false }
            return instant >= context.date(exam.date, end)
        }
        guard let exam = list.first(where: { !isOver($0) }) else {
            // Everything listed is over: the last one finished today, else nothing is known (a full list may hide
            // later exams; so may a snapshot older than its covered days).
            if let last = list.last, last.date == today { return .today(last, .finished) }
            if list.count >= WidgetSnapshotBuilder.maxExams { return .unavailable(.outdated) }
            return today > WidgetTimelinePlanner.coverageLastDay(snapshot, context: context) ? .unavailable(.outdated) : .none
        }
        let delta = today.days(to: exam.date)
        if delta > 0 { return .upcoming(exam, daysUntil: delta) }
        guard let startTime = exam.start else { return .today(exam, .allDay) }
        let start = context.date(exam.date, startTime)
        if instant < start { return .today(exam, .beforeStart(start: start)) }
        guard let endTime = exam.end, endTime > startTime else { return .today(exam, .started(start: start)) }
        return .today(exam, .inProgress(start: start, end: context.date(exam.date, endTime)))
    }
}
