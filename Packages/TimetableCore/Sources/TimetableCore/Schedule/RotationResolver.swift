import Foundation

/// Maps calendar dates to rotation positions: the cycle week of a week cycle, the cycle day of a day cycle,
/// and the rotation part of a date's `DayKey`.
///
/// Pure value type; every query is O(1) for week cycles and O(number of breaks) for day cycles (closed-form
/// week arithmetic plus a correction per break range — never a loop over the days since the anchor).
/// Overrides never move the rotation: a `followDay` changes which lessons a date runs, not the cycle.
///
/// **Week boundaries.** `firstWeekday` is the timetable's persisted `Timetable.rotationWeekStart` — never the
/// device's or user's current week start, so a locale or settings change never moves an A/B week.
/// `referenceWeek` counts whole weeks that start on it. A school with Sunday–Thursday weeks must therefore use a
/// Sunday (or Saturday) rotation week start: with a Monday one its Sunday would be counted with the *previous*
/// week and get the previous cycle week. `isoWeekParity` uses the ISO week of the middle day of the rotation
/// week (`WeekParity.representativeISOWeek`), so all days of a rotation week share one cycle week.
public struct RotationResolver: Hashable, Sendable {
    /// The timetable's rotation.
    public let scheme: RotationScheme
    /// First day of a rotation week (`Timetable.rotationWeekStart`; never the device week start).
    public let firstWeekday: Weekday
    /// Merged, ascending, non-overlapping date ranges that pause a day cycle (empty unless the scheme is a
    /// day cycle with `skipsBreaks`).
    public let pausingRanges: [LocalDateRange]

    /// A resolver for `timetable`'s rotation, counted in weeks that start on `timetable.rotationWeekStart`.
    public init(timetable: Timetable, breaks: [LocalDateRange] = []) {
        self.init(scheme: timetable.rotation, firstWeekday: timetable.rotationWeekStart, breaks: breaks)
    }

    /// Creates a resolver. `breaks` are the date ranges of the calendar breaks that apply to the timetable;
    /// they only matter for a day cycle with `skipsBreaks == true`. Empty ranges are ignored.
    public init(scheme: RotationScheme, firstWeekday: Weekday, breaks: [LocalDateRange] = []) {
        self.scheme = scheme
        self.firstWeekday = firstWeekday
        if case .dayCycle(let cycle) = scheme, cycle.skipsBreaks {
            self.pausingRanges = Self.merged(breaks)
        } else {
            self.pausingRanges = []
        }
    }

    // MARK: Week cycles

    /// The 1-based cycle week of `date`, or `nil` unless the scheme is a week cycle.
    public func cycleWeek(on date: LocalDate) -> Int? {
        guard case .weekCycle(let cycle) = scheme else { return nil }
        let length = max(1, cycle.length)
        switch cycle.anchor {
        case let .isoWeekParity(policy, offset):
            let week = WeekParity.representativeISOWeek(containing: date, firstWeekday: firstWeekday)
            return WeekParity.cycleWeek(for: week, policy: policy, offset: offset, length: length)
        case let .referenceWeek(referenceDate, referenceCycleWeek):
            let weeks = startOfWeek(containing: referenceDate).days(to: startOfWeek(containing: date)) / 7
            // Persisted values are reduced first, so hostile ones (`Int.min`) cannot overflow the sum.
            return LocalDate.floorMod(LocalDate.floorMod(referenceCycleWeek, length) - 1 + weeks, length) + 1
        }
    }

    /// The first day of the user's week containing `date` (honours `firstWeekday`).
    public func startOfWeek(containing date: LocalDate) -> LocalDate {
        date.adding(days: -LocalDate.floorMod(date.weekday.rawValue - firstWeekday.rawValue, 7))
    }

    /// The start of the first week on or after the week containing `date` whose cycle week is `cycleWeek`,
    /// or `nil` when the scheme is not a week cycle or `cycleWeek` is outside 1…length.
    /// Used by week grids to jump to "week B".
    public func startOfWeek(withCycleWeek cycleWeek: Int, onOrAfter date: LocalDate) -> LocalDate? {
        guard case .weekCycle(let cycle) = scheme, (1...max(1, cycle.length)).contains(cycleWeek) else { return nil }
        let first = startOfWeek(containing: date)
        // Every cycle week appears within length + 1 consecutive weeks, even across a strict W53 → W01 repeat.
        // Bounded for hostile lengths (validation reports lengths outside 2…6).
        for index in 0...(2 * min(max(1, cycle.length), 1_000) + 2) {
            let start = first.adding(days: 7 * index)
            if self.cycleWeek(on: start) == cycleWeek { return start }
        }
        return nil
    }

    /// The user label of `cycleWeek` (`labels[cycleWeek - 1]`), if the week cycle defines one.
    public func label(forCycleWeek cycleWeek: Int) -> String? {
        guard case .weekCycle(let cycle) = scheme, let labels = cycle.labels, labels.indices.contains(cycleWeek - 1)
        else { return nil }
        return labels[cycleWeek - 1]
    }

    // MARK: Day cycles

