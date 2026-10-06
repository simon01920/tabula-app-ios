import Foundation
import Testing
@testable import TimetableCore

/// Tier policies (D6 Time Sensitive lead time, D7 alarms), the alarm soft limit and quiet hours.
/// Now = 2026-10-06 12:00 CEST, Bratislava.
@Suite("ReminderPlanner – policies")
struct ReminderPlannerPolicyTests {
    typealias F = PlannerFixture

    // MARK: Time Sensitive (D6)

    @Test func timeSensitiveBoundaryIsInclusiveAtSixtyMinutes() throws {
        let rules = [F.rule(1, .exam, [.minutesBefore(60)], tier: .timeSensitive),
                     F.rule(2, .exam, [.minutesBefore(61)], tier: .timeSensitive)]
        let plan = ReminderPlanner.plan(F.input(rules: rules, exams: [F.exam(1, date: "2026-10-08", start: "10:00")]))
        let sixty = try #require(plan.notifications.first { $0.ruleID == F.ruleID(1) })
        let sixtyOne = try #require(plan.notifications.first { $0.ruleID == F.ruleID(2) })
        #expect(sixty.localFireTime.time == F.t("09:00"))
        #expect(sixty.requestedTier == .timeSensitive)
        #expect(sixty.effectiveTier == .timeSensitive)
        #expect(sixty.tierChanges.isEmpty)
        #expect(sixtyOne.localFireTime.time == F.t("08:59"))
        #expect(sixtyOne.requestedTier == .timeSensitive)
        #expect(sixtyOne.effectiveTier == .standard)
        #expect(sixtyOne.tierChanges == [.leadTimeTooLong])
    }

    @Test func timeSensitivePolicyIsReadFromSettings() {
        let rules = [F.rule(1, .exam, [.minutesBefore(45), .minutesBefore(50)], tier: .timeSensitive)]
        let exams = [F.exam(1, date: "2026-10-08", start: "10:00")]
        let custom = ReminderPlanner.plan(F.input(
            settings: F.settings(timeSensitive: TimeSensitivePolicy(isEnabled: true, maxLeadMinutes: 45)),
            rules: rules, exams: exams))
        #expect(custom.notifications.map(\.effectiveTier) == [.standard, .timeSensitive], "50 min > 45, 45 min = 45")
        let off = ReminderPlanner.plan(F.input(
            settings: F.settings(timeSensitive: TimeSensitivePolicy(isEnabled: false, maxLeadMinutes: 60)),
            rules: rules, exams: exams))
        #expect(off.notifications.allSatisfy { $0.effectiveTier == .standard && $0.tierChanges == [.timeSensitiveDisabled] })
    }

