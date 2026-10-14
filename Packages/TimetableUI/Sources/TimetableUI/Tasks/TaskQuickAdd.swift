// The quick-add field of the Tasks tab: a title and an optional subject make a task whose due date is smart:
// the next lesson of the chosen subject, else tomorrow. Pure, Linux-tested.
import Foundation
import TimetableCore

public enum TaskQuickAdd {
    /// The due date a quick-added task gets: the subject's next lesson (when there is a subject and it has one), else
    /// the day after `today`. The second element is the lesson link to store.
    public static func smartDue(nextLesson: NextLesson?, today: LocalDate) -> (due: TaskDue, link: LessonLink?) {
        if let nextLesson { return (nextLesson.due, nextLesson.link) }
        return (.date(today.addingIfValid(days: 1) ?? today), nil)
    }

    /// The task for `title` (nil when blank). With a subject the kind is homework, without it a to-do.
    public static func makeTask(id: TaskItem.ID, title: String, subject: Subject?, nextLesson: NextLesson?, today: LocalDate,
                                fallbackTimetableID: Timetable.ID?) -> TaskItem? {
        guard let clean = EditorText.trimmedOrNil(title) else { return nil }
        let due = smartDue(nextLesson: subject == nil ? nil : nextLesson, today: today)
        return TaskItem(id: id, meta: EditorEntities.placeholderMeta, title: clean,
                        kind: subject == nil ? .todo : .homework, subjectID: subject?.id,
                        timetableID: subject?.timetableID ?? fallbackTimetableID, due: due.due, linkedLesson: due.link)
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

    /// `task` marked open again.
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
