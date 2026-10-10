// The data behind the Exams tab (PHASE3_PLAN §0.9, PRODUCT.md "Exams"): the next exam (featured), the other upcoming
// exams grouped by exam period (university) and week, and the history of past / completed exams. Pure and
// Linux-tested; the SwiftUI views in App/Sources/Exams only render it.
//
// Rules:
//  - Upcoming = live, not completed, date >= today. An exam on today's date stays upcoming for the whole day.
//  - History = live and (completed or date < today). Newest first. An uncompleted past exam offers "mark done".
//  - Sort order of upcoming exams: date, start time (no start sorts last), title, id.
//  - Exam periods are `CalendarBreak`s of kind `.examPeriod` that end today or later. An upcoming exam belongs to the
//    first period (by start date) that contains its date and applies to its timetable. For the university profile
//    with no such break, two or more upcoming exams form one *derived* period (first to last exam date).
//  - Exams outside every period are grouped by week (`CalendarContext.startOfWeek`, honours the first weekday).
//  - The featured exam is not repeated in the groups; `periodName` of its row names its period.
import Foundation
import TimetableCore

/// How close an exam is. Escalates towards the exam; the UI shows it with text and an icon as well as colour.
public enum ExamUrgency: String, Equatable, Sendable, CaseIterable {
    case later, thisWeek, soon, tomorrow, today, past

    /// Urgency of an exam `daysUntil` days away (negative = past).
    public init(daysUntil: Int) {
        switch daysUntil {
        case ..<0: self = .past
        case 0: self = .today
        case 1: self = .tomorrow
        case 2...3: self = .soon
        case 4...7: self = .thisWeek
        default: self = .later
        }
    }

    /// SF Symbol that accompanies the urgency (never colour alone).
    public var symbolName: String {
        switch self {
        case .today: return "exclamationmark.triangle.fill"
        case .tomorrow: return "exclamationmark.circle.fill"
        case .soon: return "clock.fill"
        case .thisWeek, .later, .past: return "calendar"
        }
    }
}

/// "Today", "Tomorrow", "in 5 days", "Yesterday", "3 days ago".
public enum ExamWhen: Equatable, Sendable {
    case today, tomorrow, inDays(Int), yesterday, daysAgo(Int)

    /// The phrase for an exam `daysUntil` days away.
    public init(daysUntil: Int) {
        switch daysUntil {
        case 0: self = .today
        case 1: self = .tomorrow
        case 2...: self = .inDays(daysUntil)
        case -1: self = .yesterday
        default: self = .daysAgo(-daysUntil)
        }
    }

    /// Catalog key (plural variations on `%lld` for `inDays` / `daysAgo`).
    public var l10nKey: String {
        switch self {
        case .today: return "exams.when.today"
        case .tomorrow: return "exams.when.tomorrow"
        case .inDays: return "exams.when.inDays"
        case .yesterday: return "exams.when.yesterday"
        case .daysAgo: return "exams.when.daysAgo"
        }
    }

    /// The `%lld` argument, if the key has one.
    public var count: Int? {
        switch self {
        case .inDays(let n), .daysAgo(let n): return n
        default: return nil
        }
    }
}

/// One exam as the lists show it.
public struct ExamRow: Identifiable, Equatable, Sendable {
    public var exam: Exam
    public var subject: SubjectSummary?
    /// Whole days from today to the exam date (negative = past).
    public var daysUntil: Int
    public var when: ExamWhen
    /// `.past` for completed exams, whatever their date.
    public var urgency: ExamUrgency
    /// Name of the exam period containing the exam (only set for the featured row; the others sit under the period).
    public var periodName: String?
    public var id: Exam.ID { exam.id }

    public init(exam: Exam, subject: SubjectSummary?, today: LocalDate, periodName: String? = nil) {
        self.exam = exam
        self.subject = subject
        daysUntil = today.days(to: exam.date)
        when = ExamWhen(daysUntil: daysUntil)
        urgency = exam.isCompleted ? .past : ExamUrgency(daysUntil: daysUntil)
        self.periodName = periodName
    }
}

/// Exams of one calendar week.
public struct ExamWeekGroup: Identifiable, Equatable, Sendable {
    public enum Label: Equatable, Sendable {
        case thisWeek, nextWeek
        /// "Week of 26 Oct".
        case weekOf(LocalDate)
    }
    public var weekStart: LocalDate
    public var label: Label
    public var rows: [ExamRow]
    public var id: LocalDate { weekStart }
}

/// An exam period with the exams inside it.
public struct ExamPeriodSection: Identifiable, Equatable, Sendable {
    /// The break's id, or `derived`.
    public var id: String
    /// The break's name (user text); `nil` for a derived period.
    public var name: String?
    public var range: LocalDateRange
    public var isDerived: Bool
    /// Today lies within the range.
    public var isCurrent: Bool
    /// Upcoming exams inside the period, including the featured one.
    public var examCount: Int
    /// The exams to list under the header (without the featured one).
    public var rows: [ExamRow]
}

