import Foundation

/// Wall-clock → instant conversion for one date, with a fast path for the ~360 days a year without a DST
/// transition nearby.
///
/// When the zone's UTC offset is the same two days before the date's local midnight and three days after it,
/// every local time of the date maps uniquely with that offset, so `instant = local − offset` is exactly what
/// `CalendarContext.date(_:_:)` returns (it brackets transitions with the same ±2-day window). Otherwise — on
/// and around DST changes — it defers to `CalendarContext.date(_:_:)`, which applies the Stage 1 DST policy.
/// Saves three to four time-zone lookups per lesson; the 10-year property test compares every instant with
/// `CalendarContext.date`.
struct DayClock {
    let context: CalendarContext
    let date: LocalDate
    private let localMidnight: Int64
    private let fixedOffset: Int64?

    init(context: CalendarContext, date: LocalDate) {
        self.context = context
        self.date = date
        let midnight = Int64(date.daysSinceEpoch) * 86_400
        self.localMidnight = midnight
        let before = Self.offset(context.timeZone, atUTCSeconds: midnight - 2 * 86_400)
        let after = Self.offset(context.timeZone, atUTCSeconds: midnight + 3 * 86_400)
        self.fixedOffset = before == after ? before : nil
    }

    func instant(_ time: LocalTime) -> Date {
        guard let fixedOffset else { return context.date(date, time) }
        return Date(timeIntervalSince1970: TimeInterval(localMidnight + Int64(time.minuteOfDay) * 60 - fixedOffset))
    }

    private static func offset(_ zone: TimeZone, atUTCSeconds seconds: Int64) -> Int64 {
        Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
    }
}
