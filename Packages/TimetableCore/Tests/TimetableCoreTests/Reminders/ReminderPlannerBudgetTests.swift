import Foundation
import Testing
@testable import TimetableCore

/// The 64-pending cap (60 planned + 4 reserved), ordering and tie-breaks.
@Suite("ReminderPlanner – budget")
struct ReminderPlannerBudgetTests {
    typealias F = PlannerFixture

    /// 120 tasks, 10 per day from 2026-10-07, due every 30 min from 08:00; one reminder 30 min before each.
    static func manyTasks(_ count: Int = 120) -> [TaskItem] {
        (0..<count).map { index in
            let date = F.d("2026-10-07").adding(days: index / 10)
            let time = LocalTime(minuteOfDay: 8 * 60 + (index % 10) * 30)!
            return F.task(UInt64(index + 1), due: .dateTime(date, time))
        }
    }

    @Test func capKeepsTheSoonestSixtyOfMoreThanAHundred() throws {
        let rule = F.rule(1, .homework, [.minutesBefore(30)])
        let tasks = Self.manyTasks()
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: tasks))
        #expect(plan.notifications.count == 60)
        #expect(plan.notifications.map(\.source) == tasks.prefix(60).map { .task($0.id) })
        #expect(plan.isSaturated)
        #expect(plan.dropped.count == 60)
        #expect(plan.dropped.allSatisfy { $0.reason == .budget })
        #expect(plan.dropped.map(\.source) == tasks.suffix(60).map { .task($0.id) })
        #expect(plan.budgetDroppedCount == 60)
        #expect(plan.saturationNotice == LocalizedText(key: "reminder.notice.saturated", args: [.integer(60)]))
        let last = try #require(plan.notifications.last)
        #expect(plan.nextReplanDate == last.fireDate, "re-plan when the window runs out")
        // Never silent: every candidate is either scheduled or listed.
        #expect(Set(plan.notifications.map(\.id)).isDisjoint(with: plan.dropped.map(\.id)))
    }

    @Test func budgetCountsFollowUpsAndHonoursReserve() {
        let rule = F.rule(1, .homework, [.minutesBefore(60)], followUp: .afterMinutes(30))
        let tasks = Self.manyTasks(40) // 40 primaries + 40 follow-ups = 80 candidates
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: tasks))
        #expect(plan.notifications.count == 60)
        #expect(plan.dropped.count == 20)
        let small = ReminderPlanner.plan(F.input(rules: [rule], tasks: tasks, budget: NotificationBudget(maxPending: 10, reserved: 3)))
        #expect(small.notifications.count == 7)
        #expect(small.isSaturated)
        let none = ReminderPlanner.plan(F.input(rules: [rule], tasks: tasks, budget: NotificationBudget(maxPending: 4, reserved: 4)))
        #expect(none.notifications.isEmpty)
        #expect(none.dropped.count == 80)
        #expect(none.isSaturated)
    }

    @Test func exactlyAvailableIsNotSaturated() {
        let rule = F.rule(1, .homework, [.minutesBefore(30)])
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: Self.manyTasks(60)))
        #expect(plan.notifications.count == 60)
        #expect(!plan.isSaturated)
        #expect(plan.dropped.isEmpty)
    }

    @Test func tiesBreakByTierThenID() throws {
        let rules = [F.rule(1, .homework, [.minutesBefore(30)]),
                     F.rule(2, .assignment, [.minutesBefore(30)], tier: .timeSensitive)]
        let due = TaskDue.dateTime(F.d("2026-10-08"), F.t("10:00"))
        let tasks = [F.task(1, due: due), F.task(2, due: due), F.task(3, due: due, kind: .assignment)]
        let all = ReminderPlanner.plan(F.input(rules: rules, tasks: tasks))
        #expect(all.notifications.count == 3)
        #expect(all.notifications.first?.source == .task(F.taskID(3)), "Time Sensitive first at the same instant")
        let standardIDs = all.notifications.dropFirst().map(\.id)
        #expect(standardIDs == standardIDs.sorted(), "same tier → ascending ID")

        let capped = ReminderPlanner.plan(F.input(rules: rules, tasks: tasks, budget: NotificationBudget(maxPending: 2, reserved: 0)))
        #expect(capped.notifications.map(\.id) == Array(all.notifications.prefix(2).map(\.id)))
        #expect(capped.dropped.map(\.id) == [all.notifications[2].id])
        #expect(capped.dropped.map(\.reason) == [.budget])
    }

    @Test func soonestBeatsHigherTier() {
        let rules = [F.rule(1, .homework, [.minutesBefore(30)]),
                     F.rule(2, .assignment, [.minutesBefore(30)], tier: .timeSensitive)]
        let tasks = [F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("10:00"))),
                     F.task(2, due: .dateTime(F.d("2026-10-08"), F.t("10:01")), kind: .assignment)]
        let plan = ReminderPlanner.plan(F.input(rules: rules, tasks: tasks, budget: NotificationBudget(maxPending: 1, reserved: 0)))
        #expect(plan.notifications.map(\.source) == [.task(F.taskID(1))])
        #expect(plan.dropped.map(\.source) == [.task(F.taskID(2))])
    }

    @Test func alarmsDoNotUseTheNotificationBudget() {
        let alarmRule = F.rule(1, .exam, [.minutesBefore(30)], tier: .alarm)
        let homework = F.rule(2, .homework, [.minutesBefore(30)])
        let plan = ReminderPlanner.plan(F.input(
            settings: F.settings(alarms: F.alarmsOn), rules: [alarmRule, homework], tasks: Self.manyTasks(70),
            exams: [F.exam(1, date: "2026-10-07", start: "07:00")]))
        #expect(plan.alarms.count == 1)
        #expect(plan.notifications.count == 60)
        #expect(plan.budgetDroppedCount == 10)
    }

    @Test func budgetDefaults() {
        #expect(NotificationBudget.iOSDefault == NotificationBudget(maxPending: 64, reserved: 4))
        #expect(NotificationBudget.iOSDefault.available == 60)
        #expect(NotificationBudget(maxPending: 3, reserved: 5).available == 0)
        #expect(NotificationBudget(maxPending: 10, reserved: -2).available == 10)
    }
}
