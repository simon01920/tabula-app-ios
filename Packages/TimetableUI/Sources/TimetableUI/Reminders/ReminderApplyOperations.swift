// The add/remove/cancel/schedule operations that turn what is pending in the system into a new plan (Stage A).
// Pure, Linux-tested. The rules:
//
// Notifications (ids = planner `ReminderID`s):
//   - "known" = the last applied plan's notifications that are still pending (delivered or externally removed ones
//     are gone and simply count as absent); with `valuesKnown == false` (render signature changed: language, locale,
//     hour cycle or zone) nothing counts as known, so every pending planner notification is replaced;
//   - `ReminderDiff.between(old: known, new:)` → new, changed (remove + add under the same id) and removed ids;
//   - `ReminderDiff.reconciling(pending:new:)` → planner ids pending in the system that the new plan no longer has
//     (also catches a lost or stale state);
//   - planner ids pending in the system whose values are unknown (not in "known") but that the new plan has are
//     removed and re-added, so their text/tier/time is guaranteed current;
//   - ids that are not planner ids (`snooze.…`, `tabula.test.…`, debug probes, anything foreign) are never touched,
//     except snoozes of a task/exam that is no longer open (stale snoozes).
// Alarms (ids = `PlannedAlarm.alarmID`, deterministic UUIDs):
//   - only alarms in the adapter's ledger (or whose id the new plan derives itself and that are merely scheduled) are
//     ever cancelled; debug-probe and test alarms have random ids and are never touched;
//   - IN PROGRESS = the daemon reports it alerting / snoozed (countdown) / paused, or its applied fire date is at or
//     before `now`. The planner only plans fire dates after `now`, so such alarms are never in the new plan — they are
//     KEPT (never cancelled by a re-plan: QA Stage A blocking finding), unless their task/exam is no longer open
//     (completed or deleted), and remembered in `lingeringAlarms` until the daemon stops listing them;
//   - scheduled (future) alarms are diffed like notifications: changed ones are cancelled, then scheduled again with
//     the same id (diff, never wipe-and-reschedule: ALARMKIT.md §1 community reports).
import Foundation
import TimetableCore

public struct ReminderApplyOperations: Hashable, Sendable {
    /// Pending ids to remove, ascending (planner ids + stale snoozes).
    public var removeNotificationIDs: [String]
    /// Requests to add, in plan order (ascending fire date).
    public var addNotifications: [PlannedNotification]
    /// Planner notifications already pending with identical values.
    public var unchangedNotifications: [PlannedNotification]
    /// Snooze ids among `removeNotificationIDs`.
    public var staleSnoozeIDs: [String]
    /// Alarm ids to cancel, ascending by uuidString.
    public var cancelAlarmIDs: [UUID]
    /// Alarms to schedule, in plan order.
    public var scheduleAlarms: [PlannedAlarm]
    /// Planner alarms already scheduled with identical values.
    public var unchangedAlarms: [PlannedAlarm]
    /// In-progress planner alarms that are kept (not in the new plan, not cancelled), ascending by fire date.
    public var lingeringAlarms: [PlannedAlarm]
    /// In-progress alarms kept, including ledger alarms whose values are unknown.
    public var alarmsInProgressKept: Int
    /// Due planner notifications (fire date ≤ now, still pending) that are kept although the new plan no longer has them.
    public var dueNotificationsKept: [PlannedNotification]

    public init(removeNotificationIDs: [String], addNotifications: [PlannedNotification],
                unchangedNotifications: [PlannedNotification], staleSnoozeIDs: [String], cancelAlarmIDs: [UUID],
                scheduleAlarms: [PlannedAlarm], unchangedAlarms: [PlannedAlarm], lingeringAlarms: [PlannedAlarm] = [],
                alarmsInProgressKept: Int = 0, dueNotificationsKept: [PlannedNotification] = []) {
        self.removeNotificationIDs = removeNotificationIDs
        self.addNotifications = addNotifications
        self.unchangedNotifications = unchangedNotifications
        self.staleSnoozeIDs = staleSnoozeIDs
        self.cancelAlarmIDs = cancelAlarmIDs
        self.scheduleAlarms = scheduleAlarms
        self.unchangedAlarms = unchangedAlarms
        self.lingeringAlarms = lingeringAlarms
        self.alarmsInProgressKept = alarmsInProgressKept
        self.dueNotificationsKept = dueNotificationsKept
    }

