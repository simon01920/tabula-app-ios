import Foundation
import Testing
@testable import TimetableCore

@Suite("LocalDate")
struct LocalDateTests {
    private var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func validatesComponents() {
        #expect(LocalDate(year: 2026, month: 10, day: 6) != nil)
        #expect(LocalDate(year: 2028, month: 2, day: 29) != nil)   // leap year
        #expect(LocalDate(year: 2000, month: 2, day: 29) != nil)   // divisible by 400
        #expect(LocalDate(year: 2026, month: 2, day: 29) == nil)
        #expect(LocalDate(year: 2100, month: 2, day: 29) == nil)   // divisible by 100, not 400
        #expect(LocalDate(year: 2026, month: 4, day: 31) == nil)
        #expect(LocalDate(year: 2026, month: 0, day: 1) == nil)
        #expect(LocalDate(year: 2026, month: 13, day: 1) == nil)
        #expect(LocalDate(year: 2026, month: 1, day: 0) == nil)
        #expect(LocalDate(year: 2026, month: 1, day: 32) == nil)
        #expect(LocalDate(year: 0, month: 1, day: 1) == nil)
        #expect(LocalDate(year: 10_000, month: 1, day: 1) == nil)
        #expect(LocalDate(year: 1, month: 1, day: 1) != nil)
        #expect(LocalDate(year: 9999, month: 12, day: 31) != nil)
    }

    @Test func parsesOnlyStrictISOFormat() {
        #expect(LocalDate("2026-10-06") == LocalDate(year: 2026, month: 10, day: 6))
        #expect(LocalDate("0001-01-01") == LocalDate(year: 1, month: 1, day: 1))
        for bad in ["2026-10-6", "2026/10/06", "20261006", "2026-02-30", "0000-01-01", " 2026-10-06", "2026-10-06T00:00",
                    "+026-10-06", "２０２６-10-06", "2026-1a-06", "", "2026-10--6"] {
            #expect(LocalDate(bad) == nil, "\(bad) must not parse")
        }
    }

    @Test func codesAsISOString() throws {
        let date = Fixture.date("2028-02-29")
        #expect(try Fixture.json(date) == "\"2028-02-29\"")
        #expect(try Fixture.decode(LocalDate.self, "\"2028-02-29\"") == date)
        #expect(throws: DecodingError.self) { try Fixture.decode(LocalDate.self, "\"2027-02-29\"") }
        #expect(throws: DecodingError.self) { try Fixture.decode(LocalDate.self, "20270228") }
    }

    @Test func epochAndKnownWeekdays() {
        #expect(Fixture.date("1970-01-01").daysSinceEpoch == 0)
        #expect(Fixture.date("1969-12-31").daysSinceEpoch == -1)
        #expect(Fixture.date("2000-03-01").daysSinceEpoch == 11_017)
        #expect(Fixture.date("1970-01-01").weekday == .thursday)
        #expect(Fixture.date("2000-01-01").weekday == .saturday)
        #expect(Fixture.date("2026-10-06").weekday == .tuesday)
        #expect(Fixture.date("2028-02-29").weekday == .tuesday)
        #expect(Fixture.date("0001-01-01").weekday == .monday)
    }

    @Test func leapDayArithmetic() {
        let leap = Fixture.date("2028-02-29")
        #expect(Fixture.date("2028-02-28").adding(days: 1) == leap)
        #expect(leap.adding(days: 1) == Fixture.date("2028-03-01"))
        #expect(Fixture.date("2027-02-28").adding(days: 1) == Fixture.date("2027-03-01"))
        #expect(leap.adding(days: 365) == Fixture.date("2029-02-28"))
        #expect(leap.adding(days: -366) == Fixture.date("2027-02-28"))
        #expect(Fixture.date("2028-12-31").dayOfYear == 366)
        #expect(Fixture.date("2027-12-31").dayOfYear == 365)
        #expect(leap.isInLeapYear && !Fixture.date("2027-01-01").isInLeapYear)
        #expect(LocalDate.daysInMonth(year: 2028, month: 2) == 29)
        #expect(LocalDate.daysInMonth(year: 2027, month: 2) == 28)
    }

