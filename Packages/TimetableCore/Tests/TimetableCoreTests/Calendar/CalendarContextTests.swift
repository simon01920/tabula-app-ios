import Foundation
import Testing
@testable import TimetableCore

@Suite("CalendarContext — DST, week start, midnight, time-zone change")
struct CalendarContextTests {
    private let bratislava = CalendarContext(timeZone: Fixture.zone("Europe/Bratislava"), firstWeekday: .monday)
    private let newYork = CalendarContext(timeZone: Fixture.zone("America/New_York"), firstWeekday: .sunday)
    private let utc = CalendarContext(timeZone: Fixture.zone("UTC"), firstWeekday: .monday)

    // MARK: Europe/Bratislava

    @Test func bratislavaSpringForwardGapShiftsForward() {
        let day = Fixture.date("2026-03-29")   // 02:00 CET → 03:00 CEST
        #expect(bratislava.resolve(day, Fixture.time("01:59")) == .unique(Fixture.utc("2026-03-29", "00:59")))
        #expect(bratislava.resolve(day, Fixture.time("02:30"))
                == .skipped(shifted: Fixture.utc("2026-03-29", "01:30"), gapSeconds: 3600))
        #expect(bratislava.resolve(day, Fixture.time("02:00"))
                == .skipped(shifted: Fixture.utc("2026-03-29", "01:00"), gapSeconds: 3600))
        #expect(bratislava.resolve(day, Fixture.time("03:00")) == .unique(Fixture.utc("2026-03-29", "01:00")))
        let shifted = bratislava.date(day, Fixture.time("02:30"))
        #expect(bratislava.local(from: shifted) == LocalDateTime(date: day, time: Fixture.time("03:30")))
    }

    @Test func bratislavaFallBackOverlapTakesEarlier() {
        let day = Fixture.date("2026-10-25")   // 03:00 CEST → 02:00 CET
        #expect(bratislava.resolve(day, Fixture.time("02:30"))
                == .repeated(earlier: Fixture.utc("2026-10-25", "00:30"), later: Fixture.utc("2026-10-25", "01:30")))
        #expect(bratislava.date(day, Fixture.time("02:30")) == Fixture.utc("2026-10-25", "00:30"))
        #expect(bratislava.resolve(day, Fixture.time("02:00"))
                == .repeated(earlier: Fixture.utc("2026-10-25", "00:00"), later: Fixture.utc("2026-10-25", "01:00")))
        #expect(bratislava.resolve(day, Fixture.time("01:59")) == .unique(Fixture.utc("2026-10-24", "23:59")))
        #expect(bratislava.resolve(day, Fixture.time("03:00")) == .unique(Fixture.utc("2026-10-25", "02:00")))
        // Both instants of the repeated hour read back as the same wall-clock time.
        #expect(bratislava.local(from: Fixture.utc("2026-10-25", "00:30")).time == Fixture.time("02:30"))
        #expect(bratislava.local(from: Fixture.utc("2026-10-25", "01:30")).time == Fixture.time("02:30"))
    }

    @Test func bratislava23And25HourDays() {
        #expect(bratislava.secondsInDay(Fixture.date("2026-03-29")) == 23 * 3600)
        #expect(bratislava.secondsInDay(Fixture.date("2026-10-25")) == 25 * 3600)
        #expect(bratislava.secondsInDay(Fixture.date("2026-10-06")) == 24 * 3600)
        #expect(bratislava.startOfDay(Fixture.date("2026-10-25")) == Fixture.utc("2026-10-24", "22:00"))
        #expect(bratislava.dayInterval(Fixture.date("2026-10-25")).end == Fixture.utc("2026-10-25", "23:00"))
    }

    // MARK: America/New_York

    @Test func newYorkSpringForwardAndFallBack() {
        #expect(newYork.resolve(Fixture.date("2026-03-08"), Fixture.time("02:30"))
                == .skipped(shifted: Fixture.utc("2026-03-08", "07:30"), gapSeconds: 3600))
        #expect(newYork.local(from: newYork.date(Fixture.date("2026-03-08"), Fixture.time("02:30"))).time == Fixture.time("03:30"))
        #expect(newYork.resolve(Fixture.date("2026-03-08"), Fixture.time("01:59")) == .unique(Fixture.utc("2026-03-08", "06:59")))
        #expect(newYork.resolve(Fixture.date("2026-03-08"), Fixture.time("03:00")) == .unique(Fixture.utc("2026-03-08", "07:00")))
        #expect(newYork.resolve(Fixture.date("2026-11-01"), Fixture.time("01:30"))
                == .repeated(earlier: Fixture.utc("2026-11-01", "05:30"), later: Fixture.utc("2026-11-01", "06:30")))
        #expect(newYork.resolve(Fixture.date("2026-11-01"), Fixture.time("00:30")) == .unique(Fixture.utc("2026-11-01", "04:30")))
        #expect(newYork.resolve(Fixture.date("2026-11-01"), Fixture.time("02:00")) == .unique(Fixture.utc("2026-11-01", "07:00")))
        #expect(newYork.secondsInDay(Fixture.date("2026-03-08")) == 23 * 3600)
        #expect(newYork.secondsInDay(Fixture.date("2026-11-01")) == 25 * 3600)
    }

    /// Property: on DST days, wall clock → instant → wall clock is the identity except inside the gap, where
    /// it moves forward by exactly the gap; instant → wall clock → instant is the identity except for the
    /// later copy of a repeated hour, which maps to the earlier copy.
    @Test(arguments: [("Europe/Bratislava", "2026-03-29"), ("Europe/Bratislava", "2026-10-25"),
                      ("America/New_York", "2026-03-08"), ("America/New_York", "2026-11-01")])
    func dstDayRoundTrips(zone: String, day: String) {
        let context = CalendarContext(timeZone: Fixture.zone(zone), firstWeekday: .monday)
        let date = Fixture.date(day)
        var budget = FailureBudget()
        for minute in stride(from: 0, to: 1440, by: 5) {
            let time = LocalTime(minuteOfDay: minute)!
            let resolution = context.resolve(date, time)
            let back = context.local(from: resolution.date)
            switch resolution {
            case .unique, .repeated:
                if back != LocalDateTime(date: date, time: time) { budget.record("\(zone) \(day) \(time) → \(back)") }
            case .skipped(_, let gap):
                if back != LocalDateTime(date: date, time: time.adding(minutes: gap / 60)!) {
                    budget.record("\(zone) \(day) gap \(time) → \(back)")
                }
            }
        }
        let interval = context.dayInterval(date)
        var instant = interval.start
        while instant < interval.end {
            let local = context.local(from: instant)
            let again = context.date(local.date, local.time)
            if case .repeated(let earlier, let later) = context.resolve(local.date, local.time) {
                if !(again == earlier && (instant == earlier || instant == later)) { budget.record("overlap \(instant)") }
            } else if again != instant {
                budget.record("\(zone) instant \(instant) → \(local) → \(again)")
            }
            instant += 300
        }
        #expect(budget.count == 0)
    }

    // MARK: Unusual transitions

    @Test func midnightTransitionStartsDayAtFirstExistingMinute() {
        // Brazil 2018-11-04: clocks jumped from 00:00 to 01:00 (historic tz data).
        let saoPaulo = CalendarContext(timeZone: Fixture.zone("America/Sao_Paulo"), firstWeekday: .monday)
        let day = Fixture.date("2018-11-04")
        #expect(saoPaulo.resolve(day, .midnight) == .skipped(shifted: Fixture.utc("2018-11-04", "03:00"), gapSeconds: 3600))
        #expect(saoPaulo.local(from: saoPaulo.startOfDay(day)) == LocalDateTime(date: day, time: Fixture.time("01:00")))
        #expect(saoPaulo.secondsInDay(day) == 23 * 3600)
    }

    @Test func skippedCalendarDayShiftsByTwentyFourHours() {
        // Samoa skipped 2011-12-30 entirely (UTC−10 → UTC+14).
        let apia = CalendarContext(timeZone: Fixture.zone("Pacific/Apia"), firstWeekday: .monday)
        let resolution = apia.resolve(Fixture.date("2011-12-30"), Fixture.time("12:00"))
        guard case .skipped(let shifted, let gap) = resolution else {
            Issue.record("expected a skipped day, got \(resolution)")
            return
        }
        #expect(gap == 86_400)
        #expect(apia.local(from: shifted) == LocalDateTime(date: Fixture.date("2011-12-31"), time: Fixture.time("12:00")))
    }

    // MARK: Week start

    @Test func startOfWeekHonoursFirstWeekday() {
        let wednesday = Fixture.date("2026-10-07")
        func context(_ first: Weekday) -> CalendarContext { CalendarContext(timeZone: Fixture.zone("UTC"), firstWeekday: first) }
        #expect(context(.monday).startOfWeek(containing: wednesday) == Fixture.date("2026-10-05"))
        #expect(context(.sunday).startOfWeek(containing: wednesday) == Fixture.date("2026-10-04"))
        #expect(context(.saturday).startOfWeek(containing: wednesday) == Fixture.date("2026-10-03"))
        #expect(context(.saturday).startOfWeek(containing: Fixture.date("2026-10-09")) == Fixture.date("2026-10-03"))
        #expect(context(.saturday).startOfWeek(containing: Fixture.date("2026-10-10")) == Fixture.date("2026-10-10"))
        #expect(context(.sunday).startOfWeek(containing: Fixture.date("2026-10-04")) == Fixture.date("2026-10-04"))
        #expect(context(.monday).startOfWeek(containing: Fixture.date("2027-01-01")) == Fixture.date("2026-12-28"))
        #expect(context(.sunday).week(containing: wednesday).map(\.weekday) == Weekday.week(startingAt: .sunday))
    }

    /// Property: `startOfWeek` equals Foundation's week interval start for every first weekday, every day of 2026–2027.
    @Test func startOfWeekMatchesFoundationForAllFirstWeekdays() {
        var budget = FailureBudget()
        for first in Weekday.allCases {
            let context = CalendarContext(timeZone: Fixture.zone("UTC"), firstWeekday: first)
            var date = Fixture.date("2026-01-01")
            while date <= Fixture.date("2027-12-31") {
                let noon = Date(timeIntervalSince1970: TimeInterval(Int64(date.daysSinceEpoch) * 86_400 + 43_200))
                guard let interval = context.calendar.dateInterval(of: .weekOfYear, for: noon) else {
                    budget.record("no interval for \(date)")
                    break
                }
                let foundationStart = context.local(from: interval.start).date
                if foundationStart != context.startOfWeek(containing: date) {
                    budget.record("first \(first) \(date): Foundation \(foundationStart) vs \(context.startOfWeek(containing: date))")
                }
                date = date.adding(days: 1)
            }
        }
        #expect(budget.count == 0)
    }

    @Test func calendarIsConfigured() {
        #expect(newYork.calendar.firstWeekday == 1)
        #expect(bratislava.calendar.firstWeekday == 2)
        #expect(bratislava.calendar.timeZone.identifier == "Europe/Bratislava")
        #expect(CalendarContext(timeZoneIdentifier: "Not/AZone", firstWeekday: .monday) == nil)
        #expect(CalendarContext(timeZoneIdentifier: "Europe/Bratislava", firstWeekday: .monday) == bratislava)
    }

    // MARK: Midnight rollover

    @Test func midnightRollover() {
        let lastMinute = utc.date(Fixture.date("2026-12-31"), Fixture.time("23:59"))
        #expect(utc.local(from: lastMinute + 60) == LocalDateTime(date: Fixture.date("2027-01-01"), time: .midnight))
        #expect(utc.local(from: lastMinute + 59.999) == LocalDateTime(date: Fixture.date("2026-12-31"), time: Fixture.time("23:59")))
        #expect(utc.dayInterval(Fixture.date("2026-12-31")).end == utc.startOfDay(Fixture.date("2027-01-01")))
        #expect(utc.local(from: Date(timeIntervalSince1970: -1)) == LocalDateTime(date: Fixture.date("1969-12-31"), time: Fixture.time("23:59")))
        #expect(utc.local(from: Date(timeIntervalSince1970: -0.5)).date == Fixture.date("1969-12-31"))
        // 23:30 in Bratislava (summer) is 21:30 UTC the same day; 00:30 is 22:30 UTC the previous day.
        #expect(bratislava.date(Fixture.date("2026-07-01"), Fixture.time("00:30")) == Fixture.utc("2026-06-30", "22:30"))
        #expect(bratislava.localDate(of: Fixture.utc("2026-06-30", "22:30")) == Fixture.date("2026-07-01"))
        #expect(newYork.localDate(of: Fixture.utc("2026-07-01", "03:59")) == Fixture.date("2026-06-30"))
    }

    @Test func instantsAfter2038DoNotOverflow() {
        let late = Fixture.date("2100-06-15")
        let instant = bratislava.date(late, Fixture.time("12:00"))
        #expect(bratislava.local(from: instant) == LocalDateTime(date: late, time: Fixture.time("12:00")))
    }

    // MARK: Time-zone change between scheduling and firing

    @Test func timeZoneChangeBetweenSchedulingAndFiring() {
        let lessonDay = Fixture.date("2026-10-06"), lessonTime = Fixture.time("08:00")
        let scheduledInBratislava = bratislava.date(lessonDay, lessonTime)
        #expect(scheduledInBratislava == Fixture.utc("2026-10-06", "06:00"))

        // The user flies to London; with .followDevice the wall-clock lesson is now an hour later in UTC…
        let london = CalendarContext(timeZone: Fixture.zone("Europe/London"), firstWeekday: .monday)
        #expect(london.date(lessonDay, lessonTime) == Fixture.utc("2026-10-06", "07:00"))
        // …and a reminder planned before the flight would fire at 07:00 London time, not 08:00 → re-plan needed.
        #expect(london.local(from: scheduledInBratislava).time == Fixture.time("07:00"))
        #expect(newYork.date(lessonDay, lessonTime) == Fixture.utc("2026-10-06", "12:00"))

        // With a fixed zone the instant does not move when the device zone changes.
        var settings = AppSettings(meta: Fixture.meta(), timeZoneMode: .fixed(identifier: "Europe/Bratislava"))
        let fixedAbroad = CalendarContext(settings: settings, deviceTimeZone: Fixture.zone("America/New_York"),
                                          localeFirstWeekday: .sunday)
        #expect(fixedAbroad.date(lessonDay, lessonTime) == scheduledInBratislava)
        #expect(fixedAbroad.firstWeekday == .sunday)

        settings.timeZoneMode = .followDevice
        settings.weekStartOverride = .saturday
        let following = CalendarContext(settings: settings, deviceTimeZone: Fixture.zone("Europe/London"),
                                        localeFirstWeekday: .monday)
        #expect(following.timeZone.identifier == "Europe/London")
        #expect(following.firstWeekday == .saturday)
    }
}

