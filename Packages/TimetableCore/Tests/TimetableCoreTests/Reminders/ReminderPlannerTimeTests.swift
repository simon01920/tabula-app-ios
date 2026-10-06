import Foundation
import Testing
@testable import TimetableCore

/// DST weekends, time-zone changes, horizon and re-plan date.
@Suite("ReminderPlanner – DST, time zones, horizon")
struct ReminderPlannerTimeTests {
    typealias F = PlannerFixture

    struct DSTCase: Sendable, CustomTestStringConvertible {
        let zone: String
        let now: Date
        let examDate: String
        let examStart: String
        /// Expected UTC instants of "1 day before at 19:00" and "morning of at 07:00".
        let dayBefore: Date
        let morningOf: Date

        var testDescription: String { "\(zone) exam \(examDate)" }
    }

    static let dstCases: [DSTCase] = [
        // Europe/Bratislava fall-back 2026-10-25 03:00 CEST → 02:00 CET.
        DSTCase(zone: "Europe/Bratislava", now: Fixture.utc("2026-10-20", "10:00"), examDate: "2026-10-25", examStart: "10:00",
                dayBefore: Fixture.utc("2026-10-24", "17:00"), morningOf: Fixture.utc("2026-10-25", "06:00")),
        DSTCase(zone: "Europe/Bratislava", now: Fixture.utc("2026-10-20", "10:00"), examDate: "2026-10-26", examStart: "08:00",
                dayBefore: Fixture.utc("2026-10-25", "18:00"), morningOf: Fixture.utc("2026-10-26", "06:00")),
        // Europe/Bratislava spring-forward 2027-03-28 02:00 CET → 03:00 CEST.
        DSTCase(zone: "Europe/Bratislava", now: Fixture.utc("2027-03-22", "10:00"), examDate: "2027-03-28", examStart: "09:00",
                dayBefore: Fixture.utc("2027-03-27", "18:00"), morningOf: Fixture.utc("2027-03-28", "05:00")),
        DSTCase(zone: "Europe/Bratislava", now: Fixture.utc("2027-03-22", "10:00"), examDate: "2027-03-29", examStart: "08:00",
                dayBefore: Fixture.utc("2027-03-28", "17:00"), morningOf: Fixture.utc("2027-03-29", "05:00")),
        // America/New_York fall-back 2026-11-01 02:00 EDT → 01:00 EST.
        DSTCase(zone: "America/New_York", now: Fixture.utc("2026-10-26", "12:00"), examDate: "2026-11-01", examStart: "10:00",
                dayBefore: Fixture.utc("2026-10-31", "23:00"), morningOf: Fixture.utc("2026-11-01", "12:00")),
        DSTCase(zone: "America/New_York", now: Fixture.utc("2026-10-26", "12:00"), examDate: "2026-11-02", examStart: "08:00",
                dayBefore: Fixture.utc("2026-11-02", "00:00"), morningOf: Fixture.utc("2026-11-02", "12:00")),
        // America/New_York spring-forward 2027-03-14 02:00 EST → 03:00 EDT.
        DSTCase(zone: "America/New_York", now: Fixture.utc("2027-03-08", "12:00"), examDate: "2027-03-14", examStart: "10:00",
                dayBefore: Fixture.utc("2027-03-14", "00:00"), morningOf: Fixture.utc("2027-03-14", "11:00")),
        DSTCase(zone: "America/New_York", now: Fixture.utc("2027-03-08", "12:00"), examDate: "2027-03-15", examStart: "08:00",
                dayBefore: Fixture.utc("2027-03-14", "23:00"), morningOf: Fixture.utc("2027-03-15", "11:00")),
    ]