    @Test func dayBeforeTimeSensitiveIsDowngraded() throws {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("19:00"))], tier: .timeSensitive)
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))]))
        let note = try #require(plan.notifications.first)
        #expect(note.effectiveTier == .standard)
        #expect(note.tierChanges == [.leadTimeTooLong])
    }

    @Test func leadTimeIsMeasuredAfterQuietHours() throws {
        // 06:00 is quiet (22:00–07:00) → moved to 07:00, 45 min before the 07:45 exam → stays Time Sensitive.
        let rule = F.rule(1, .exam, [.minutesBefore(105)], tier: .timeSensitive)
        let plan = ReminderPlanner.plan(F.input(
            settings: F.settings(quiet: QuietHours(start: F.t("22:00"), end: F.t("07:00"))),
            rules: [rule], exams: [F.exam(1, date: "2026-10-08", start: "07:45")]))
        let note = try #require(plan.notifications.first)
        #expect(note.localFireTime.time == F.t("07:00"))
        #expect(note.movedByQuietHours)
        #expect(note.effectiveTier == .timeSensitive)
    }

    // MARK: Alarms (D7)

    @Test func userAlarmRuleProducesAnAlarm() throws {
        let rule = F.rule(1, .exam, [.daysBefore(0, at: F.t("06:30"))], tier: .alarm, origin: .user)
        let exam = F.exam(1, date: "2026-10-08", start: "08:00", title: "Maturita")
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [rule], exams: [exam]))
        #expect(plan.notifications.isEmpty)
        let alarm = try #require(plan.alarms.first)
        #expect(plan.alarms.count == 1)
        #expect(alarm.fireDate == Fixture.utc("2026-10-08", "04:30"))
        #expect(alarm.localFireTime == LocalDateTime(date: F.d("2026-10-08"), time: F.t("06:30")))
        #expect(alarm.source == .exam(exam.id))
        #expect(alarm.ruleID == rule.id)
        #expect(alarm.content.title == LocalizedText(key: "reminder.exam.title", args: [.string("Maturita")]))
        #expect(alarm.content.body == LocalizedText(key: "reminder.exam.todayAt", args: [.time(F.t("08:00"))]))
        #expect(alarm.alarmID.uuidString.dropFirst(14).first == "8", "RFC 9562 version 8")
        // Deterministic: planning again yields the same AlarmKit ID.
        let again = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [rule], exams: [exam]))
        #expect(again.alarms.first?.alarmID == alarm.alarmID)
        #expect(plan.nextReplanDate == alarm.fireDate, "alarms count as scheduled fire dates")
    }

    @Test func presetAlarmRuleIsDowngraded() throws {
        let rules = [F.rule(1, .exam, [.minutesBefore(30)], tier: .alarm, origin: .preset),
                     F.rule(2, .exam, [.minutesBefore(120)], tier: .alarm, origin: .preset)]
        let exams = [F.exam(1, date: "2026-10-08", start: "10:00")]
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: rules, exams: exams))
        #expect(plan.alarms.isEmpty)
        let short = try #require(plan.notifications.first { $0.ruleID == F.ruleID(1) })
        let long = try #require(plan.notifications.first { $0.ruleID == F.ruleID(2) })
        #expect(short.requestedTier == .alarm)
        #expect(short.effectiveTier == .timeSensitive)
        #expect(short.tierChanges == [.presetRuleAlarm])
        #expect(long.effectiveTier == .standard)
        #expect(long.tierChanges == [.presetRuleAlarm, .leadTimeTooLong])

        // The policy switch lets preset rules ring.
        let allowed = ReminderPlanner.plan(F.input(
            settings: F.settings(alarms: AlarmPolicy(isEnabled: true, allowsPresetRules: true)), rules: rules, exams: exams))
        #expect(allowed.alarms.count == 2)
        #expect(allowed.notifications.isEmpty)
    }

    @Test func alarmsNeedThePolicyAndAvailability() throws {
        let rule = F.rule(1, .exam, [.minutesBefore(30)], tier: .alarm, origin: .user)
        let exams = [F.exam(1, date: "2026-10-08", start: "10:00")]
        let disabled = ReminderPlanner.plan(F.input(rules: [rule], exams: exams))
        #expect(disabled.alarms.isEmpty)
        #expect(disabled.notifications.map(\.tierChanges) == [[.alarmsDisabled]])
        #expect(disabled.notifications.map(\.effectiveTier) == [.timeSensitive])
        let unavailable = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [rule], exams: exams,
                                                       canScheduleAlarms: false))
        #expect(unavailable.alarms.isEmpty)
        #expect(unavailable.notifications.map(\.tierChanges) == [[.alarmsUnavailable]])
    }

    @Test func overrideTierCountsAsAUserChoice() {
        let preset = F.rule(1, .exam, [.minutesBefore(30)], origin: .preset)
        let exam = F.exam(1, date: "2026-10-08", start: "10:00", override: ReminderOverride(tier: .alarm))
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [preset], exams: [exam]))
        #expect(plan.alarms.count == 1)
        #expect(plan.notifications.isEmpty)
    }

    @Test func alarmSoftLimitFallsBackToNotifications() {
        let rule = F.rule(1, .exam, [.minutesBefore(30)], tier: .alarm)
        let exams = (1...12).map { F.exam(UInt64($0), date: "2026-10-\(PaddedNumber.decimal($0 + 6, width: 2))", start: "09:00") }
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [rule], exams: exams))
        #expect(plan.alarms.count == 10)
        #expect(plan.alarms.map(\.source) == (1...10).map { .exam(F.examID(UInt64($0))) }, "soonest alarms are kept")
        #expect(plan.notifications.count == 2)
        #expect(plan.notifications.allSatisfy { $0.requestedTier == .alarm && $0.effectiveTier == .timeSensitive
                                                && $0.tierChanges == [.alarmLimitReached] })
        #expect(plan.alarmOverflow == plan.notifications.map(\.id).sorted())
        #expect(plan.isAlarmSaturated)
        #expect(!plan.isSaturated)
        #expect(plan.alarmOverflowNotice == LocalizedText(key: "reminder.notice.alarmLimit", args: [.integer(2)]))
        let none = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [rule], exams: exams,
                                                alarmSoftLimit: 0))
        #expect(none.alarms.isEmpty)
        #expect(none.notifications.count == 12)
    }

    @Test func followUpsNeverRing() throws {
        let rule = F.rule(1, .exam, [.minutesBefore(90)], tier: .alarm, followUp: .afterMinutes(45))
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn), rules: [rule],
                                                exams: [F.exam(1, date: "2026-10-08", start: "10:00")]))
        #expect(plan.alarms.map(\.localFireTime.time) == [F.t("08:30")])
        let followUp = try #require(plan.notifications.first)
        #expect(followUp.isFollowUp)
        #expect(followUp.localFireTime.time == F.t("09:15"))
        #expect(followUp.effectiveTier == .timeSensitive)
        #expect(followUp.tierChanges == [.followUpNeverAlarm])
    }

    // MARK: Quiet hours

    @Test func quietHoursSpanningMidnight() throws {
        let quiet = QuietHours(start: F.t("22:00"), end: F.t("07:00"))
        let cases: [(offset: String, expected: LocalDateTime, moved: Bool)] = [
            ("23:30", LocalDateTime(date: F.d("2026-10-08"), time: F.t("07:00")), true),
            ("22:00", LocalDateTime(date: F.d("2026-10-08"), time: F.t("07:00")), true),
            ("21:59", LocalDateTime(date: F.d("2026-10-07"), time: F.t("21:59")), false),
        ]
        for (index, item) in cases.enumerated() {
            let rule = F.rule(UInt64(index + 1), .homework, [.daysBefore(1, at: F.t(item.offset))])
            let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: quiet), rules: [rule],
                                                    tasks: [F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))]))
            let note = try #require(plan.notifications.first)
            #expect(note.localFireTime == item.expected, "\(item.offset)")
            #expect(note.movedByQuietHours == item.moved, "\(item.offset)")
        }
        // After midnight inside the window → the same morning; exactly at the end → untouched.
        let morning = F.rule(9, .homework, [.daysBefore(0, at: F.t("06:00")), .daysBefore(0, at: F.t("07:00"))])
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: quiet), rules: [morning],
                                                tasks: [F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))]))
        // 06:00 → 07:00 collides with the 07:00 reminder of the same task: one is kept (deduplicated).
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("07:00")])
        #expect(plan.dropped.map(\.reason) == [.duplicate])
    }

    @Test func quietHoursPastTheStartTimeDropTheReminder() throws {
        let quiet = QuietHours(start: F.t("22:00"), end: F.t("07:00"))
        let rule = F.rule(1, .exam, [.minutesBefore(30)])
        let early = F.exam(1, date: "2026-10-08", start: "06:45")
        let fine = F.exam(2, date: "2026-10-09", start: "07:30")
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: quiet), rules: [rule], exams: [early, fine]))
        #expect(plan.notifications.map(\.source) == [.exam(fine.id)])
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("07:00")])
        let dropped = try #require(plan.dropped.first)
        #expect(plan.dropped.count == 1)
        #expect(dropped.reason == .quietHoursAfterDue)
        #expect(dropped.source == .exam(early.id))
        #expect(dropped.fireDate == F.at("2026-10-08", "07:00"))
        #expect(!dropped.isFollowUp)
    }

    @Test func dateOnlyItemDroppedWhenQuietHoursPushPastTheDay() {
        let quiet = QuietHours(start: F.t("22:00"), end: F.t("07:00"))
        let rule = F.rule(1, .homework, [.daysBefore(0, at: F.t("23:30"))])
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: quiet), rules: [rule],
                                                tasks: [F.task(1, due: .date(F.d("2026-10-08")))]))
        #expect(plan.notifications.isEmpty)
        #expect(plan.dropped.map(\.reason) == [.quietHoursAfterDue])
    }

    @Test func globalAndRuleQuietHoursChain() throws {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("23:00"))],
                          quiet: QuietHours(start: F.t("06:30"), end: F.t("08:00")))
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: QuietHours(start: F.t("22:00"), end: F.t("07:00"))),
                                                rules: [rule], tasks: [F.task(1, due: .dateTime(F.d("2026-10-09"), F.t("12:00")))]))
        let note = try #require(plan.notifications.first)
        #expect(note.localFireTime == LocalDateTime(date: F.d("2026-10-09"), time: F.t("08:00")))
        #expect(note.fireDate == Fixture.utc("2026-10-09", "06:00"))
    }

    @Test func ruleQuietHoursApplyWithoutGlobalOnes() throws {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("13:00"))], quiet: QuietHours(start: F.t("12:00"), end: F.t("14:00")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: .dateTime(F.d("2026-10-09"), F.t("12:00")))]))
        #expect(plan.notifications.first?.localFireTime.time == F.t("14:00"))
    }

    @Test func emptyQuietWindowIsIgnored() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("23:00"))])
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: QuietHours(start: F.t("22:00"), end: F.t("22:00"))),
                                                rules: [rule], tasks: [F.task(1, due: .dateTime(F.d("2026-10-09"), F.t("12:00")))]))
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("23:00")])
        #expect(plan.notifications.allSatisfy { !$0.movedByQuietHours })
    }

    @Test func alarmsIgnoreGlobalButHonourRuleQuietHours() {
        let global = F.settings(quiet: QuietHours(start: F.t("22:00"), end: F.t("07:00")), alarms: F.alarmsOn)
        let wakeUp = F.rule(1, .exam, [.daysBefore(0, at: F.t("06:30"))], tier: .alarm)
        let exams = [F.exam(1, date: "2026-10-08", start: "08:00")]
        let plan = ReminderPlanner.plan(F.input(settings: global, rules: [wakeUp], exams: exams))
        #expect(plan.alarms.map(\.localFireTime.time) == [F.t("06:30")])
        #expect(plan.alarms.allSatisfy { !$0.movedByQuietHours })
        let own = F.rule(1, .exam, [.daysBefore(0, at: F.t("06:30"))], tier: .alarm,
                         quiet: QuietHours(start: F.t("06:00"), end: F.t("06:45")))
        let moved = ReminderPlanner.plan(F.input(settings: global, rules: [own], exams: exams))
        #expect(moved.alarms.map(\.localFireTime.time) == [F.t("06:45")])
        #expect(moved.alarms.allSatisfy { $0.movedByQuietHours })
        // A downgraded alarm request is a notification and honours global quiet hours again.
        let downgraded = ReminderPlanner.plan(F.input(settings: F.settings(quiet: QuietHours(start: F.t("22:00"), end: F.t("07:00"))),
                                                      rules: [wakeUp], exams: exams))
        #expect(downgraded.notifications.map(\.localFireTime.time) == [F.t("07:00")])
    }

    @Test func quietHoursShiftHandlesDSTGapAtTheWindowEnd() {
        // Window ends at 02:30, which does not exist on 2027-03-28 in Bratislava → shifted to 03:30 CEST.
        let window = QuietHours(start: F.t("01:00"), end: F.t("02:30"))
        let (fire, moved) = QuietHoursShift.apply(F.at("2027-03-28", "01:15"), windows: [window], context: F.bratislava)
        #expect(moved)
        #expect(fire == Fixture.utc("2027-03-28", "01:30"))
        #expect(F.bratislava.local(from: fire).time == F.t("03:30"))
    }

    @Test func quietHoursShiftHandlesTheRepeatedFallBackHour() {
        // New York 2026-11-01: 01:00–02:00 happens twice. 01:10 EST (06:10Z, the second pass) is inside a
        // 01:00–01:30 window; its end must be 01:30 EST (06:30Z), not the already-past 01:30 EDT (05:30Z).
        let window = QuietHours(start: F.t("01:00"), end: F.t("01:30"))
        let (second, movedSecond) = QuietHoursShift.apply(Fixture.utc("2026-11-01", "06:10"), windows: [window], context: F.newYork)
        #expect(movedSecond)
        #expect(second == Fixture.utc("2026-11-01", "06:30"))
        let (first, movedFirst) = QuietHoursShift.apply(Fixture.utc("2026-11-01", "05:10"), windows: [window], context: F.newYork)
        #expect(movedFirst)
        #expect(first == Fixture.utc("2026-11-01", "05:30"))
    }

    @Test func quietHoursCoveringTheWholeDayTerminate() {
        let windows = [QuietHours(start: F.t("00:00"), end: F.t("12:00")), QuietHours(start: F.t("12:00"), end: F.t("00:00"))]
        let start = F.at("2026-10-08", "09:00")
        let (fire, moved) = QuietHoursShift.apply(start, windows: windows, context: F.bratislava)
        #expect(moved)
        #expect(fire > start)
    }
}
