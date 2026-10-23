// What the adapter remembers between runs (Phase 3 Stage A): the last APPLIED plan (the values that are pending in
// the system right now), the ledger of loud-alarm ids it scheduled, and the alarm limit it learned from
// `maximumLimitReached`. Persisted as one Codable value (App Group UserDefaults on device, in memory in seed mode).
// Pure Swift + Foundation, Linux-tested.
import Foundation
import TimetableCore

/// A loud-alarm limit learned from AlarmKit refusing an alarm (`maximumLimitReached`). AlarmKit's limit is dynamic
/// and undocumented (ALARMKIT.md F5), so the learned value expires and the default is tried again later.
public struct LearnedAlarmLimit: Hashable, Sendable, Codable {
    /// Planner alarms that were scheduled when AlarmKit refused the next one (≥ 0).
    public var count: Int
    public var learnedAt: Date

    /// How long a learned limit is trusted.
    public static let validity: TimeInterval = 24 * 60 * 60

    public init(count: Int, learnedAt: Date) {
        self.count = max(0, count)
        self.learnedAt = learnedAt
    }

    /// The soft limit to plan with at `now`: the learned count while valid (never above `defaultLimit`), else
    /// `defaultLimit`.
    public func softLimit(defaultLimit: Int, now: Date) -> Int {
        guard now.timeIntervalSince(learnedAt) < Self.validity, now >= learnedAt else { return defaultLimit }
        return min(defaultLimit, count)
    }
}

/// What rendered notification text depends on besides the plan: when any of it changes, every pending planner
/// notification is replaced so its language, date/time format and wording are current (QA Stage A finding 2).
public struct ReminderRenderSignature: Hashable, Sendable, Codable {
    /// The bundle's chosen localization (`Bundle.main.preferredLocalizations.first`).
    public var language: String
    /// The formatter's locale identifier.
    public var localeIdentifier: String
    /// `AppSettings.hourCycle.rawValue`.
    public var hourCycle: String
    /// The plan's zone identifier.
    public var timeZoneIdentifier: String
    /// The loud alarms' button policy (`AlarmSecondaryAction.policyID`, Phase 4 B3 final QA m8): the alarm diff compares
    /// planned values only, not buttons, so a policy change (a build with App Intents metadata, `doneReplacesSnooze`)
    /// changes the signature and every scheduled alarm is cancelled and scheduled again once with the new buttons.
    /// Optional: a state saved before B3 decodes as `nil`, which differs from every policy → one re-schedule.
    public var alarmButtons: String?

    public init(language: String, localeIdentifier: String, hourCycle: String, timeZoneIdentifier: String,
                alarmButtons: String? = nil) {
        self.language = language
        self.localeIdentifier = localeIdentifier
        self.hourCycle = hourCycle
        self.timeZoneIdentifier = timeZoneIdentifier
        self.alarmButtons = alarmButtons
    }
}

/// Counts and problems of one apply pass (debug screen, health check).
public struct ReminderApplyReport: Hashable, Sendable, Codable {
    public var notificationsAdded: Int
    public var notificationsRemoved: Int
    public var notificationsUnchanged: Int
    public var alarmsScheduled: Int
    public var alarmsCancelled: Int
    public var alarmsUnchanged: Int
    /// Snooze requests removed because their task/exam was completed or deleted.
    public var staleSnoozesRemoved: Int
    /// `add` failures (id + message).
    public var notificationFailures: [String]
    /// Alarms that could not be scheduled (reminder ids).
    public var alarmFailures: [String]
    /// `true` when AlarmKit answered `maximumLimitReached` in this run.
    public var alarmLimitReached: Bool
    /// In-progress (ringing / snoozed / paused) alarms kept despite not being in the new plan.
    public var alarmsInProgressKept: Int
    /// `true` when the render signature changed and every planner notification was replaced.
    public var renderSignatureChanged: Bool

