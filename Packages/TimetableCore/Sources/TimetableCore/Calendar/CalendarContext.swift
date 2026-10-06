import Foundation

/// The explicit calendar environment for all date ↔ instant conversions: a time zone and a week start.
///
/// Core logic never reads `TimeZone.current`, `Calendar.current` or `Locale.current`; the app builds a
/// context (see `init(settings:deviceTimeZone:localeFirstWeekday:)`) and passes it in.
///
/// **DST policy** for wall-clock → instant (`date(_:_:)`):
/// - A *nonexistent* local time (spring-forward gap) is shifted forward by the gap length
///   (Europe/Bratislava 2026-03-29 02:30 → 03:30 CEST).
/// - An *ambiguous* local time (fall-back overlap) resolves to the **earlier** instant
///   (Europe/Bratislava 2026-10-25 02:30 → 02:30 CEST = 00:30 UTC).
public struct CalendarContext: Hashable, Sendable {
    /// Time zone used to interpret wall-clock times.
    public let timeZone: TimeZone
    /// First day of the week for week-based views and week cycles.
    public let firstWeekday: Weekday
    /// A Gregorian calendar configured with `timeZone` and `firstWeekday` (for UI formatting needs).
    public let calendar: Calendar

    /// Creates a context.
    public init(timeZone: TimeZone, firstWeekday: Weekday) {
        self.timeZone = timeZone
        self.firstWeekday = firstWeekday
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday.foundationWeekday
        self.calendar = calendar
    }

    /// Creates a context from a time-zone identifier, or `nil` if the identifier is unknown.
    public init?(timeZoneIdentifier: String, firstWeekday: Weekday) {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        self.init(timeZone: zone, firstWeekday: firstWeekday)
    }

    /// Builds the context the app should use: the settings' time-zone mode resolved against the device
    /// zone, and the settings' week-start override or else the locale's first weekday.
    public init(settings: AppSettings, deviceTimeZone: TimeZone, localeFirstWeekday: Weekday) {
        self.init(timeZone: settings.timeZoneMode.resolve(deviceTimeZone: deviceTimeZone),
                  firstWeekday: settings.weekStartOverride ?? localeFirstWeekday)
    }

    // MARK: Wall clock → instant

    /// How a wall-clock date-time maps to instants in this time zone.
    public enum Resolution: Hashable, Sendable {
        /// Exactly one instant.
        case unique(Date)
        /// The local time does not exist (DST gap). `shifted` is the policy result (moved forward by
        /// `gapSeconds`).
        case skipped(shifted: Date, gapSeconds: Int)
        /// The local time occurs twice (DST overlap); `earlier < later`.
        case repeated(earlier: Date, later: Date)

        /// The instant chosen by the DST policy.
        public var date: Date {
            switch self {
            case .unique(let date): return date
            case .skipped(let shifted, _): return shifted
            case .repeated(let earlier, _): return earlier
            }
        }
    }

    /// The instant for wall-clock `time` on `date`, applying the DST policy (gap → forward, overlap → earlier).
    public func date(_ date: LocalDate, _ time: LocalTime) -> Date {
        resolve(date, time).date
    }

    /// Classifies how `date` `time` maps to instants (unique, skipped by a gap, or repeated in an overlap).
    public func resolve(_ date: LocalDate, _ time: LocalTime) -> Resolution {
        resolve(localSeconds: Int64(date.daysSinceEpoch) * 86_400 + Int64(time.minuteOfDay) * 60)
    }

