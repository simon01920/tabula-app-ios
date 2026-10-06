import Foundation

/// A proleptic Gregorian calendar date without time or time zone ("2026-10-06").
///
/// All arithmetic is pure integer math (Howard Hinnant's days-from-civil), so `adding(days:)`,
/// `weekday` and `isoWeek` never touch `Calendar` and are identical on every platform.
/// Valid years are 1…9999. JSON: `"yyyy-MM-dd"`.
public struct LocalDate: Hashable, Comparable, Strideable, Sendable {
    /// Calendar year, 1…9999.
    public let year: Int
    /// Month, 1…12.
    public let month: Int
    /// Day of month, 1…`LocalDate.daysInMonth(year:month:)`.
    public let day: Int

    /// The supported year range (four-digit `yyyy` encoding).
    public static let validYears: ClosedRange<Int> = 1...9999

    /// Creates a date, or `nil` when the components do not form a valid date in 1…9999.
    public init?(year: Int, month: Int, day: Int) {
        guard Self.validYears.contains(year), (1...12).contains(month),
              day >= 1, day <= Self.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Creates the date `daysSinceEpoch` days after 1970-01-01, or `nil` outside years 1…9999.
    public init?(daysSinceEpoch days: Int) {
        guard (Self.minDaysSinceEpoch...Self.maxDaysSinceEpoch).contains(days) else { return nil }
        let (y, m, d) = Self.civil(fromDays: days)
        self.init(unchecked: y, m, d)
    }

    /// Parses exactly `yyyy-MM-dd` (ASCII digits, zero-padded); `nil` for anything else or an invalid date.
    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              let y = Self.parseDigits(bytes[0..<4]), let m = Self.parseDigits(bytes[5..<7]),
              let d = Self.parseDigits(bytes[8..<10]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    // MARK: Derived values

    /// Days since 1970-01-01 (negative before). Bijective with the date.
    public var daysSinceEpoch: Int { Self.days(fromCivil: year, month, day) }

    /// ISO weekday (Monday = 1 … Sunday = 7).
    public var weekday: Weekday {
        // 1970-01-01 was a Thursday (ISO 4).
        let index = Self.floorMod(daysSinceEpoch + 3, 7) // 0 = Monday
        return Weekday(rawValue: index + 1)!
    }

    /// Day of the year, 1…366.
    public var dayOfYear: Int {
        daysSinceEpoch - Self.days(fromCivil: year, 1, 1) + 1
    }

    /// The ISO-8601 week (weeks start Monday; week 1 contains the year's first Thursday).
    public var isoWeek: ISOWeek {
        let thursday = adding(days: Weekday.thursday.rawValue - weekday.rawValue)
        return ISOWeek(unchecked: thursday.year, (thursday.dayOfYear - 1) / 7 + 1)
    }

    /// `true` when `year` is a Gregorian leap year.
    public var isInLeapYear: Bool { Self.isLeapYear(year) }

    /// `"yyyy-MM-dd"`.
    public var isoString: String {
        "\(PaddedNumber.decimal(year, width: 4))-\(PaddedNumber.decimal(month, width: 2))-\(PaddedNumber.decimal(day, width: 2))"
    }

    // MARK: Arithmetic

    /// The earliest supported date, 0001-01-01.
    public static let earliest = LocalDate(unchecked: 1, 1, 1)
    /// The latest supported date, 9999-12-31.
    public static let latest = LocalDate(unchecked: 9999, 12, 31)

    /// The date `days` days later (earlier when negative), **saturating** at `earliest`/`latest` when the result
    /// would leave years 1…9999 (Stage 3: it used to trap, and hostile persisted values — a `daysBefore` offset
    /// of `Int.max`, a task due 9999-12-31, a reference week on 0001-01-01 — reached it). Real dates never get
    /// near the bounds; code that must know uses `addingIfValid(days:)`.
    public func adding(days: Int) -> LocalDate {
        addingIfValid(days: days) ?? (days < 0 ? .earliest : .latest)
    }

    /// The date `days` days later (earlier when negative), or `nil` when it would leave years 1…9999
    /// (overflow-safe for any `days`).
    public func addingIfValid(days: Int) -> LocalDate? {
        let (sum, overflow) = daysSinceEpoch.addingReportingOverflow(days)
        return overflow ? nil : LocalDate(daysSinceEpoch: sum)
    }

    /// Signed number of days from `self` to `other` (`other - self`).
    public func days(to other: LocalDate) -> Int { other.daysSinceEpoch - daysSinceEpoch }

    /// `Strideable`: days from `self` to `other`.
    public func distance(to other: LocalDate) -> Int { days(to: other) }

    /// `Strideable`: the date `n` days later.
    public func advanced(by n: Int) -> LocalDate { adding(days: n) }

    // MARK: Comparable / Equatable

    public static func == (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
        hasher.combine(day)
    }

    // MARK: Static helpers

    /// `true` for Gregorian leap years.
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Number of days in `month` of `year` (0 for an invalid month).
    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    static let minDaysSinceEpoch = days(fromCivil: 1, 1, 1)
    static let maxDaysSinceEpoch = days(fromCivil: 9999, 12, 31)

    /// Days since 1970-01-01 for a civil date (Hinnant, valid for the proleptic Gregorian calendar).
    static func days(fromCivil year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                   // [0, 399]
        let mp = (month + 9) % 12                                 // March = 0
        let doy = (153 * mp + 2) / 5 + day - 1                    // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy           // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// Civil date for days since 1970-01-01 (inverse of `days(fromCivil:)`).
    static func civil(fromDays days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097                                         // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365   // [0, 399]
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)                   // [0, 365]
        let mp = (5 * doy + 2) / 153                                        // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return (y, m, d)
    }

    /// Mathematical modulo (result in 0..<m for m > 0).
    static func floorMod(_ a: Int, _ m: Int) -> Int {
        let r = a % m
        return r < 0 ? r + m : r
    }

    private static func parseDigits(_ bytes: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for byte in bytes {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
        }
        return value
    }
}

extension LocalDate: CustomStringConvertible {
    /// `"yyyy-MM-dd"`.
    public var description: String { isoString }
}

extension LocalDate: Codable {
    /// Decodes `"yyyy-MM-dd"`; any other string is a `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = LocalDate(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid LocalDate '\(string)'")
        }
        self = value
    }

    /// Encodes `"yyyy-MM-dd"`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
