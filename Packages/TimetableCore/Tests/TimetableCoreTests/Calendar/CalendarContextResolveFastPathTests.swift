import Foundation
import Testing
@testable import TimetableCore

/// Phase 10 C4: `CalendarContext.resolve` returns early when the offsets two days before and after a local time
/// agree. The full search it used before is kept here as the reference; both must give the same `Resolution`
/// every 15 minutes within ±3 days of every offset change 2020–2030 (and Samoa's 2011 skipped day).
@Suite("CalendarContext — resolve fast path equals the full search")
struct CalendarContextResolveFastPathTests {
    /// The pre-Phase-10 algorithm, verbatim apart from reading the zone directly.
    static func referenceResolve(_ zone: TimeZone, localSeconds: Int64) -> CalendarContext.Resolution {
        func offset(_ seconds: Int64) -> Int64 {
            Int64(zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(seconds))))
        }
        func date(_ seconds: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }
        let window: Int64 = 2 * 86_400
        let offsetBefore = offset(localSeconds - window)
        let offsetAfter = offset(localSeconds + window)
        let offsetHere = offset(localSeconds)
        var instants: [Int64] = []
        for candidate in Set([offsetBefore, offsetAfter, offsetHere]) {
            let instant = localSeconds - candidate
            if offset(instant) == candidate { instants.append(instant) }
        }
        instants.sort()
        switch instants.count {
        case 0:
            return .skipped(shifted: date(localSeconds - offsetBefore), gapSeconds: Int(offsetAfter - offsetBefore))
        case 1:
            return .unique(date(instants[0]))
        default:
            return .repeated(earlier: date(instants.first!), later: date(instants.last!))
        }
    }

    /// Local dates within ±3 days of each offset change in `years` (found by comparing the offsets at
    /// consecutive UTC midnights, so standard-offset changes count as well as DST).
    static func datesAroundTransitions(_ zone: TimeZone, years: ClosedRange<Int>) -> [LocalDate] {
        let first = LocalDate(year: years.lowerBound, month: 1, day: 1)!.adding(days: -4)
        let last = LocalDate(year: years.upperBound, month: 12, day: 31)!.adding(days: 4)
        var dates = Set<LocalDate>()
        var previous = zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(Int64(first.daysSinceEpoch) * 86_400)))
        var day = first
        while day < last {
            let next = day.adding(days: 1)
            let offset = zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(Int64(next.daysSinceEpoch) * 86_400)))
            if offset != previous {
                for delta in -3...4 { dates.insert(day.adding(days: delta)) }
            }
            previous = offset
            day = next
        }
        return dates.sorted()
    }

    static func compare(_ zoneID: String, dates: [LocalDate], failures: inout FailureBudget) -> Int {
        let zone = Fixture.zone(zoneID)
        let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
        var nonUnique = 0
        for date in dates {
            for minute in stride(from: 0, to: LocalTime.minutesPerDay, by: 15) {
                let time = LocalTime(minuteOfDay: minute)!
                let expected = referenceResolve(zone, localSeconds: Int64(date.daysSinceEpoch) * 86_400 + Int64(minute) * 60)
                let actual = context.resolve(date, time)
                if actual != expected { failures.record("\(zoneID) \(date) \(time): \(actual) ≠ reference \(expected)") }
                if case .unique = expected {} else { nonUnique += 1 }
            }
        }
        return nonUnique
    }

    @Test(arguments: ["Europe/Bratislava", "America/New_York", "Australia/Lord_Howe", "Pacific/Apia", "America/Santiago",
                      "Asia/Gaza"])
    func equalsReferenceAroundEveryTransition(zoneID: String) {
        let zone = Fixture.zone(zoneID)
        var dates = Self.datesAroundTransitions(zone, years: 2020...2030)
        if zoneID == "Pacific/Apia" { dates += Self.datesAroundTransitions(zone, years: 2011...2011) }
        #expect(!dates.isEmpty, "no offset change found for \(zoneID)")
        var failures = FailureBudget()
        let nonUnique = Self.compare(zoneID, dates: dates, failures: &failures)
        #expect(failures.count == 0)
        // The sample really reaches the slow path: it contains gaps and overlaps, not only unique times.
        #expect(nonUnique > 0)
    }

    @Test func samoaSkippedDayIsCovered() {
        let dates = Self.datesAroundTransitions(Fixture.zone("Pacific/Apia"), years: 2011...2011)
        #expect(dates.contains(Fixture.date("2011-12-30")))
        let context = CalendarContext(timeZone: Fixture.zone("Pacific/Apia"), firstWeekday: .monday)
        #expect(context.resolve(Fixture.date("2011-12-30"), Fixture.time("00:00"))
                == Self.referenceResolve(Fixture.zone("Pacific/Apia"),
                                         localSeconds: Int64(Fixture.date("2011-12-30").daysSinceEpoch) * 86_400))
    }

    @Test func equalsReferenceWithoutDST() {
        // Asia/Tokyo and UTC have no offset change in the range: every local time takes the fast path.
        for zoneID in ["Asia/Tokyo", "UTC"] {
            #expect(Self.datesAroundTransitions(Fixture.zone(zoneID), years: 2020...2030).isEmpty)
            let dates = (2020...2030).flatMap { year in (1...12).map { LocalDate(year: year, month: $0, day: 1 + $0)! } }
            var failures = FailureBudget()
            #expect(Self.compare(zoneID, dates: dates, failures: &failures) == 0)
            #expect(failures.count == 0)
        }
    }
}
