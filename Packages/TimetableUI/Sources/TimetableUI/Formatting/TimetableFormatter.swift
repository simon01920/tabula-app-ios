// Locale-aware formatting of times and dates with an explicit locale, calendar and time zone (CLAUDE.md "Dates:
// explicit Calendar/TimeZone everywhere"), honouring the 12/24 h setting (`AppSettings.hourCycle`).
// Pure Foundation (Date.FormatStyle), Linux-tested with fixed locales and zones.
//
// Wall-clock values (`LocalTime`, `LocalDate`) are formatted in UTC from a synthetic instant, so DST never shifts
// them; instants (`Date`) are formatted in the calendar context's zone.
//
// VERIFIED on Linux (swift-foundation, 2026-10-09): `Locale.Components.hourCycle` drives Date.FormatStyle
// (en_US + h23 → "13:05", sk_SK + h12 → "1:05 PM"). Same on iOS = device checklist item.
import Foundation
import TimetableCore

/// Formats times and dates for display.
public struct TimetableFormatter: Sendable {
    /// Date styles used across the app.
    public enum DateStyle: Sendable {
        /// "13. 10. 2026" / "10/13/2026".
        case numeric
        /// "13. okt 2026" / "Oct 13, 2026".
        case abbreviated
        /// "utorok 13. októbra 2026" / "Tuesday, October 13, 2026".
        case full
        /// "ut 13. 10." / "Tue, Oct 13": weekday + day + month, no year.
        case weekdayDayMonth
        /// "Thu 22" / "cs 22.": abbreviated weekday + day of month (narrow Lock Screen lines).
        case weekdayDay
        /// "13. 10." / "Oct 13": day + month.
        case dayMonth
    }

    /// Weekday name widths.
    public enum WeekdayWidth: Sendable {
        /// "utorok" / "Tuesday".
        case wide
        /// "ut" / "Tue".
        case abbreviated
        /// "U" / "T".
        case narrow
    }

    /// The locale with the hour-cycle preference applied.
    public let locale: Locale
    /// Zone used for instants.
    public let timeZone: TimeZone
    private let utc: TimeZone
    private let calendar: Calendar
    private let utcCalendar: Calendar

    /// Creates a formatter. `hourCycle` `.auto` (or unknown) follows `locale`; `.h12`/`.h24` force the clock.
    public init(locale: Locale, hourCycle: HourCycle, timeZone: TimeZone) {
        self.locale = Self.applying(hourCycle, to: locale)
        self.timeZone = timeZone
        utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = self.locale
        calendar.timeZone = timeZone
        self.calendar = calendar
        var utcCalendar = calendar
        utcCalendar.timeZone = utc
        self.utcCalendar = utcCalendar
    }

    /// Convenience: the formatter for `settings` in `context` with the device `locale`.
    public init(settings: AppSettings, context: CalendarContext, locale: Locale) {
        self.init(locale: locale, hourCycle: settings.hourCycle, timeZone: context.timeZone)
    }

    /// `locale` with `hourCycle` applied (`.auto` and unknown values leave the locale's own clock).
    public static func applying(_ hourCycle: HourCycle, to locale: Locale) -> Locale {
        var components = Locale.Components(locale: locale)
        switch hourCycle.effective {
        case .h12: components.hourCycle = .oneToTwelve
        case .h24: components.hourCycle = .zeroToTwentyThree
        default: return locale
        }
        return Locale(components: components)
    }

    // MARK: Times

    /// "8:55" / "8:55 AM".
    public func time(_ time: LocalTime) -> String {
        wallClockInstant(time).formatted(timeStyle(in: utc))
    }

    /// The time of `instant` in `timeZone`.
    public func time(_ instant: Date) -> String {
        instant.formatted(timeStyle(in: timeZone))
    }

    /// "8:55 – 9:40" / "8:55 – 9:40 AM" / "8:55–9:40 Uhr" (the locale's interval pattern).
    public func timeRange(_ start: LocalTime, _ end: LocalTime) -> String {
        let lower = wallClockInstant(start)
        let upper = max(lower, wallClockInstant(end))
        return (lower..<upper).formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                                  calendar: utcCalendar, timeZone: utc))
    }

    // MARK: Dates

    /// A calendar date.
    public func date(_ date: LocalDate, style: DateStyle = .abbreviated) -> String {
        let instant = Date(timeIntervalSince1970: TimeInterval(date.daysSinceEpoch) * 86_400)
        let base = Date.FormatStyle(locale: locale, calendar: utcCalendar, timeZone: utc)
        switch style {
        case .numeric: return instant.formatted(base.year().month(.defaultDigits).day())
        case .abbreviated: return instant.formatted(base.year().month(.abbreviated).day())
        case .full: return instant.formatted(base.year().month(.wide).day().weekday(.wide))
        case .weekdayDayMonth: return instant.formatted(base.month(.abbreviated).day().weekday(.abbreviated))
        case .weekdayDay: return instant.formatted(base.day().weekday(.abbreviated))
        case .dayMonth: return instant.formatted(base.month(.abbreviated).day())
        }
    }

    /// Stand-alone weekday name (for column headers and pickers).
    public func weekdayName(_ weekday: Weekday, width: WeekdayWidth = .wide) -> String {
        let symbols: [String]
        switch width {
        case .wide: symbols = calendar.standaloneWeekdaySymbols
        case .abbreviated: symbols = calendar.shortStandaloneWeekdaySymbols
        case .narrow: symbols = calendar.veryShortStandaloneWeekdaySymbols
        }
        let index = weekday.foundationWeekday - 1
        return symbols.indices.contains(index) ? symbols[index] : String(weekday.rawValue)
    }

    /// A list ("A, B and C" / "A, B a C") for user text such as a bring list.
    public func list(_ items: [String]) -> String {
        items.formatted(.list(type: .and, width: .standard).locale(locale))
    }

    // MARK: Internals

    private func timeStyle(in zone: TimeZone) -> Date.FormatStyle {
        var zoned = calendar
        zoned.timeZone = zone
        return Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: zoned, timeZone: zone)
    }

    private func wallClockInstant(_ time: LocalTime) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.minuteOfDay) * 60)
    }
}
