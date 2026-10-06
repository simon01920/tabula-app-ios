import Foundation

/// The classic periods × days grid: rows are periods, columns are dates, cells are occurrences that may span
/// several rows.
///
/// - **Rows** come from the timetable's default bell schedule (all periods, or only lesson periods when
///   `includeBreakRows == false`). Free-form timetables (or a missing default schedule) get one row per
///   distinct start–end pair of the shown occurrences.
/// - **Cells**: a period-slotted occurrence starts in the row of its period (by `Period.ID`, else by the
///   same ordinal among periods of the same kind — so a short Friday's "period 3" sits in row "3") and spans
///   its lesson periods plus any break rows in between. A time-slotted occurrence covers the rows of the
///   lesson periods it overlaps in its day's bell schedule. Occurrences without a matching row are listed in
///   `unplaced` (the UI shows them below the grid). Cancelled occurrences are cells too (struck through).
/// - **Empty slots**: lesson rows of school-day columns that no cell covers (free periods).
/// - **Which cycle week**: `week(containing:)` shows the cycle week of that week (`cycleWeek`); use
///   `RotationResolver.startOfWeek(withCycleWeek:onOrAfter:)` to jump to "week B" and
///   `displayWeekStart(today:resolver:)` for the default week (next week once this week's school days are over).
public struct GridLayout: Hashable, Sendable, Codable {
    /// One grid row (a period).
    public struct Row: Hashable, Sendable, Codable {
        /// Index in `rows`.
        public var index: Int
        /// Lesson, break or lunch (free-form rows are `.lesson`).
        public var kind: PeriodKind
        /// The period of the reference schedule (`nil` for free-form rows).
        public var periodID: Period.ID?
        /// The period's user label, if any.
        public var label: String?
        /// 1-based number among lesson rows (`nil` for break rows).
        public var lessonNumber: Int?
        /// Start of the period in the reference schedule (or of the free-form slot).
        public var start: LocalTime
        /// End of the period in the reference schedule (or of the free-form slot).
        public var end: LocalTime

        /// `true` for lesson rows.
        public var isLessonRow: Bool { kind == .lesson }
    }

    /// One grid column (a date).
    public struct Column: Hashable, Sendable, Codable {
        /// Index in `columns`.
        public var index: Int
        /// Date.
        public var date: LocalDate
        /// Resolved day key (after `followDay`).
        public var dayKey: DayKey?
        /// Cycle week (week cycles).
        public var cycleWeek: Int?
        /// User label of the cycle week/day, if any.
        public var cycleLabel: String?
        /// Whether regular lessons take place.
        public var isSchoolDay: Bool
        /// Break covering the date.
        public var activeBreakID: CalendarBreak.ID?
        /// `cancelDay` override, if the day is cancelled.
        public var cancellingOverrideID: ScheduleOverride.ID?
        /// Bell schedule used on the date.
        public var bellScheduleID: BellSchedule.ID?

        /// Weekday of `date`.
        public var weekday: Weekday { date.weekday }
    }

    /// An occurrence placed in the grid.
    public struct Cell: Hashable, Sendable, Codable {
        /// Column index.
        public var column: Int
        /// First row index.
        public var row: Int
        /// Number of rows covered (≥ 1), including break rows inside a multi-period occurrence.
        public var rowSpan: Int
        /// The occurrence.
        public var entry: ResolvedLesson
        /// `true` when the occurrence is part of a conflict on its date.
        public var isInConflict: Bool
    }

    /// A (column, row) position.
    public struct Slot: Hashable, Sendable, Codable {
        /// Column index.
        public var column: Int
        /// Row index.
        public var row: Int
    }

    /// First day of the week shown (`week(containing:)` only).
    public var weekStart: LocalDate?
    /// Cycle week shown (week cycles, `week(containing:)` only).
    public var cycleWeek: Int?
    /// User label of `cycleWeek`, if any.
    public var cycleLabel: String?
    /// Bell schedule the rows come from (`nil` for free-form rows).
    public var referenceBellScheduleID: BellSchedule.ID?
    /// Rows, top to bottom.
    public var rows: [Row]
    /// Columns, left to right (leading to trailing).
    public var columns: [Column]
    /// Cells, ascending by (column, row, rowSpan, entry order).
    public var cells: [Cell]
    /// Free lesson slots of school-day columns, ascending by (column, row).
    public var emptySlots: [Slot]
    /// Occurrences that match no row, in day order.
    public var unplaced: [ResolvedLesson]

