// What the read-only task detail shows: the row model, kind, notes, subtasks, repetition summary and the linked
// lesson date. Fields that are empty are absent (`nil` / empty), never placeholders. Pure, Linux-tested.
import Foundation
import TimetableCore

/// The repetition of a task as display lines ("Every 2 weeks", "On Mon, Wed", "Until Jan 31, 2027").
public struct TaskRepeatSummary: Equatable, Sendable {
    public let frequency: RepeatFrequency
    public let interval: Int
    public let weekdays: [Weekday]
    public let until: LocalDate?

    /// `nil` when the task does not repeat or the frequency is from a newer app version.
    public init?(rule: RepeatRule?) {
        guard let rule, RepeatFrequency.knownValues.contains(rule.frequency) else { return nil }
        frequency = rule.frequency
        interval = max(1, rule.interval)
        weekdays = rule.frequency == .weekly ? rule.weekdays.sorted() : []
        until = rule.until
    }

    /// The display lines, each one complete catalog phrase.
    public func lines(renderer: LocalizedTextRenderer) -> [String] {
        var lines = [renderer.format(key: "tasks.repeat.every." + frequency.rawValue, arguments: [.integer(Int64(interval))])]
        if !weekdays.isEmpty {
            let names = weekdays.map { renderer.formatter.weekdayName($0, width: .abbreviated) }
            lines.append(renderer.format(key: "tasks.repeat.onDays", arguments: [.text(renderer.formatter.list(names))]))
        }
        if let until {
            lines.append(renderer.format(key: "tasks.repeat.until",
                                         arguments: [.text(renderer.formatter.date(until, style: .abbreviated))]))
        }
        return lines
    }
}

/// The detail view's data.
public struct TaskDetailModel: Equatable, Sendable {
    public let row: TaskRowModel
    /// Catalog key of the kind's name (`nil` for a kind from a newer app version: show `kindRawValue`).
    public let kindKey: String?
    public let kindRawValue: String
    public let notes: String?
    public let subtasks: [Subtask]
    public let repeatSummary: TaskRepeatSummary?
    public let linkedLessonDate: LocalDate?
    public let isCompleted: Bool

    public init(task: TaskItem, subjects: [Subject.ID: Subject], now: LocalDateTime) {
        row = TaskRowModel(task: task, subjects: subjects, now: now)
        kindKey = TaskL10nKeys.kind(task.kind)
        kindRawValue = task.kind.rawValue
        notes = task.notes.flatMap(EditorText.trimmedOrNil)
        subtasks = TaskEdits.liveSubtasks(of: task)
        repeatSummary = TaskRepeatSummary(rule: task.repeatRule)
        linkedLessonDate = task.linkedLesson?.date
        isCompleted = task.isCompleted
    }
}
