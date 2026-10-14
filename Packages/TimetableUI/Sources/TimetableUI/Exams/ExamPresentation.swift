// Texts and visible facts of exams for the Exams tab, the exam detail and VoiceOver. Pure, Linux-tested.
//
// Field rule (PHASE2_PLAN §0.8, applied to exams): room, building and notes follow the timetable's
// `FieldVisibility` (a disabled field is hidden everywhere; an enabled-but-empty field is simply absent). The
// timetable is the exam's own, else the active one. Subject, title, kind, date, time and topics are always shown
// when present. No sentence is concatenated from translated fragments; user text is inserted verbatim.
import Foundation
import TimetableCore

extension ExamWhen {
    /// Every catalog key `l10nKey` can return (for `DynamicL10nKeys.allKeys`).
    public static let allKeys: [String] = [
        "exams.when.today", "exams.when.tomorrow", "exams.when.inDays", "exams.when.yesterday", "exams.when.daysAgo",
    ]
}

/// The non-empty, visible optional fields of an exam.
public struct ExamFacts: Equatable, Sendable {
    public var room: String?
    public var building: String?
    public var notes: String?
    /// Non-blank topics in the user's order.
    public var topics: [String]

    public init(exam: Exam, visibility: FieldVisibility) {
        room = visibility.isVisible(.room) ? EditorText.trimmedOrNil(exam.room ?? "") : nil
        building = visibility.isVisible(.building) ? EditorText.trimmedOrNil(exam.building ?? "") : nil
        notes = visibility.isVisible(.notes) ? EditorText.trimmedOrNil(exam.notes ?? "") : nil
        topics = EditorText.cleanedList(exam.topics)
    }

    /// "A214, FIIT" (user text only), or the one that exists, or `nil`.
    public var location: String? {
        let parts = [room, building].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The visibility that applies to `exam`: its timetable's, else the active timetable's, else everything.
    public static func visibility(for exam: Exam, in database: TabulaDatabase) -> FieldVisibility {
        visibility(timetableID: exam.timetableID, in: database)
    }

    /// The visibility of `timetableID`'s timetable, else the active timetable's, else everything.
    public static func visibility(timetableID: Timetable.ID?, in database: TabulaDatabase) -> FieldVisibility {
        let own = timetableID.flatMap { id in database.timetables.first { $0.id == id && !$0.isDeleted } }
        return (own ?? ActiveTimetable.resolve(database))?.fieldVisibility ?? .all
    }
}

/// Renders exam texts with a `LocalizedTextRenderer`.
public struct ExamTexts: Sendable {
    public let renderer: LocalizedTextRenderer

    public init(renderer: LocalizedTextRenderer) { self.renderer = renderer }

    /// "Today" / "Tomorrow" / "in 5 days" / "Yesterday" / "3 days ago".
    public func when(_ when: ExamWhen) -> String {
        if let count = when.count {
            return renderer.format(key: when.l10nKey, arguments: [.integer(Int64(count))])
        }
        return renderer.string(forKey: when.l10nKey)
    }

    /// "Written exam", … for the known kinds; the user's own word for any other (open vocabulary).
    public func kind(_ kind: ExamKind) -> String {
        kind.isKnown ? renderer.string(forKey: DynamicL10nKeys.examKind(kind)) : kind.rawValue
    }

    /// "Tue, Oct 20".
    public func date(_ date: LocalDate) -> String { renderer.formatter.date(date, style: .weekdayDayMonth) }

    /// "Tuesday, October 20, 2026".
    public func fullDate(_ date: LocalDate) -> String { renderer.formatter.date(date, style: .full) }

    /// "8:00" or "8:00 – 9:30"; `nil` without a start (an end alone is not shown).
    public func time(_ exam: Exam) -> String? {
        guard let start = exam.start else { return nil }
        if let end = exam.end, end > start { return renderer.formatter.timeRange(start, end) }
        return renderer.formatter.time(start)
    }

    /// Header of a week group.
    public func weekTitle(_ label: ExamWeekGroup.Label) -> String {
        switch label {
        case .thisWeek: return renderer.string(forKey: "exams.week.thisWeek")
        case .nextWeek: return renderer.string(forKey: "exams.week.nextWeek")
        case .weekOf(let start):
            return renderer.format(key: "exams.week.of", arguments: [.text(renderer.formatter.date(start, style: .dayMonth))])
        }
    }

    /// Name of an exam period (derived ones get a generic name).
    public func periodTitle(_ section: ExamPeriodSection) -> String {
        EditorText.trimmedOrNil(section.name ?? "") ?? renderer.string(forKey: "exams.period.derived")
    }

    /// "Oct 26 – Nov 6".
    public func periodRange(_ range: LocalDateRange) -> String {
        renderer.format(key: "exams.period.range", arguments: [
            .text(renderer.formatter.date(range.start, style: .dayMonth)),
            .text(renderer.formatter.date(range.end, style: .dayMonth)),
        ])
    }

    /// "3 exams" (plural variations), or "No exams yet" for zero.
    public func periodCount(_ section: ExamPeriodSection) -> String {
        section.examCount == 0
            ? renderer.string(forKey: "exams.period.none")
            : renderer.format(key: "exams.period.count", arguments: [.integer(Int64(section.examCount))])
    }

    /// First three topics ("limits, derivatives and series"), with an ellipsis when there are more; `nil` without topics.
    public func topicsPreview(_ topics: [String]) -> String? {
        guard !topics.isEmpty else { return nil }
        let shown = renderer.formatter.list(Array(topics.prefix(3)))
        return topics.count > 3 ? shown + "…" : shown
    }

    /// The one-sentence VoiceOver label of a row or the featured card: title, subject, kind, when, date, time,
    /// room, building and the completed state, joined as a locale-aware list.
    public func accessibilityLabel(_ row: ExamRow, facts: ExamFacts) -> String {
        var parts: [String] = []
        if let title = EditorText.trimmedOrNil(row.exam.title) { parts.append(title) }
        if let name = row.subject?.name { parts.append(name) }
        parts.append(kind(row.exam.kind))
        parts.append(when(row.when))
        parts.append(fullDate(row.exam.date))
        if let time = time(row.exam) { parts.append(time) }
        if let room = facts.room { parts.append(renderer.format(key: "exams.a11y.room", arguments: [.text(room)])) }
        if let building = facts.building {
            parts.append(renderer.format(key: "exams.a11y.building", arguments: [.text(building)]))
        }
        if row.exam.isCompleted { parts.append(renderer.string(forKey: "exams.a11y.done")) }
        return renderer.formatter.list(parts)
    }
}
