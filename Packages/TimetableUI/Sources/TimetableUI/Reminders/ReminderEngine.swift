// One re-plan pass (Phase 3 Stage A): planner input → `ReminderPlanner.plan` → operations against what is really
// pending → apply through the clients → persist the applied state. Never decides timing itself
// (PHASE3_PLAN §0.2). Main-actor isolated (the app calls it from `ReminderCoordinator`); the clients are Sendable and
// do their own hopping. Linux-tested with the in-memory clients.
//
// Loud-alarm limits: AlarmKit's limit is dynamic (ALARMKIT.md F5). When `schedule` answers `maximumLimitReached`, the
// engine learns the number of planner alarms that fit (`LearnedAlarmLimit`, valid 24 h) and plans once more with that
// soft limit, so the planner itself demotes the rest to Time Sensitive notifications and reports them in
// `ReminderPlan.alarmOverflow` (the in-app notice). Same for an alarm authorisation lost between the check and the
// call (plan again with `canScheduleAlarms == false`).
//
// Performance (Phase 10 P4):
// - The planner (`ReminderInputBuilder.input` + `ReminderPlanner.plan`, pure value types, all Sendable) runs in a
//   detached task at the caller's priority, so a re-plan no longer blocks the main thread while it resolves 14+ days of
//   lessons. Client calls (UNUserNotificationCenter, AlarmKit) and every write of `state` stay on the main actor.
// - The state is saved ONCE per run (it was up to five times). The only extra save is the documented write-ahead of
//   the alarm ledger, and only when a pass is about to schedule an alarm id the ledger does not hold yet. A run cut
//   short before its final save loses only the render signature / learned limit / applied plan of that run: the next
//   run re-diffs against what is really pending (the same path as a lost state), and the ledger already lists every
//   alarm that may exist.
//
// Re-entrancy (QA fix after Phase 10): `run` suspends at every client call, so two calls could interleave and diff
// against the same `state`. A call that arrives while a run is in progress is coalesced like
// `ReminderCoordinator.runCoalesced`: its input (the newest wins) is run once more after the current run, and every
// caller returns the result of that last run.
import Foundation
import TimetableCore

/// Inputs of one run.
public struct ReminderRunInput: Sendable {
    public var database: TabulaDatabase
    /// `ScheduleResolver.all(database:context:)` for `database` and `context`.
    public var resolvers: [ScheduleResolver]
    public var context: CalendarContext
    /// Renders catalog keys in the app's language.
    public var renderer: LocalizedTextRenderer
    public var now: Date
    /// `EntitlementsProvider.isAllowed(.loudAlarms)`.
    public var loudAlarmsEntitled: Bool
    public var horizonDays: Int
    /// `maxPending` = the system cap; `reserved` = the minimum reserve. The engine raises the reserve to the number of
    /// non-planner requests actually pending (snoozes, tests), so they never push planner requests out.
    public var budget: NotificationBudget
    public var defaultAlarmSoftLimit: Int
    /// Language / locale / hour cycle / zone the text is rendered with; a change re-adds every planner notification.
    public var renderSignature: ReminderRenderSignature?

    public init(database: TabulaDatabase, resolvers: [ScheduleResolver], context: CalendarContext,
                renderer: LocalizedTextRenderer, now: Date, loudAlarmsEntitled: Bool, horizonDays: Int = 14,
                budget: NotificationBudget = .iOSDefault, defaultAlarmSoftLimit: Int = 10,
                renderSignature: ReminderRenderSignature? = nil) {
        self.database = database
        self.resolvers = resolvers
        self.context = context
        self.renderer = renderer
        self.now = now
        self.loudAlarmsEntitled = loudAlarmsEntitled
        self.horizonDays = horizonDays
        self.budget = budget
        self.defaultAlarmSoftLimit = defaultAlarmSoftLimit
        self.renderSignature = renderSignature
    }
}