    /// `localSeconds` = wall-clock seconds since 1970-01-01T00:00 *as if* the zone were UTC.
    /// `Int64` throughout: `Int` is 32-bit on arm64_32 Apple Watch hardware and overflows after 2038.
    private func resolve(localSeconds: Int64) -> Resolution {
        // Offsets on either side of any transition near this local time. Real-world zones never have two
        // transitions within ±2 days, and no offset change exceeds 26 h, so this window brackets it.
        let window: Int64 = 2 * 86_400
        let offsetBefore = offset(atUTCSeconds: localSeconds - window)
        let offsetAfter = offset(atUTCSeconds: localSeconds + window)
        let offsetHere = offset(atUTCSeconds: localSeconds)
        var instants: [Int64] = []
        for candidate in Set([offsetBefore, offsetAfter, offsetHere]) {
            let instant = localSeconds - candidate
            if offset(atUTCSeconds: instant) == candidate { instants.append(instant) }
        }
        instants.sort()
        switch instants.count {
        case 0:
            // Gap: interpret with the pre-transition offset → lands after the transition, shifted forward.
            let shifted = localSeconds - offsetBefore
            return .skipped(shifted: Self.date(utcSeconds: shifted), gapSeconds: Int(offsetAfter - offsetBefore))
        case 1:
            return .unique(Self.date(utcSeconds: instants[0]))
        default:
            return .repeated(earlier: Self.date(utcSeconds: instants.first!), later: Self.date(utcSeconds: instants.last!))
        }
    }

    private func offset(atUTCSeconds seconds: Int64) -> Int64 {
        Int64(timeZone.secondsFromGMT(for: Self.date(utcSeconds: seconds)))
    }

    private static func date(utcSeconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(utcSeconds))
    }

    // MARK: Instant → wall clock

    /// The wall-clock date and time (minute precision; seconds are truncated) of `instant` in this zone.
    public func local(from instant: Date) -> LocalDateTime {
        let localSeconds = Self.floorSeconds(instant) + Int64(timeZone.secondsFromGMT(for: instant))
        let days = Self.floorDiv(localSeconds, 86_400)
        let secondOfDay = localSeconds - days * 86_400
        guard let date = LocalDate(daysSinceEpoch: Int(days)) else {
            preconditionFailure("CalendarContext.local(from:) outside years 1…9999")
        }
        return LocalDateTime(date: date, time: LocalTime(unchecked: Int(secondOfDay / 60)))
    }

    /// The calendar date of `instant` in this zone.
    public func localDate(of instant: Date) -> LocalDate { local(from: instant).date }

    // MARK: Days and weeks

    /// The first instant of `date` (local midnight, or the first existing minute if midnight is skipped).
    public func startOfDay(_ date: LocalDate) -> Date { self.date(date, .midnight) }

    /// The half-open interval `[startOfDay(date), startOfDay(date + 1))`; 23 h or 25 h on DST days.
    public func dayInterval(_ date: LocalDate) -> DateInterval {
        let start = startOfDay(date)
        return DateInterval(start: start, end: startOfDay(date.adding(days: 1)))
    }

    /// Length of `date` in seconds (86 400, or e.g. 82 800 / 90 000 on DST days).
    public func secondsInDay(_ date: LocalDate) -> Int {
        Int(dayInterval(date).duration.rounded())
    }

    /// The first day of the week containing `date`, honouring `firstWeekday`. Pure arithmetic.
    public func startOfWeek(containing date: LocalDate) -> LocalDate {
        let delta = LocalDate.floorMod(date.weekday.rawValue - firstWeekday.rawValue, 7)
        return date.adding(days: -delta)
    }

    /// The seven days of the week containing `date`, starting at `firstWeekday`.
    public func week(containing date: LocalDate) -> [LocalDate] {
        let start = startOfWeek(containing: date)
        return (0..<7).map { start.adding(days: $0) }
    }

    // MARK: Hashable (Calendar is derived from the stored fields)

    public static func == (lhs: CalendarContext, rhs: CalendarContext) -> Bool {
        lhs.timeZone.identifier == rhs.timeZone.identifier && lhs.firstWeekday == rhs.firstWeekday
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(timeZone.identifier)
        hasher.combine(firstWeekday)
    }

    // MARK: Integer helpers

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func floorSeconds(_ instant: Date) -> Int64 {
        Int64(instant.timeIntervalSince1970.rounded(.down))
    }
}
