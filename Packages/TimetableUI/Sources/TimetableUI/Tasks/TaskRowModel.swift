// What one task row (and the detail header) shows: title, subject, relative due text, priority badge, subtask
// progress, attachment / repeat indicators, plus the one-sentence VoiceOver label. Pure, Linux-tested.
//
// Absence rule: a field that is empty or disabled yields `nil` / `0` / `false` here, so the view simply omits it
// (no placeholders, no dashes).
import Foundation
import TimetableCore

/// A due date described relative to today ("Today, 8:00", "Tomorrow", "In 3 days", "2 days overdue", "Oct 20, 2026").
public struct TaskDueDescription: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case today
        case tomorrow
        /// 2...6 days ahead.
        case inDays(Int)
        /// The due date is before today (>= 1 day ago).
        case overdueDays(Int)
        /// A date further away.
        case onDate(LocalDate)
    }

    public let kind: Kind
    /// The due time of a `dateTime` due (not shown for overdue-by-days).
    public let time: LocalTime?

    public init(kind: Kind, time: LocalTime?) {
        self.kind = kind
        self.time = kind.isOverdueDays ? nil : time
    }

    /// `nil` for a task without a (known) due date.
    public static func make(due: TaskDue?, today: LocalDate) -> TaskDueDescription? {
        guard let due, let date = due.date else { return nil }
        let delta = today.days(to: date)
        let kind: Kind
        switch delta {
        case ..<0: kind = .overdueDays(-delta)
        case 0: kind = .today
        case 1: kind = .tomorrow
        case 2...6: kind = .inDays(delta)
        default: kind = .onDate(date)
        }
        return TaskDueDescription(kind: kind, time: due.time)
    }

    /// The catalog key of the phrase (see `TaskL10nKeys.dueKeys`).
    public var catalogKey: String {
        switch (kind, time != nil) {
        case (.today, false): return "tasks.due.today"
        case (.today, true): return "tasks.due.todayAt"
        case (.tomorrow, false): return "tasks.due.tomorrow"
        case (.tomorrow, true): return "tasks.due.tomorrowAt"
        case (.inDays, false): return "tasks.due.inDays"
        case (.inDays, true): return "tasks.due.inDaysAt"
        case (.overdueDays, _): return "tasks.due.overdueDays"
        case (.onDate, false): return "tasks.due.onDate"
        case (.onDate, true): return "tasks.due.onDateAt"
        }
    }

    /// The arguments of `catalogKey`'s format.
    public func arguments(formatter: TimetableFormatter) -> [CatalogArgument] {
        let timeText = time.map { [CatalogArgument.text(formatter.time($0))] } ?? []
        switch kind {
        case .today, .tomorrow: return timeText
        case .inDays(let days): return [.integer(Int64(days))] + timeText
        case .overdueDays(let days): return [.integer(Int64(days))]
        case .onDate(let date): return [.text(formatter.date(date, style: .abbreviated))] + timeText
        }
    }

    /// The phrase for display.
    public func text(renderer: LocalizedTextRenderer) -> String {
        renderer.format(key: catalogKey, arguments: arguments(formatter: renderer.formatter))
    }

    /// What a row shows for the due date under a list section (M10): the header already says "Today" / "Tomorrow", so a
    /// date-only due of that day shows nothing and a timed one only the time. Everything else keeps the full phrase.
    public enum Line: Equatable, Sendable {
        case full(TaskDueDescription)
        case timeOnly(LocalTime)
    }

    /// The line to show under `section` (`nil` section = no grouping: always the full phrase); `nil` = show nothing.
    public func line(in section: TaskSection?) -> Line? {
        switch (section, kind) {
        case (.today?, .today), (.tomorrow?, .tomorrow): return time.map(Line.timeOnly)
        default: return .full(self)
        }
    }

    /// Every catalog key `catalogKey` can return.
    public static let allKeys: [String] = [
        "tasks.due.today", "tasks.due.todayAt", "tasks.due.tomorrow", "tasks.due.tomorrowAt", "tasks.due.inDays",
        "tasks.due.inDaysAt", "tasks.due.overdueDays", "tasks.due.onDate", "tasks.due.onDateAt",
    ]
}