    // MARK: Factories

    /// The grid of the user's week containing `date` (week start = `resolver.context.firstWeekday`), with the
    /// columns of `weekdays` (default: the timetable's enabled days) in week order.
    public static func week(containing date: LocalDate, resolver: ScheduleResolver, options: ResolutionOptions = .actual,
                            weekdays: Set<Weekday>? = nil, includeBreakRows: Bool = true) -> GridLayout {
        let start = resolver.rotation.startOfWeek(containing: date)
        let shown = weekdays ?? resolver.timetable.enabledDays
        let dates = (0..<7).map { start.adding(days: $0) }.filter { shown.contains($0.weekday) }
        var layout = make(days: dates.map { resolver.day($0, options: options) }, resolver: resolver,
                          includeBreakRows: includeBreakRows)
        layout.weekStart = start
        layout.cycleWeek = resolver.rotation.cycleWeek(on: start)
        layout.cycleLabel = layout.cycleWeek.flatMap(resolver.rotation.label(forCycleWeek:))
        return layout
    }

    /// One full day cycle ("Day 1 … Day N" columns): the first date on or after `date` with cycle day 1 and the
    /// following school days of the cycle. `nil` unless the timetable has a day cycle. Defaults to
    /// `.regular` (the template, without holidays or one-off changes).
    public static func dayCycle(startingOnOrAfter date: LocalDate, resolver: ScheduleResolver,
                                options: ResolutionOptions = .regular, includeBreakRows: Bool = true) -> GridLayout? {
        guard case .dayCycle(let cycle) = resolver.timetable.rotation, cycle.length >= 1,
              let first = resolver.rotation.firstDate(withCycleDay: 1, onOrAfter: date) else { return nil }
        var dates: [LocalDate] = []
        var candidate = first
        var guardDays = 0
        while dates.count < cycle.length && guardDays < 800 {
            if resolver.rotation.cycleDay(on: candidate) != nil { dates.append(candidate) }
            candidate = candidate.adding(days: 1)
            guardDays += 1
        }
        return make(days: dates.map { resolver.day($0, options: options) }, resolver: resolver,
                    includeBreakRows: includeBreakRows)
    }

    /// The week a week grid should open on: the week containing `today`, or the next one once `today` is after
    /// the last enabled weekday of its week (weekend → next week).
    public static func displayWeekStart(today: LocalDate, resolver: ScheduleResolver) -> LocalDate {
        let start = resolver.rotation.startOfWeek(containing: today)
        let lastEnabled = (0..<7).map { start.adding(days: $0) }.last { resolver.timetable.enabledDays.contains($0.weekday) }
        if let lastEnabled, today > lastEnabled { return start.adding(days: 7) }
        return start
    }

