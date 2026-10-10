// The add/remove/cancel/schedule operations that turn what is pending in the system into a new plan (Stage A).
// Pure, Linux-tested. The rules:
//
// Notifications (ids = planner `ReminderID`s):
//   - "known" = the last applied plan's notifications that are still pending (delivered or externally removed ones
//     are gone and simply count as absent);
//   - `ReminderDiff.between(old: known, new:)` → new, changed (remove + add under the same id) and removed ids;
//   - `ReminderDiff.reconciling(pending:new:)` → planner ids pending in the system that the new plan no longer has
//     (also catches a lost or stale state);
//   - planner ids pending in the system whose values are unknown (not in "known") but that the new plan has are
//     removed and re-added, so their text/tier/time is guaranteed current;
//   - ids that are not planner ids (`snooze.…`, `tabula.test.…`, debug probes, anything foreign) are never touched,
//     except snoozes of a task/exam that is no longer open (stale snoozes).
// Alarms (ids = `PlannedAlarm.alarmID`, deterministic UUIDs):
//   - same scheme against the daemon's alarm list, but only alarms in the adapter's ledger (or whose id the new plan
//     derives itself) are ever cancelled (debug probe and test alarms have random ids). Changed alarms are cancelled, then scheduled again with the same id
//     (diff, never wipe-and-reschedule: ALARMKIT.md §1 community reports).
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

    public init(removeNotificationIDs: [String], addNotifications: [PlannedNotification],
                unchangedNotifications: [PlannedNotification], staleSnoozeIDs: [String], cancelAlarmIDs: [UUID],
                scheduleAlarms: [PlannedAlarm], unchangedAlarms: [PlannedAlarm]) {
        self.removeNotificationIDs = removeNotificationIDs
        self.addNotifications = addNotifications
        self.unchangedNotifications = unchangedNotifications
        self.staleSnoozeIDs = staleSnoozeIDs
        self.cancelAlarmIDs = cancelAlarmIDs
        self.scheduleAlarms = scheduleAlarms
        self.unchangedAlarms = unchangedAlarms
    }

    /// `true` when nothing needs to change.
    public var isEmpty: Bool {
        removeNotificationIDs.isEmpty && addNotifications.isEmpty && cancelAlarmIDs.isEmpty && scheduleAlarms.isEmpty
    }

    /// Computes the operations.
    /// - Parameters:
    ///   - lastApplied: the persisted plan as applied (`nil` = unknown).
    ///   - alarmLedger: alarm ids the adapter scheduled earlier.
    ///   - plan: the new plan.
    ///   - pending: the system's pending requests.
    ///   - scheduledAlarmIDs: the daemon's alarms, `nil` when unreadable (then the ledger is assumed to be scheduled).
    ///   - openSources: `ReminderSource.rawValue`s of open (not deleted, not completed) tasks and exams; snoozes of
    ///     other task/exam sources are stale. `nil` = keep every snooze.
    public static func compute(lastApplied: ReminderPlan?, alarmLedger: [UUID], plan: ReminderPlan,
                               pending: [PendingNotificationInfo], scheduledAlarmIDs: [UUID]?,
                               openSources: Set<String>?) -> ReminderApplyOperations {
        // Notifications.
        let pendingIDs = pending.map(\.id)
        let pendingPlanner = Set(pendingIDs.filter(ReminderID.isPlannerID))
        let known = (lastApplied?.notifications ?? []).filter { pendingPlanner.contains($0.id.rawValue) }
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
                guard let raw = request.userInfo[ReminderUserInfo.source], let source = ReminderSource(rawValue: raw),
                      source.isCompletable, !openSources.contains(raw) else { continue }
                stale.append(request.id)
            }
        }
        remove.formUnion(stale)

        // Alarms.
        let ledger = Set(alarmLedger)
        let scheduled = scheduledAlarmIDs.map(Set.init) ?? ledger
        let ours = scheduled.intersection(ledger)
        let knownAlarms = (lastApplied?.alarms ?? []).filter { ours.contains($0.alarmID) }
        let knownAlarmIDs = Set(knownAlarms.map(\.alarmID))
        let alarmDiff = ReminderDiff.between(old: knownAlarms, new: plan.alarms)
        let newAlarmIDs = Set(plan.alarms.map(\.alarmID))
        let byReminder = Dictionary(knownAlarms.map { ($0.id, $0.alarmID) }, uniquingKeysWith: { first, _ in first })
        var cancel = Set(alarmDiff.toRemove.compactMap { byReminder[$0] })
        // Ours in the daemon but values unknown: cancel; re-scheduled below when still planned.
        cancel.formUnion(ours.subtracting(knownAlarmIDs))
        let unchangedAlarmSet = Set(alarmDiff.unchanged)
        let unchangedAlarmIDs = Set(knownAlarms.filter { unchangedAlarmSet.contains($0.id) }.map(\.alarmID))
        // A planned id already in the daemon but missing from the ledger (ledger lost): the id is derived from our own
        // reminder key, so it is ours — cancel before scheduling it again rather than relying on undocumented
        // duplicate-id behaviour.
        cancel.formUnion(scheduled.intersection(newAlarmIDs).subtracting(unchangedAlarmIDs))
        let scheduleIDs = Set(alarmDiff.toAdd.map(\.alarmID))
        let schedule = plan.alarms.filter { scheduleIDs.contains($0.alarmID) }
        let unchangedAlarms = plan.alarms.filter { unchangedAlarmSet.contains($0.id) }

        return ReminderApplyOperations(
            removeNotificationIDs: remove.sorted(), addNotifications: add, unchangedNotifications: unchanged,
            staleSnoozeIDs: stale.sorted(), cancelAlarmIDs: cancel.sorted { $0.uuidString < $1.uuidString },
            scheduleAlarms: schedule, unchangedAlarms: unchangedAlarms)
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
}