extension TaskDueDescription.Kind {
    fileprivate var isOverdueDays: Bool {
        if case .overdueDays = self { return true }
        return false
    }
}

/// The presentation model of one task row.
public struct TaskRowModel: Identifiable, Equatable, Sendable {
    public let id: TaskItem.ID
    public let title: String
    public let isCompleted: Bool
    /// Open and past due (by date, or today with the time passed).
    public let isOverdue: Bool
    /// The task's subject, if it has one that still exists.
    public let subject: SubjectSummary?
    public let due: TaskDueDescription?
    public let priority: TaskPriority
    /// Live subtasks done / total (`total == 0`: no subtasks).
    public let subtasksDone: Int
    public let subtasksTotal: Int
    public let attachmentCount: Int
    public let repeats: Bool

    /// Builds the model. `subjects` are looked up by the task's `subjectID` (deleted subjects are ignored).
    public init(task: TaskItem, subjects: [Subject.ID: Subject], now: LocalDateTime) {
        id = task.id
        title = task.title
        isCompleted = task.isCompleted
        isOverdue = TaskListModel.segment(of: task, now: now) == .overdue
        subject = task.subjectID.flatMap { subjects[$0] }.flatMap { $0.isDeleted ? nil : SubjectSummary($0) }
        due = TaskDueDescription.make(due: task.due, today: now.date)
        priority = task.priority
        let liveSubtasks = task.subtasks.filter { !$0.meta.isDeleted }
        subtasksTotal = liveSubtasks.count
        subtasksDone = liveSubtasks.filter { $0.completedAt != nil }.count
        attachmentCount = task.attachments.filter { !$0.meta.isDeleted }.count
        repeats = task.repeatRule != nil
    }

    /// The due line under `section`; `nil` when the section header already says it (M10).
    public func dueLine(in section: TaskSection?) -> TaskDueDescription.Line? { due?.line(in: section) }

    /// `true` for High and Urgent (Low and Normal show no badge).
    public var showsPriorityBadge: Bool { priority >= .high }

    /// Catalog key of the badge text, `nil` when there is no badge.
    public var priorityBadgeKey: String? { showsPriorityBadge ? TaskL10nKeys.priority(priority) : nil }

    /// SF Symbol of the priority badge (shape, never colour alone).
    public var prioritySymbolName: String {
        (priority == .urgent ? AppSymbol.priorityUrgent : AppSymbol.priorityHigh).rawValue
    }

    /// The one-sentence VoiceOver label: parts joined with the catalog's list separator, empty parts omitted.
    public func accessibilityLabel(renderer: LocalizedTextRenderer) -> String {
        accessibilityParts(renderer: renderer).joined(separator: renderer.string(forKey: "a11y.separator"))
    }

    /// The phrases of `accessibilityLabel`, in reading order (exposed for tests).
    public func accessibilityParts(renderer: LocalizedTextRenderer) -> [String] {
        var parts = [title]
        if let subject { parts.append(subject.name) }
        if let due {
            let text = due.text(renderer: renderer)
            if case .overdueDays = due.kind {
                parts.append(text)
            } else {
                if isOverdue { parts.append(renderer.string(forKey: "a11y.task.overdue")) }
                parts.append(renderer.format(key: "a11y.task.due", arguments: [.text(text)]))
            }
        }
        if showsPriorityBadge { parts.append(renderer.string(forKey: TaskL10nKeys.priorityAccessibility(priority))) }
        if subtasksTotal > 0 {
            parts.append(renderer.format(key: "a11y.task.subtasks",
                                         arguments: [.integer(Int64(subtasksDone)), .integer(Int64(subtasksTotal))]))
        }
        if attachmentCount > 0 {
            parts.append(renderer.format(key: "a11y.task.attachments", arguments: [.integer(Int64(attachmentCount))]))
        }
        if repeats { parts.append(renderer.string(forKey: "a11y.task.repeats")) }
        if isCompleted { parts.append(renderer.string(forKey: "a11y.task.completed")) }
        return parts
    }
}