    /// Lays out `days` (one column each, in the given order).
    public static func make(days: [DaySchedule], resolver: ScheduleResolver, includeBreakRows: Bool = true) -> GridLayout {
        var reference: BellScheduleIndex?
        if case let .bellSchedule(defaultID, _) = resolver.timetable.timeStructure {
            reference = resolver.schedulesByID[defaultID]
        }
        let columns = days.enumerated().map { index, day in
            Column(index: index, date: day.date, dayKey: day.dayKey, cycleWeek: day.cycleWeek, cycleLabel: day.cycleLabel,
                   isSchoolDay: day.isSchoolDay, activeBreakID: day.activeBreakID,
                   cancellingOverrideID: day.cancellingOverrideID, bellScheduleID: day.bellScheduleID)
        }

        var rows: [Row] = []
        var rowByPosition: [Int: Int] = [:]
        if let reference {
            for (position, period) in reference.periods.enumerated() where includeBreakRows || period.kind == .lesson {
                rowByPosition[position] = rows.count
                rows.append(Row(index: rows.count, kind: period.kind, periodID: period.id, label: period.label,
                                lessonNumber: reference.lessonNumber(atPosition: position), start: period.start, end: period.end))
            }
        } else {
            let pairs = Set(days.flatMap { $0.entries.map { TimePair(start: $0.startTime, end: $0.endTime) } }).sorted()
            for pair in pairs {
                rows.append(Row(index: rows.count, kind: .lesson, periodID: nil, label: nil, lessonNumber: rows.count + 1,
                                start: pair.start, end: pair.end))
            }
        }

        var cells: [Cell] = []
        var unplaced: [ResolvedLesson] = []
        for (columnIndex, day) in days.enumerated() {
            let conflicted = Set(day.conflicts.flatMap(\.occurrenceIDs))
            let dayIndex = day.bellScheduleID.flatMap { resolver.schedulesByID[$0] }
            for entry in day.entries {
                let span: (first: Int, last: Int)?
                if let reference {
                    span = rowSpan(of: entry, reference: reference, dayIndex: dayIndex, rowByPosition: rowByPosition)
                } else {
                    span = rows.firstIndex { $0.start == entry.startTime && $0.end == entry.endTime }.map { ($0, $0) }
                }
                guard let span else {
                    unplaced.append(entry)
                    continue
                }
                cells.append(Cell(column: columnIndex, row: span.first, rowSpan: span.last - span.first + 1, entry: entry,
                                  isInConflict: conflicted.contains(entry.id)))
            }
        }
        cells.sort { lhs, rhs in
            if (lhs.column, lhs.row, lhs.rowSpan) != (rhs.column, rhs.row, rhs.rowSpan) {
                return (lhs.column, lhs.row, lhs.rowSpan) < (rhs.column, rhs.row, rhs.rowSpan)
            }
            return ScheduleResolver.wallClockOrder(lhs.entry, rhs.entry)
        }

        var emptySlots: [Slot] = []
        for column in columns where column.isSchoolDay {
            let covered = cells.filter { $0.column == column.index }.flatMap { $0.row..<($0.row + $0.rowSpan) }
            let coveredSet = Set(covered)
            for row in rows where row.isLessonRow && !coveredSet.contains(row.index) {
                emptySlots.append(Slot(column: column.index, row: row.index))
            }
        }

        return GridLayout(weekStart: nil, cycleWeek: nil, cycleLabel: nil, referenceBellScheduleID: reference?.id,
                          rows: rows, columns: columns, cells: cells, emptySlots: emptySlots, unplaced: unplaced)
    }

    // MARK: Placement helpers

    private struct TimePair: Hashable, Comparable {
        var start: LocalTime
        var end: LocalTime
        static func < (lhs: TimePair, rhs: TimePair) -> Bool { (lhs.start, lhs.end) < (rhs.start, rhs.end) }
    }

    /// First and last row of `entry` in the reference schedule's rows, or `nil` when it matches no row.
    private static func rowSpan(of entry: ResolvedLesson, reference: BellScheduleIndex, dayIndex: BellScheduleIndex?,
                                rowByPosition: [Int: Int]) -> (first: Int, last: Int)? {
        let positions: (first: Int, last: Int)?
        if let periodID = entry.periodID {
            guard let first = referencePosition(of: periodID, reference: reference, dayIndex: dayIndex) else { return nil }
            let following = reference.lessonPositions.filter { $0 > first }.prefix(max(1, entry.periodSpan ?? 1) - 1)
            positions = (first, following.last ?? first)
        } else {
            // Time-slotted: lesson periods of the day's schedule (else the reference) that overlap the occurrence.
            let source = dayIndex ?? reference
            let overlapping = source.lessonPositions.filter { position in
                let period = source.periods[position]
                return period.start < entry.endTime && entry.startTime < period.end
            }
            let mapped = overlapping.compactMap { referencePosition(of: source.periods[$0].id, reference: reference, dayIndex: source) }
            guard let low = mapped.min(), let high = mapped.max() else { return nil }
            positions = (low, high)
        }
        guard let positions else { return nil }
        // With break rows hidden, a break position maps to the nearest lesson row inside the span.
        let firstRow = (positions.first...positions.last).lazy.compactMap { rowByPosition[$0] }.first
        let lastRow = (positions.first...positions.last).reversed().lazy.compactMap { rowByPosition[$0] }.first
        guard let firstRow, let lastRow else { return nil }
        return (firstRow, lastRow)
    }

    /// Position of `periodID` in the reference schedule: by ID, else by its ordinal (same kind) in `dayIndex`.
    private static func referencePosition(of periodID: Period.ID, reference: BellScheduleIndex,
                                          dayIndex: BellScheduleIndex?) -> Int? {
        if let position = reference.positionByID[periodID] { return position }
        guard let (kind, ordinal) = dayIndex?.ordinal(of: periodID) else { return nil }
        return reference.position(ofOrdinal: ordinal, kind: kind)
    }
}
