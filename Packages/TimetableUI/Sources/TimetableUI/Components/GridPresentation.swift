// Presentation decisions of the days × periods grid and the week time-block view that do not need SwiftUI:
// grid-or-list (accessibility sizes and very narrow screens switch to a list), the transposed grid (`DayPeriodGrid`),
// column widths and row heights, the list fallback's rows, cell titles, VoiceOver sentences with row/column context
// and the current-time line. Pure, Linux-tested.
import Foundation
import TimetableCore

/// Grid or list, and the grid's geometry.
public enum GridMode: Equatable, Sendable {
    case grid
    case list

    /// Narrowest period column (points) at the default text size. 46 pt is above the 44 pt tap target (HIG) and lets
    /// 7 periods share the width of a 375 pt phone in portrait next to the day column, without scrolling.
    public static let minimumColumnWidth = 46.0
    /// Below this many visible period columns the grid is not worth scrolling: the list is used.
    public static let minimumVisibleColumns = 3

    /// The list at accessibility text sizes (REFERENCE_ANALYSIS anti-pattern 5) or when fewer than
    /// `minimumVisibleColumns` period columns of `minimumWidth` fit next to the day column.
    public static func choose(isAccessibilitySize: Bool, availableWidth: Double, labelColumnWidth: Double,
                              minimumWidth: Double = minimumColumnWidth) -> GridMode {
        if isAccessibilitySize { return .list }
        return (availableWidth - labelColumnWidth) / minimumWidth >= Double(minimumVisibleColumns) ? .grid : .list
    }

    /// Width of each of `count` period columns: they share the width when each gets at least `minimumWidth` (always
    /// when `fitAll`, e.g. the export page); otherwise they keep `minimumWidth` and scroll horizontally.
    public static func columnWidth(count: Int, availableWidth: Double, labelColumnWidth: Double,
                                   minimumWidth: Double = minimumColumnWidth,
                                   fitAll: Bool = false) -> (width: Double, scrolls: Bool) {
        let share = (availableWidth - labelColumnWidth) / Double(max(1, count))
        if fitAll || share >= minimumWidth { return (max(1, share), false) }
        return (minimumWidth, true)
    }

    /// Height of each of `count` day rows: they share `available`, at least `minimum` (the grid then scrolls
    /// vertically) and at most `maximum` (a short week should not get half-screen cells).
    public static func rowHeight(count: Int, available: Double, minimum: Double, maximum: Double) -> Double {
        guard count > 0 else { return minimum }
        return min(max(minimum, available / Double(count)), max(minimum, maximum))
    }
}

/// The Grid as days × periods (human decision 2026-11-01, the Slovak aSc layout): rows are the layout's columns
/// (dates), columns are its lesson rows (periods). Break rows are dropped: the header's start times show the gaps, a
/// phone needs every point for periods, and a double period across a break simply spans two adjacent columns.
/// Free-form timetables keep `GridLayout`'s rows: one column per distinct start–end pair of the week, in time order.
public struct DayPeriodGrid: Equatable, Sendable {
    /// A lesson placed in a day row.
    public struct Cell: Equatable, Sendable {
        /// Day row (index in `days`, = `GridLayout.Column.index`).
        public var day: Int
        /// First period column (index in `periods`).
        public var period: Int
        /// Number of period columns covered (≥ 1).
        public var span: Int
        /// The layout's cell.
        public var cell: GridLayout.Cell
    }

    /// A free period of a school day (tap → quick add).
    public struct Free: Hashable, Sendable {
        /// Day row.
        public var day: Int
        /// Period column.
        public var period: Int
        /// The `GridLayout` row index (for quick add and VoiceOver).
        public var row: Int
    }

    /// Period columns, leading to trailing: the layout's lesson rows (only periods the bell schedule has).
    public var periods: [GridLayout.Row]
    /// Day rows, top to bottom.
    public var days: [GridLayout.Column]
    /// Lessons, in the layout's order (day, then period).
    public var cells: [Cell]
    /// Free periods, by day then period.
    public var free: [Free]
    /// Lessons that match no period column (outside the bell schedule, or only on a break), by date and time.
    public var unplaced: [ResolvedLesson]

    public init(_ layout: GridLayout) {
        periods = layout.rows.filter(\.isLessonRow)
        days = layout.columns
        var periodOfRow: [Int: Int] = [:]
        for (period, row) in periods.enumerated() { periodOfRow[row.index] = period }
        var unplaced = layout.unplaced
        cells = layout.cells.compactMap { cell in
            let covered = (cell.row..<(cell.row + cell.rowSpan)).compactMap { periodOfRow[$0] }
            guard let first = covered.first, let last = covered.last else {
                unplaced.append(cell.entry)
                return nil
            }
            return Cell(day: cell.column, period: first, span: last - first + 1, cell: cell)
        }
        free = layout.emptySlots.compactMap { slot in
            guard let period = periodOfRow[slot.row] else { return nil }
            let row = layout.rows[slot.row]
            // Free-form columns overlap (8:00–9:30 and 9:00–10:30): a slot whose start time a lesson of that day is
            // running at is not free (Monday 9:00 during an 8:00–9:30 lecture).
            if row.periodID == nil, layout.cells.contains(where: {
                $0.column == slot.column && $0.entry.startTime <= row.start && row.start < $0.entry.endTime
            }) { return nil }
            return Free(day: slot.column, period: period, row: slot.row)
        }
        self.unplaced = unplaced.sorted { ($0.date, $0.startTime) < ($1.date, $1.startTime) }
    }

    /// `true` when period column `period` is running at `minuteOfDay` and `today` is one of the shown days.
    public func isCurrent(period: Int, today: LocalDate, minuteOfDay: Int) -> Bool {
        guard periods.indices.contains(period), days.contains(where: { $0.date == today }) else { return false }
        let row = periods[period]
        return row.start.minuteOfDay <= minuteOfDay && minuteOfDay < row.end.minuteOfDay
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

    /// VoiceOver sentence of a free slot: "Tuesday, 13 October, period 3, 9:50 to 10:35, free". Free-form slots
    /// (no bell-schedule period) have no period number: "Tuesday, 13 October, 9:00 to 10:30, free".
    public static func freeSlotAccessibilityLabel(column: GridLayout.Column, row: GridLayout.Row,
                                                  renderer: LocalizedTextRenderer) -> String {
        var parts = [renderer.formatter.date(column.date, style: .full)]
        if row.periodID != nil, let number = row.lessonNumber {
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
