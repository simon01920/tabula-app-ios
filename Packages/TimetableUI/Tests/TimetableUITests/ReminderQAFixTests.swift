import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Stage A QA fixes: in-progress loud alarms survive re-plans, due notifications are not swallowed, the render signature
// re-adds text, the reserve follows the pending snoozes, Mark as Done clears the item's delivered notifications.

@MainActor
@Suite("Reminder adapter: QA fixes")
struct ReminderQAFixTests {
    private func plannedAlarm() -> PlannedAlarm {
        ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                        now: Fixture.now,
                                                        options: ReminderPlanningOptions(canScheduleAlarms: true))).alarms[0]
    }

    @Test func snoozedAlarmSurvivesReplansUntilTheDaemonDropsIt() async {
        let alarms = InMemoryAlarmClient()
        let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: alarms,
                                    store: InMemoryReminderStateStore())
        _ = await engine.run(Fixture.input(Fixture.database()))
        let alarm = plannedAlarm()
        await alarms.setState(alarm.alarmID, .countdown)                  // rang, user tapped Snooze
        let afterSnooze = await engine.run(Fixture.input(Fixture.database(), now: alarm.fireDate.addingTimeInterval(120)))
        #expect(await alarms.alarms[alarm.alarmID] != nil)
        #expect(await alarms.cancelled.isEmpty)
        #expect(afterSnooze.report.alarmsInProgressKept == 1)
        #expect(engine.state.activeAlarms.map(\.alarmID) == [alarm.alarmID])
        #expect(engine.state.alarmLedger.contains(alarm.alarmID))
        // Still snoozed a few minutes later: still kept (remembered through `activeAlarms`).
        _ = await engine.run(Fixture.input(Fixture.database(), now: alarm.fireDate.addingTimeInterval(400)))
        #expect(await alarms.alarms[alarm.alarmID] != nil)
        #expect(await alarms.cancelled.isEmpty)
        // Stopped: the daemon drops it → pruned from ledger and active list, nothing cancelled.
        await alarms.fire(alarm.alarmID)
        _ = await engine.run(Fixture.input(Fixture.database(), now: alarm.fireDate.addingTimeInterval(700)))
        #expect(engine.state.activeAlarms.isEmpty)
        #expect(!engine.state.alarmLedger.contains(alarm.alarmID))
        #expect(await alarms.cancelled.isEmpty)
    }

    @Test func replanAtTheFireInstantKeepsTheAlarmAndTheDueNotification() async {
        let alarms = InMemoryAlarmClient()
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: alarms, store: InMemoryReminderStateStore())
        let first = await engine.run(Fixture.input(Fixture.database()))
        let alarm = plannedAlarm()
        // A notification at its fire instant, still pending (being delivered): not removed, and still protected later.
        let due = first.plan.notifications[0]
        #expect(due.fireDate < alarm.fireDate)
        _ = await engine.run(Fixture.input(Fixture.database(), now: due.fireDate))
        #expect(await center.requests[due.id.rawValue] != nil)
        // Exactly at the alarm's fire instant, the daemon still says `.scheduled` (not alerting yet): kept.
        _ = await engine.run(Fixture.input(Fixture.database(), now: alarm.fireDate))
        #expect(await alarms.alarms[alarm.alarmID] != nil)
        #expect(await alarms.cancelled.isEmpty)
        #expect(await center.requests[due.id.rawValue] != nil)
    }

    @Test func inProgressAlarmOfACompletedExamIsCancelled() async {
        let alarms = InMemoryAlarmClient()
        let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: alarms,
                                    store: InMemoryReminderStateStore())
        _ = await engine.run(Fixture.input(Fixture.database()))
        let alarm = plannedAlarm()
        await alarms.setState(alarm.alarmID, .alerting)
        var exam = Fixture.exam
        exam.completedAt = alarm.fireDate
        _ = await engine.run(Fixture.input(Fixture.database(exams: [exam]), now: alarm.fireDate.addingTimeInterval(30)))
        #expect(await alarms.cancelled == [alarm.alarmID])
        #expect(engine.state.activeAlarms.isEmpty)
        #expect(engine.state.alarmLedger.isEmpty)
    }

    @Test func dueNotificationOfACompletedTaskIsRemoved() async {
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let first = await engine.run(Fixture.input(Fixture.database()))
        let essay = first.plan.notifications.first { $0.source == .task(Fixture.homework.id) }!
        var done = Fixture.homework
        done.completedAt = essay.fireDate
        _ = await engine.run(Fixture.input(Fixture.database(tasks: [done, Fixture.weekly]), now: essay.fireDate))
        #expect(await center.requests[essay.id.rawValue] == nil)
    }

    @Test func replanDateNeverCoincidesWithAFireInstant() {
        var plan = ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                                   now: Fixture.now,
                                                                   options: ReminderPlanningOptions(canScheduleAlarms: true)))
        let fires = plan.alarms.map(\.fireDate) + plan.notifications.map(\.fireDate)
        for fire in fires {
            plan.nextReplanDate = fire
            let date = BackgroundRefreshPolicy.replanDate(for: plan)
            #expect(date >= fire.addingTimeInterval(60))
            #expect(fires.allSatisfy { abs($0.timeIntervalSince(date)) >= 60 })
        }
        plan.nextReplanDate = Fixture.now.addingTimeInterval(7)              // nowhere near a fire instant: unchanged
        #expect(BackgroundRefreshPolicy.replanDate(for: plan) == Fixture.now.addingTimeInterval(7))
    }

    @Test func renderSignatureChangeReplacesEveryPlannerNotificationOnce() async {
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        var input = Fixture.input(Fixture.database())
        input.renderSignature = ReminderRenderSignature(language: "en", localeIdentifier: "en_GB", hourCycle: "auto",
                                                        timeZoneIdentifier: "Europe/Bratislava")
        let first = await engine.run(input)
        #expect(await engine.run(input).report.isNoOp)
        input.renderSignature?.language = "sk"
        let changed = await engine.run(input)
        #expect(changed.report.renderSignatureChanged)
        #expect(changed.report.notificationsRemoved == first.plan.notifications.count)
        #expect(changed.report.notificationsAdded == first.plan.notifications.count)
        #expect(await center.pendingRequests().count == first.plan.notifications.count)
        #expect(await engine.run(input).report.isNoOp)
        input.renderSignature?.hourCycle = "h12"
        #expect(await engine.run(input).report.renderSignatureChanged)
    }

    @Test func reserveFollowsPendingSnoozesWithoutChurn() async {
        let center = InMemoryNotificationCenterClient()
        let open = ReminderSource.task(Fixture.homework.id).rawValue
        for index in 0..<6 {
            await center.seedForeign(PendingNotificationInfo(id: "snooze.rem.00000000000000a\(index)",
                                                             userInfo: [ReminderUserInfo.source: open]))
        }
        let many = (0..<70).map { index in
            TaskItem(id: TaskItem.ID(Fixture.uuid(1000 + index)), meta: Fixture.meta, title: "Task \(index)", kind: .homework,
                     due: .dateTime(Fixture.today.adding(days: 2 + index % 12), LocalTime(hour: 8, minute: index % 60)!))
        }
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let database = Fixture.database(tasks: [Fixture.homework] + many)
        let first = await engine.run(Fixture.input(database))
        #expect(first.plan.notifications.count == 64 - 6)
        #expect(first.plan.isSaturated)
        #expect(await center.pendingRequests().count == 64)
        let second = await engine.run(Fixture.input(database))
        #expect(second.report.isNoOp)
        #expect(await center.pendingRequests().count == 64)
    }

    @Test func markDoneClearsTheItemsDeliveredNotifications() async {
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database()))
        let essay = result.plan.notifications.filter { $0.source == .task(Fixture.homework.id) }
        let other = result.plan.notifications.first { $0.source != .task(Fixture.homework.id) }!
        for planned in essay + [other] { await center.deliver(planned.id.rawValue) }
        await engine.removeDelivered(for: .task(Fixture.homework.id))
        let left = await center.deliveredNotifications().map(\.id)
        #expect(left == [other.id.rawValue])
    }
}