@Suite("TimeZoneMode")
struct TimeZoneModeTests {
    @Test func resolvesAndFallsBack() {
        let device = Fixture.zone("Europe/Prague")
        #expect(TimeZoneMode.followDevice.resolve(deviceTimeZone: device).identifier == "Europe/Prague")
        #expect(TimeZoneMode.fixed(identifier: "Asia/Tokyo").resolve(deviceTimeZone: device).identifier == "Asia/Tokyo")
        #expect(TimeZoneMode.fixed(identifier: "Mars/Olympus").resolve(deviceTimeZone: device).identifier == "Europe/Prague")
    }

    @Test func jsonShape() throws {
        #expect(try Fixture.json(TimeZoneMode.followDevice) == #"{"kind":"followDevice"}"#)
        #expect(try Fixture.json(TimeZoneMode.fixed(identifier: "Europe/Bratislava"))
                == #"{"identifier":"Europe/Bratislava","kind":"fixed"}"#)
        #expect(try Fixture.roundTrip(TimeZoneMode.fixed(identifier: "Asia/Tokyo")) == .fixed(identifier: "Asia/Tokyo"))
        #expect(throws: DecodingError.self) { try Fixture.decode(TimeZoneMode.self, #"{"kind":"lunar"}"#) }
    }
}