    /// `true` when nothing needs to change.
    public var isEmpty: Bool {
        removeNotificationIDs.isEmpty && addNotifications.isEmpty && cancelAlarmIDs.isEmpty && scheduleAlarms.isEmpty
    }

    /// Computes the operations.
    /// - Parameters:
    ///   - lastApplied: the persisted plan as applied (`nil` = unknown).
    ///   - activeAlarms: in-progress alarms remembered from earlier runs (`AppliedReminderState.activeAlarms`).
    ///   - alarmLedger: alarm ids the adapter scheduled earlier.
    ///   - plan: the new plan.
    ///   - pending: the system's pending requests.
    ///   - scheduledAlarms: the daemon's alarms with their states, `nil` when unreadable (then the ledger is assumed to be
    ///     scheduled and "in progress" is decided by fire date alone).
    ///   - openSources: `ReminderSource.rawValue`s of open (not deleted, not completed) tasks and exams; snoozes and
    ///     in-progress alarms of other task/exam sources are stale. `nil` = keep them all.
    ///   - now: the planning instant.
    ///   - valuesKnown: `false` when the render signature changed — nothing pending counts as up to date.
    public static func compute(lastApplied: ReminderPlan?, activeAlarms: [PlannedAlarm] = [], alarmLedger: [UUID],
                               plan: ReminderPlan, pending: [PendingNotificationInfo],
                               scheduledAlarms: [ScheduledAlarmInfo]?, openSources: Set<String>?, now: Date,
                               valuesKnown: Bool = true) -> ReminderApplyOperations {
        // Notifications.
        let pendingIDs = pending.map(\.id)
        let pendingPlanner = Set(pendingIDs.filter(ReminderID.isPlannerID))
        let known = valuesKnown ? (lastApplied?.notifications ?? []).filter { pendingPlanner.contains($0.id.rawValue) } : []
        let knownIDs = Set(known.map(\.id.rawValue))
        let between = ReminderDiff.between(old: known, new: plan.notifications)
        let reconciled = ReminderDiff.reconciling(pending: pendingIDs, new: plan.notifications)
        let newIDs = Set(plan.notifications.map(\.id.rawValue))
        let unknownValues = pendingPlanner.subtracting(knownIDs).intersection(newIDs)
        var remove = Set(between.toRemove.map(\.rawValue))
        remove.formUnion(reconciled.toRemove.map(\.rawValue))
        remove.formUnion(unknownValues)
        let addIDs = Set(between.toAdd.map(\.id.rawValue))
        let unchangedSet = Set(between.unchanged.map(\.rawValue))
        let add = plan.notifications.filter { addIDs.contains($0.id.rawValue) }
        let unchanged = plan.notifications.filter { unchangedSet.contains($0.id.rawValue) }
        var stale: [String] = []
        if let openSources {
            for request in pending where ReminderRequestID.isSnooze(request.id) {
                guard let raw = request.userInfo[ReminderUserInfo.source], isClosed(raw, openSources) else { continue }
                stale.append(request.id)
            }
        }
        remove.formUnion(stale)
        // Due but not yet delivered (fire date at or before `now`, still pending): the planner drops them because they
        // are not in the future — removing them would swallow a reminder that is being delivered right now. Keep them
        // unless their task/exam is no longer open.
        var dueKept: [PlannedNotification] = []
        for planned in lastApplied?.notifications ?? []
        where planned.fireDate <= now && pendingPlanner.contains(planned.id.rawValue) && !newIDs.contains(planned.id.rawValue) {
            if let openSources, isClosed(planned.source.rawValue, openSources) { continue }
            remove.remove(planned.id.rawValue)
            dueKept.append(planned)
        }

        // Alarms.
        let ledger = Set(alarmLedger)
        var daemonState: [UUID: ScheduledAlarmInfo.State] = [:]
        for info in scheduledAlarms ?? alarmLedger.map({ ScheduledAlarmInfo(id: $0) }) where daemonState[info.id] == nil {
            daemonState[info.id] = info.state
        }
        let statesKnown = scheduledAlarms != nil
        let ours = Set(daemonState.keys).intersection(ledger)
        var knownByID: [UUID: PlannedAlarm] = [:]
        for alarm in (lastApplied?.alarms ?? []) + activeAlarms where ours.contains(alarm.alarmID) && knownByID[alarm.alarmID] == nil {
            knownByID[alarm.alarmID] = alarm
        }
        let newAlarmIDs = Set(plan.alarms.map(\.alarmID))
        func inProgress(_ id: UUID, fireDate: Date?) -> Bool {
            if statesKnown, let state = daemonState[id], state != .scheduled { return true }
            if let fireDate, fireDate <= now { return true }
            return false
        }
        var cancel = Set<UUID>()
        var lingering: [PlannedAlarm] = []
        var keptInProgress = 0
        var knownScheduled: [PlannedAlarm] = []
        for alarm in knownByID.values {
            if inProgress(alarm.alarmID, fireDate: alarm.fireDate), !newAlarmIDs.contains(alarm.alarmID) {
                if let openSources, isClosed(alarm.source.rawValue, openSources) {
                    cancel.insert(alarm.alarmID)              // its exam/task was completed or deleted
                } else {
                    lingering.append(alarm)
                    keptInProgress += 1
                }
            } else {
                knownScheduled.append(alarm)
            }
        }
        // Ours in the daemon but values unknown: keep when in progress (cannot know its item), else cancel; still
        // planned ones are scheduled again below.
        for id in ours where knownByID[id] == nil {
            if inProgress(id, fireDate: nil) { keptInProgress += 1 } else { cancel.insert(id) }
        }
        let comparable = valuesKnown ? knownScheduled : []
        if !valuesKnown { cancel.formUnion(knownScheduled.map(\.alarmID)) }
        let alarmDiff = ReminderDiff.between(old: comparable, new: plan.alarms)
        let byReminder = Dictionary(comparable.map { ($0.id, $0.alarmID) }, uniquingKeysWith: { first, _ in first })
        cancel.formUnion(alarmDiff.toRemove.compactMap { byReminder[$0] })
        let unchangedAlarmSet = Set(alarmDiff.unchanged)
        let unchangedAlarmIDs = Set(comparable.filter { unchangedAlarmSet.contains($0.id) }.map(\.alarmID))
        // A planned id already in the daemon but missing from the ledger (ledger lost): the id is derived from our own
        // reminder key, so it is ours — cancel a merely scheduled one before scheduling it again rather than relying on
        // undocumented duplicate-id behaviour.
        for id in Set(daemonState.keys).intersection(newAlarmIDs).subtracting(unchangedAlarmIDs)
        where !inProgress(id, fireDate: nil) {
            cancel.insert(id)
        }
        let scheduleIDs = Set(alarmDiff.toAdd.map(\.alarmID))
        let schedule = plan.alarms.filter { scheduleIDs.contains($0.alarmID) }
        let unchangedAlarms = plan.alarms.filter { unchangedAlarmSet.contains($0.id) }

        return ReminderApplyOperations(
            removeNotificationIDs: remove.sorted(), addNotifications: add, unchangedNotifications: unchanged,
            staleSnoozeIDs: stale.sorted(), cancelAlarmIDs: cancel.sorted { $0.uuidString < $1.uuidString },
            scheduleAlarms: schedule, unchangedAlarms: unchangedAlarms,
            lingeringAlarms: lingering.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) },
            alarmsInProgressKept: keptInProgress, dueNotificationsKept: dueKept)
    }

    /// `true` for a task/exam source that is not open any more.
    private static func isClosed(_ raw: String, _ openSources: Set<String>) -> Bool {
        guard let source = ReminderSource(rawValue: raw), source.isCompletable else { return false }
        return !openSources.contains(raw)
    }

    /// Open task/exam sources of `database` (for `openSources`).
    public static func openSources(in database: TabulaDatabase) -> Set<String> {
        var result = Set<String>()
        for task in database.tasks where !task.isDeleted && !task.isCompleted {
            result.insert(ReminderSource.task(task.id).rawValue)
        }
        for exam in database.exams where !exam.isDeleted && !exam.isCompleted {
            result.insert(ReminderSource.exam(exam.id).rawValue)
        }
        return result
    }

    /// Non-planner pending requests (snoozes, tests, other features): they share the 64 slots, so the planner's
    /// reserve is `max(4, this count)` (QA Stage A finding 3).
    public static func foreignPendingCount(_ pending: [PendingNotificationInfo]) -> Int {
        pending.filter { !ReminderID.isPlannerID($0.id) }.count
    }
}
