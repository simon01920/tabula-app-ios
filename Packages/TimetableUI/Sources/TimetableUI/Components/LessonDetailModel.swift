// Read-only lesson detail: what the occurrence looks like on its date, what changed against the regular timetable
// (with the usual value where it is a visible field) and which editor actions apply. Pure, Linux-tested.
import Foundation
import TimetableCore

/// One change of an occurrence against its regular version.
public struct LessonChangeLine: Equatable, Sendable, Identifiable {
    public var reason: ModificationReason
    /// The regular value ("usually 214"), when the field is visible and the regular occurrence is known.
    public var usualValue: String?
    public var id: ModificationReason { reason }
}

/// The detail screen's data.
public struct LessonDetailModel: Equatable, Sendable {
    public var lesson: ResolvedLesson
    public var reasons: [ModificationReason]
    /// Visible, non-empty optional fields.
    public var fields: [LessonFieldLine]
    public var changes: [LessonChangeLine]
    /// The recurring lesson behind the occurrence (`nil` for one-off lessons).
    public var lessonID: Lesson.ID?
    /// The lesson runs only in some cycle weeks (week cycles): their numbers, ascending.
    public var cycleWeeks: [Int]

    /// Builds the detail of `occurrenceID` on `date`, or `nil` when it does not exist (deleted meanwhile).
    public static func make(occurrenceID: OccurrenceID, date: LocalDate, resolver: ScheduleResolver,
                            database: TabulaDatabase, formatter: TimetableFormatter) -> LessonDetailModel? {
        let actual = resolver.resolution(for: date)
        guard let lesson = actual.schedule.entries.first(where: { $0.id == occurrenceID }) else { return nil }
        let reasons = actual.reasons(for: occurrenceID)
        let visibility = resolver.timetable.fieldVisibility
        let regular = resolver.day(date, options: .regular).entries.first { $0.id == occurrenceID }
        let changes = reasons.map { reason in
            LessonChangeLine(reason: reason, usualValue: regular.flatMap {
                usualValue(of: reason, regular: $0, visibility: visibility, formatter: formatter)
            })
        }
        var lessonID: Lesson.ID?
        var cycleWeeks: [Int] = []
        if case .lesson(let id) = lesson.source {
            lessonID = id
            if case .weekCycle = resolver.timetable.rotation,
               let weeks = database.lessons.first(where: { $0.id == id })?.occurrence.cycleWeeks {
                cycleWeeks = weeks.sorted()
            }
        }
        return LessonDetailModel(lesson: lesson, reasons: reasons,
                                 fields: LessonFieldLines.make(lesson: lesson, visibility: visibility),
                                 changes: changes, lessonID: lessonID, cycleWeeks: cycleWeeks)
    }

    /// The regular value of the field a reason is about, respecting the field rule (hidden or empty → `nil`).
    static func usualValue(of reason: ModificationReason, regular: ResolvedLesson, visibility: FieldVisibility,
                           formatter: TimetableFormatter) -> String? {
        let fields = VisibleLessonFields(lesson: regular, visibility: visibility)
        switch reason {
        case .timeChanged: return formatter.timeRange(regular.startTime, regular.endTime)
        case .subjectChanged: return regular.subject.name
        case .roomChanged: return fields.room
        case .buildingChanged: return fields.building
        case .teacherChanged: return fields.teacher
        case .notesChanged, .lessonTypeChanged, .bringListChanged: return nil
        }
    }
}
