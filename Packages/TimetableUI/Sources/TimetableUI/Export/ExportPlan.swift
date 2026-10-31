// Pure logic of the Export sheet (Phase 8 E2): the choices, range resolution, page list, file names and the
// `ExportLabels` built from catalog keys. No SwiftUI, so it runs in the Linux tests.
import Foundation
import TimetableCore

/// What the file is.
public enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case image, pdf, csv, excel, calendar
    public var id: String { rawValue }
    /// The View picker applies to image and PDF only.
    public var showsView: Bool { self == .image || self == .pdf }
    public var fileExtension: String {
        switch self {
        case .image: "png"
        case .pdf: "pdf"
        case .csv: "csv"
        case .excel: "xlsx"
        case .calendar: "ics"
        }
    }
    public var nameKey: String { "export.type.\(rawValue)" }
}

/// Which of the timetable's views an image or PDF shows.
public enum ExportView: String, CaseIterable, Identifiable, Sendable {
    case grid, week, day
    public var id: String { rawValue }
    /// Existing catalog keys of the Timetable view picker.
    public var nameKey: String {
        switch self {
        case .grid: "timetable.view.grid"
        case .week: "timetable.view.timeBlocks"
        case .day: "timetable.view.day"
        }
    }
}

public enum ExportRangeChoice: String, CaseIterable, Identifiable, Sendable {
    case thisWeek, term, custom
    public var id: String { rawValue }
    public var nameKey: String { "export.range.\(rawValue)" }
}

public enum ExportPlan {
    /// A custom range longer than this is cut (bounds file size and PDF pages).
    public static let maximumDays = 366
    /// Without a current term: today plus this many days.
    public static let fallbackDays = 28
    /// An image holds at most this many pages stacked (bitmap size limit); a PDF has no cap.
    public static let maximumImagePages = 6

    /// The dates to export. `terms` are the timetable's live terms; the current term is the one containing today.
    public static func range(_ choice: ExportRangeChoice, custom: LocalDateRange, today: LocalDate,
                             context: CalendarContext, terms: [Term]) -> LocalDateRange {
        switch choice {
        case .thisWeek:
            let start = context.startOfWeek(containing: today)
            return LocalDateRange(start: start, end: start.adding(days: 6))
        case .term:
            if let term = currentTerm(terms, today: today) { return term.range }
            return LocalDateRange(start: today, end: today.adding(days: fallbackDays - 1))
        case .custom:
            let end = max(custom.start, custom.end)
            let capped = min(end, custom.start.adding(days: maximumDays - 1))
            return LocalDateRange(start: custom.start, end: capped)
        }
    }

    /// The term containing `today` (the earliest-starting one when they overlap).
    public static func currentTerm(_ terms: [Term], today: LocalDate) -> Term? {
        terms.filter { $0.range.contains(today) }.min { $0.range.start < $1.range.start }
    }

    /// The localised tail of the file name: "week 42", the term's name, "next 4 weeks" or "2026-10-12 to 2026-10-18".
    public static func fileSuffix(_ choice: ExportRangeChoice, range: LocalDateRange, termName: String?,
                                  renderer: LocalizedTextRenderer) -> String {
        switch choice {
        case .thisWeek:
            return renderer.format(key: "export.file.week",
                                   arguments: [.integer(Int64(range.start.adding(days: 3).isoWeek.week))])
        case .term:
            return termName ?? renderer.string(forKey: "export.file.nextWeeks")
        case .custom:
            return renderer.format(key: "export.file.custom",
                                   arguments: [.text(range.start.isoString), .text(range.end.isoString)])
        }
    }

    /// The first day of every page: each week of `range` for grid and week, each enabled day for day.
    public static func pages(view: ExportView, range: LocalDateRange, context: CalendarContext,
                             enabledDays: Set<Weekday>) -> [LocalDate] {
        guard !range.isEmpty else { return [] }
        if view == .day {
            return range.days.filter { enabledDays.isEmpty || enabledDays.contains($0.weekday) }
        }
        var pages: [LocalDate] = []
        var week = context.startOfWeek(containing: range.start)
        while week <= range.end {
            pages.append(week)
            week = week.adding(days: 7)
        }
        return pages
    }

    /// `Timetable 2.B – week 42.pdf`: only characters that are safe in a file name, no path separators,
    /// at most 80 characters of base name. `suffix` is the localised range description.
    public static func fileName(timetable: String, suffix: String, ext: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        func clean(_ text: String) -> String {
            var out = ""
            for scalar in text.unicodeScalars { out.unicodeScalars.append(forbidden.contains(scalar) ? " " : scalar) }
            return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }
        var base = clean([timetable, suffix].filter { !$0.isEmpty }.joined(separator: " – "))
        while let first = base.first, first == "." || first == " " { base.removeFirst() }   // no hidden or "../" names
        if base.count > 80 { base = String(base.prefix(80)).trimmingCharacters(in: .whitespaces) }
        if base.isEmpty { base = "Timetable" }
        return base + "." + ext
    }

    /// Column titles and the change text from catalog keys. A modified row lists its reasons with the locale's
    /// list format (nothing is concatenated); a changed row without reasons says "Changed".
    public static func labels(renderer: LocalizedTextRenderer) -> ExportLabels {
        let formatter = renderer.formatter
        return ExportLabels(
            date: renderer.string(forKey: "export.column.date"), start: renderer.string(forKey: "export.column.start"),
            end: renderer.string(forKey: "export.column.end"), subject: renderer.string(forKey: "export.column.subject"),
            room: renderer.string(forKey: "export.column.room"), teacher: renderer.string(forKey: "export.column.teacher"),
            change: renderer.string(forKey: "export.column.change"),
            changeText: { row in
                switch row.status {
                case .scheduled: return ""
                case .cancelled: return renderer.string(forKey: "lesson.status.cancelled")
                case .added: return renderer.string(forKey: "lesson.status.added")
                case .modified:
                    guard !row.reasons.isEmpty else { return renderer.string(forKey: "lesson.status.modified") }
                    return formatter.list(row.reasons.map { renderer.string(forKey: $0.l10nKey) })
                }
            })
    }
}