    @Test func monthAndYearRollover() {
        #expect(Fixture.date("2026-12-31").adding(days: 1) == Fixture.date("2027-01-01"))
        #expect(Fixture.date("2026-01-01").adding(days: -1) == Fixture.date("2025-12-31"))
        #expect(Fixture.date("2026-04-30").adding(days: 1) == Fixture.date("2026-05-01"))
        #expect(Fixture.date("2026-01-01").days(to: Fixture.date("2027-01-01")) == 365)
        #expect(Fixture.date("2028-01-01").days(to: Fixture.date("2029-01-01")) == 366)
    }

    @Test func comparableAndStrideable() {
        let a = Fixture.date("2026-10-06"), b = Fixture.date("2026-10-07"), c = Fixture.date("2027-01-01")
        #expect(a < b && b < c && !(c < a))
        #expect([c, a, b].sorted() == [a, b, c])
        #expect(Array(stride(from: a, through: Fixture.date("2026-10-09"), by: 1)).count == 4)
        #expect(a.distance(to: c) == 87)
        #expect(a.advanced(by: 87) == c)
        #expect(Set([a, Fixture.date("2026-10-06")]).count == 1)
    }

    /// Property: the civil ↔ day-number mapping is a bijection over the whole supported range.
    @Test func civilConversionRoundTripsAcrossSupportedRange() {
        var budget = FailureBudget()
        var previous: LocalDate?
        var day = LocalDate.minDaysSinceEpoch
        while day <= LocalDate.maxDaysSinceEpoch {
            guard let date = LocalDate(daysSinceEpoch: day) else {
                budget.record("no date for day \(day)")
                break
            }
            if date.daysSinceEpoch != day { budget.record("round trip failed for \(date)") }
            if let previous, !(previous < date) { budget.record("ordering broke at \(date)") }
            if LocalDate(date.isoString) != date { budget.record("string round trip failed for \(date)") }
            previous = date
            // Every day in 1900…2100, sparse elsewhere.
            day += (day >= -25_567 && day <= 47_847) ? 1 : 97
        }
        #expect(LocalDate(daysSinceEpoch: LocalDate.minDaysSinceEpoch - 1) == nil)
        #expect(LocalDate(daysSinceEpoch: LocalDate.maxDaysSinceEpoch + 1) == nil)
        #expect(LocalDate(daysSinceEpoch: LocalDate.minDaysSinceEpoch) == Fixture.date("0001-01-01"))
        #expect(LocalDate(daysSinceEpoch: LocalDate.maxDaysSinceEpoch) == Fixture.date("9999-12-31"))
        #expect(budget.count == 0)
    }

    /// Property: pure arithmetic agrees with Foundation's Gregorian calendar for every day 2020…2040
    /// (components, weekday and day addition).
    @Test func agreesWithFoundationGregorianEveryDay2020To2040() {
        let calendar = utcGregorian
        var budget = FailureBudget()
        var date = Fixture.date("2020-01-01")
        let end = Fixture.date("2040-12-31")
        while date <= end {
            let instant = Date(timeIntervalSince1970: TimeInterval(Int64(date.daysSinceEpoch) * 86_400 + 43_200))
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: instant)
            if parts.year != date.year || parts.month != date.month || parts.day != date.day {
                budget.record("components differ for \(date): \(parts)")
            }
            if parts.weekday != date.weekday.foundationWeekday { budget.record("weekday differs for \(date)") }
            let next = calendar.date(byAdding: .day, value: 1, to: instant)!
            let nextParts = calendar.dateComponents([.year, .month, .day], from: next)
            let mine = date.adding(days: 1)
            if nextParts.year != mine.year || nextParts.month != mine.month || nextParts.day != mine.day {
                budget.record("adding(days: 1) differs for \(date)")
            }
            date = mine
        }
        #expect(budget.count == 0)
    }
}

