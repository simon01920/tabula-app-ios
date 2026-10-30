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

    /// "Every day" / "Every 3 weeks" (`nil` for a frequency from a newer app version).
    public static func everyText(frequency: RepeatFrequency, interval: Int, renderer: LocalizedTextRenderer) -> String? {
        guard RepeatFrequency.knownValues.contains(frequency) else { return nil }
        let key = TaskL10nKeys.repeatEvery(frequency: frequency, interval: interval)
        return renderer.format(key: key, arguments: interval == 1 ? [] : [.integer(Int64(interval))])
    }

    /// The rule on ONE line (M22): "Weekly on Tuesday", "Every 2 weeks on Monday and Wednesday", "Every day". Each variant
    /// is one complete catalog phrase; the weekday list comes from the formatter (no concatenated fragments).
    public func line(renderer: LocalizedTextRenderer) -> String {
        guard frequency == .weekly, !weekdays.isEmpty else {
            return Self.everyText(frequency: frequency, interval: interval, renderer: renderer) ?? ""
        }
        let days = renderer.formatter.list(weekdays.map { renderer.formatter.weekdayName($0, width: .wide) })
        if interval == 1 { return renderer.format(key: "tasks.repeat.summary.weeklyOn", arguments: [.text(days)]) }
        return renderer.format(key: "tasks.repeat.summary.everyWeeksOn", arguments: [.integer(Int64(interval)), .text(days)])
    }

    /// "Until Jan 31, 2027" (`nil` without an end date).
    public func untilText(renderer: LocalizedTextRenderer) -> String? {
        until.map { renderer.format(key: "tasks.repeat.until", arguments: [.text(renderer.formatter.date($0, style: .abbreviated))]) }
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
