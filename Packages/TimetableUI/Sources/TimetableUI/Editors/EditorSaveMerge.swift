// Saving an editor's draft against what is stored NOW (Phase 3 final QA fix Q5). Pure, Linux-tested.
//
// The task and exam editors copy the entity once, when they open; `upsert` then replaces the whole entity. Meanwhile
// the stored entity can change under the open editor: "Mark as Done" from a notification sets `completedAt` (and for a
// repeating task inserts the successor), or the item is deleted. Without a merge, Save would write the old
// `completedAt = nil` back and resurrect a completed task next to its successor.
//
// Rules:
//   - completion: the editors never change it, so the STORED `completedAt` wins unless the edited value differs from
//     what the editor opened with (a future editor that changes completion keeps the user's choice);
//   - stored entity deleted (tombstone) or gone while editing an existing one → `.deletedMeanwhile`: nothing is
//     written (the editor shows the inline "could not be applied" error; the caller never resurrects it);
//   - a new entity (nothing stored yet) is saved as edited.
import Foundation
import TimetableCore

/// What to do with an editor's result.
public enum EditorSaveMerge<Entity: Equatable & Sendable>: Equatable, Sendable {
    /// Store this (the edit merged with the stored entity).
    case save(Entity)
    /// The entity was deleted while the editor was open: write nothing.
    case deletedMeanwhile
}

public enum EditorStoreMerge {
    /// Merges an edited task with the stored one.
    /// - Parameters:
    ///   - edited: the editor's result (`TaskDraft.makeTask(now:)`).
    ///   - openedCompletedAt: `completedAt` of the task when the editor opened.
    ///   - stored: the task with the same id in the database now (live or tombstone), `nil` if absent.
    ///   - isNew: the editor creates the task.
    public static func task(_ edited: TaskItem, openedCompletedAt: Date?, stored: TaskItem?,
                            isNew: Bool) -> EditorSaveMerge<TaskItem> {
        guard let stored else { return isNew ? .save(edited) : .deletedMeanwhile }
        if stored.isDeleted { return .deletedMeanwhile }
        var merged = edited
        merged.completedAt = completion(edited: edited.completedAt, opened: openedCompletedAt, stored: stored.completedAt)
        return .save(merged)
    }

    /// Merges an edited exam with the stored one (same rules as `task`).
    public static func exam(_ edited: Exam, openedCompletedAt: Date?, stored: Exam?, isNew: Bool) -> EditorSaveMerge<Exam> {
        guard let stored else { return isNew ? .save(edited) : .deletedMeanwhile }
        if stored.isDeleted { return .deletedMeanwhile }
        var merged = edited
        merged.completedAt = completion(edited: edited.completedAt, opened: openedCompletedAt, stored: stored.completedAt)
        return .save(merged)
    }

    /// The editor's value when the user changed completion in the editor, else the stored one.
    static func completion(edited: Date?, opened: Date?, stored: Date?) -> Date? {
        edited == opened ? stored : edited
    }
}

extension TaskDraft {
    /// The task to save, merged with `stored` (the task with this id in the database now); `nil` while `issues` is not
    /// empty.
    public func taskForSave(now: Date, stored: TaskItem?) -> EditorSaveMerge<TaskItem>? {
        guard let task = makeTask(now: now) else { return nil }
        return EditorStoreMerge.task(task, openedCompletedAt: openedCompletedAt, stored: stored, isNew: isNew)
    }
}

extension ExamDraft {
    /// The exam to save, merged with `stored` (the exam with this id in the database now); `nil` while `issues` is not
    /// empty.
    public func examForSave(visibility: FieldVisibility, stored: Exam?) -> EditorSaveMerge<Exam>? {
        guard let exam = makeExam(visibility: visibility) else { return nil }
        return EditorStoreMerge.exam(exam, openedCompletedAt: openedCompletedAt, stored: stored, isNew: isNew)
    }
}
