// "Due at the next <subject> lesson": finds the next lesson of a subject through the schedule resolver, so
// substitutions, cancelled lessons, breaks and rotation weeks are honoured. Pure, Linux-tested.
//
// Decision (documented in the report): the task's `due` becomes the lesson's DATE (`.date`, no time) and
// `linkedLesson` records the occurrence. Reminders then use the rule times (typically the evening before),
// instead of firing relative to the lesson's start time.
import Foundation
import TimetableCore

/// The occurrence a task is due at.
public struct NextLesson: Equatable, Sendable {
    /// The occurrence date.
    public let date: LocalDate
    /// Start time of the occurrence; `nil` when only the stored link is known (editing an existing task).
    public let startTime: LocalTime?
    /// The recurring lesson; `nil` for a one-off lesson added by a day change (it cannot be linked).
    public let lessonID: Lesson.ID?

    public init(date: LocalDate, startTime: LocalTime?, lessonID: Lesson.ID?) {
        self.date = date
        self.startTime = startTime
        self.lessonID = lessonID
    }

    /// The stored link for the task (`nil` for one-off lessons).
    public var link: LessonLink? { lessonID.map { LessonLink(lessonID: $0, date: date) } }

    /// The due value: the lesson's date.
    public var due: TaskDue { .date(date) }
}

/// Finds the next lesson of a subject.
public enum NextLessonResolver {
    /// How many days ahead are searched.
    public static let horizonDays = 120

    /// The first non-cancelled occurrence of `subjectID` that starts after `now`, or `nil` within the horizon.
    public static func find(subjectID: Subject.ID, resolver: ScheduleResolver, now: Date) -> NextLesson? {
        let first = resolver.context.localDate(of: now)
        for offset in 0...horizonDays {
            let date = first.adding(days: offset)
            for entry in resolver.day(date).entries
            where entry.status != .cancelled && entry.subject.id == subjectID && entry.start > now {
                var lessonID: Lesson.ID?
                if case .lesson(let id) = entry.source { lessonID = id }
                return NextLesson(date: entry.date, startTime: entry.startTime, lessonID: lessonID)
            }
        }
        return nil
    }

    /// The stored link as a `NextLesson` (for editing a task that already has one).
    public static func stored(_ link: LessonLink) -> NextLesson {
        NextLesson(date: link.date, startTime: nil, lessonID: link.lessonID)
    }
}