    /// `true` when `date` advances a day cycle: its weekday is one of the cycle's `schoolDays` and, with
    /// `skipsBreaks`, it is not inside a break. Always `false` for other schemes.
    public func advancesCycle(on date: LocalDate) -> Bool {
        guard case .dayCycle(let cycle) = scheme, cycle.length >= 1 else { return false }
        return cycle.schoolDays.contains(date.weekday) && !isPaused(date)
    }

    /// The 1-based cycle day of `date`, or `nil` when the scheme is not a day cycle or `date` does not
    /// advance it (weekend, break with `skipsBreaks`).
    ///
    /// The anchor's index belongs to the first counted day on or after `anchorDate` (so an anchor that falls
    /// on a weekend or holiday still works); counting runs in both directions.
    public func cycleDay(on date: LocalDate) -> Int? {
        guard case .dayCycle(let cycle) = scheme, cycle.length >= 1, advancesCycle(on: date) else { return nil }
        let steps: Int
        if date >= cycle.anchorDate {
            steps = countedDays(from: cycle.anchorDate, through: date) - 1
        } else {
            steps = -countedDays(from: date, through: cycle.anchorDate.adding(days: -1))
        }
        // `anchorIndex` is persisted data: reduce it first so that a hostile value cannot overflow the sum.
        return LocalDate.floorMod(LocalDate.floorMod(cycle.anchorIndex, cycle.length) - 1 + steps, cycle.length) + 1
    }

    /// The user label of `cycleDay` (`labels[cycleDay - 1]`), if the day cycle defines one.
    public func label(forCycleDay cycleDay: Int) -> String? {
        guard case .dayCycle(let cycle) = scheme, let labels = cycle.labels, labels.indices.contains(cycleDay - 1)
        else { return nil }
        return labels[cycleDay - 1]
    }

    /// Number of days in `start…end` (inclusive) that advance the day cycle. 0 when `end < start` or the
    /// scheme is not a day cycle. O(number of pausing ranges).
    public func countedDays(from start: LocalDate, through end: LocalDate) -> Int {
        guard case .dayCycle(let cycle) = scheme, start <= end else { return 0 }
        var count = Self.weekdayCount(from: start, through: end, in: cycle.schoolDays)
        for range in pausingRanges {
            if range.start > end { break } // ascending: nothing later can intersect
            let lower = max(range.start, start), upper = min(range.end, end)
            if lower <= upper { count -= Self.weekdayCount(from: lower, through: upper, in: cycle.schoolDays) }
        }
        return count
    }

    /// The first date on or after `date` whose cycle day is `cycleDay`, searching at most `searchDays` days.
    public func firstDate(withCycleDay cycleDay: Int, onOrAfter date: LocalDate, searchDays: Int = 400) -> LocalDate? {
        guard case .dayCycle = scheme else { return nil }
        for offset in 0..<max(0, searchDays) {
            let candidate = date.adding(days: offset)
            if self.cycleDay(on: candidate) == cycleDay { return candidate }
        }
        return nil
    }

    /// The rotation part of a date's day key: `.weekday(date.weekday)` without rotation or with a week cycle,
    /// `.cycleDay(n)` for a day cycle (`nil` when the date does not advance the cycle). Enabled weekdays,
    /// breaks and overrides are applied by `ScheduleResolver`.
    public func dayKey(on date: LocalDate) -> DayKey? {
        switch scheme {
        case .none, .weekCycle: return .weekday(date.weekday)
        case .dayCycle: return cycleDay(on: date).map(DayKey.cycleDay)
        }
    }

    /// The user label of the date's cycle position (week label for week cycles, day label for day cycles).
    public func label(for dayKey: DayKey?, cycleWeek: Int?) -> String? {
        switch scheme {
        case .none: return nil
        case .weekCycle: return cycleWeek.flatMap(label(forCycleWeek:))
        case .dayCycle:
            if case .cycleDay(let index)? = dayKey { return label(forCycleDay: index) }
            return nil
        }
    }

    // MARK: Helpers

    private func isPaused(_ date: LocalDate) -> Bool {
        // Binary search over the merged ascending ranges.
        var low = 0, high = pausingRanges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = pausingRanges[mid]
            if date < range.start { high = mid - 1 } else if date > range.end { low = mid + 1 } else { return true }
        }
        return false
    }

    /// Number of days in `start…end` (inclusive) whose weekday is in `days`: whole weeks in closed form plus at
    /// most six remainder days.
    static func weekdayCount(from start: LocalDate, through end: LocalDate, in days: Set<Weekday>) -> Int {
        let total = start.days(to: end) + 1
        guard total > 0, !days.isEmpty else { return 0 }
        var count = (total / 7) * days.count
        var weekday = start.weekday // the remainder starts on the same weekday as `start`
        for _ in 0..<(total % 7) {
            if days.contains(weekday) { count += 1 }
            weekday = weekday.adding(1)
        }
        return count
    }

    /// Sorts and merges overlapping or adjacent ranges; drops empty ones.
    static func merged(_ ranges: [LocalDateRange]) -> [LocalDateRange] {
        let sorted = ranges.filter { !$0.isEmpty }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [LocalDateRange] = []
        for range in sorted {
            if let last = result.last, range.start.daysSinceEpoch <= last.end.daysSinceEpoch + 1 {
                result[result.count - 1].end = max(last.end, range.end)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
