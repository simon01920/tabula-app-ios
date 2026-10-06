import Foundation
import Testing
@testable import TimetableCore

@Suite("RotationResolver")
struct RotationResolverTests {
    private let d = Fixture.date

    private func weekCycle(_ anchor: WeekCycleAnchor, length: Int = 2, labels: [String]? = nil,
                           firstWeekday: Weekday = .monday) -> RotationResolver {
        RotationResolver(scheme: .weekCycle(WeekCycle(length: length, anchor: anchor, labels: labels)), firstWeekday: firstWeekday)
    }

    private func dayCycle(length: Int = 6, anchor: String = "2026-09-01", index: Int = 1,
                          schoolDays: Set<Weekday> = Weekday.workweek, skipsBreaks: Bool = true,
                          breaks: [LocalDateRange] = [], labels: [String]? = nil) -> RotationResolver {
        RotationResolver(scheme: .dayCycle(DayCycle(length: length, anchorDate: d(anchor), anchorIndex: index,
                                                    schoolDays: schoolDays, skipsBreaks: skipsBreaks, labels: labels)),
                         firstWeekday: .monday, breaks: breaks)
    }

    // MARK: Week cycles

    @Test func referenceWeekCountsInBothDirections() {
        let rotation = weekCycle(.referenceWeek(date: d("2026-09-01"), cycleWeek: 1))
        #expect(rotation.cycleWeek(on: d("2026-08-31")) == 1) // Monday of the reference week
        #expect(rotation.cycleWeek(on: d("2026-09-06")) == 1) // Sunday of it
        #expect(rotation.cycleWeek(on: d("2026-09-07")) == 2)
        #expect(rotation.cycleWeek(on: d("2026-09-14")) == 1)
        #expect(rotation.cycleWeek(on: d("2026-08-30")) == 2) // previous week
        #expect(rotation.cycleWeek(on: d("2025-09-01")) == 1) // exactly 52 weeks earlier
        #expect(rotation.cycleWeek(on: d("2025-09-08")) == 2) // 51 weeks earlier
        let three = weekCycle(.referenceWeek(date: d("2026-09-01"), cycleWeek: 2), length: 3)
        #expect([0, 7, 14, 21, -7].map { three.cycleWeek(on: d("2026-09-02").adding(days: $0)) } == [2, 3, 1, 2, 1])
    }

    @Test func referenceWeekHonoursTheWeekStart() {
        let anchor = WeekCycleAnchor.referenceWeek(date: d("2026-09-01"), cycleWeek: 1)
        let sundayStart = weekCycle(anchor, firstWeekday: .sunday)
        let mondayStart = weekCycle(anchor, firstWeekday: .monday)
        let saturdayStart = weekCycle(anchor, firstWeekday: .saturday)
        // Sun 2026-09-06: with a Monday start it closes week 1; with a Sunday start it opens week 2
        // (a Sun–Thu school must use a Sunday week start, see RotationResolver docs).
        #expect(mondayStart.cycleWeek(on: d("2026-09-06")) == 1)
        #expect(sundayStart.cycleWeek(on: d("2026-09-06")) == 2)
        #expect(sundayStart.cycleWeek(on: d("2026-08-30")) == 1)
        #expect(saturdayStart.cycleWeek(on: d("2026-08-29")) == 1)
        #expect(saturdayStart.cycleWeek(on: d("2026-09-05")) == 2)
        #expect(sundayStart.startOfWeek(containing: d("2026-09-01")) == d("2026-08-30"))
        #expect(saturdayStart.startOfWeek(containing: d("2026-09-01")) == d("2026-08-29"))
    }

