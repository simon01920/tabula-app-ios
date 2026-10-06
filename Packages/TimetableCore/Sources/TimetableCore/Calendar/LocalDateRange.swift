import Foundation

/// An **inclusive** range of calendar dates (`start…end`). JSON: `{"end":"yyyy-MM-dd","start":"yyyy-MM-dd"}`.
///
/// Construction never fails, so user data with `end < start` still decodes; such a range is
/// `isEmpty`, contains nothing, and `TabulaDatabase.validate()` reports it (`invalidDateRange`).
public struct LocalDateRange: Hashable, Sendable, Codable, CustomStringConvertible {
    /// First day (inclusive).
    public var start: LocalDate
    /// Last day (inclusive).
    public var end: LocalDate

    /// Creates a range. `end < start` is allowed and yields an empty range.
    public init(start: LocalDate, end: LocalDate) {
        self.start = start
        self.end = end
    }

    /// A single-day range.
    public init(day: LocalDate) {
        self.init(start: day, end: day)
    }

    /// `true` when `end < start`.
    public var isEmpty: Bool { end < start }

    /// Number of days in the range (0 when empty).
    public var dayCount: Int { isEmpty ? 0 : start.days(to: end) + 1 }

    /// `true` when `date` lies within `start…end`.
    public func contains(_ date: LocalDate) -> Bool { start <= date && date <= end }

    /// `true` when the two ranges share at least one day.
    public func overlaps(_ other: LocalDateRange) -> Bool {
        !isEmpty && !other.isEmpty && start <= other.end && other.start <= end
    }

    /// Every day in the range, ascending (lazy; empty when `end < start`).
    public var days: StrideThrough<LocalDate> { stride(from: start, through: end, by: 1) }

    /// `"start…end"`.
    public var description: String { "\(start)…\(end)" }
}