    public init(notificationsAdded: Int = 0, notificationsRemoved: Int = 0, notificationsUnchanged: Int = 0,
                alarmsScheduled: Int = 0, alarmsCancelled: Int = 0, alarmsUnchanged: Int = 0, staleSnoozesRemoved: Int = 0,
                notificationFailures: [String] = [], alarmFailures: [String] = [], alarmLimitReached: Bool = false,
                alarmsInProgressKept: Int = 0, renderSignatureChanged: Bool = false) {
        self.notificationsAdded = notificationsAdded
        self.notificationsRemoved = notificationsRemoved
        self.notificationsUnchanged = notificationsUnchanged
        self.alarmsScheduled = alarmsScheduled
        self.alarmsCancelled = alarmsCancelled
        self.alarmsUnchanged = alarmsUnchanged
        self.staleSnoozesRemoved = staleSnoozesRemoved
        self.notificationFailures = notificationFailures
        self.alarmFailures = alarmFailures
        self.alarmLimitReached = alarmLimitReached
        self.alarmsInProgressKept = alarmsInProgressKept
        self.renderSignatureChanged = renderSignatureChanged
    }

    /// `true` when nothing had to change.
    public var isNoOp: Bool {
        notificationsAdded == 0 && notificationsRemoved == 0 && alarmsScheduled == 0 && alarmsCancelled == 0
            && staleSnoozesRemoved == 0
    }
}

/// The adapter's persisted state.
public struct AppliedReminderState: Hashable, Sendable, Codable {
    /// Bumped when the shape changes incompatibly (an unreadable state is treated as "nothing applied").
    /// 2: `activeAlarms` and `renderSignature` (Stage A QA fixes).
    public static let currentVersion = 2

    public var version: Int
    /// The plan as applied: only notifications/alarms that are really pending (failed adds are left out so the next
    /// run retries them). `nil` = nothing applied yet (first launch, lost state).
    public var plan: ReminderPlan?
    /// Alarm ids scheduled from plans that may still exist in the daemon, ascending. Written **before** scheduling,
    /// so an alarm can never exist without being in the ledger (a lost plan must not leave an orphan alarm ringing for
    /// a completed exam). Debug-probe and test alarms are never in it and therefore never cancelled by the diff.
    public var alarmLedger: [UUID]
    /// Planner alarms that are past their fire time but still in the daemon (ringing, snoozed, paused). Kept so a
    /// re-plan never cancels them unless their task/exam is no longer open; pruned when the daemon drops them.
    public var activeAlarms: [PlannedAlarm]
    /// The render signature of the applied notifications (`nil` before the first run).
    public var renderSignature: ReminderRenderSignature?
    public var learnedAlarmLimit: LearnedAlarmLimit?
    public var lastReport: ReminderApplyReport?
    /// When the last run finished.
    public var lastRunAt: Date?

    public init(plan: ReminderPlan? = nil, alarmLedger: [UUID] = [], activeAlarms: [PlannedAlarm] = [],
                renderSignature: ReminderRenderSignature? = nil, learnedAlarmLimit: LearnedAlarmLimit? = nil,
                lastReport: ReminderApplyReport? = nil, lastRunAt: Date? = nil) {
        version = Self.currentVersion
        self.plan = plan
        self.alarmLedger = alarmLedger.sorted { $0.uuidString < $1.uuidString }
        self.activeAlarms = activeAlarms
        self.renderSignature = renderSignature
        self.learnedAlarmLimit = learnedAlarmLimit
        self.lastReport = lastReport
        self.lastRunAt = lastRunAt
    }

    /// The empty state.
    public static let empty = AppliedReminderState()
}

/// Where `AppliedReminderState` lives.
public protocol ReminderStateStore: Sendable {
    func load() -> AppliedReminderState?
    func save(_ state: AppliedReminderState)
}

/// In memory (tests, `-TabulaSeed`).
public final class InMemoryReminderStateStore: ReminderStateStore, @unchecked Sendable {
    // Guarded by `lock`; the class holds no other state.
    private let lock = NSLock()
    private var state: AppliedReminderState?

    public init(_ state: AppliedReminderState? = nil) {
        self.state = state
    }

    public func load() -> AppliedReminderState? { lock.withLock { state } }
    public func save(_ state: AppliedReminderState) { lock.withLock { self.state = state } }
}

/// JSON under one UserDefaults key (the App Group suite on device, like the HLC).
public final class UserDefaultsReminderStateStore: ReminderStateStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; the class holds no other state.
    private let defaults: UserDefaults
    public static let key = "tabula.reminders.state.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> AppliedReminderState? {
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(AppliedReminderState.self, from: data),
              state.version == AppliedReminderState.currentVersion else { return nil }
        return state
    }

    public func save(_ state: AppliedReminderState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