    @Test func isoParityGivesTheWholeUserWeekOneCycleWeek() {
        let anchor = WeekCycleAnchor.isoWeekParity(policy: .strict, offset: 0)
        for firstWeekday in [Weekday.monday, .sunday, .saturday] {
            let rotation = weekCycle(anchor, firstWeekday: firstWeekday)
            var start = rotation.startOfWeek(containing: d("2026-01-01"))
            while start < d("2028-01-01") {
                let weeks = Set((0..<7).map { rotation.cycleWeek(on: start.adding(days: $0)) })
                #expect(weeks.count == 1, "\(firstWeekday) week of \(start)")
                start = start.adding(days: 7)
            }
        }
        // Sunday 2026-10-04 is ISO W40 (even) but belongs to the W41 school week when weeks start on Sunday.
        #expect(weekCycle(anchor, firstWeekday: .monday).cycleWeek(on: d("2026-10-04")) == 2)
        #expect(weekCycle(anchor, firstWeekday: .sunday).cycleWeek(on: d("2026-10-04")) == 1)
    }

    @Test func weekCycleLabelsAndJumping() {
        let rotation = weekCycle(.isoWeekParity(policy: .strict, offset: 0), labels: ["A", "B"])
        #expect(rotation.label(forCycleWeek: 1) == "A" && rotation.label(forCycleWeek: 2) == "B")
        #expect(rotation.label(forCycleWeek: 3) == nil)
        #expect(rotation.startOfWeek(withCycleWeek: 2, onOrAfter: d("2026-10-07")) == d("2026-10-12")) // W41 odd → W42
        #expect(rotation.startOfWeek(withCycleWeek: 1, onOrAfter: d("2026-10-07")) == d("2026-10-05"))
        #expect(rotation.startOfWeek(withCycleWeek: 3, onOrAfter: d("2026-10-07")) == nil)
        // Across the strict W53 → W01 repeat, week 2 is two weeks away.
        #expect(rotation.startOfWeek(withCycleWeek: 2, onOrAfter: d("2026-12-28")) == d("2027-01-11"))
        #expect(dayCycle().startOfWeek(withCycleWeek: 1, onOrAfter: d("2026-10-07")) == nil)
        #expect(RotationResolver(scheme: .none, firstWeekday: .monday).cycleWeek(on: d("2026-10-07")) == nil)
        #expect(rotation.dayKey(on: d("2026-10-07")) == .weekday(.wednesday))
        #expect(rotation.label(for: .weekday(.wednesday), cycleWeek: 2) == "B")
    }

    // MARK: Day cycles

    @Test func dayCycleCountsSchoolDaysOnly() {
        let rotation = dayCycle()
        let expected: [(String, Int?)] = [
            ("2026-09-01", 1), ("2026-09-02", 2), ("2026-09-03", 3), ("2026-09-04", 4), ("2026-09-05", nil),
            ("2026-09-06", nil), ("2026-09-07", 5), ("2026-09-08", 6), ("2026-09-09", 1),
            ("2026-08-31", 6), ("2026-08-28", 5), ("2026-08-24", 1), ("2026-08-21", 6),
        ]
        for (date, index) in expected {
            #expect(rotation.cycleDay(on: d(date)) == index, "\(date)")
        }
        #expect(rotation.dayKey(on: d("2026-09-09")) == .cycleDay(1))
        #expect(rotation.dayKey(on: d("2026-09-05")) == nil)
        #expect(rotation.cycleWeek(on: d("2026-09-09")) == nil)
    }

    @Test func anchorOnANonSchoolDayBelongsToTheNextSchoolDay() {
        let rotation = dayCycle(length: 4, anchor: "2026-09-05", index: 3) // a Saturday
        #expect(rotation.cycleDay(on: d("2026-09-07")) == 3)
        #expect(rotation.cycleDay(on: d("2026-09-08")) == 4)
        #expect(rotation.cycleDay(on: d("2026-09-04")) == 2)
        #expect(rotation.cycleDay(on: d("2026-09-05")) == nil)
    }

