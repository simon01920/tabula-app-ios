// What an editor sheet opened from a timetable view should edit. Editor routes (`editor.*`, stage B3) are built with
// a no-argument `AppRoute.makeView`, so the presenting view passes the target through the SwiftUI environment:
//
//   route.makeView().environment(\.editorContext, EditorContext(timetableID: …, target: .lesson(id)))
//
// An editor reads `@Environment(\.editorContext)`; `nil` means "opened as a launch route" (screenshot mode: pick
// sample data). Plain `EnvironmentKey` (no `@Entry` macro: TimetableUI stays macro-free for Linux and the watch
// type-check). The value type is pure and Linux-tested.
import Foundation
import TimetableCore

/// The thing an editor sheet opens on.
public struct EditorContext: Hashable, Sendable {
    /// The target.
    public enum Target: Hashable, Sendable {
        /// Edit a recurring lesson.
        case lesson(Lesson.ID)
        /// Create a lesson in an empty slot (prefilled day, cycle week and slot).
        case newLesson(QuickAddTarget)
        /// Create a subject (e.g. "New subject…" from the quick-add sheet).
        case newSubject
        /// Change one date ("Change for this day"): optionally about one occurrence.
        case dayChange(date: LocalDate, occurrence: OccurrenceID?, lessonID: Lesson.ID?)
        /// A new task for one lesson occurrence ("Add homework for this lesson", route `tasks.editor-new`).
        case newTask(TaskPrefill)
    }

    public var timetableID: Timetable.ID
    public var target: Target

    public init(timetableID: Timetable.ID, target: Target) {
        self.timetableID = timetableID
        self.target = target
    }

    /// Route ids of the editors opened from timetable views.
    public enum RouteID {
        public static let lesson = "editor.lesson"
        public static let subject = "editor.subject"
        public static let dayChange = "editor.day-change"
        /// The task editor for a new task (Phase 3 C1: opened prefilled from the lesson detail).
        public static let newTask = "tasks.editor-new"
    }
}

/// What "Add homework for this lesson" prefills in the task editor: the subject, the occurrence's date as the due date
/// and, for a recurring lesson, the occurrence as `linkedLesson` (a one-off lesson cannot be linked; its date is used).
public struct TaskPrefill: Hashable, Sendable {
    public var subjectID: Subject.ID
    public var date: LocalDate
    public var startTime: LocalTime?
    /// The recurring lesson; `nil` for a one-off lesson added by a day change.
    public var lessonID: Lesson.ID?

    public init(subjectID: Subject.ID, date: LocalDate, startTime: LocalTime?, lessonID: Lesson.ID?) {
        self.subjectID = subjectID
        self.date = date
        self.startTime = startTime
        self.lessonID = lessonID
    }

    /// The prefill for `lesson`'s occurrence.
    public init(lesson: ResolvedLesson) {
        var lessonID: Lesson.ID?
        if case .lesson(let id) = lesson.source { lessonID = id }
        self.init(subjectID: lesson.subject.id, date: lesson.date, startTime: lesson.startTime, lessonID: lessonID)
    }

    /// The occurrence as the editor's "lesson" due (due = its date, linked when recurring).
    public var lesson: NextLesson { NextLesson(date: date, startTime: startTime, lessonID: lessonID) }

    /// A new homework draft for this occurrence (`timetableID`: the lesson's timetable).
    public func draft(newWithID id: TaskItem.ID, today: LocalDate, timetableID: Timetable.ID?) -> TaskDraft {
        TaskDraft(newWithID: id, today: today, timetableID: timetableID, subjectID: subjectID, nextLesson: lesson)
    }
}

#if canImport(SwiftUI)
import SwiftUI

private struct EditorContextKey: EnvironmentKey {
    static let defaultValue: EditorContext? = nil
}

extension EnvironmentValues {
    /// The target of the editor being presented; `nil` when the editor was opened without one (launch route).
    public var editorContext: EditorContext? {
        get { self[EditorContextKey.self] }
        set { self[EditorContextKey.self] = newValue }
    }
}
#endif
