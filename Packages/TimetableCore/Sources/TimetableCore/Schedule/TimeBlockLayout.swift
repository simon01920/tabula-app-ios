import Foundation

/// Proportional (time-to-height) layout for the weekly time-block and daily views.
///
/// Positions are fractions of the visible time range (0 = top, 1 = bottom) computed on **wall-clock minutes**,
/// so a 45-minute lesson has the same height on a 23-hour DST day. Overlapping occurrences of one column are
/// placed side by side in lanes (`lane` of `laneCount`, per group of mutually overlapping occurrences).
public struct TimeBlockLayout: Hashable, Sendable, Codable {
    /// How the visible time range is chosen.
    public enum Bounds: Hashable, Sendable, Codable {
        /// From the earliest start to the latest end of the shown occurrences, widened outwards to multiples of
        /// `snapMinutes` (≤ 0: no widening); `fallbackStart…fallbackEnd` when nothing is shown.
        case automatic(snapMinutes: Int, fallbackStart: LocalTime, fallbackEnd: LocalTime)
        /// User-chosen bounds. Occurrences outside are listed in `outOfBounds`; partly visible ones are clipped.
        case fixed(start: LocalTime, end: LocalTime)

        /// Earliest/latest lesson snapped to full hours; 08:00–16:00 when empty.
        public static let standard = Bounds.automatic(snapMinutes: 60, fallbackStart: LocalTime(hour: 8, minute: 0)!,
                                                      fallbackEnd: LocalTime(hour: 16, minute: 0)!)
    }

    /// One column (a date).
    public struct Column: Hashable, Sendable, Codable {
        /// Index in `columns`.
        public var index: Int
        /// Date.
        public var date: LocalDate
        /// Resolved day key.
        public var dayKey: DayKey?
        /// User label of the cycle week/day, if any.
        public var cycleLabel: String?
        /// Whether regular lessons take place.
        public var isSchoolDay: Bool
        /// Break covering the date.
        public var activeBreakID: CalendarBreak.ID?
    }

    /// One positioned occurrence.
    public struct Block: Hashable, Sendable, Codable {
        /// Column index.
        public var column: Int
        /// The occurrence.
        public var entry: ResolvedLesson
        /// Top edge as a fraction of the visible range (0…1, clipped).
        public var top: Double
        /// Height as a fraction of the visible range (> 0, clipped).
        public var height: Double
        /// 0-based lane among overlapping occurrences.
        public var lane: Int
        /// Number of lanes of its overlap group (1 when it overlaps nothing).
        public var laneCount: Int
        /// The occurrence starts before the visible range.
        public var isClippedAtStart: Bool
        /// The occurrence ends after the visible range.
        public var isClippedAtEnd: Bool
        /// `true` when the occurrence is part of a conflict on its date.
        public var isInConflict: Bool
    }

    /// A full-hour gridline.
    public struct HourMark: Hashable, Sendable, Codable {
        /// Minutes since midnight (multiple of 60; 1440 = end of day).
        public var minuteOfDay: Int
        /// Position as a fraction of the visible range.
        public var position: Double
    }

    /// First visible minute of the day (0…1439).
    public var startMinute: Int
    /// End of the visible range in minutes (startMinute < endMinute ≤ 1440).
    public var endMinute: Int
    /// Columns, leading to trailing.
    public var columns: [Column]
    /// Blocks, ascending by (column, wall-clock order).
    public var blocks: [Block]
    /// Full hours inside the visible range.
    public var hourMarks: [HourMark]
    /// Occurrences entirely outside fixed bounds, in day order.
    public var outOfBounds: [ResolvedLesson]

    /// Fractional position of `minuteOfDay` (not clipped).
    public func position(ofMinute minuteOfDay: Int) -> Double {
        Double(minuteOfDay - startMinute) / Double(endMinute - startMinute)
    }

    /// Fractional position of `time` (not clipped).
    public func position(of time: LocalTime) -> Double { position(ofMinute: time.minuteOfDay) }

    // MARK: Factories

    /// The user's week containing `date` (week start = `resolver.context.firstWeekday`), with the columns of
    /// `weekdays` (default: the timetable's enabled days).
    public static func week(containing date: LocalDate, resolver: ScheduleResolver, options: ResolutionOptions = .actual,
                            weekdays: Set<Weekday>? = nil, bounds: Bounds = .standard,
                            includeCancelled: Bool = true) -> TimeBlockLayout {
        let start = resolver.rotation.startOfWeek(containing: date)
        let shown = weekdays ?? resolver.timetable.enabledDays
        let dates = (0..<7).map { start.adding(days: $0) }.filter { shown.contains($0.weekday) }
        return make(days: dates.map { resolver.day($0, options: options) }, bounds: bounds,
                    includeCancelled: includeCancelled)
    }

