// Presentation decisions of the periods × days grid and the week time-block view that do not need SwiftUI:
// grid-or-list (accessibility sizes and very narrow columns switch to a list), the list fallback's rows, cell titles,
// VoiceOver sentences with row/column context and the current-time line. Pure, Linux-tested.
import Foundation
import TimetableCore

/// Grid or list.
public enum GridMode: Equatable, Sendable {
    case grid
    case list

    /// Narrowest day column (points) the grid is drawn with; below it the list is used. 44 pt is the minimum tap target
    /// (HIG): a 7-day week fits the grid from about 350 pt of usable width (44 + 7 x 44), narrower screens get the list.
    public static let minimumColumnWidth = 44.0

    /// The list at accessibility text sizes (REFERENCE_ANALYSIS anti-pattern 5) or when `columnCount` columns of at
    /// least `minimumColumnWidth` do not fit into `availableWidth` next to the period column.
    public static func choose(isAccessibilitySize: Bool, columnCount: Int, availableWidth: Double,
                              periodColumnWidth: Double) -> GridMode {
        if isAccessibilitySize { return .list }
        guard columnCount > 0 else { return .grid }
        let perColumn = (availableWidth - periodColumnWidth) / Double(columnCount)
        return perColumn >= minimumColumnWidth ? .grid : .list
    }
}

/// One row of the list fallback for one day.
public enum GridListItem: Equatable, Sendable, Identifiable {
    /// An occurrence starting in `row`.
    case lesson(GridLayout.Cell, row: GridLayout.Row)
    /// A free lesson period (tap → quick add).
    case free(column: Int, row: GridLayout.Row)
    /// A break or lunch period.
    case breakRow(GridLayout.Row)

    public var id: String {
        switch self {
        case let .lesson(cell, _): return "lesson:\(cell.entry.id.rawValue)"
        case let .free(column, row): return "free:\(column):\(row.index)"
        case let .breakRow(row): return "break:\(row.index)"
        }
    }
}

/// One day of the list fallback.
public struct GridListSection: Equatable, Sendable, Identifiable {
    public var column: GridLayout.Column
    public var items: [GridListItem]
    public var id: Int { column.index }
}

/// Builds view data from a `GridLayout`.
public enum GridPresentation {
    /// The list fallback: per column, rows top to bottom; a spanning cell appears once (at its first row); break rows
    /// are kept only between two items of the day (never leading or trailing); unplaced occurrences are appended in
    /// time order.
    public static func listSections(_ layout: GridLayout) -> [GridListSection] {
        layout.columns.map { column in
            let cells = layout.cells.filter { $0.column == column.index }
            let free = Set(layout.emptySlots.filter { $0.column == column.index }.map(\.row))
            var items: [GridListItem] = []
            var pendingBreak: GridLayout.Row?
            for row in layout.rows {
                let starting = cells.filter { $0.row == row.index }
                if !row.isLessonRow {
                    if starting.isEmpty {
                        // Several break rows in a row collapse into one separator; lunch wins.
                        if !items.isEmpty, pendingBreak == nil || row.kind == .lunch { pendingBreak = row }
                        continue
                    }
                }
                var rowItems: [GridListItem] = starting.map { .lesson($0, row: row) }
                if starting.isEmpty, free.contains(row.index) {
                    rowItems.append(.free(column: column.index, row: row))
                }
                guard !rowItems.isEmpty else { continue }
                if let pending = pendingBreak { items.append(.breakRow(pending)) }
                pendingBreak = nil
                items += rowItems
            }
            return GridListSection(column: column, items: items)
        }
    }

    /// Occurrences of `column` that match no grid row (free-form times outside the bell schedule).
    public static func unplaced(_ layout: GridLayout, column: GridLayout.Column) -> [ResolvedLesson] {
        layout.unplaced.filter { $0.date == column.date }
    }

    /// The text of a grid cell: the short name when the subject has one (user data), else the full name.
    public static func cellTitle(_ subject: SubjectSummary) -> String {
        if let short = TodayState.nonBlank(subject.shortName) { return short }
        return subject.name
    }

    /// The emoji of a subject, if it has one (SF Symbols are drawn by the view).
    public static func emoji(_ subject: SubjectSummary) -> String? {
        if case .emoji(let emoji)? = subject.symbol { return TodayState.nonBlank(emoji) }
        return nil
    }

    /// The period column label of a row: the user label, else the lesson number; `nil` for unlabelled breaks.
    public static func rowLabel(_ row: GridLayout.Row) -> String? {
        if let label = TodayState.nonBlank(row.label) { return label }
        return row.lessonNumber.map(String.init)
    }

    /// VoiceOver sentence of a grid/list cell with its column context: "Tuesday, 13 October: Matematika, period 2, …".
    public static func cellAccessibilityLabel(_ cell: GridLayout.Cell, reasons: [ModificationReason],
                                              visibility: FieldVisibility, badges: LessonBadges? = nil,
                                              renderer: LocalizedTextRenderer) -> String {
        let lesson = LessonAccessibilityLabel.make(lesson: cell.entry, visibility: visibility, reasons: reasons,
                                                   badges: badges, renderer: renderer)
        var text = renderer.format(key: "timetable.a11y.cell", arguments: [
            .text(renderer.formatter.date(cell.entry.date, style: .full)), .text(lesson),
        ])
        if cell.isInConflict {
            text += renderer.string(forKey: "a11y.separator") + renderer.string(forKey: "timetable.a11y.conflict")
        }
        return text
    }

    /// VoiceOver sentence of a free slot: "Tuesday, 13 October, period 3, 9:50 to 10:35, free".
    public static func freeSlotAccessibilityLabel(column: GridLayout.Column, row: GridLayout.Row,
                                                  renderer: LocalizedTextRenderer) -> String {
        var parts = [renderer.formatter.date(column.date, style: .full)]
        if let number = row.lessonNumber {
            parts.append(renderer.format(key: "a11y.lesson.period", arguments: [.integer(Int64(number))]))
        } else if let label = TodayState.nonBlank(row.label) {
            parts.append(renderer.format(key: "a11y.lesson.periodLabel", arguments: [.text(label)]))
        }
        parts.append(renderer.format(key: "a11y.lesson.time", arguments: [
            .text(renderer.formatter.time(row.start)), .text(renderer.formatter.time(row.end)),
        ]))
        parts.append(renderer.string(forKey: "timetable.a11y.free"))
        return parts.joined(separator: renderer.string(forKey: "a11y.separator"))
    }

    /// Where the current-time line goes in a time-block layout: the column of `today` and the fractional position of
    /// `minuteOfDay`, or `nil` when today is not shown or the time is outside the visible range.
    public static func nowMarker(_ layout: TimeBlockLayout, today: LocalDate, minuteOfDay: Int) -> (column: Int, position: Double)? {
        guard let column = layout.columns.first(where: { $0.date == today }),
              minuteOfDay >= layout.startMinute, minuteOfDay <= layout.endMinute else { return nil }
        return (column.index, layout.position(ofMinute: minuteOfDay))
    }
}

/// Minimum tap target (HIG: 44 x 44 pt). Proportional views (time blocks) keep their drawn size and only widen the
/// hit area, so proportions are not distorted.
public enum TapTarget {
    public static let minimum = 44.0

    /// The hit length for a drawn `length` and the amount the hit area extends beyond it on each side.
    public static func hitArea(drawn length: Double) -> (length: Double, overhang: Double) {
        let hit = max(length, minimum)
        return (hit, (hit - length) / 2)
    }
}
