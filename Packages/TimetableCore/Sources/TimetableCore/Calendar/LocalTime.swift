import Foundation

/// A wall-clock time of day with minute precision, 00:00…23:59. JSON: `"HH:mm"` (24-hour).
///
/// School times are wall-clock times: the instant they denote depends on the date and the
/// `CalendarContext` (see `CalendarContext.date(_:_:)` for the DST policy). Lessons never span
/// midnight; there is no 24:00.
public struct LocalTime: Hashable, Comparable, Sendable {
    /// Minutes since local midnight, 0…1439.
    public let minuteOfDay: Int

    /// Number of minutes in a (nominal) day.
    public static let minutesPerDay = 1440

    /// 00:00.
    public static let midnight = LocalTime(unchecked: 0)

    /// Creates a time from minutes since midnight, or `nil` outside 0…1439.
    public init?(minuteOfDay: Int) {
        guard (0..<Self.minutesPerDay).contains(minuteOfDay) else { return nil }
        self.minuteOfDay = minuteOfDay
    }

    /// Creates a time, or `nil` unless `hour` is 0…23 and `minute` is 0…59.
    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.minuteOfDay = hour * 60 + minute
    }

    /// Parses exactly `HH:mm` (two ASCII digits each, 24-hour); `nil` otherwise.
    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 5, bytes[2] == UInt8(ascii: ":"),
              let h = Self.twoDigits(bytes[0], bytes[1]), let m = Self.twoDigits(bytes[3], bytes[4]) else { return nil }
        self.init(hour: h, minute: m)
    }

    init(unchecked minuteOfDay: Int) {
        self.minuteOfDay = minuteOfDay
    }

    /// Hour, 0…23.
    public var hour: Int { minuteOfDay / 60 }

    /// Minute, 0…59.
    public var minute: Int { minuteOfDay % 60 }

    /// The time `minutes` later on the same day, or `nil` if that crosses midnight in either direction.
    public func adding(minutes: Int) -> LocalTime? {
        LocalTime(minuteOfDay: minuteOfDay + minutes)
    }

    /// Signed minutes from `self` to `other` on the same day (`other - self`).
    public func minutes(to other: LocalTime) -> Int { other.minuteOfDay - minuteOfDay }

    public static func < (lhs: LocalTime, rhs: LocalTime) -> Bool { lhs.minuteOfDay < rhs.minuteOfDay }

    /// `"HH:mm"`.
    public var isoString: String {
        "\(PaddedNumber.decimal(hour, width: 2)):\(PaddedNumber.decimal(minute, width: 2))"
    }

    private static func twoDigits(_ a: UInt8, _ b: UInt8) -> Int? {
        let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
        guard (zero...nine).contains(a), (zero...nine).contains(b) else { return nil }
        return Int(a - zero) * 10 + Int(b - zero)
    }
}

extension LocalTime: CustomStringConvertible {
    /// `"HH:mm"`.
    public var description: String { isoString }
}

extension LocalTime: Codable {
    /// Decodes `"HH:mm"`; anything else is a `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = LocalTime(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid LocalTime '\(string)'")
        }
        self = value
    }

    /// Encodes `"HH:mm"`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}

/// A wall-clock date and time (minute precision) without a time zone.
public struct LocalDateTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The calendar date.
    public var date: LocalDate
    /// The time of day.
    public var time: LocalTime

    /// Creates a local date-time.
    public init(date: LocalDate, time: LocalTime) {
        self.date = date
        self.time = time
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        (lhs.date, lhs.time) < (rhs.date, rhs.time)
    }

    /// `"yyyy-MM-ddTHH:mm"`.
    public var description: String { "\(date)T\(time)" }
}
