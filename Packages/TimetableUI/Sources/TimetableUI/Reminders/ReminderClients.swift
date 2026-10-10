// The seams between the reminder adapter and the operating system (Phase 3 Stage A, PHASE3_PLAN §0.2).
//
// The planner (TimetableCore `ReminderPlanner`) decides WHAT and WHEN. The adapter only applies its plan through two
// thin clients:
//   - `NotificationCenterClient`: real = `UNUserNotificationCenter` (App/Sources/Reminders/LiveNotificationCenterClient.swift),
//     fake = `InMemoryNotificationCenterClient` (tests, `-TabulaSeed` screenshot mode).
//   - `AlarmClient`: real = AlarmKit `AlarmManager.shared` (App/Sources/Reminders/LiveAlarmClient.swift),
//     fake = `InMemoryAlarmClient`.
// Everything that crosses the seam is a plain Sendable value (no UserNotifications / AlarmKit types), so the whole
// apply logic is unit-tested on Linux. Pure Swift + Foundation.
import Foundation
import TimetableCore

// MARK: - Notifications

/// `UNNotificationInterruptionLevel` subset the planner can ask for (`.critical` is never used: NOTIFICATIONS.md).
public enum NotificationInterruption: String, Hashable, Sendable, Codable {
    /// `.active`: standard delivery.
    case active
    /// `.timeSensitive`: breaks through Focus / Scheduled Summary when the entitlement and the user allow it.
    case timeSensitive
}

/// Wall-clock components of a calendar trigger, interpreted in `timeZoneIdentifier` (see `NotificationRequestSpec`).
public struct NotificationTriggerTime: Hashable, Sendable, Codable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int
    /// IANA identifier of the plan's zone (`CalendarContext.timeZone`).
    public var timeZoneIdentifier: String

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, timeZoneIdentifier: String) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// The components of `instant` in `zone` (Gregorian), i.e. exactly one absolute instant once the zone is attached.
    public init(instant: Date, zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1, hour: parts.hour ?? 0,
                  minute: parts.minute ?? 0, second: parts.second ?? 0, timeZoneIdentifier: zone.identifier)
    }

    /// The instant these components denote (Gregorian calendar in `timeZoneIdentifier`), `nil` for an unknown zone.
    public var instant: Date? {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(timeZone: zone, year: year, month: month, day: day, hour: hour,
                                                  minute: minute, second: second))
    }
}

/// Everything needed to build one `UNNotificationRequest`.
///
/// **Trigger semantics (decision, Phase 3 Stage A):** the real client builds a non-repeating
/// `UNCalendarNotificationTrigger` whose `DateComponents` carry year…second **and** an explicit Gregorian `calendar` and
/// `timeZone` = the plan's zone, i.e. one absolute instant (`fireDate`). Apple's docs do not state how the trigger
/// treats `DateComponents.timeZone` (checked 2026-10-10, docs/ENVIRONMENT.md §21); attaching it removes any dependence
/// on the device zone at delivery time. A time-zone change re-plans (planner IDs are wall-clock based, so the same IDs
/// get a re-mapped `fireDate`; the diff replaces them). Until the app runs again after a zone change, a pending
/// notification fires at the previously planned instant (device checklist A-TZ rows).
public struct NotificationRequestSpec: Hashable, Sendable {
    /// Request identifier (`rem.…` from the planner, `snooze.rem.…` for snoozes, `tabula.test.…` for the test).
    public var id: String
    public var title: String
    public var subtitle: String?
    public var body: String
    public var interruption: NotificationInterruption
    /// `threadIdentifier` (groups an item's reminders).
    public var threadID: String
    /// `categoryIdentifier` (`ReminderCategory.rawValue`; empty = no actions).
    public var categoryID: String
    /// Plist-safe `userInfo` (see `ReminderUserInfo`).
    public var userInfo: [String: String]
    /// When to deliver (absolute).
    public var fireDate: Date
    /// The calendar-trigger components for `fireDate` in the plan's zone.
    public var trigger: NotificationTriggerTime

    public init(id: String, title: String, subtitle: String?, body: String, interruption: NotificationInterruption,
                threadID: String, categoryID: String, userInfo: [String: String], fireDate: Date,
                trigger: NotificationTriggerTime) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.interruption = interruption
        self.threadID = threadID
        self.categoryID = categoryID
        self.userInfo = userInfo
        self.fireDate = fireDate
        self.trigger = trigger
    }
}

