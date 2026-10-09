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
