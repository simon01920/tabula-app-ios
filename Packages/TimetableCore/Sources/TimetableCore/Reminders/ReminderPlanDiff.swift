import Foundation

/// The changes that turn one set of scheduled reminders into another, keyed by `ReminderID`.
///
/// An item whose ID exists on both sides but whose value differs (re-mapped `fireDate` after a time-zone
/// change, new text, new tier) is **changed**: it appears in both `toRemove` and `toAdd`, so the adapter
/// removes the old request first and then adds the new one. This is the safe order for AlarmKit too
/// (cancel, then schedule with the same `Alarm.ID`). Never "remove all and re-add": community reports tie
/// that pattern to misfiring alarms (docs/spikes/ALARMKIT.md §1).
public struct ReminderDiff<Item: Hashable & Sendable & Identifiable>: Hashable, Sendable where Item.ID == ReminderID {
    /// New or changed items, ascending by ID.
    public var toAdd: [Item]
    /// IDs that disappeared or changed, ascending.
    public var toRemove: [ReminderID]
    /// IDs present on both sides with identical values, ascending.
    public var unchanged: [ReminderID]
    /// IDs present on both sides with different values (subset of `toAdd`/`toRemove`), ascending.
    public var changed: [ReminderID]

    /// Creates a diff.
    public init(toAdd: [Item], toRemove: [ReminderID], unchanged: [ReminderID], changed: [ReminderID]) {
        self.toAdd = toAdd
        self.toRemove = toRemove
        self.unchanged = unchanged
        self.changed = changed
    }

    /// `true` when nothing needs to change.
    public var isEmpty: Bool { toAdd.isEmpty && toRemove.isEmpty }

    /// Diffs `old` against `new` by ID, comparing whole values. Duplicate IDs keep the first occurrence.
    public static func between(old: [Item], new: [Item]) -> ReminderDiff {
        let oldByID = Self.index(old)
        let newByID = Self.index(new)
        var toAdd: [Item] = []
        var toRemove: [ReminderID] = []
        var unchanged: [ReminderID] = []
        var changed: [ReminderID] = []
        for id in oldByID.keys.sorted() where newByID[id] == nil { toRemove.append(id) }
        for id in newByID.keys.sorted() {
            let item = newByID[id]!
            guard let previous = oldByID[id] else {
                toAdd.append(item)
                continue
            }
            if previous == item {
                unchanged.append(id)
            } else {
                changed.append(id)
                toRemove.append(id)
                toAdd.append(item)
            }
        }
        return ReminderDiff(toAdd: toAdd, toRemove: toRemove.sorted(), unchanged: unchanged, changed: changed)
    }

    /// Diffs the identifiers currently pending in the system against `new`, when the previous plan's values
    /// are unknown (first launch, lost cache). Identifiers that are not planner IDs (`ReminderID.isPlannerID`)
    /// are ignored — they belong to snoozes or other features. Every planned item whose ID is pending counts
    /// as unchanged (values cannot be compared); prefer `between(old:new:)` with the last applied plan.
    public static func reconciling(pending identifiers: [String], new: [Item]) -> ReminderDiff {
        let pending = Set(identifiers.filter(ReminderID.isPlannerID).map(ReminderID.init(rawValue:)))
        let newByID = Self.index(new)
        let toRemove = pending.filter { newByID[$0] == nil }.sorted()
        var toAdd: [Item] = []
        var unchanged: [ReminderID] = []
        for id in newByID.keys.sorted() {
            if pending.contains(id) { unchanged.append(id) } else { toAdd.append(newByID[id]!) }
        }
        return ReminderDiff(toAdd: toAdd, toRemove: toRemove, unchanged: unchanged, changed: [])
    }

    private static func index(_ items: [Item]) -> [ReminderID: Item] {
        var result: [ReminderID: Item] = [:]
        for item in items where result[item.id] == nil { result[item.id] = item }
        return result
    }
}

/// Notification and alarm diffs between two plans, for the Phase 3 adapters.
public struct ReminderPlanDiff: Hashable, Sendable {
    /// Local-notification changes.
    public var notifications: ReminderDiff<PlannedNotification>
    /// Loud-alarm changes.
    public var alarms: ReminderDiff<PlannedAlarm>

    /// Creates a plan diff.
    public init(notifications: ReminderDiff<PlannedNotification>, alarms: ReminderDiff<PlannedAlarm>) {
        self.notifications = notifications
        self.alarms = alarms
    }

    /// `true` when neither side needs a change.
    public var isEmpty: Bool { notifications.isEmpty && alarms.isEmpty }

    /// Diffs two plans by ID. `old == nil` (nothing applied yet) adds everything.
    public static func diff(old: ReminderPlan?, new: ReminderPlan) -> ReminderPlanDiff {
        ReminderPlanDiff(notifications: .between(old: old?.notifications ?? [], new: new.notifications),
                         alarms: .between(old: old?.alarms ?? [], new: new.alarms))
    }
}