/// One pending request as the system reports it.
public struct PendingNotificationInfo: Hashable, Sendable {
    public var id: String
    /// `UNCalendarNotificationTrigger.nextTriggerDate()` (nil for other trigger kinds or when unknown).
    public var nextTriggerDate: Date?
    /// String values of the request's `userInfo` (non-string values are dropped).
    public var userInfo: [String: String]

    public init(id: String, nextTriggerDate: Date? = nil, userInfo: [String: String] = [:]) {
        self.id = id
        self.nextTriggerDate = nextTriggerDate
        self.userInfo = userInfo
    }
}

/// `UNAuthorizationStatus`.
public enum NotificationAuthorization: String, Hashable, Sendable, Codable, CaseIterable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown

    /// `true` when the system delivers our notifications in some form.
    public var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied, .unknown: return false
        }
    }
}

/// `UNNotificationSetting`.
public enum NotificationSettingState: String, Hashable, Sendable, Codable, CaseIterable {
    case enabled, disabled, notSupported, unknown
}

/// The parts of `UNNotificationSettings` the health check needs.
public struct NotificationSettingsSnapshot: Hashable, Sendable {
    public var authorization: NotificationAuthorization
    /// `timeSensitiveSetting` (iOS 15+). Without the paid-only entitlement the value is unverified (ALARMKIT.md Q4).
    public var timeSensitive: NotificationSettingState
    public var alert: NotificationSettingState
    public var sound: NotificationSettingState

    public init(authorization: NotificationAuthorization, timeSensitive: NotificationSettingState = .unknown,
                alert: NotificationSettingState = .unknown, sound: NotificationSettingState = .unknown) {
        self.authorization = authorization
        self.timeSensitive = timeSensitive
        self.alert = alert
        self.sound = sound
    }
}

/// One notification action button.
public struct NotificationActionSpec: Hashable, Sendable {
    /// `ReminderAction.rawValue`.
    public var id: String
    /// Localised button title.
    public var title: String
    /// SF Symbol for `UNNotificationActionIcon(systemImageName:)`.
    public var systemImage: String
    /// `.foreground` option (opens the app). Mark done / snooze run in the background.
    public var opensApp: Bool

    public init(id: String, title: String, systemImage: String, opensApp: Bool = false) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.opensApp = opensApp
    }
}

/// One notification category (`UNNotificationCategory`).
public struct NotificationCategorySpec: Hashable, Sendable {
    public var id: String
    public var actions: [NotificationActionSpec]

    public init(id: String, actions: [NotificationActionSpec]) {
        self.id = id
        self.actions = actions
    }
}

/// Result of adding one request.
public enum NotificationAddOutcome: Hashable, Sendable {
    case added
    case failed(String)
}

/// The notification centre as the adapter sees it. Implementations must be safe to call from any isolation.
public protocol NotificationCenterClient: Sendable {
    /// All pending requests of the app (planner, snooze, test and foreign ids alike).
    func pendingRequests() async -> [PendingNotificationInfo]
    /// Schedules one request (replaces a pending request with the same id, like the system does).
    func add(_ request: NotificationRequestSpec) async -> NotificationAddOutcome
    /// Removes pending requests by id (unknown ids are ignored).
    func removePending(ids: [String]) async
    /// Notifications currently shown in Notification Center (id + string userInfo; `nextTriggerDate` unused).
    func deliveredNotifications() async -> [PendingNotificationInfo]
    /// Removes delivered notifications from Notification Center by id.
    func removeDelivered(ids: [String]) async
    /// Current settings.
    func settings() async -> NotificationSettingsSnapshot
    /// Shows the system prompt (only from explicit UI, never at launch). Returns the resulting authorization.
    func requestAuthorization() async -> NotificationAuthorization
    /// Registers all categories at once (replaces the previous set).
    func registerCategories(_ categories: [NotificationCategorySpec]) async
}

// MARK: - Alarms

/// `AlarmManager.AuthorizationState`, plus `.unavailable` where AlarmKit does not exist.
public enum AlarmAuthorization: String, Hashable, Sendable, Codable, CaseIterable {
    case notDetermined, denied, authorized, unavailable
}

