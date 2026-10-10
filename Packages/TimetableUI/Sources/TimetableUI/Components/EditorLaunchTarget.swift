// Pure mapping from the `EditorContext` a timetable view passes to an editor sheet to a description of what that
// editor should open on. The App-side route views turn the description into a concrete editor (Linux-tested here).
import Foundation
import TimetableCore

/// What an editor opens on, derived from an `EditorContext`.
public enum EditorLaunchTarget: Equatable, Sendable {
    /// Edit the existing lesson.
    case editLesson(Lesson.ID, timetableID: Timetable.ID)
    /// New lesson prefilled from the tapped empty cell.
    case newLesson(NewLessonContext, timetableID: Timetable.ID)
    /// New subject.
    case newSubject(timetableID: Timetable.ID)
    /// "Change for this day" for `date`, optionally with one lesson preselected.
    case dayChange(date: LocalDate, lessonID: Lesson.ID?, timetableID: Timetable.ID)

    /// `nil` context (launch route) yields `nil`: the editor falls back to sample data.
    public init?(_ context: EditorContext?) {
        guard let context else { return nil }
        let id = context.timetableID
        switch context.target {
        case .lesson(let lessonID):
            self = .editLesson(lessonID, timetableID: id)
        case .newLesson(let quick):
            self = .newLesson(NewLessonContext(day: quick.dayKey, slot: quick.slot, subjectID: nil,
                                               cycleWeek: quick.cycleWeek), timetableID: id)
        case .newSubject:
            self = .newSubject(timetableID: id)
        case .dayChange(let date, _, let lessonID):
            self = .dayChange(date: date, lessonID: lessonID, timetableID: id)
        }
    }
}
