// Edit state of the task editor (Phase 3 B1): title, kind, subject, due (none / date / date + time / next lesson of the
// subject), priority, notes, subtasks, repetition, reminder override, attachments. Pure, Linux-tested.
//
// The draft never touches sync metadata: `makeTask(now:)` returns the task as it should be stored and
// `AppModel.apply(.upsert(_:))` stamps it (new children are created, removed children become tombstones).
// Values from a newer app version (unknown due kind, unknown repeat frequency) survive an edit that does not touch
// them. Validation is inline: `issues` lists what blocks saving, in display order.
import Foundation
import TimetableCore

/// One checklist row in the editor.
public struct SubtaskDraft: Equatable, Sendable, Identifiable {
    public let id: Subtask.ID
    public var title: String
    public var isDone: Bool
    fileprivate let meta: EntityMeta
    fileprivate let originalCompletedAt: Date?

    /// A new, open subtask.
    public init(id: Subtask.ID, title: String) {
        self.id = id
        self.title = title
        isDone = false
        meta = EditorEntities.placeholderMeta
        originalCompletedAt = nil
    }

    /// An existing subtask.
    public init(_ subtask: Subtask) {
        id = subtask.id
        title = subtask.title
        isDone = subtask.completedAt != nil
        meta = subtask.meta
        originalCompletedAt = subtask.completedAt
    }
}

/// The task editor's state.
public struct TaskDraft: Equatable, Sendable {
    /// How the due date is chosen.
    public enum DueMode: String, CaseIterable, Sendable, Equatable {
        case none, date, dateTime, nextLesson
    }

    /// How the task repeats.
    public enum RepeatMode: String, CaseIterable, Sendable, Equatable {
        case none, daily, weekly, monthly

        /// The stored frequency; `nil` for `.none`.
        public var frequency: RepeatFrequency? {
            switch self {
            case .none: return nil
            case .daily: return .daily
            case .weekly: return .weekly
            case .monthly: return .monthly
            }
        }
    }

    /// A problem that blocks saving.
    public enum Issue: String, CaseIterable, Sendable, Equatable {
        case titleEmpty
        case nextLessonNeedsSubject
        case nextLessonNotFound
        case repeatNeedsDue
        case untilBeforeDue

        /// Catalog key of the explanation.
        public var l10nKey: String { "tasks.editor.issue." + rawValue }
    }

    /// Time used when a date-only due becomes a date + time due.
    public static let defaultDueTime = LocalTime(hour: 8, minute: 0) ?? .midnight
    /// Longest allowed repeat interval.
    public static let maxInterval = 99

    public let taskID: TaskItem.ID
    public let isNew: Bool
    public var timetableID: Timetable.ID?
    public var title: String
    public var kind: TaskKind
    public var subjectID: Subject.ID?
    public private(set) var dueMode: DueMode
    public var dueDate: LocalDate
    public var dueTime: LocalTime
    /// The resolved "next lesson" (`nil` until resolved or when the subject has none).
    public var nextLesson: NextLesson?
    public var priority: TaskPriority
    public var notes: String
    public var subtasks: [SubtaskDraft]
    public private(set) var repeatMode: RepeatMode
    public var repeatInterval: Int
    public var repeatWeekdays: Set<Weekday>
    public var hasUntil: Bool
    public var until: LocalDate
    public var reminderOverride: ReminderOverride?
    public var attachments: [AttachmentRef]
    private let base: TaskItem
    private var keepsUnknownDue: Bool
    private var keepsUnknownRepeat: Bool

    // MARK: Creating

    /// Edits `task`. `today` seeds the date pickers when the task has no usable due date.
    public init(task: TaskItem, today: LocalDate) {
        self.init(task: task, today: today, isNew: false)
    }

    private init(task: TaskItem, today: LocalDate, isNew: Bool) {
        taskID = task.id
        self.isNew = isNew
        base = task
        timetableID = task.timetableID
        title = task.title
        kind = task.kind
        subjectID = task.subjectID
        priority = task.priority
        notes = task.notes ?? ""
        subtasks = task.subtasks.filter { !$0.meta.isDeleted }.sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
            .map(SubtaskDraft.init)
        reminderOverride = task.reminderOverride
        attachments = task.attachments.filter { !$0.meta.isDeleted }
            .sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
        let seedDate = today.addingIfValid(days: 1) ?? today
        dueDate = task.due?.date ?? seedDate
        dueTime = task.due?.time ?? Self.defaultDueTime
        nextLesson = nil
        keepsUnknownDue = false
        switch task.due {
        case nil:
            dueMode = .none
        case .date?:
            if let link = task.linkedLesson {
                dueMode = .nextLesson
                nextLesson = NextLessonResolver.stored(link)
            } else {
                dueMode = .date
            }
        case .dateTime?:
            dueMode = .dateTime
        case .unknown?:
            dueMode = .none
            keepsUnknownDue = true
        }
        let rule = task.repeatRule
        repeatInterval = max(1, min(Self.maxInterval, rule?.interval ?? 1))
        repeatWeekdays = rule?.weekdays ?? []
        hasUntil = rule?.until != nil
        until = rule?.until ?? dueDate.adding(days: 84)
        keepsUnknownRepeat = false
        if let rule {
            if let mode = RepeatMode.allCases.first(where: { $0.frequency == rule.frequency }) {
                repeatMode = mode
            } else {
                repeatMode = .none
                keepsUnknownRepeat = true
            }
        } else {
            repeatMode = .none
        }
    }

