import Foundation

// Rotation data types. These are persisted data only; the resolver that maps a date to a `DayKey`
// and cycle week is Stage 2B (`Schedule/RotationResolver`).

/// How a timetable's schedule changes between weeks or days.
///
/// JSON: `{"kind":"none"}`, `{"kind":"weekCycle","weekCycle":{…}}` or `{"kind":"dayCycle","dayCycle":{…}}`.
/// Closed union: a new kind needs a schema version bump.
public enum RotationScheme: Hashable, Sendable {
    /// The same week every week.
    case none
    /// A cycle of 2…6 weeks (A/B weeks, odd/even weeks, N-week cycles). Lessons pick weeks via
    /// `LessonOccurrenceRule.cycleWeeks`.
    case weekCycle(WeekCycle)
    /// A cycle of 2…10 school days (Day A/B, "Day 1…6") that advances only on school days.
    case dayCycle(DayCycle)
}

/// A repeating cycle of weeks. Cycle weeks are numbered 1…`length`.
public struct WeekCycle: Hashable, Sendable, Codable {
    /// Supported cycle lengths.
    public static let validLengths: ClosedRange<Int> = 2...6

    /// Number of weeks in the cycle, 2…6.
    public var length: Int
    /// How the cycle is aligned to the calendar.
    public var anchor: WeekCycleAnchor
    /// Optional user labels per cycle week (`labels[0]` = week 1). `nil` → the UI derives "A/B" or "Week n".
    /// When present it must contain exactly `length` entries.
    public var labels: [String]?

    /// Creates a week cycle.
    public init(length: Int, anchor: WeekCycleAnchor, labels: [String]? = nil) {
        self.length = length
        self.anchor = anchor
        self.labels = labels
    }
}

/// How a week cycle is aligned to the calendar.
///
/// JSON: `{"kind":"isoWeekParity","policy":"strict","offset":0}` or
/// `{"kind":"referenceWeek","date":"2026-09-01","cycleWeek":1}`.
public enum WeekCycleAnchor: Hashable, Sendable {
    /// Derive the cycle week from the ISO week number (odd/even weeks for `length == 2`).
    /// `offset` (default 0) shifts the mapping, e.g. to swap A and B. How ISO 53-week years are handled is
    /// selected by `policy`; the mapping function itself is Stage 2B (PHASE1_PLAN §4, §10).
    case isoWeekParity(policy: ISOWeekParityPolicy, offset: Int)
    /// The week containing `date` (weeks start on the user's first weekday) is cycle week `cycleWeek`
    /// (1-based); weeks count continuously from there in both directions. Typical: "1 September = week A".
    case referenceWeek(date: LocalDate, cycleWeek: Int)
}

/// What happens to ISO-week parity across a 53-week ISO year (2026, 2032 …).
public enum ISOWeekParityPolicy: String, CaseIterable, Codable, Sendable {
    /// Use the ISO week number literally: W53 and the following W01 are both odd, so the cycle repeats a week.
    case strict
    /// Keep alternating across the year boundary as if weeks were counted continuously (no repeated week).
    case continuous
}

/// A repeating cycle of school days. Cycle days are numbered 1…`length`.
public struct DayCycle: Hashable, Sendable {
    /// Supported cycle lengths.
    public static let validLengths: ClosedRange<Int> = 2...10

    /// Number of days in the cycle, 2…10.
    public var length: Int
    /// A school day whose cycle day is known.
    public var anchorDate: LocalDate
    /// Cycle day (1-based) of `anchorDate`.
    public var anchorIndex: Int
    /// Weekdays on which the cycle advances (usually Monday–Friday).
    public var schoolDays: Set<Weekday>
    /// When `true`, days inside a `CalendarBreak` do not advance the cycle.
    public var skipsBreaks: Bool
    /// Optional user labels per cycle day (`labels[0]` = day 1); exactly `length` entries when present.
    public var labels: [String]?

    /// Creates a day cycle.
    public init(length: Int, anchorDate: LocalDate, anchorIndex: Int = 1,
                schoolDays: Set<Weekday> = Weekday.workweek, skipsBreaks: Bool = true, labels: [String]? = nil) {
        self.length = length
        self.anchorDate = anchorDate
        self.anchorIndex = anchorIndex
        self.schoolDays = schoolDays
        self.skipsBreaks = skipsBreaks
        self.labels = labels
    }
}

extension DayCycle: Codable {
    private enum CodingKeys: String, CodingKey {
        case length, anchorDate, anchorIndex, schoolDays, skipsBreaks, labels
    }

