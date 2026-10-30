// The Tasks tab's list logic (Phase 3 B1): which task belongs to which segment (Today / Upcoming / Overdue /
// Completed), the subject filter, the sort orders and the segment counts. Pure value logic, Linux-tested.
// Phase 4U U2 (R2): the tab is ONE grouped list. `TaskSection` (Overdue, Today, Tomorrow, This week, Later, No date)
// groups the open tasks; completed tasks sit behind a button. `TaskSegment` stays as the "where to look" vocabulary of
// the routes and of `AppNavigation.showTasks` (it maps to a scroll anchor, `TaskListModel.anchor(for:in:)`).
//
// Classification (all in the user's wall clock, `now` = `CalendarContext.local(from:)`):
//   - completed (`completedAt` set)                        -> Completed
//   - open, due date before today                          -> Overdue
//   - open, due today with a time that has already passed  -> Overdue (a date-only task is due all day)
//   - open, due today                                      -> Today
//   - open, due later, undated, or an unknown due kind     -> Upcoming (undated tasks sort last)
// Tombstoned tasks never appear. Segments are disjoint, so the counts add up.
import Foundation
import TimetableCore

/// The segments of the Tasks tab, in display order.
public enum TaskSegment: String, CaseIterable, Sendable, Equatable {
    case today, upcoming, overdue, completed

}

/// The sections of the grouped Tasks list, in display order (R2). Undated tasks get their own "No date" section, last:
/// they are neither late nor planned, and a "Later" section full of undated items would hide the dated ones.
public enum TaskSection: String, CaseIterable, Sendable, Equatable, Hashable {
    case overdue, today, tomorrow, thisWeek, later, noDate

    /// Catalog key of the section header.
    public var titleKey: String { "tasks.section." + rawValue }
}

/// One non-empty section with its tasks (sorted).
public struct TaskSectionGroup: Equatable, Sendable, Identifiable {
    public let section: TaskSection
    public let tasks: [TaskItem]
    public var id: TaskSection { section }

    public init(section: TaskSection, tasks: [TaskItem]) {
        self.section = section
        self.tasks = tasks
    }
}

/// A place in the grouped list a route or an in-app link can scroll to.
public enum TaskListAnchor: Hashable, Sendable {
    case section(TaskSection)
    /// The "Show N completed tasks" button; also opens the completed tasks.
    case completed
}

/// How a segment is sorted.
public enum TaskSort: String, CaseIterable, Sendable, Equatable {
    /// Due date/time ascending, undated last; ties by priority (highest first), title, id.
    case due
    /// Priority (highest first); ties by due date/time (undated last), title, id.
    case priority

    /// Catalog key of the menu entry.
    public var titleKey: String { "tasks.sort." + rawValue }
}

/// Number of tasks per segment (after the subject filter).
public struct TaskSegmentCounts: Equatable, Sendable {
    public var today = 0
    public var upcoming = 0
    public var overdue = 0
    public var completed = 0

    public init(today: Int = 0, upcoming: Int = 0, overdue: Int = 0, completed: Int = 0) {
        self.today = today
        self.upcoming = upcoming
        self.overdue = overdue
        self.completed = completed
    }

    public subscript(segment: TaskSegment) -> Int {
        switch segment {
        case .today: return today
        case .upcoming: return upcoming
        case .overdue: return overdue
        case .completed: return completed
        }
    }

    /// Open tasks (everything but Completed).
    public var open: Int { today + upcoming + overdue }
    /// All shown tasks.
    public var total: Int { open + completed }
}

/// Classification, filtering and sorting.
public enum TaskListModel {
    /// The segment of `task` at `now`; `nil` for tombstoned tasks.
    public static func segment(of task: TaskItem, now: LocalDateTime) -> TaskSegment? {
        guard !task.isDeleted else { return nil }
        if task.isCompleted { return .completed }
        guard let due = task.due, let date = due.date else { return .upcoming }
        if date < now.date { return .overdue }
        if date > now.date { return .upcoming }
        if let time = due.time, time < now.time { return .overdue }
        return .today
    }

    /// The last day of the calendar week that contains `today` (honours the first weekday).
    public static func lastDayOfWeek(containing today: LocalDate, context: CalendarContext) -> LocalDate {
        context.startOfWeek(containing: today).adding(days: 6)
    }

    /// The grouped-list section of an OPEN task; `nil` for completed and deleted tasks. Overdue = before today, or today
    /// with a time that has passed (`segment(of:)`); "This week" = after tomorrow until `lastDayOfWeek`; later weeks
    /// are "Later"; undated and unknown due kinds are "No date". Dates are calendar days (`LocalDate`), so DST changes
    /// cannot move a task between sections.
    public static func section(of task: TaskItem, now: LocalDateTime, lastDayOfWeek: LocalDate) -> TaskSection? {
        switch segment(of: task, now: now) {
        case nil, .completed?: return nil
        case .overdue?: return .overdue
        case .today?: return .today
        case .upcoming?:
            guard let date = task.due?.date else { return .noDate }
            let ahead = now.date.days(to: date)
            if ahead == 1 { return .tomorrow }
            return date <= lastDayOfWeek ? .thisWeek : .later
        }
    }