    @Test func breaksPauseTheCycleOnlyWhenConfigured() {
        let autumn = LocalDateRange(start: d("2026-10-26"), end: d("2026-10-30"))
        let skipping = dayCycle(length: 2, skipsBreaks: true, breaks: [autumn])
        let running = dayCycle(length: 2, skipsBreaks: false, breaks: [autumn])
        let friday = d("2026-10-23"), monday = d("2026-11-02")
        #expect(skipping.cycleDay(on: d("2026-10-27")) == nil)
        #expect(running.cycleDay(on: d("2026-10-27")) != nil)
        // Five break days are skipped (odd): with skipping the cycle continues from Friday; running flips it.
        let afterSkipping = skipping.cycleDay(on: monday)!, afterRunning = running.cycleDay(on: monday)!
        #expect(afterSkipping == skipping.cycleDay(on: friday)! % 2 + 1)
        #expect(afterRunning == skipping.cycleDay(on: friday)!) // 6 steps later with length 2
        #expect(skipping.countedDays(from: friday, through: monday) == 2)
        #expect(running.countedDays(from: friday, through: monday) == 7)
        #expect(skipping.pausingRanges == [autumn] && running.pausingRanges.isEmpty)
    }

    @Test func overlappingBreaksAreMerged() {
        let ranges = [LocalDateRange(start: d("2026-12-21"), end: d("2027-01-03")),
                      LocalDateRange(start: d("2026-12-28"), end: d("2027-01-08")),
                      LocalDateRange(start: d("2027-01-09"), end: d("2027-01-10")), // adjacent
                      LocalDateRange(start: d("2027-02-10"), end: d("2027-02-01"))] // empty → ignored
        let rotation = dayCycle(breaks: ranges)
        #expect(rotation.pausingRanges == [LocalDateRange(start: d("2026-12-21"), end: d("2027-01-10"))])
        let cycle = DayCycle(length: 6, anchorDate: d("2026-09-01"))
        #expect(rotation.countedDays(from: d("2026-12-01"), through: d("2027-01-31"))
                == ScheduleOracle.countedDays(cycle, breaks: ranges, from: d("2026-12-01"), through: d("2027-01-31")))
    }

    @Test func labelsAndSearch() {
        let rotation = dayCycle(length: 3, labels: ["Red", "Green", "Blue"])
        #expect(rotation.label(forCycleDay: 2) == "Green")
        #expect(rotation.label(for: .cycleDay(3), cycleWeek: nil) == "Blue")
        #expect(rotation.label(for: nil, cycleWeek: nil) == nil)
        #expect(rotation.firstDate(withCycleDay: 1, onOrAfter: d("2026-09-02")) == d("2026-09-04"))
        #expect(weekCycle(.isoWeekParity(policy: .strict, offset: 0)).firstDate(withCycleDay: 1, onOrAfter: d("2026-09-02")) == nil)
        #expect(RotationResolver(scheme: .none, firstWeekday: .monday).label(for: .weekday(.monday), cycleWeek: nil) == nil)
    }

    @Test func degenerateParametersNeverTrap() {
        #expect(dayCycle(length: 0).cycleDay(on: d("2026-09-01")) == nil)
        #expect(dayCycle(schoolDays: []).cycleDay(on: d("2026-09-01")) == nil)
        #expect(dayCycle(schoolDays: []).countedDays(from: d("2026-09-01"), through: d("2027-09-01")) == 0)
        #expect(dayCycle(index: 99).cycleDay(on: d("2026-09-01")) == 3) // (99 - 1) mod 6 + 1
        #expect(weekCycle(.referenceWeek(date: d("2026-09-01"), cycleWeek: 7)).cycleWeek(on: d("2026-09-01")) == 1)
        #expect(weekCycle(.isoWeekParity(policy: .strict, offset: 0), length: 0).cycleWeek(on: d("2026-09-01")) == 1)
        #expect(dayCycle().countedDays(from: d("2026-09-10"), through: d("2026-09-01")) == 0)
    }

    @Test func weekdayCountMatchesBruteForce() {
        var rng = TestRNG(seed: 0x2B01)
        for _ in 0..<500 {
            let days = ScheduleOracle.randomWeekdays(&rng)
            let start = ScheduleOracle.randomDate(&rng, from: d("2020-01-01"), days: 4000)
            let end = start.adding(days: Int.random(in: -3...800, using: &rng))
            let brute = start <= end ? LocalDateRange(start: start, end: end).days.filter { days.contains($0.weekday) }.count : 0
            #expect(RotationResolver.weekdayCount(from: start, through: end, in: days) == brute)
        }
    }
}