    /// Encodes with `schoolDays` as an ascending array.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(length, forKey: .length)
        try container.encode(anchorDate, forKey: .anchorDate)
        try container.encode(anchorIndex, forKey: .anchorIndex)
        try container.encodeSorted(schoolDays, forKey: .schoolDays)
        try container.encode(skipsBreaks, forKey: .skipsBreaks)
        try container.encodeIfPresent(labels, forKey: .labels)
    }
}

/// Which day of the schedule a lesson belongs to.
///
/// JSON: `{"kind":"weekday","weekday":1}` (ISO numbering) or `{"kind":"cycleDay","index":3}` (1-based).
public enum DayKey: Hashable, Sendable, Comparable {
    /// A weekday (timetables without rotation or with a week cycle).
    case weekday(Weekday)
    /// A day of a `DayCycle`, 1-based.
    case cycleDay(Int)

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        switch (lhs, rhs) {
        case let (.weekday(a), .weekday(b)): return a < b
        case let (.cycleDay(a), .cycleDay(b)): return a < b
        case (.weekday, .cycleDay): return true
        case (.cycleDay, .weekday): return false
        }
    }
}

/// When a lesson occurs: on a day key, optionally only in some weeks of a week cycle.
///
/// JSON: `{"day":{…DayKey…},"cycleWeeks":[1,3]}`; `cycleWeeks` is omitted for "every week".
public struct LessonOccurrenceRule: Hashable, Sendable {
    /// The day of the schedule.
    public var day: DayKey
    /// 1-based cycle weeks in which the lesson occurs; `nil` = every week. Only meaningful with a week cycle.
    public var cycleWeeks: Set<Int>?

    /// Creates an occurrence rule.
    public init(day: DayKey, cycleWeeks: Set<Int>? = nil) {
        self.day = day
        self.cycleWeeks = cycleWeeks
    }

    /// Every week on `weekday`.
    public static func every(_ weekday: Weekday) -> LessonOccurrenceRule {
        LessonOccurrenceRule(day: .weekday(weekday))
    }
}

extension LessonOccurrenceRule: Codable {
    private enum CodingKeys: String, CodingKey { case day, cycleWeeks }

    /// Encodes with `cycleWeeks` as an ascending array (omitted when `nil`).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encodeSortedIfPresent(cycleWeeks, forKey: .cycleWeeks)
    }
}

// MARK: - Codable for the unions

extension RotationScheme: Codable {
    private enum CodingKeys: String, CodingKey { case kind, weekCycle, dayCycle }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "none": self = .none
        case "weekCycle": self = .weekCycle(try container.decode(WeekCycle.self, forKey: .weekCycle))
        case "dayCycle": self = .dayCycle(try container.decode(DayCycle.self, forKey: .dayCycle))
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "RotationScheme")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .kind)
        case .weekCycle(let cycle):
            try container.encode("weekCycle", forKey: .kind)
            try container.encode(cycle, forKey: .weekCycle)
        case .dayCycle(let cycle):
            try container.encode("dayCycle", forKey: .kind)
            try container.encode(cycle, forKey: .dayCycle)
        }
    }
}

extension WeekCycleAnchor: Codable {
    private enum CodingKeys: String, CodingKey { case kind, policy, offset, date, cycleWeek }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "isoWeekParity":
            self = .isoWeekParity(policy: try container.decode(ISOWeekParityPolicy.self, forKey: .policy),
                                  offset: try container.decodeIfPresent(Int.self, forKey: .offset) ?? 0)
        case "referenceWeek":
            self = .referenceWeek(date: try container.decode(LocalDate.self, forKey: .date),
                                  cycleWeek: try container.decode(Int.self, forKey: .cycleWeek))
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "WeekCycleAnchor")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .isoWeekParity(policy, offset):
            try container.encode("isoWeekParity", forKey: .kind)
            try container.encode(policy, forKey: .policy)
            try container.encode(offset, forKey: .offset)
        case let .referenceWeek(date, cycleWeek):
            try container.encode("referenceWeek", forKey: .kind)
            try container.encode(date, forKey: .date)
            try container.encode(cycleWeek, forKey: .cycleWeek)
        }
    }
}

extension DayKey: Codable {
    private enum CodingKeys: String, CodingKey { case kind, weekday, index }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "weekday": self = .weekday(try container.decode(Weekday.self, forKey: .weekday))
        case "cycleDay": self = .cycleDay(try container.decode(Int.self, forKey: .index))
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "DayKey")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .weekday(let weekday):
            try container.encode("weekday", forKey: .kind)
            try container.encode(weekday, forKey: .weekday)
        case .cycleDay(let index):
            try container.encode("cycleDay", forKey: .kind)
            try container.encode(index, forKey: .index)
        }
    }
}
