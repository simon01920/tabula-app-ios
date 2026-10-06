import Foundation

/// An ISO-8601 week: weeks start on Monday and week 1 is the week containing the year's first Thursday.
///
/// The ISO `year` can differ from the calendar year of a date near New Year (2027-01-01 is in 2026-W53).
/// Years have 52 or 53 weeks; 2020, 2026, 2032 and 2037 have 53 (relevant for odd/even week rotations).
public struct ISOWeek: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// ISO week-based year.
    public let year: Int
    /// Week number, 1…`ISOWeek.weeksInYear(year)`.
    public let week: Int

    /// Creates a week, or `nil` if `week` is outside 1…`weeksInYear(year)` or the year is unsupported.
    public init?(year: Int, week: Int) {
        guard LocalDate.validYears.contains(year), week >= 1, week <= Self.weeksInYear(year) else { return nil }
        self.year = year
        self.week = week
    }

    init(unchecked year: Int, _ week: Int) {
        self.year = year
        self.week = week
    }

    /// Number of ISO weeks (52 or 53) in the ISO year `year`. 28 December always lies in the last week.
    public static func weeksInYear(_ year: Int) -> Int {
        guard let december28 = LocalDate(year: year, month: 12, day: 28) else { return 52 }
        return december28.isoWeek.week
    }

    /// The Monday that starts this week.
    public var monday: LocalDate {
        // 4 January is always in week 1.
        let january4 = LocalDate(year: year, month: 1, day: 4)!
        let mondayOfWeek1 = january4.adding(days: 1 - january4.weekday.rawValue)
        return mondayOfWeek1.adding(days: (week - 1) * 7)
    }

    /// The week `weeks` weeks later (earlier when negative), crossing ISO years as needed.
    public func adding(weeks: Int) -> ISOWeek {
        monday.adding(days: weeks * 7).isoWeek
    }

    public static func < (lhs: ISOWeek, rhs: ISOWeek) -> Bool {
        (lhs.year, lhs.week) < (rhs.year, rhs.week)
    }

    /// `"yyyy-Www"`, e.g. `"2026-W53"`.
    public var description: String {
        "\(PaddedNumber.decimal(year, width: 4))-W\(PaddedNumber.decimal(week, width: 2))"
    }
}