@Suite("ISOWeek")
struct ISOWeekTests {
    private var foundationISO: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Property: `isoWeek` equals Foundation's ISO-8601 calendar for every day 2020…2040.
    @Test func matchesFoundationISO8601EveryDay2020To2040() {
        let calendar = foundationISO
        #expect(calendar.firstWeekday == 2 && calendar.minimumDaysInFirstWeek == 4)
        var budget = FailureBudget()
        var date = Fixture.date("2020-01-01")
        var checked = 0
        while date <= Fixture.date("2040-12-31") {
            let instant = Date(timeIntervalSince1970: TimeInterval(Int64(date.daysSinceEpoch) * 86_400 + 43_200))
            let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: instant)
            let mine = date.isoWeek
            if parts.yearForWeekOfYear != mine.year || parts.weekOfYear != mine.week {
                budget.record("\(date): Foundation \(parts.yearForWeekOfYear ?? -1)-W\(parts.weekOfYear ?? -1), mine \(mine)")
            }
            if mine.monday != date.adding(days: 1 - date.weekday.rawValue) { budget.record("monday wrong for \(date)") }
            checked += 1
            date = date.adding(days: 1)
        }
        #expect(checked == 7_671)
        #expect(budget.count == 0)
    }

    @Test func fiftyThreeWeekYears() {
        #expect(ISOWeek.weeksInYear(2026) == 53)
        #expect(ISOWeek.weeksInYear(2032) == 53)
        #expect(ISOWeek.weeksInYear(2020) == 53)
        #expect(ISOWeek.weeksInYear(2037) == 53)
        #expect(ISOWeek.weeksInYear(2025) == 52)
        #expect(ISOWeek.weeksInYear(2027) == 52)
        #expect(ISOWeek.weeksInYear(2028) == 52)
        let years = (2020...2040).filter { ISOWeek.weeksInYear($0) == 53 }
        #expect(years == [2020, 2026, 2032, 2037])
    }

    @Test func weeksAroundNewYear() {
        #expect(Fixture.date("2026-12-28").isoWeek == ISOWeek(year: 2026, week: 53))
        #expect(Fixture.date("2026-12-31").isoWeek == ISOWeek(year: 2026, week: 53))
        #expect(Fixture.date("2027-01-01").isoWeek == ISOWeek(year: 2026, week: 53))
        #expect(Fixture.date("2027-01-03").isoWeek == ISOWeek(year: 2026, week: 53))
        #expect(Fixture.date("2027-01-04").isoWeek == ISOWeek(year: 2027, week: 1))
        #expect(Fixture.date("2032-12-31").isoWeek == ISOWeek(year: 2032, week: 53))
        #expect(Fixture.date("2033-01-02").isoWeek == ISOWeek(year: 2032, week: 53))
        #expect(Fixture.date("2033-01-03").isoWeek == ISOWeek(year: 2033, week: 1))
        #expect(Fixture.date("2024-12-30").isoWeek == ISOWeek(year: 2025, week: 1))   // ISO year ahead
        #expect(Fixture.date("2026-01-01").isoWeek == ISOWeek(year: 2026, week: 1))
        #expect(Fixture.date("2025-12-29").isoWeek == ISOWeek(year: 2026, week: 1))
    }

    @Test func validationMondayAndAddition() {
        #expect(ISOWeek(year: 2027, week: 53) == nil)
        #expect(ISOWeek(year: 2026, week: 0) == nil)
        #expect(ISOWeek(year: 2026, week: 53)?.monday == Fixture.date("2026-12-28"))
        #expect(ISOWeek(year: 2026, week: 1)?.monday == Fixture.date("2025-12-29"))
        #expect(ISOWeek(year: 2026, week: 53)?.adding(weeks: 1) == ISOWeek(year: 2027, week: 1))
        #expect(ISOWeek(year: 2027, week: 1)?.adding(weeks: -1) == ISOWeek(year: 2026, week: 53))
        #expect(ISOWeek(year: 2026, week: 53)!.description == "2026-W53")
        #expect(ISOWeek(year: 2026, week: 52)! < ISOWeek(year: 2026, week: 53)!)
        #expect(ISOWeek(year: 2026, week: 53)! < ISOWeek(year: 2027, week: 1)!)
    }
}
