// The quick-entry sheet of the Tasks tab (Phase 4U U2, Opus R2 / H6 / M21): a title, a subject that defaults to the
// current or next lesson's, a due choice (next lesson / tomorrow / pick a date) and a type. It edits a normal
// `TaskDraft` (no second model): the sheet's save path, validation and "More options" (the full editor on the same
// draft) are the task editor's. Pure, Linux-tested.
//
// Defaults (M21): a task with a subject is Homework due at that subject's next lesson; without a subject it is a
// To-do due tomorrow. While the user has not chosen the type or the due herself, changing the subject re-derives them.
import Foundation
import TimetableCore

/// How the quick-entry sheet asks for the due date.
public enum QuickDue: String, CaseIterable, Sendable, Equatable {
    case nextLesson, tomorrow, date
}

public enum TaskQuickEntry {
    /// The types the segmented control offers, in the order of the review (R2).
    public static let kinds: [TaskKind] = [.homework, .todo, .assignment]

    /// The due choices on offer: "next lesson" only when the subject has one.
    public static func options(nextLesson: NextLesson?) -> [QuickDue] {
        nextLesson == nil ? [.tomorrow, .date] : [.nextLesson, .tomorrow, .date]
    }

    /// The default due: the next lesson for Homework that has one, else tomorrow.
    public static func defaultDue(kind: TaskKind, nextLesson: NextLesson?) -> QuickDue {
        kind == .homework && nextLesson != nil ? .nextLesson : .tomorrow
    }

    /// The type a task gets from its subject (Homework with, To-do without).
    public static func defaultKind(subjectID: Subject.ID?) -> TaskKind { subjectID == nil ? .todo : .homework }

    /// The draft the sheet opens on: `subjectID` (the current or next lesson's) and its `nextLesson`.
    public static func initialDraft(id: TaskItem.ID, today: LocalDate, timetableID: Timetable.ID?, subjectID: Subject.ID?,
                                    nextLesson: NextLesson?) -> TaskDraft {
        TaskDraft(newWithID: id, today: today, timetableID: timetableID, subjectID: subjectID,
                  nextLesson: subjectID == nil ? nil : nextLesson)
    }

    /// The choice a draft currently represents (for the picker's selection); `date` for every explicit date.
    public static func choice(of draft: TaskDraft, today: LocalDate) -> QuickDue {
        switch draft.dueMode {
        case .nextLesson: return .nextLesson
        case .date where draft.dueDate == (today.addingIfValid(days: 1) ?? today): return .tomorrow
        default: return .date
        }
    }
}

extension TaskDraft {
    /// Applies a due choice. `.nextLesson` without a lesson falls back to tomorrow (it is never offered then).
    public mutating func quickApply(_ due: QuickDue, nextLesson: NextLesson?, today: LocalDate) {
        switch due {
        case .nextLesson where nextLesson != nil:
            setDueMode(.nextLesson)
            self.nextLesson = nextLesson
            if let lesson = nextLesson { dueDate = lesson.date }
        case .nextLesson, .tomorrow:
            setDueMode(.date)
            dueDate = today.addingIfValid(days: 1) ?? today
        case .date:
            setDueMode(.date)
        }
    }

    /// The subject changed. `followKind` / `followDue`: the user has not chosen the type / the due, so they follow the
    /// subject (M21); otherwise a chosen "next lesson" only moves to the new subject's lesson.
    public mutating func quickChooseSubject(_ id: Subject.ID?, nextLesson: NextLesson?, today: LocalDate, followKind: Bool,
                                            followDue: Bool) {
        setSubject(id)
        if followKind { kind = TaskQuickEntry.defaultKind(subjectID: id) }
        let lesson = id == nil ? nil : nextLesson
        if followDue {
            quickApply(TaskQuickEntry.defaultDue(kind: kind, nextLesson: lesson), nextLesson: lesson, today: today)
        } else if dueMode == .nextLesson {
            quickApply(.nextLesson, nextLesson: lesson, today: today)
        }
    }

    /// The type changed; with `followDue` the due is re-derived (Homework: next lesson, others: tomorrow).
    public mutating func quickChooseKind(_ newKind: TaskKind, nextLesson: NextLesson?, today: LocalDate, followDue: Bool) {
        kind = newKind
        guard followDue else { return }
        let lesson = subjectID == nil ? nil : nextLesson
        quickApply(TaskQuickEntry.defaultDue(kind: newKind, nextLesson: lesson), nextLesson: lesson, today: today)
    }
}

/// Small edits the list and detail views apply with `DatabaseMutation.upsert`.
public enum TaskEdits {
    /// `task` with the subtask `id` toggled (done at `now` / reopened); `nil` when the task has no such live subtask.
    public static func togglingSubtask(_ id: Subtask.ID, in task: TaskItem, now: Date) -> TaskItem? {
        guard let index = task.subtasks.firstIndex(where: { $0.id == id && !$0.meta.isDeleted }) else { return nil }
        var edited = task
        edited.subtasks[index].completedAt = edited.subtasks[index].completedAt == nil ? now : nil
        return edited
    }

    /// `task` marked open again. (Undo of a completed repeating task keeps the next occurrence the completion made:
    /// deleting it would leave a tombstone that stops the series from continuing, DOMAIN_MODEL §3.9.)
    public static func reopened(_ task: TaskItem) -> TaskItem {
        var edited = task
        edited.completedAt = nil
        return edited
    }

    /// The live subtasks in display order.
    public static func liveSubtasks(of task: TaskItem) -> [Subtask] {
        task.subtasks.filter { !$0.meta.isDeleted }.sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
    }
}