    @Test(arguments: dstCases)
    func dayBeforeAndMorningOfAcrossDST(_ dst: DSTCase) throws {
        let context = CalendarContext(timeZone: Fixture.zone(dst.zone), firstWeekday: .monday)
        let rule = F.rule(1, .exam, [.daysBefore(1, at: F.t("19:00")), .daysBefore(0, at: F.t("07:00"))])
        let plan = ReminderPlanner.plan(F.input(now: dst.now, context: context, rules: [rule],
                                                exams: [F.exam(1, date: dst.examDate, start: dst.examStart)]))
        #expect(plan.notifications.map(\.fireDate) == [dst.dayBefore, dst.morningOf])
        // The wall clock is preserved even though the UTC offset changed in between.
        #expect(plan.notifications.map { context.local(from: $0.fireDate).time } == [F.t("19:00"), F.t("07:00")])
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("19:00"), F.t("07:00")])
        #expect(plan.dropped.isEmpty)
    }

    @Test func nonexistentLocalTimeShiftsForward() throws {
        // "1 day before at 02:30" lands on the spring-forward Sunday, where 02:30 does not exist.
        let rule = F.rule(1, .exam, [.daysBefore(1, at: F.t("02:30"))])
        let bratislava = ReminderPlanner.plan(F.input(now: Fixture.utc("2027-03-22", "10:00"), rules: [rule],
                                                      exams: [F.exam(1, date: "2027-03-29", start: "08:00")]))
        let note = try #require(bratislava.notifications.first)
        #expect(note.fireDate == Fixture.utc("2027-03-28", "01:30"))
        #expect(note.localFireTime == LocalDateTime(date: F.d("2027-03-28"), time: F.t("03:30")))
        let newYork = ReminderPlanner.plan(F.input(now: Fixture.utc("2027-03-08", "12:00"), context: F.newYork, rules: [rule],
                                                   exams: [F.exam(1, date: "2027-03-15", start: "08:00")]))
        #expect(newYork.notifications.map(\.fireDate) == [Fixture.utc("2027-03-14", "07:30")])
        #expect(newYork.notifications.map(\.localFireTime.time) == [F.t("03:30")])
    }

    @Test func ambiguousLocalTimeTakesTheEarlierInstant() {
        let rule = F.rule(1, .exam, [.daysBefore(1, at: F.t("01:30"))])
        let plan = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-26", "12:00"), context: F.newYork, rules: [rule],
                                                exams: [F.exam(1, date: "2026-11-02", start: "08:00")]))
        #expect(plan.notifications.map(\.fireDate) == [Fixture.utc("2026-11-01", "05:30")], "01:30 EDT, not 01:30 EST")
    }

    @Test func minutesBeforeIsElapsedTimeAcrossDST() {
        // Exam 2026-10-25 08:00 CET (07:00Z); 600 min earlier = 21:00Z = 23:00 CEST (not 22:00 wall clock).
        let rule = F.rule(1, .exam, [.minutesBefore(600)])
        let plan = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-20", "10:00"), rules: [rule],
                                                exams: [F.exam(1, date: "2026-10-25", start: "08:00")]))
        #expect(plan.notifications.map(\.fireDate) == [Fixture.utc("2026-10-24", "21:00")])
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("23:00")])
    }

    @Test func timeZoneChangeKeepsIDsAndRemapsInstants() throws {
        let rules = [F.rule(1, .exam, [.daysBefore(1, at: F.t("19:00")), .minutesBefore(45)]),
                     F.rule(2, .homework, [.daysBefore(0, at: F.t("07:00"))], followUp: .afterMinutes(30))]
        let tasks = [F.task(1, due: .dateTime(F.d("2026-10-10"), F.t("12:00"))), F.task(2, due: .date(F.d("2026-10-11")))]
        let exams = [F.exam(1, date: "2026-10-09", start: "09:00"), F.exam(2, date: "2026-10-12")]
        let now = Fixture.utc("2026-10-06", "00:00")
        let home = ReminderPlanner.plan(F.input(now: now, context: F.bratislava, rules: rules, tasks: tasks, exams: exams))
        let away = ReminderPlanner.plan(F.input(now: now, context: F.newYork, rules: rules, tasks: tasks, exams: exams))
        #expect(home.notifications.count == 8) // 2 per item (offsets or primary + follow-up)
        #expect(home.notifications.map(\.id) == away.notifications.map(\.id))
        for (a, b) in zip(home.notifications, away.notifications) {
            #expect(a.localFireTime == b.localFireTime)
            #expect(b.fireDate.timeIntervalSince(a.fireDate) == 6 * 3600, "CEST (UTC+2) → EDT (UTC−4)")
            #expect(a.content == b.content)
        }
        let diff = ReminderPlanDiff.diff(old: home, new: away)
        #expect(diff.notifications.unchanged.isEmpty)
        #expect(diff.notifications.changed == home.notifications.map(\.id).sorted())
        #expect(diff.notifications.toRemove == diff.notifications.changed)
        #expect(diff.notifications.toAdd.map(\.id) == diff.notifications.changed)
    }

    @Test func horizonEndAndReplanDate() {
        let rule = F.rule(1, .exam, [.minutesBefore(30)])
        let one = ReminderPlanner.plan(F.input(rules: [rule], horizonDays: 1))
        #expect(one.horizonEnd == Fixture.utc("2026-10-07", "10:00"))
        #expect(one.nextReplanDate == one.horizonEnd)
        let zero = ReminderPlanner.plan(F.input(rules: [rule], horizonDays: 0))
        #expect(zero.horizonEnd == one.horizonEnd, "horizon is at least one day")
        let three = ReminderPlanner.plan(F.input(rules: [rule], exams: [F.exam(1, date: "2026-10-09", start: "10:00")],
                                                 horizonDays: 3))
        #expect(three.horizonEnd == Fixture.utc("2026-10-09", "10:00"))
        #expect(three.notifications.count == 1, "09:30 local = 07:30Z is inside the horizon")
        #expect(three.nextReplanDate == Fixture.utc("2026-10-08", "10:00"), "horizon end − 1 day beats the 07:30Z fire")
        // Horizon end across the fall-back night: same wall-clock time, 25 h later on that day.
        let dst = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-20", "10:00"), rules: [rule], horizonDays: 7))
        #expect(dst.horizonEnd == Fixture.utc("2026-10-27", "11:00"))
    }

    @Test func nowIsExclusive() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))])
        let task = F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))
        let atFire = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-07", "15:00"), rules: [rule], tasks: [task]))
        #expect(atFire.notifications.isEmpty)
        let justBefore = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-07", "14:59"), rules: [rule], tasks: [task]))
        #expect(justBefore.notifications.count == 1)
    }

    @Test func secondsOfNowDoNotLeakIntoFireDates() {
        let rule = F.rule(1, .homework, [.minutesBefore(15)])
        let plan = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-06", "10:00", seconds: 37), rules: [rule],
                                                tasks: [F.task(1, due: .dateTime(F.d("2026-10-07"), F.t("08:00")))]))
        #expect(plan.notifications.map(\.fireDate) == [Fixture.utc("2026-10-07", "05:45")])
    }
}
