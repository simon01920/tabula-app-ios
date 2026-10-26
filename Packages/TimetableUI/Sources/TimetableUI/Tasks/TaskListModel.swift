// The Tasks tab's list logic (Phase 3 B1): which task belongs to which segment (Today / Upcoming / Overdue /
// Completed), the subject filter, the sort orders and the segment counts. Pure value logic, Linux-tested.
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

    /// Catalog key of the segment label with its count (`%lld`), shown in the segmented control.
    public var countedTitleKey: String { "tasks.segment." + rawValue + ".count" }
    /// SF Symbol of the segment (empty states).
    public var symbolName: String {
        switch self {
        case .today: return AppSymbol.today.rawValue
        case .upcoming: return AppSymbol.date.rawValue
        case .overdue: return AppSymbol.overdue.rawValue
        case .completed: return AppSymbol.completed.rawValue
        }
    }
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
