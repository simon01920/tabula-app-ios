import Foundation

/// Day of the week with **ISO numbering**: Monday = 1 … Sunday = 7. JSON: the integer 1…7.
///
/// Foundation's `Calendar` numbers Sunday = 1 … Saturday = 7; convert with `foundationWeekday` /
/// `init?(foundationWeekday:)` and never mix the two numberings.
public enum Weekday: Int, CaseIterable, Codable, Comparable, Sendable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    /// Monday–Friday.
    public static let workweek: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// Foundation numbering (Sunday = 1 … Saturday = 7).
    public var foundationWeekday: Int { rawValue % 7 + 1 }

    /// Creates a weekday from Foundation numbering (Sunday = 1 … Saturday = 7).
    public init?(foundationWeekday: Int) {
        guard (1...7).contains(foundationWeekday) else { return nil }
        self.init(rawValue: foundationWeekday == 1 ? 7 : foundationWeekday - 1)
    }

    /// The weekday `days` days later (earlier when negative).
    public func adding(_ days: Int) -> Weekday {
        Weekday(rawValue: LocalDate.floorMod(rawValue - 1 + days, 7) + 1)!
    }

    /// All seven weekdays in order, starting with `first` (e.g. Sunday … Saturday for US locales).
    public static func week(startingAt first: Weekday) -> [Weekday] {
        (0..<7).map { first.adding($0) }
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}
