import Foundation
import Testing
@testable import TimetableCore

@Suite("LocalTime")
struct LocalTimeTests {
    @Test func validatesAndParses() {
        #expect(LocalTime(hour: 0, minute: 0) == .midnight)
        #expect(LocalTime(hour: 23, minute: 59)?.minuteOfDay == 1439)
        #expect(LocalTime(hour: 24, minute: 0) == nil)
        #expect(LocalTime(hour: 8, minute: 60) == nil)
        #expect(LocalTime(minuteOfDay: 1440) == nil)
        #expect(LocalTime(minuteOfDay: -1) == nil)
        #expect(LocalTime("08:05") == LocalTime(hour: 8, minute: 5))
        for bad in ["24:00", "8:00", "08:60", "08-00", "0800", "08:00:00", "", "ab:cd", " 8:00"] {
            #expect(LocalTime(bad) == nil, "\(bad) must not parse")
        }
    }

    @Test func codesAsHHmm() throws {
        #expect(try Fixture.json(Fixture.time("07:30")) == "\"07:30\"")
        #expect(try Fixture.decode(LocalTime.self, "\"23:59\"") == Fixture.time("23:59"))
        #expect(throws: DecodingError.self) { try Fixture.decode(LocalTime.self, "\"24:00\"") }
    }

    @Test func arithmeticNeverCrossesMidnight() {
        let t = Fixture.time("23:30")
        #expect(t.hour == 23 && t.minute == 30)
        #expect(t.adding(minutes: 29) == Fixture.time("23:59"))
        #expect(t.adding(minutes: 30) == nil)
        #expect(Fixture.time("00:10").adding(minutes: -11) == nil)
        #expect(Fixture.time("08:00").minutes(to: Fixture.time("09:30")) == 90)
        #expect(Fixture.time("09:30").minutes(to: Fixture.time("08:00")) == -90)
        #expect(Fixture.time("08:00") < Fixture.time("08:01"))
        #expect(LocalDateTime(date: Fixture.date("2026-10-06"), time: Fixture.time("23:59"))
                < LocalDateTime(date: Fixture.date("2026-10-07"), time: .midnight))
    }
}

@Suite("Weekday")
struct WeekdayTests {
    @Test func isoNumberingAndFoundationConversion() {
        #expect(Weekday.monday.rawValue == 1 && Weekday.sunday.rawValue == 7)
        let expected: [Weekday: Int] = [.sunday: 1, .monday: 2, .tuesday: 3, .wednesday: 4, .thursday: 5, .friday: 6, .saturday: 7]
        for (day, foundation) in expected {
            #expect(day.foundationWeekday == foundation)
            #expect(Weekday(foundationWeekday: foundation) == day)
        }
        #expect(Weekday(foundationWeekday: 0) == nil)
        #expect(Weekday(foundationWeekday: 8) == nil)
    }

    @Test func arithmeticAndWeekOrder() {
        #expect(Weekday.sunday.adding(1) == .monday)
        #expect(Weekday.monday.adding(-1) == .sunday)
        #expect(Weekday.wednesday.adding(14) == .wednesday)
        #expect(Weekday.week(startingAt: .monday).first == .monday && Weekday.week(startingAt: .monday).last == .sunday)
        #expect(Weekday.week(startingAt: .sunday) == [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        #expect(Weekday.week(startingAt: .saturday) == [.saturday, .sunday, .monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(Weekday.workweek.count == 5 && !Weekday.workweek.contains(.saturday))
    }

    @Test func codesAsISOInteger() throws {
        #expect(try Fixture.json(Weekday.monday) == "1")
        #expect(try Fixture.json(Weekday.sunday) == "7")
        #expect(try Fixture.decode(Weekday.self, "5") == .friday)
        #expect(throws: DecodingError.self) { try Fixture.decode(Weekday.self, "0") }
    }
}

@Suite("LocalDateRange")
struct LocalDateRangeTests {
    @Test func inclusiveBoundsAndDays() {
        let range = LocalDateRange(start: Fixture.date("2026-12-30"), end: Fixture.date("2027-01-02"))
        #expect(range.contains(Fixture.date("2026-12-30")) && range.contains(Fixture.date("2027-01-02")))
        #expect(!range.contains(Fixture.date("2026-12-29")) && !range.contains(Fixture.date("2027-01-03")))
        #expect(range.dayCount == 4)
        #expect(Array(range.days) == ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02"].map(Fixture.date))
        #expect(LocalDateRange(day: Fixture.date("2028-02-29")).dayCount == 1)
    }

    @Test func invertedRangeIsEmptyNotFatal() throws {
        let inverted = LocalDateRange(start: Fixture.date("2026-10-10"), end: Fixture.date("2026-10-01"))
        #expect(inverted.isEmpty && inverted.dayCount == 0)
        #expect(Array(inverted.days).isEmpty)
        #expect(!inverted.contains(Fixture.date("2026-10-05")))
        #expect(try Fixture.roundTrip(inverted) == inverted)
    }

    @Test func overlaps() {
        let a = LocalDateRange(start: Fixture.date("2026-10-01"), end: Fixture.date("2026-10-10"))
        #expect(a.overlaps(LocalDateRange(day: Fixture.date("2026-10-10"))))
        #expect(!a.overlaps(LocalDateRange(day: Fixture.date("2026-10-11"))))
        #expect(!a.overlaps(LocalDateRange(start: Fixture.date("2026-10-05"), end: Fixture.date("2026-10-04"))))
    }

    @Test func jsonShape() throws {
        let range = LocalDateRange(start: Fixture.date("2026-09-01"), end: Fixture.date("2027-01-31"))
        #expect(try Fixture.json(range) == #"{"end":"2027-01-31","start":"2026-09-01"}"#)
    }
}