/// Outcome of one run.
public struct ReminderRunResult: Sendable, Hashable {
    /// The plan as applied (failed adds left out).
    public var plan: ReminderPlan
    public var report: ReminderApplyReport
    public var alarmAuthorization: AlarmAuthorization
    /// Planner requests (notifications + loud alarms) in the last computed plan, counted before any add failed. The
    /// in-context permission offer uses it: while the permission is "not determined" adds may fail or never show, but
    /// the plan still says a reminder would be scheduled (`ReminderPermissionOffer`).
    public var plannedRequestCount: Int = 0
    /// Gentle in-app notices (saturation, loud alarms that fell back to notifications), in that order.
    public var notices: [LocalizedText] {
        [plan.saturationNotice, plan.alarmOverflowNotice].compactMap { $0 }
    }

    /// When to re-plan next: `nextReplanDate`, kept ≥ 1 min away from every fire instant
    /// (`BackgroundRefreshPolicy.replanDate(for:)`).
    public var replanDate: Date { BackgroundRefreshPolicy.replanDate(for: plan) }
}

@MainActor
public final class ReminderEngine {
    public let notifications: any NotificationCenterClient
    public let alarms: any AlarmClient
    private let store: any ReminderStateStore
    /// The persisted state (loaded once, saved once per run, plus the ledger's write-ahead).
    public private(set) var state: AppliedReminderState
    /// A run is in progress (`run(_:)` coalesces further calls).
    public private(set) var isRunning = false
    /// The newest input that arrived while a run was in progress; run once more after it.
    private var queuedInput: ReminderRunInput?
    /// Callers waiting for the coalesced run.
    private var waiters: [CheckedContinuation<ReminderRunResult, Never>] = []
    /// Number of callers waiting for a coalesced run (tests, debug).
    public var waitingRunCount: Int { waiters.count }

    public init(notifications: any NotificationCenterClient, alarms: any AlarmClient, store: any ReminderStateStore) {
        self.notifications = notifications
        self.alarms = alarms
        self.store = store
        state = store.load() ?? .empty
    }

