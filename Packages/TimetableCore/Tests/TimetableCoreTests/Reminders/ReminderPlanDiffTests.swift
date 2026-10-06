import Foundation
import Testing
@testable import TimetableCore

/// ID stability across re-plans and `ReminderPlanDiff`.
@Suite("ReminderPlanDiff and ID stability")
struct ReminderPlanDiffTests {
    typealias F = PlannerFixture

    static let rules = [F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00")), .minutesBefore(30)], followUp: .afterMinutes(20)),
                        F.rule(2, .exam, [.daysBefore(3, at: F.t("18:00"))], tier: .timeSensitive)]
    static let base = F.task(1, due: .dateTime(F.d("2026-10-09"), F.t("08:00")))

    @Test func idsAreStableAcrossUnrelatedChanges() {
        let before = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [Self.base]))
        let after = ReminderPlanner.plan(F.input(
            now: Fixture.now.addingTimeInterval(3600), // planned an hour later
            settings: F.settings(timeSensitive: TimeSensitivePolicy(isEnabled: true, maxLeadMinutes: 30)),
            rules: Self.rules.reversed(),
            tasks: [F.task(9, due: .dateTime(F.d("2026-10-08"), F.t("09:00"))), Self.base,
                    F.task(10, due: .date(F.d("2026-10-10")))],
            exams: [F.exam(1, date: "2026-10-12", start: "08:00")],
            lessons: [F.lesson(1, date: "2026-10-08", start: "08:00", end: "08:45", subject: F.subject(1, "Bio"))]))
        let mine = after.plannerNotifications(for: .task(Self.base.id))
        #expect(before.notifications.count == 4)
        #expect(mine == before.notifications)
        let diff = ReminderPlanDiff.diff(old: before, new: after)
        #expect(Set(diff.notifications.unchanged) == Set(before.notifications.map(\.id)))
        #expect(diff.notifications.toRemove.isEmpty)
        #expect(diff.notifications.changed.isEmpty)
        #expect(diff.notifications.toAdd.count == after.notifications.count - 4)
    }

    @Test func idsDependOnRuleOffsetSourceAndWallClock() {
        let plan = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [Self.base]))
        let ids = plan.notifications.map(\.id)
        #expect(Set(ids).count == ids.count)
        // Moving the due date changes the wall-clock keys and therefore every ID.
        let moved = F.task(1, due: .dateTime(F.d("2026-10-10"), F.t("08:00")))
        let movedIDs = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [moved])).notifications.map(\.id)
        #expect(Set(movedIDs).isDisjoint(with: ids))
        // A different time on the same day keeps the daysBefore ID (same nominal 17:00) but not the minutesBefore one.
        let later = F.task(1, due: .dateTime(F.d("2026-10-09"), F.t("09:00")))
        let laterPlan = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [later]))
        let shared = Set(laterPlan.notifications.map(\.id)).intersection(ids)
        #expect(shared.count == 2, "17:00 primary and its follow-up")
    }

    @Test func diffFromNothingAddsEverything() {
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(alarms: F.alarmsOn),
                                                rules: Self.rules + [F.rule(3, .exam, [.minutesBefore(60)], tier: .alarm)],
                                                tasks: [Self.base], exams: [F.exam(1, date: "2026-10-12", start: "08:00")]))
        let diff = ReminderPlanDiff.diff(old: nil, new: plan)
        #expect(diff.notifications.toAdd.map(\.id) == plan.notifications.map(\.id).sorted())
        #expect(diff.alarms.toAdd == plan.alarms)
        #expect(diff.notifications.toRemove.isEmpty && diff.alarms.toRemove.isEmpty)
        #expect(!diff.isEmpty)
        #expect(ReminderPlanDiff.diff(old: plan, new: plan).isEmpty)
        #expect(ReminderPlanDiff.diff(old: plan, new: plan).notifications.unchanged.count == plan.notifications.count)
    }

    @Test func diffAddsRemovesAndReplaces() throws {
        let t2 = F.task(2, due: .dateTime(F.d("2026-10-10"), F.t("08:00")))
        let old = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [Self.base, t2]))
        let renamed = F.task(1, due: .dateTime(F.d("2026-10-09"), F.t("08:00")), title: "Renamed")
        let t3 = F.task(3, due: .dateTime(F.d("2026-10-11"), F.t("08:00")))
        let new = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [renamed, F.task(2, due: t2.due, completed: true), t3]))
        let diff = ReminderPlanDiff.diff(old: old, new: new).notifications
        let baseIDs = old.plannerNotifications(for: .task(Self.base.id)).map(\.id)
        let t2IDs = old.plannerNotifications(for: .task(t2.id)).map(\.id)
        let t3IDs = new.plannerNotifications(for: .task(t3.id)).map(\.id)
        #expect(diff.changed == baseIDs.sorted(), "same IDs, new title")
        #expect(diff.toRemove == (t2IDs + baseIDs).sorted())
        #expect(diff.toAdd.map(\.id) == (t3IDs + baseIDs).sorted())
        #expect(diff.unchanged.isEmpty)
        let replacement = try #require(diff.toAdd.first { $0.source == .task(Self.base.id) })
        #expect(replacement.content.title.args == [.string("Renamed")])
    }

    @Test func alarmDiffUsesReminderIDs() {
        let settings = F.settings(alarms: F.alarmsOn)
        let rule = F.rule(3, .exam, [.minutesBefore(60)], tier: .alarm)
        let a = ReminderPlanner.plan(F.input(settings: settings, rules: [rule], exams: [F.exam(1, date: "2026-10-12", start: "08:00")]))
        let b = ReminderPlanner.plan(F.input(settings: settings, rules: [rule], exams: [F.exam(1, date: "2026-10-12", start: "09:00")]))
        let diff = ReminderPlanDiff.diff(old: a, new: b).alarms
        #expect(diff.toRemove == a.alarms.map(\.id))
        #expect(diff.toAdd == b.alarms)
        #expect(a.alarms.first?.alarmID != b.alarms.first?.alarmID)
    }

    @Test func reconcilingAgainstPendingIdentifiers() {
        let plan = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [Self.base]))
        let ids = plan.notifications.map(\.id.rawValue)
        let stale = "rem.0123456789abcdef"
        let pending = [ids[0], ids[2], stale, "snooze-123", "rem.XYZ"]
        let diff = ReminderDiff<PlannedNotification>.reconciling(pending: pending, new: plan.notifications)
        #expect(diff.toRemove == [ReminderID(rawValue: stale)], "foreign identifiers are left alone")
        #expect(diff.unchanged == [ids[0], ids[2]].map(ReminderID.init(rawValue:)).sorted())
        #expect(Set(diff.toAdd.map(\.id.rawValue)) == Set([ids[1], ids[3]]))
        #expect(diff.changed.isEmpty)
    }

    @Test func diffToleratesDuplicateIDsOnInput() {
        let plan = ReminderPlanner.plan(F.input(rules: Self.rules, tasks: [Self.base]))
        let doubled = plan.notifications + plan.notifications
        let diff = ReminderDiff.between(old: doubled, new: plan.notifications)
        #expect(diff.unchanged.count == plan.notifications.count)
        #expect(diff.isEmpty)
    }
}
