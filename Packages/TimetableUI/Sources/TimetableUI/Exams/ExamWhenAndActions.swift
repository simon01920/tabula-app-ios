// Phase 4U U2 exam logic that is not list grouping: the editor's "When" choices (M25), the completion action that
// depends on the date (H15 / D6) and the rules for how far ahead a relative time is shown (M24). Pure, Linux-tested.
import Foundation
import TimetableCore

/// How the exam editor asks for the time (M25). A view over the stored start / end; see `ExamDraft`.
public enum ExamTimeMode: String, CaseIterable, Sendable, Equatable {
    case lesson, custom, allDay

    /// Catalog key of the option.
    public var l10nKey: String { "exams.editor.when." + rawValue }
}

/// One lesson of the exam's date that "During a lesson" can take its times from.
public struct ExamLessonChoice: Equatable, Sendable, Identifiable {
    public let id: OccurrenceID
    public let subject: SubjectSummary
    public let start: LocalTime
    public let end: LocalTime

    public init(lesson: ResolvedLesson) {
        id = lesson.id
        subject = lesson.subject
        start = lesson.startTime
        end = lesson.endTime
    }

    /// The choices of a day: lessons that are not cancelled, by start time.
    public static func choices(from lessons: [ResolvedLesson]) -> [ExamLessonChoice] {
        lessons.filter { $0.status != .cancelled }
            .sorted { ($0.startTime.minuteOfDay, $0.id) < ($1.startTime.minuteOfDay, $1.id) }
            .map(ExamLessonChoice.init(lesson:))
    }
}

/// What the "done" action of an exam is called and where it lives (H15 / D6): "I've Taken This Exam" from the exam date
/// on, as a button; before that "Move to History" in the ⋯ menu. Both do the same thing (`completeExam`).
public enum ExamCompletionAction: Equatable, Sendable {
    case takenIt, moveToHistory

    public init(examDate: LocalDate, today: LocalDate) {
        self = today >= examDate ? .takenIt : .moveToHistory
    }

    /// Catalog key of the label.
    public var l10nKey: String { self == .takenIt ? "exams.action.takenIt" : "exams.action.moveToHistory" }

    /// `true`: a button in the detail's body. `false`: only in the ⋯ menu.
    public var isPrimaryButton: Bool { self == .takenIt }

    /// Every catalog key `l10nKey` can return.
    public static let allKeys = ["exams.action.takenIt", "exams.action.moveToHistory"]
}

extension ExamRow {
    /// Beyond this many days "in 91 days" carries no meaning, so only the date is shown (M24).
    public static let relativeTimeHorizonDays = 14

    /// `false` when the exam is further away (or further back) than `relativeTimeHorizonDays`.
    public var showsRelativeTime: Bool { abs(daysUntil) <= Self.relativeTimeHorizonDays }
}

extension ExamUrgency {
    /// The symbol that stresses imminence; `nil` where the urgency is no more than "a date" (a second calendar glyph
    /// next to the date line was M24's "two calendar icons").
    public var emphasisSymbolName: String? {
        switch self {
        case .today, .tomorrow, .soon: return symbolName
        case .thisWeek, .later, .past: return nil
        }
    }
}