/// The whole Exams tab.
public struct ExamListModel: Equatable, Sendable {
    public var next: ExamRow?
    public var periods: [ExamPeriodSection]
    public var weeks: [ExamWeekGroup]
    public var history: [ExamRow]

    /// Nothing to show on either segment.
    public var isEmpty: Bool { next == nil && periods.isEmpty && weeks.isEmpty && history.isEmpty }
    /// At least one upcoming exam.
    public var hasUpcoming: Bool { next != nil }

    /// Builds the model from the live exams of `database` as seen on `today`.
    public static func make(database: TabulaDatabase, today: LocalDate, context: CalendarContext) -> ExamListModel {
        let subjects = Dictionary(database.subjects.filter { !$0.isDeleted }.map { ($0.id, SubjectSummary($0)) },
                                  uniquingKeysWith: { first, _ in first })
        func row(_ exam: Exam, period: String? = nil) -> ExamRow {
            ExamRow(exam: exam, subject: exam.subjectID.flatMap { subjects[$0] }, today: today, periodName: period)
        }
        let live = database.exams.filter { !$0.isDeleted }
        let upcoming = live.filter { !$0.isCompleted && $0.date >= today }.sorted(by: order)
        let history = live.filter { $0.isCompleted || $0.date < today }
            .sorted { ($1.date, $1.start ?? .midnight, $1.id) < ($0.date, $0.start ?? .midnight, $0.id) }
            .map { row($0) }

        guard let first = upcoming.first else {
            return ExamListModel(next: nil, periods: [], weeks: [], history: history)
        }

        let candidates = periodCandidates(database: database, upcoming: upcoming, today: today)
        var sections = candidates.map(\.section)
        // exam → index of the first period it belongs to.
        var assigned: [Exam.ID: Int] = [:]
        for exam in upcoming {
            assigned[exam.id] = candidates.firstIndex {
                $0.section.range.contains(exam.date)
                    && ($0.timetableID == nil || exam.timetableID == nil || $0.timetableID == exam.timetableID)
            }
        }
        var inPeriod = [[ExamRow]](repeating: [], count: sections.count)
        var weekly: [Exam] = []
        for exam in upcoming.dropFirst() {
            if let index = assigned[exam.id] {
                inPeriod[index].append(row(exam))
            } else {
                weekly.append(exam)
            }
        }
        for index in sections.indices {
            sections[index].rows = inPeriod[index]
            sections[index].examCount = assigned.values.filter { $0 == index }.count
        }

        let todayWeek = context.startOfWeek(containing: today)
        var weeks: [ExamWeekGroup] = []
        for exam in weekly {
            let start = context.startOfWeek(containing: exam.date)
            if let last = weeks.last, last.weekStart == start {
                weeks[weeks.count - 1].rows.append(row(exam))
            } else {
                weeks.append(ExamWeekGroup(weekStart: start, label: weekLabel(start, todayWeek: todayWeek),
                                           rows: [row(exam)]))
            }
        }
        let featuredPeriodName = assigned[first.id].flatMap { sections[$0].name }
        return ExamListModel(next: row(first, period: featuredPeriodName), periods: sections, weeks: weeks,
                             history: history)
    }

    // MARK: Internals

    private static func order(_ lhs: Exam, _ rhs: Exam) -> Bool {
        func key(_ exam: Exam) -> (LocalDate, Int, String, Exam.ID) {
            (exam.date, exam.start?.minuteOfDay ?? Int.max, exam.title, exam.id)
        }
        return key(lhs) < key(rhs)
    }

    private static func weekLabel(_ start: LocalDate, todayWeek: LocalDate) -> ExamWeekGroup.Label {
        switch todayWeek.days(to: start) {
        case 0: return .thisWeek
        case 7: return .nextWeek
        default: return .weekOf(start)
        }
    }

    /// The exam-period breaks that end today or later (with the timetable they apply to), or the derived period.
    private static func periodCandidates(database: TabulaDatabase, upcoming: [Exam], today: LocalDate)
        -> [(section: ExamPeriodSection, timetableID: Timetable.ID?)] {
        let breaks = database.breaks
            .filter { !$0.isDeleted && $0.kind == .examPeriod && !$0.range.isEmpty && $0.range.end >= today }
            .sorted { ($0.range.start, $0.range.end, $0.id) < ($1.range.start, $1.range.end, $1.id) }
        if !breaks.isEmpty {
            return breaks.map {
                (ExamPeriodSection(id: $0.id.uuid.uuidString, name: $0.name, range: $0.range, isDerived: false,
                                   isCurrent: $0.range.contains(today), examCount: 0, rows: []), $0.timetableID)
            }
        }
        guard database.settings.profile.effective == .university, upcoming.count >= 2,
              let lower = upcoming.map(\.date).min(), let upper = upcoming.map(\.date).max() else { return [] }
        let range = LocalDateRange(start: lower, end: upper)
        return [(ExamPeriodSection(id: "derived", name: nil, range: range, isDerived: true,
                                   isCurrent: range.contains(today), examCount: 0, rows: []), nil)]
    }
}