    /// The non-empty sections of the open tasks in display order, each sorted by `sort`. Filters: one subject, one kind.
    public static func sections(of tasks: [TaskItem], now: LocalDateTime, lastDayOfWeek: LocalDate,
                                subjectFilter: Subject.ID? = nil, kindFilter: TaskKind? = nil,
                                sort: TaskSort = .due) -> [TaskSectionGroup] {
        let shown = tasks.filter { matches($0, subjectFilter) && (kindFilter == nil || $0.kind == kindFilter) }
        return TaskSection.allCases.compactMap { section in
            let inSection = shown.filter { Self.section(of: $0, now: now, lastDayOfWeek: lastDayOfWeek) == section }
            return inSection.isEmpty ? nil : TaskSectionGroup(section: section, tasks: inSection.sorted { precedes($0, $1, sort: sort) })
        }
    }

    /// The completed tasks (same filters), newest completed first.
    public static func completedTasks(of tasks: [TaskItem], now: LocalDateTime, subjectFilter: Subject.ID? = nil,
                                      kindFilter: TaskKind? = nil) -> [TaskItem] {
        self.tasks(in: .completed, from: tasks.filter { kindFilter == nil || $0.kind == kindFilter }, now: now,
                   subjectFilter: subjectFilter)
    }

    /// Where `segment` points in the grouped list: Overdue and Today to their sections (`nil` when empty), Upcoming to
    /// the first non-empty section after today, Completed to the completed button. `nil` = stay at the top.
    public static func anchor(for segment: TaskSegment, in groups: [TaskSectionGroup]) -> TaskListAnchor? {
        let present = Set(groups.map(\.section))
        switch segment {
        case .completed: return .completed
        case .overdue: return present.contains(.overdue) ? .section(.overdue) : nil
        case .today: return present.contains(.today) ? .section(.today) : nil
        case .upcoming:
            return [TaskSection.tomorrow, .thisWeek, .later, .noDate].first(where: present.contains).map { .section($0) }
        }
    }

    /// Counts per segment. `subjectFilter` limits to one subject (`nil` = all).
    public static func counts(of tasks: [TaskItem], now: LocalDateTime, subjectFilter: Subject.ID? = nil) -> TaskSegmentCounts {
        var counts = TaskSegmentCounts()
        for task in tasks where matches(task, subjectFilter) {
            switch segment(of: task, now: now) {
            case .today?: counts.today += 1
            case .upcoming?: counts.upcoming += 1
            case .overdue?: counts.overdue += 1
            case .completed?: counts.completed += 1
            case nil: break
            }
        }
        return counts
    }

    /// The tasks of `segment`, sorted. Completed tasks are always newest-completed first (`sort` does not apply).
    public static func tasks(in segment: TaskSegment, from tasks: [TaskItem], now: LocalDateTime,
                             subjectFilter: Subject.ID? = nil, sort: TaskSort = .due) -> [TaskItem] {
        let inSegment = tasks.filter { matches($0, subjectFilter) && Self.segment(of: $0, now: now) == segment }
        switch segment {
        case .completed:
            return inSegment.sorted {
                ($0.completedAt ?? Date.distantPast, $1.title, $1.id) > ($1.completedAt ?? Date.distantPast, $0.title, $0.id)
            }
        default:
            return inSegment.sorted { precedes($0, $1, sort: sort) }
        }
    }

    /// The subjects (live, referenced by at least one live task) a filter menu should offer: grouped by timetable in
    /// `timetableOrder` (the timetables list order), each timetable's subjects in display order (`SubjectOrder`).
    public static func filterSubjects(tasks: [TaskItem], subjects: [Subject], timetableOrder: [Timetable.ID],
                                      locale: Locale) -> [Subject] {
        let used = Set(tasks.filter { !$0.isDeleted }.compactMap(\.subjectID))
        return SubjectOrder.sorted(subjects.filter { !$0.isDeleted && used.contains($0.id) },
                                   timetableOrder: timetableOrder, locale: locale)
    }

    // MARK: Internals

    private static func matches(_ task: TaskItem, _ filter: Subject.ID?) -> Bool {
        filter == nil || task.subjectID == filter
    }

    /// Sort key of the due date: undated (or unknown due) tasks sort after every dated task.
    private static func dueKey(_ task: TaskItem) -> Int {
        guard let due = task.due, let date = due.date else { return Int.max }
        return date.daysSinceEpoch * 1_440 + (due.time?.minuteOfDay ?? 1_439)
    }

    private static func precedes(_ a: TaskItem, _ b: TaskItem, sort: TaskSort) -> Bool {
        switch sort {
        case .due:
            if dueKey(a) != dueKey(b) { return dueKey(a) < dueKey(b) }
            if a.priority != b.priority { return a.priority > b.priority }
        case .priority:
            if a.priority != b.priority { return a.priority > b.priority }
            if dueKey(a) != dueKey(b) { return dueKey(a) < dueKey(b) }
        }
        return (a.title, a.id) < (b.title, b.id)
    }
}