    /// Re-plans and applies. Safe to call repeatedly: a second run with the same input changes nothing. Never two at
    /// once: a call during a run waits, its input (the newest of the waiting ones) runs right after, and every caller
    /// returns that last run's result.
    public func run(_ input: ReminderRunInput) async -> ReminderRunResult {
        if isRunning {
            queuedInput = input
            return await withCheckedContinuation { waiters.append($0) }
        }
        isRunning = true
        var result = await runOnce(input)
        while let queued = queuedInput {
            queuedInput = nil
            result = await runOnce(queued)
        }
        isRunning = false
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume(returning: result) }
        return result
    }

    /// One run (`run(_:)` guarantees it never overlaps another).
    private func runOnce(_ input: ReminderRunInput) async -> ReminderRunResult {
        let authorization = await alarms.authorization()
        var canScheduleAlarms = authorization == .authorized && input.loudAlarmsEntitled
        var softLimit = state.learnedAlarmLimit?.softLimit(defaultLimit: input.defaultAlarmSoftLimit, now: input.now)
            ?? input.defaultAlarmSoftLimit
        let builder = ReminderRequestBuilder(renderer: input.renderer, context: input.context)
        let openSources = ReminderApplyOperations.openSources(in: input.database)
        var report = ReminderApplyReport()
        var applied: ReminderPlan
        var plannedRequestCount = 0
        var attempt = 0
        while true {
            attempt += 1
            let pending = await notifications.pendingRequests()
            let daemonAlarms = await alarms.scheduledAlarms()
            let budget = NotificationBudget(maxPending: input.budget.maxPending,
                                            reserved: max(input.budget.reserved,
                                                          ReminderApplyOperations.foreignPendingCount(pending)))
            let options = ReminderPlanningOptions(horizonDays: input.horizonDays, budget: budget,
                                                  alarmSoftLimit: softLimit, canScheduleAlarms: canScheduleAlarms)
            let plan = await Self.plan(database: input.database, resolvers: input.resolvers, context: input.context,
                                       now: input.now, options: options)
            plannedRequestCount = plan.notifications.count + plan.alarms.count
            let valuesKnown = input.renderSignature == nil || input.renderSignature == state.renderSignature
            if !valuesKnown { report.renderSignatureChanged = true }
            let ops = ReminderApplyOperations.compute(lastApplied: state.plan, activeAlarms: state.activeAlarms,
                                                      alarmLedger: state.alarmLedger, plan: plan, pending: pending,
                                                      scheduledAlarms: daemonAlarms, openSources: openSources,
                                                      now: input.now, valuesKnown: valuesKnown)
            let pass = await apply(ops, plan: plan, builder: builder, daemonAlarms: daemonAlarms.map { $0.map(\.id) })
            if input.renderSignature != nil {
                state.renderSignature = input.renderSignature   // saved with the run (final save)
            }
            applied = pass.applied
            report.notificationsAdded += pass.report.notificationsAdded
            report.notificationsRemoved += pass.report.notificationsRemoved
            report.notificationsUnchanged = pass.report.notificationsUnchanged
            report.alarmsScheduled += pass.report.alarmsScheduled
            report.alarmsCancelled += pass.report.alarmsCancelled
            report.alarmsUnchanged = pass.report.alarmsUnchanged
            report.staleSnoozesRemoved += pass.report.staleSnoozesRemoved
            report.notificationFailures += pass.report.notificationFailures
            report.alarmFailures = pass.report.alarmFailures
            report.alarmsInProgressKept = pass.report.alarmsInProgressKept
            guard attempt < 2 else { break }
            if pass.report.alarmLimitReached {
                report.alarmLimitReached = true
                softLimit = applied.alarms.count
                state.learnedAlarmLimit = LearnedAlarmLimit(count: softLimit, learnedAt: input.now)   // final save
                continue
            }
            if pass.alarmsUnauthorized {
                canScheduleAlarms = false
                continue
            }
            break
        }
        state.lastReport = report
        state.lastRunAt = input.now
        store.save(state)
        return ReminderRunResult(plan: applied, report: report, alarmAuthorization: authorization,
                                 plannedRequestCount: plannedRequestCount)
    }

    /// The pure planning step, off the main actor (only Sendable values cross; the result is a value).
    nonisolated static func plan(database: TabulaDatabase, resolvers: [ScheduleResolver], context: CalendarContext,
                                 now: Date, options: ReminderPlanningOptions) async -> ReminderPlan {
        await Task.detached(priority: Task.currentPriority) {
            ReminderPlanner.plan(ReminderInputBuilder.input(database: database, resolvers: resolvers, context: context,
                                                            now: now, options: options))
        }.value
    }

    private struct Pass {
        var applied: ReminderPlan
        var report: ReminderApplyReport
        var alarmsUnauthorized: Bool
    }

    private func apply(_ ops: ReminderApplyOperations, plan: ReminderPlan, builder: ReminderRequestBuilder,
                       daemonAlarms: [UUID]?) async -> Pass {
        var report = ReminderApplyReport()
        // Notifications: remove first (changed ids are re-added under the same id), then add.
        if !ops.removeNotificationIDs.isEmpty {
            await notifications.removePending(ids: ops.removeNotificationIDs)
        }
        report.notificationsRemoved = ops.removeNotificationIDs.count - ops.staleSnoozeIDs.count
        report.staleSnoozesRemoved = ops.staleSnoozeIDs.count
        report.notificationsUnchanged = ops.unchangedNotifications.count
        var added = Set<ReminderID>()
        for planned in ops.addNotifications {
            switch await notifications.add(builder.request(for: planned)) {
            case .added:
                added.insert(planned.id)
            case .failed(let message):
                report.notificationFailures.append("\(planned.id.rawValue): \(message)")
            }
        }
        report.notificationsAdded = added.count

        // Alarms: ledger first (write-ahead), then cancel, then schedule in plan order (soonest first). The write-ahead
        // is saved only when it adds an id (an alarm must never exist without being in the persisted ledger).
        let previousLedger = Set(state.alarmLedger)
        let aheadLedger = previousLedger.union(ops.scheduleAlarms.map(\.alarmID))
        state.alarmLedger = Self.sorted(aheadLedger)
        if aheadLedger.count > previousLedger.count { store.save(state) }
        for id in ops.cancelAlarmIDs { await alarms.cancel(id: id) }
        report.alarmsCancelled = ops.cancelAlarmIDs.count
        report.alarmsUnchanged = ops.unchangedAlarms.count
        report.alarmsInProgressKept = ops.alarmsInProgressKept
        var scheduled = Set<ReminderID>()
        var stop: AlarmScheduleOutcome?
        for planned in ops.scheduleAlarms {
            if stop != nil {
                report.alarmFailures.append(planned.id.rawValue)
                continue
            }
            let outcome = await alarms.schedule(builder.alarm(for: planned))
            switch outcome {
            case .scheduled:
                scheduled.insert(planned.id)
            case .limitReached, .notAuthorized:
                stop = outcome
                report.alarmFailures.append(planned.id.rawValue)
            case .failed:
                report.alarmFailures.append(planned.id.rawValue)
            }
        }
        report.alarmsScheduled = scheduled.count
        report.alarmLimitReached = stop == .limitReached

        // The applied subset of the plan.
        let keptNotifications = Set(ops.unchangedNotifications.map(\.id)).union(added)
        let keptAlarms = Set(ops.unchangedAlarms.map(\.id)).union(scheduled)
        var applied = plan
        // Kept due notifications stay in the applied plan, so the next run protects them too (until delivered).
        applied.notifications = ops.dueNotificationsKept + plan.notifications.filter { keptNotifications.contains($0.id) }
        applied.alarms = plan.alarms.filter { keptAlarms.contains($0.id) }

        // Ledger: what the applied plan holds, plus earlier ledger alarms still in the daemon that were not cancelled.
        let stillThere = (daemonAlarms.map(Set.init) ?? previousLedger).intersection(previousLedger)
            .subtracting(ops.cancelAlarmIDs)
        state.alarmLedger = Self.sorted(Set(applied.alarms.map(\.alarmID)).union(stillThere))
        state.activeAlarms = ops.lingeringAlarms
        state.plan = applied   // saved with the run (final save in `run`)
        return Pass(applied: applied, report: report, alarmsUnauthorized: stop == .notAuthorized)
    }

    private static func sorted(_ ids: Set<UUID>) -> [UUID] { ids.sorted { $0.uuidString < $1.uuidString } }

    // MARK: Ad-hoc requests

    /// Registers the notification categories (call once per launch; titles follow the app language).
    public func registerCategories(renderer: LocalizedTextRenderer, context: CalendarContext) async {
        await notifications.registerCategories(ReminderRequestBuilder(renderer: renderer, context: context).categories())
    }

    /// Adds the snooze for a delivered notification (`nil` for non-snooze actions).
    public func snooze(_ delivered: DeliveredNotification, action: ReminderAction, context: CalendarContext,
                       renderer: LocalizedTextRenderer, now: Date) async -> NotificationAddOutcome? {
        guard let date = action.snoozeDate(now: now, context: context) else { return nil }
        let spec = ReminderRequestBuilder(renderer: renderer, context: context).snooze(delivered, until: date)
        return await notifications.add(spec)
    }

    /// Phase 10 B12: tells the user right away that a notification "Mark as Done" could not be saved.
    public func notifyMarkDoneFailed(_ delivered: DeliveredNotification, context: CalendarContext,
                                     renderer: LocalizedTextRenderer, now: Date) async -> NotificationAddOutcome {
        await notifications.add(ReminderRequestBuilder(renderer: renderer, context: context)
            .markDoneFailedNotice(for: delivered, now: now))
    }

    /// Removes every delivered notification of `source` from Notification Center (after Mark as Done).
    public func removeDelivered(for source: ReminderSource) async {
        let ids = await notifications.deliveredNotifications()
            .filter { $0.userInfo[ReminderUserInfo.source] == source.rawValue }.map(\.id)
        if !ids.isEmpty { await notifications.removeDelivered(ids: ids) }
    }

    /// Schedules the health check's test notification (5 s).
    public func sendTestNotification(renderer: LocalizedTextRenderer, context: CalendarContext,
                                     now: Date) async -> NotificationAddOutcome {
        await notifications.add(ReminderRequestBuilder(renderer: renderer, context: context).testNotification(now: now))
    }

    /// Schedules the health check's test alarm (60 s; random id, never cancelled by the diff).
    public func sendTestAlarm(renderer: LocalizedTextRenderer, context: CalendarContext, now: Date) async -> AlarmScheduleOutcome {
        await alarms.schedule(ReminderRequestBuilder(renderer: renderer, context: context).testAlarm(now: now))
    }
}