    /// A new task. `nextLesson` (the subject's next lesson) selects "next lesson" as the due; otherwise the due is
    /// the day after `today`.
    public init(newWithID id: TaskItem.ID, today: LocalDate, timetableID: Timetable.ID?, subjectID: Subject.ID? = nil,
                nextLesson: NextLesson? = nil) {
        var task = TaskItem(id: id, meta: EditorEntities.placeholderMeta, title: "", kind: subjectID == nil ? .todo : .homework,
                            subjectID: subjectID, timetableID: timetableID)
        let tomorrow = today.addingIfValid(days: 1) ?? today
        task.due = .date(tomorrow)
        self.init(task: task, today: today, isNew: true)
        if let nextLesson {
            dueMode = .nextLesson
            self.nextLesson = nextLesson
            dueDate = nextLesson.date
        }
    }

    // MARK: Editing

    /// Chooses how the due date is given. Choosing `.nextLesson` clears the resolved lesson: the caller resolves it
    /// (`NextLessonResolver`) and assigns `nextLesson`.
    public mutating func setDueMode(_ mode: DueMode) {
        guard mode != dueMode else { return }
        dueMode = mode
        keepsUnknownDue = false
        nextLesson = nil
    }

    /// Chooses the subject; a "next lesson" due must be resolved again.
    public mutating func setSubject(_ id: Subject.ID?) {
        guard id != subjectID else { return }
        subjectID = id
        if dueMode == .nextLesson { nextLesson = nil }
    }

    /// Chooses the repetition.
    public mutating func setRepeatMode(_ mode: RepeatMode) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        keepsUnknownRepeat = false
    }

    /// Adds or removes `weekday` from the weekly repeat days.
    public mutating func toggleWeekday(_ weekday: Weekday) {
        if repeatWeekdays.contains(weekday) { repeatWeekdays.remove(weekday) } else { repeatWeekdays.insert(weekday) }
    }

    /// Appends an open subtask; blank titles are ignored. Returns `true` when added.
    @discardableResult
    public mutating func addSubtask(title: String, id: Subtask.ID) -> Bool {
        guard let clean = EditorText.trimmedOrNil(title) else { return false }
        subtasks.append(SubtaskDraft(id: id, title: clean))
        return true
    }

    /// Removes the subtasks at `offsets`.
    public mutating func removeSubtasks(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where subtasks.indices.contains(index) { subtasks.remove(at: index) }
    }

    /// Reorders like SwiftUI's `move(fromOffsets:toOffset:)`.
    public mutating func moveSubtasks(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { subtasks.indices.contains($0) }.map { subtasks[$0] }
        let before = source.filter { $0 < destination }.count
        var rest: [SubtaskDraft] = []
        for (index, item) in subtasks.enumerated() where !source.contains(index) { rest.append(item) }
        rest.insert(contentsOf: moving, at: max(0, min(rest.count, destination - before)))
        subtasks = rest
    }

    // MARK: Validation

    /// The due date the task will have (`nil` = undated).
    public var effectiveDueDate: LocalDate? {
        switch dueMode {
        case .none: return nil
        case .date, .dateTime: return dueDate
        case .nextLesson: return nextLesson?.date
        }
    }

    /// Problems that block saving, in display order.
    public var issues: [Issue] {
        var found: [Issue] = []
        if EditorText.trimmedOrNil(title) == nil { found.append(.titleEmpty) }
        if dueMode == .nextLesson {
            if subjectID == nil {
                found.append(.nextLessonNeedsSubject)
            } else if nextLesson == nil {
                found.append(.nextLessonNotFound)
            }
        }
        if repeatMode != .none {
            if dueMode == .none {
                found.append(.repeatNeedsDue)
            } else if hasUntil, let due = effectiveDueDate, until < due {
                found.append(.untilBeforeDue)
            }
        }
        return found
    }

    /// `true` when nothing blocks saving.
    public var canSave: Bool { issues.isEmpty }

    // MARK: Result

    /// The task to store, or `nil` while `issues` is not empty.
    public func makeTask(now: Date) -> TaskItem? {
        guard canSave, let cleanTitle = EditorText.trimmedOrNil(title) else { return nil }
        var task = base
        task.title = cleanTitle
        task.kind = kind
        task.subjectID = subjectID
        task.timetableID = timetableID
        switch dueMode {
        case .none:
            if !keepsUnknownDue {
                task.due = nil
                task.linkedLesson = nil
            }
        case .date:
            task.due = .date(dueDate)
            task.linkedLesson = nil
        case .dateTime:
            task.due = .dateTime(dueDate, dueTime)
            task.linkedLesson = nil
        case .nextLesson:
            if let nextLesson {
                task.due = nextLesson.due
                task.linkedLesson = nextLesson.link
            }
        }
        task.priority = priority
        task.notes = EditorText.trimmedOrNil(notes)
        task.subtasks = subtasks.enumerated().compactMap { index, draft in
            guard let clean = EditorText.trimmedOrNil(draft.title) else { return nil }
            let done = draft.isDone ? (draft.originalCompletedAt ?? now) : nil
            return Subtask(id: draft.id, meta: draft.meta, title: clean, completedAt: done, sortIndex: index)
        }
        task.attachments = attachments
        if let frequency = repeatMode.frequency {
            task.repeatRule = RepeatRule(frequency: frequency, interval: max(1, min(Self.maxInterval, repeatInterval)),
                                         weekdays: repeatMode == .weekly ? repeatWeekdays : [],
                                         until: hasUntil ? until : nil)
        } else if !keepsUnknownRepeat {
            task.repeatRule = nil
        }
        task.reminderOverride = reminderOverride
        return task
    }
}
