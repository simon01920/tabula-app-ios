import Foundation
import Testing
@testable import TimetableCore

@Suite("WeekParity (ISO week → cycle week)")
struct WeekParityTests {
    private func week(_ year: Int, _ number: Int) -> ISOWeek { ISOWeek(year: year, week: number)! }

    @Test func strictMapsOddWeeksToWeekOneAndOffsetSwaps() {
        #expect(WeekParity.cycleWeek(for: week(2026, 41), policy: .strict, offset: 0) == 1)
        #expect(WeekParity.cycleWeek(for: week(2026, 42), policy: .strict, offset: 0) == 2)
        #expect(WeekParity.cycleWeek(for: week(2026, 41), policy: .strict, offset: 1) == 2)
        #expect(WeekParity.cycleWeek(for: week(2026, 42), policy: .strict, offset: 1) == 1)
        #expect(WeekParity.cycleWeek(for: week(2026, 41), policy: .strict, offset: -1) == 2)
        #expect(WeekParity.cycleWeek(for: week(2026, 41), policy: .strict, offset: 3) == 2)
        // Length 3: W01 → 1, W02 → 2, W03 → 3, W04 → 1.
        #expect([1, 2, 3, 4].map { WeekParity.cycleWeek(for: week(2027, $0), policy: .strict, offset: 0, length: 3) } == [1, 2, 3, 1])
    }

    @Test func strictRepeatsAWeekAfterA53WeekYear() {
        #expect(ISOWeek.weeksInYear(2026) == 53 && ISOWeek.weeksInYear(2032) == 53)
        for year in [2026, 2032] {
            #expect(WeekParity.cycleWeek(for: week(year, 52), policy: .strict, offset: 0) == 2)
            #expect(WeekParity.cycleWeek(for: week(year, 53), policy: .strict, offset: 0) == 1)
            #expect(WeekParity.cycleWeek(for: week(year + 1, 1), policy: .strict, offset: 0) == 1, "W53 and W01 are both odd")
            #expect(WeekParity.cycleWeek(for: week(year + 1, 2), policy: .strict, offset: 0) == 2)
        }
    }

    @Test func continuousAlternatesAcrossA53WeekNewYear() {
        // School year 2026/27 starts in 2026-W36 (1 Sep 2026 is a Tuesday); 2032/33 in 2032-W36.
        #expect(WeekParity.schoolYearStartWeek(for: week(2027, 1)) == week(2026, 36))
        #expect(WeekParity.schoolYearStartWeek(for: week(2033, 1)) == week(2032, 36))
        for year in [2026, 2032] {
            let sequence = [week(year, 52), week(year, 53), week(year + 1, 1), week(year + 1, 2), week(year + 1, 3)]
                .map { WeekParity.cycleWeek(for: $0, policy: .continuous, offset: 0) }
            #expect(sequence == [2, 1, 2, 1, 2], "\(year): \(sequence)")
            // From W01 to the summer, continuous is the opposite of strict.
            for number in 1...30 {
                let w = week(year + 1, number)
                #expect(WeekParity.cycleWeek(for: w, policy: .continuous, offset: 0)
                        != WeekParity.cycleWeek(for: w, policy: .strict, offset: 0))
            }
        }
    }

    @Test func continuousEqualsStrictWhenTheSchoolYearHasNo53rdWeek() {
        // School year 2027/28: ISO 2027 has 52 weeks → identical for length 2 over the whole school year.
        let start = WeekParity.schoolYearStartWeek(for: week(2027, 40))!
        #expect(start == week(2027, 35)) // 1 Sep 2027 is a Wednesday
        var current = start
        let nextStart = week(2028, 35) // 1 Sep 2028 is a Friday → 2028-W35
        #expect(WeekParity.schoolYearStartWeek(for: nextStart) == nextStart)
        while current < nextStart {
            #expect(WeekParity.cycleWeek(for: current, policy: .continuous, offset: 0)
                    == WeekParity.cycleWeek(for: current, policy: .strict, offset: 0), "\(current)")
            current = current.adding(weeks: 1)
        }
    }

    @Test func continuousReanchorsAtTheSchoolYearStart() {
        // The re-anchoring repeats a cycle week in the summer: 2027-W34 (old year) and 2027-W35 (new year).
        #expect(WeekParity.schoolYearStartWeek(for: week(2027, 34)) == week(2026, 36))
        #expect(WeekParity.schoolYearStartWeek(for: week(2027, 35)) == week(2027, 35))
        #expect(WeekParity.cycleWeek(for: week(2027, 34), policy: .continuous, offset: 0) == 1)
        #expect(WeekParity.cycleWeek(for: week(2027, 35), policy: .continuous, offset: 0) == 1)
        // The week containing 1 September belongs to the new school year even if it starts in August.
        #expect(WeekParity.schoolYearStartWeek(for: LocalDate(year: 2026, month: 8, day: 31)!.isoWeek) == week(2026, 36))
        #expect(WeekParity.schoolYearStartWeek(for: LocalDate(year: 2026, month: 8, day: 30)!.isoWeek) == week(2025, 36))
    }

    @Test func continuousNeverRepeatsInsideASchoolYearForAnyLength() {
        var failures = FailureBudget()
        for length in 2...6 {
            var current = week(2019, 30)
            while current < week(2041, 1) {
                let next = current.adding(weeks: 1)
                if WeekParity.schoolYearStartWeek(for: next) == WeekParity.schoolYearStartWeek(for: current) {
                    let a = WeekParity.cycleWeek(for: current, policy: .continuous, offset: 2, length: length)
                    let b = WeekParity.cycleWeek(for: next, policy: .continuous, offset: 2, length: length)
                    if b != a % length + 1 { failures.record("length \(length): \(current) → \(next): \(a) → \(b)") }
                }
                current = next
            }
        }
        #expect(failures.count == 0)
    }

    @Test func representativeWeekUsesTheMiddleOfTheUsersWeek() {
        let sunday = Fixture.date("2026-10-04")
        #expect(sunday.isoWeek == week(2026, 40))
        #expect(WeekParity.representativeISOWeek(containing: sunday, firstWeekday: .monday) == week(2026, 40))
        #expect(WeekParity.representativeISOWeek(containing: sunday, firstWeekday: .sunday) == week(2026, 41))
        #expect(WeekParity.representativeISOWeek(containing: Fixture.date("2026-10-03"), firstWeekday: .saturday) == week(2026, 41))
        // Monday start: identical to the date's own ISO week, every day of several years.
        for date in LocalDateRange(start: Fixture.date("2025-12-01"), end: Fixture.date("2028-01-31")).days {
            #expect(WeekParity.representativeISOWeek(containing: date, firstWeekday: .monday) == date.isoWeek)
        }
    }

    @Test func defaultPolicyIsStrictAndLengthIsClamped() {
        for profile in [UserProfile.elementary, .secondary, .university, .other] {
            #expect(WeekParity.defaultPolicy(for: profile, regionCode: "SK") == .strict)
            #expect(WeekParity.defaultPolicy(for: profile, regionCode: nil) == .strict)
        }
        #expect(WeekParity.cycleWeek(for: week(2026, 41), policy: .strict, offset: 0, length: 0) == 1)
        #expect(WeekParity.cycleWeek(for: week(1, 5), policy: .continuous, offset: 0) == 1) // no previous school year
    }
}
