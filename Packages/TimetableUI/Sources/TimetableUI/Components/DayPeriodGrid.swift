// The Grid as days × periods (`GridLayoutStyle.daysAsRows`, human decision 2026-11-01, the Slovak aSc layout): the
// transposed view data and its width / height maths. The periods × days layout (`GridLayout` as is, `GridMode.choose`
// with a column count) stays the second option. Pure, Linux-tested.
import Foundation
import TimetableCore

extension GridMode {
    /// Narrowest period column (points) at the default text size. 46 pt is above the 44 pt tap target (HIG) and lets
    /// 7 periods share the width of a 375 pt phone in portrait next to the day column, without scrolling.
    public static let minimumPeriodColumnWidth = 46.0
    /// Below this many visible period columns the grid is not worth scrolling: the list is used.
    public static let minimumVisiblePeriodColumns = 3

    /// Days × periods: the list at accessibility text sizes or when fewer than `minimumVisiblePeriodColumns` period
    /// columns of `minimumWidth` fit next to the day column (more periods scroll horizontally).
    public static func choose(isAccessibilitySize: Bool, availableWidth: Double, dayColumnWidth: Double,
                              minimumWidth: Double = minimumPeriodColumnWidth) -> GridMode {
        if isAccessibilitySize { return .list }
        return (availableWidth - dayColumnWidth) / minimumWidth >= Double(minimumVisiblePeriodColumns) ? .grid : .list
    }

    /// Width of each of `count` period columns: they share the width when each gets at least `minimumWidth` (always
    /// when `fitAll`, e.g. the export page); otherwise they keep `minimumWidth` and scroll horizontally.
    public static func periodColumnWidth(count: Int, availableWidth: Double, dayColumnWidth: Double,
                                         minimumWidth: Double = minimumPeriodColumnWidth,
                                         fitAll: Bool = false) -> (width: Double, scrolls: Bool) {
        let share = (availableWidth - dayColumnWidth) / Double(max(1, count))
        if fitAll || share >= minimumWidth { return (max(1, share), false) }
        return (minimumWidth, true)
    }

    /// Height of each of `count` day rows: they share `available`, at least `minimum` (the grid then scrolls
    /// vertically) and at most `maximum` (a short week should not get half-screen cells).
    public static func dayRowHeight(count: Int, available: Double, minimum: Double, maximum: Double) -> Double {
        guard count > 0 else { return minimum }
        return min(max(minimum, available / Double(count)), max(minimum, maximum))
    }
}

/// Rows are the layout's columns (dates), columns are its lesson rows (periods). Break rows are dropped: the header's
/// start times show the gaps, a phone needs every point for periods, and a double period across a break simply spans
/// two adjacent columns. Free-form timetables keep `GridLayout`'s rows: one column per distinct start–end pair of the
/// week, in time order.
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