    /// Lays out `days` (one column each, in the given order).
    public static func make(days: [DaySchedule], bounds: Bounds = .standard, includeCancelled: Bool = true) -> TimeBlockLayout {
        let shownByDay = days.map { day in day.entries.filter { includeCancelled || $0.status != .cancelled } }
        let all = shownByDay.flatMap { $0 }

        var lower: Int, upper: Int
        switch bounds {
        case let .automatic(snap, fallbackStart, fallbackEnd):
            if let earliest = all.map(\.startTime.minuteOfDay).min(), let latest = all.map(\.endTime.minuteOfDay).max() {
                lower = earliest
                upper = latest
            } else {
                lower = fallbackStart.minuteOfDay
                upper = fallbackEnd.minuteOfDay
            }
            if snap > 0 {
                lower = (lower / snap) * snap
                upper = min(LocalTime.minutesPerDay, ((upper + snap - 1) / snap) * snap)
            }
        case let .fixed(start, end):
            lower = start.minuteOfDay
            upper = end.minuteOfDay
        }
        if upper <= lower { upper = min(LocalTime.minutesPerDay, lower + 60) }
        if upper <= lower { lower = upper - 60 } // lower was 23:xx

        let span = Double(upper - lower)
        var blocks: [Block] = []
        var outOfBounds: [ResolvedLesson] = []
        for (columnIndex, entries) in shownByDay.enumerated() {
            let conflicted = Set(days[columnIndex].conflicts.flatMap(\.occurrenceIDs))
            let visible = entries.filter { entry in
                let inside = entry.startTime.minuteOfDay < upper && entry.endTime.minuteOfDay > lower
                if !inside { outOfBounds.append(entry) }
                return inside
            }.sorted(by: ScheduleResolver.wallClockOrder)
            for (entry, lane, laneCount) in lanes(for: visible) {
                let start = max(entry.startTime.minuteOfDay, lower), end = min(entry.endTime.minuteOfDay, upper)
                blocks.append(Block(column: columnIndex, entry: entry, top: Double(start - lower) / span,
                                    height: Double(end - start) / span, lane: lane, laneCount: laneCount,
                                    isClippedAtStart: entry.startTime.minuteOfDay < lower,
                                    isClippedAtEnd: entry.endTime.minuteOfDay > upper,
                                    isInConflict: conflicted.contains(entry.id)))
            }
        }
        let firstHour = (lower + 59) / 60
        let hourMarks = stride(from: firstHour * 60, through: upper, by: 60).map {
            HourMark(minuteOfDay: $0, position: Double($0 - lower) / span)
        }
        let columns = days.enumerated().map { index, day in
            Column(index: index, date: day.date, dayKey: day.dayKey, cycleLabel: day.cycleLabel,
                   isSchoolDay: day.isSchoolDay, activeBreakID: day.activeBreakID)
        }
        return TimeBlockLayout(startMinute: lower, endMinute: upper, columns: columns, blocks: blocks,
                               hourMarks: hourMarks, outOfBounds: outOfBounds)
    }

    /// Greedy lane assignment per group of transitively overlapping occurrences (input in wall-clock order).
    static func lanes(for entries: [ResolvedLesson]) -> [(ResolvedLesson, Int, Int)] {
        var result: [(ResolvedLesson, Int, Int)] = []
        var group: [(ResolvedLesson, Int)] = []
        var laneEnds: [Int] = []
        var groupEnd = Int.min
        func flush() {
            let count = max(1, laneEnds.count)
            result += group.map { ($0.0, $0.1, count) }
            group.removeAll()
            laneEnds.removeAll()
        }
        for entry in entries {
            let start = entry.startTime.minuteOfDay, end = entry.endTime.minuteOfDay
            if !group.isEmpty && start >= groupEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= start }) {
                laneEnds[free] = end
                group.append((entry, free))
            } else {
                laneEnds.append(end)
                group.append((entry, laneEnds.count - 1))
            }
            groupEnd = group.count == 1 ? end : max(groupEnd, end)
        }
        flush()
        return result
    }
}