/// Everything needed to schedule one fixed-time loud alarm (`Alarm.Schedule.fixed(fireDate)`).
public struct AlarmSpec: Hashable, Sendable {
    /// `Alarm.ID` = `PlannedAlarm.alarmID` (deterministic from the reminder key).
    public var id: UUID
    /// The planner's `ReminderID.rawValue` (alarm metadata; the Live Activity has no other way to know it).
    public var reminderID: String
    /// When to ring (absolute; `.fixed` does not follow time-zone changes, ALARMKIT.md F15).
    public var fireDate: Date
    /// Rendered alert title.
    public var title: String
    /// Rendered secondary line (Live Activity).
    public var subtitle: String?
    /// Countdown title while snoozed.
    public var snoozedTitle: String
    /// `ReminderSource.rawValue`.
    public var sourceRawValue: String
    /// Snooze (post-alert countdown) length; `nil` = alert-only alarm without a Snooze button.
    public var snoozeSeconds: TimeInterval?

    public init(id: UUID, reminderID: String, fireDate: Date, title: String, subtitle: String?, snoozedTitle: String,
                sourceRawValue: String, snoozeSeconds: TimeInterval?) {
        self.id = id
        self.reminderID = reminderID
        self.fireDate = fireDate
        self.title = title
        self.subtitle = subtitle
        self.snoozedTitle = snoozedTitle
        self.sourceRawValue = sourceRawValue
        self.snoozeSeconds = snoozeSeconds
    }
}

/// One alarm as the AlarmKit daemon reports it (`Alarm.id` + `Alarm.state`).
public struct ScheduledAlarmInfo: Hashable, Sendable {
    /// `Alarm.State`, plus `.unknown` for future cases.
    public enum State: String, Hashable, Sendable, Codable {
        case scheduled, alerting, countdown, paused, unknown
    }

    public var id: UUID
    public var state: State

    public init(id: UUID, state: State = .scheduled) {
        self.id = id
        self.state = state
    }

    /// Ringing, snoozed (post-alert countdown) or paused: the alarm is in progress and must not be cancelled by a
    /// re-plan unless its item is no longer open.
    public var isInProgress: Bool { state != .scheduled }
}

/// Result of scheduling one alarm.
public enum AlarmScheduleOutcome: Hashable, Sendable {
    case scheduled
    /// `AlarmManager.AlarmError.maximumLimitReached`: the dynamic, undocumented limit (ALARMKIT.md F5).
    case limitReached
    /// Not authorised (denied or not determined: the adapter never triggers the implicit prompt).
    case notAuthorized
    case failed(String)
}

/// AlarmKit as the adapter sees it.
public protocol AlarmClient: Sendable {
    /// Current authorization (no prompt).
    func authorization() async -> AlarmAuthorization
    /// Shows the system prompt (only when the user picks a Loud-alarm rule). Returns the resulting state.
    func requestAuthorization() async -> AlarmAuthorization
    /// Every alarm of this app known to the daemon (planner, test and debug-probe alarms alike, in every state:
    /// scheduled, alerting, snoozed countdown, paused), or `nil` when the list cannot be read.
    func scheduledAlarms() async -> [ScheduledAlarmInfo]?
    /// Schedules one alarm. Must **not** prompt: implementations return `.notAuthorized` unless authorised.
    func schedule(_ alarm: AlarmSpec) async -> AlarmScheduleOutcome
    /// Cancels one alarm (unknown ids are ignored).
    func cancel(id: UUID) async
    /// Authorization changes (Settings toggles while the app runs).
    func authorizationUpdates() -> AsyncStream<AlarmAuthorization>
}

// MARK: - Background refresh / device state

/// `UIBackgroundRefreshStatus`.
public enum BackgroundRefreshState: String, Hashable, Sendable, Codable, CaseIterable {
    case available, denied, restricted, unknown
}

/// Values the health check reads from the device (real: UIKit / ProcessInfo; fake: fixed values).
public struct DeviceReminderState: Hashable, Sendable {
    public var isLowPowerModeEnabled: Bool
    public var backgroundRefresh: BackgroundRefreshState

    public init(isLowPowerModeEnabled: Bool, backgroundRefresh: BackgroundRefreshState) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.backgroundRefresh = backgroundRefresh
    }
}
