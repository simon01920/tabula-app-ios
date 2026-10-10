// The Reminders health check model (PHASE3_PLAN §0.6; the screen itself is stage B4). Pure derivation from a snapshot
// of permission states, device state and the last applied plan; Linux-tested. Every row carries catalog keys (+ at most
// one argument list) and an optional action, so B4 only lays it out.
//
// Rows, in display order:
//   notifications   permission (problem when denied / not asked while reminders exist)
//   timeSensitive   only when a rule asks for Time Sensitive (warning when the system setting is off / unsupported)
//   alarms          only when a Loud-alarm rule is enabled (problem when denied, warning when not asked yet)
//   focus           info: allow-list hint
//   silentMode      info: Silent mode / Action button
//   lowPower        warning when on
//   backgroundRefresh warning when denied (restricted = info: the user cannot change it, UIKit docs)
//   pending         info: pending count against the 64 cap
//   saturation      warning: reminders that did not fit (planner notice)
//   alarmOverflow   warning: loud alarms delivered as notifications (planner notice)
//   hiddenApp       info, with loud alarms: alarms of hidden / Face ID-locked apps fail silently (ALARMKIT.md F6)
import Foundation
import TimetableCore

public enum ReminderHealthStatus: Int, Hashable, Sendable, Comparable, CaseIterable {
    case ok = 0, info = 1, warning = 2, problem = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A button the row offers.
public enum ReminderHealthAction: String, Hashable, Sendable, CaseIterable {
    /// `requestNotificationAuthorization()` (only while not determined; B4 shows its pre-explainer first).
    case requestNotifications
    /// `UIApplication.openNotificationSettingsURLString`.
    case openNotificationSettings
    /// `AlarmClient.requestAuthorization()` (only while not determined).
    case requestAlarms
    /// `UIApplication.openSettingsURLString` (alarms, background refresh).
    case openAppSettings

    /// Catalog key of the button title.
    public var titleKey: String {
        switch self {
        case .requestNotifications: return "health.action.allowNotifications"
        case .openNotificationSettings, .openAppSettings: return "health.action.openSettings"
        case .requestAlarms: return "health.action.allowAlarms"
        }
    }
}

public struct ReminderHealthItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case notifications, timeSensitive, alarms, focus, silentMode, lowPower, backgroundRefresh, pending, saturation,
             alarmOverflow, hiddenApp
    }

    public var kind: Kind
    public var status: ReminderHealthStatus
    public var titleKey: String
    /// Catalog key (a format when `detail` has arguments).
    public var detailKey: String
    /// Arguments for `detailKey` (rendered with `LocalizedTextRenderer`); empty for plain keys.
    public var detail: LocalizedText
    public var action: ReminderHealthAction?

    public var id: Kind { kind }

    public init(kind: Kind, status: ReminderHealthStatus, titleKey: String, detail: LocalizedText,
                action: ReminderHealthAction? = nil) {
        self.kind = kind
        self.status = status
        self.titleKey = titleKey
        self.detailKey = detail.key
        self.detail = detail
        self.action = action
    }
}

/// Everything the health check reads.
public struct ReminderHealthInput: Hashable, Sendable {
    public var notifications: NotificationSettingsSnapshot
    public var alarmAuthorization: AlarmAuthorization
    public var device: DeviceReminderState
    /// All pending requests of the app (planner + snoozes + others).
    public var pendingCount: Int
    /// The system cap (64).
    public var pendingCap: Int
    /// The last applied plan (`nil` before the first run).
    public var lastPlan: ReminderPlan?
    /// Some enabled rule or item override asks for Time Sensitive (and the policy allows it).
    public var usesTimeSensitive: Bool
    /// Some enabled rule asks for a loud alarm and loud alarms are on in settings.
    public var usesLoudAlarms: Bool
    /// There is anything to remind about (enabled rules exist).
    public var hasReminders: Bool

    public init(notifications: NotificationSettingsSnapshot, alarmAuthorization: AlarmAuthorization,
                device: DeviceReminderState, pendingCount: Int, pendingCap: Int = 64, lastPlan: ReminderPlan?,
                usesTimeSensitive: Bool, usesLoudAlarms: Bool, hasReminders: Bool) {
        self.notifications = notifications
        self.alarmAuthorization = alarmAuthorization
        self.device = device
        self.pendingCount = pendingCount
        self.pendingCap = pendingCap
        self.lastPlan = lastPlan
        self.usesTimeSensitive = usesTimeSensitive
        self.usesLoudAlarms = usesLoudAlarms
        self.hasReminders = hasReminders
    }

    /// Fills the rule-derived flags from `database`.
    public init(notifications: NotificationSettingsSnapshot, alarmAuthorization: AlarmAuthorization,
                device: DeviceReminderState, pendingCount: Int, pendingCap: Int = 64, lastPlan: ReminderPlan?,
                database: TabulaDatabase?) {
        let usage = ReminderHealthCheck.usage(in: database)
        self.init(notifications: notifications, alarmAuthorization: alarmAuthorization, device: device,
                  pendingCount: pendingCount, pendingCap: pendingCap, lastPlan: lastPlan,
                  usesTimeSensitive: usage.timeSensitive, usesLoudAlarms: usage.loudAlarms, hasReminders: usage.any)
    }
}

public enum ReminderHealthCheck {
    /// Catalog keys used by the rows (validate_config.py checks they exist through the tests' key list).
    public static var allKeys: [String] {
        var keys = ReminderHealthItem.Kind.allCases.map { "health.\($0.rawValue).title" }
        keys += ["health.notifications.authorized", "health.notifications.denied", "health.notifications.notDetermined",
                 "health.notifications.provisional", "health.timeSensitive.enabled", "health.timeSensitive.disabled",
                 "health.timeSensitive.notSupported", "health.alarms.authorized", "health.alarms.denied",
                 "health.alarms.notDetermined", "health.alarms.unavailable", "health.focus.detail",
                 "health.silentMode.detail", "health.lowPower.on", "health.lowPower.off", "health.backgroundRefresh.available",
                 "health.backgroundRefresh.denied", "health.backgroundRefresh.restricted", "health.pending.detail",
                 "health.hiddenApp.detail", ReminderL10n.noticeSaturated, ReminderL10n.noticeAlarmLimit]
        keys += ReminderHealthAction.allCases.map(\.titleKey)
        return Array(Set(keys)).sorted()
    }

    /// The rows for `input`.
    public static func evaluate(_ input: ReminderHealthInput) -> [ReminderHealthItem] {
        var items: [ReminderHealthItem] = []
        items.append(notificationsRow(input))
        if input.usesTimeSensitive { items.append(timeSensitiveRow(input)) }
        if input.usesLoudAlarms { items.append(alarmsRow(input)) }
        items.append(ReminderHealthItem(kind: .focus, status: .info, titleKey: "health.focus.title",
                                        detail: LocalizedText(key: "health.focus.detail")))
        items.append(ReminderHealthItem(kind: .silentMode, status: .info, titleKey: "health.silentMode.title",
                                        detail: LocalizedText(key: "health.silentMode.detail")))
        items.append(ReminderHealthItem(kind: .lowPower, status: input.device.isLowPowerModeEnabled ? .warning : .ok,
                                        titleKey: "health.lowPower.title",
                                        detail: LocalizedText(key: input.device.isLowPowerModeEnabled ? "health.lowPower.on"
                                                                                                     : "health.lowPower.off")))
        items.append(backgroundRefreshRow(input))
        items.append(ReminderHealthItem(kind: .pending, status: .info, titleKey: "health.pending.title",
                                        detail: LocalizedText(key: "health.pending.detail",
                                                              args: [.integer(input.pendingCount), .integer(input.pendingCap)])))
        if let notice = input.lastPlan?.saturationNotice {
            items.append(ReminderHealthItem(kind: .saturation, status: .warning, titleKey: "health.saturation.title",
                                            detail: notice))
        }
        if let notice = input.lastPlan?.alarmOverflowNotice {
            items.append(ReminderHealthItem(kind: .alarmOverflow, status: .warning, titleKey: "health.alarmOverflow.title",
                                            detail: notice))
        }
        if input.usesLoudAlarms {
            items.append(ReminderHealthItem(kind: .hiddenApp, status: .info, titleKey: "health.hiddenApp.title",
                                            detail: LocalizedText(key: "health.hiddenApp.detail")))
        }
        return items
    }

    /// The worst status among `items` (`.ok` when empty).
    public static func overall(_ items: [ReminderHealthItem]) -> ReminderHealthStatus {
        items.map(\.status).max() ?? .ok
    }

    private static func notificationsRow(_ input: ReminderHealthInput) -> ReminderHealthItem {
        let title = "health.notifications.title"
        switch input.notifications.authorization {
        case .authorized, .ephemeral:
            return ReminderHealthItem(kind: .notifications, status: .ok, titleKey: title,
                                      detail: LocalizedText(key: "health.notifications.authorized"))
        case .provisional:
            return ReminderHealthItem(kind: .notifications, status: .warning, titleKey: title,
                                      detail: LocalizedText(key: "health.notifications.provisional"),
                                      action: .openNotificationSettings)
        case .denied:
            return ReminderHealthItem(kind: .notifications, status: .problem, titleKey: title,
                                      detail: LocalizedText(key: "health.notifications.denied"),
                                      action: .openNotificationSettings)
        case .notDetermined, .unknown:
            return ReminderHealthItem(kind: .notifications, status: input.hasReminders ? .warning : .info, titleKey: title,
                                      detail: LocalizedText(key: "health.notifications.notDetermined"),
                                      action: .requestNotifications)
        }
    }

    private static func timeSensitiveRow(_ input: ReminderHealthInput) -> ReminderHealthItem {
        let title = "health.timeSensitive.title"
        switch input.notifications.timeSensitive {
        case .enabled:
            return ReminderHealthItem(kind: .timeSensitive, status: .ok, titleKey: title,
                                      detail: LocalizedText(key: "health.timeSensitive.enabled"))
        case .disabled:
            return ReminderHealthItem(kind: .timeSensitive, status: .warning, titleKey: title,
                                      detail: LocalizedText(key: "health.timeSensitive.disabled"),
                                      action: .openNotificationSettings)
        case .notSupported, .unknown:
            return ReminderHealthItem(kind: .timeSensitive, status: .warning, titleKey: title,
                                      detail: LocalizedText(key: "health.timeSensitive.notSupported"))
        }
    }

    private static func alarmsRow(_ input: ReminderHealthInput) -> ReminderHealthItem {
        let title = "health.alarms.title"
        switch input.alarmAuthorization {
        case .authorized:
            return ReminderHealthItem(kind: .alarms, status: .ok, titleKey: title,
                                      detail: LocalizedText(key: "health.alarms.authorized"))
        case .denied:
            return ReminderHealthItem(kind: .alarms, status: .problem, titleKey: title,
                                      detail: LocalizedText(key: "health.alarms.denied"), action: .openAppSettings)
        case .notDetermined:
            return ReminderHealthItem(kind: .alarms, status: .warning, titleKey: title,
                                      detail: LocalizedText(key: "health.alarms.notDetermined"), action: .requestAlarms)
        case .unavailable:
            return ReminderHealthItem(kind: .alarms, status: .warning, titleKey: title,
                                      detail: LocalizedText(key: "health.alarms.unavailable"))
        }
    }

    private static func backgroundRefreshRow(_ input: ReminderHealthInput) -> ReminderHealthItem {
        let title = "health.backgroundRefresh.title"
        switch input.device.backgroundRefresh {
        case .available, .unknown:
            return ReminderHealthItem(kind: .backgroundRefresh, status: .ok, titleKey: title,
                                      detail: LocalizedText(key: "health.backgroundRefresh.available"))
        case .denied:
            return ReminderHealthItem(kind: .backgroundRefresh, status: .warning, titleKey: title,
                                      detail: LocalizedText(key: "health.backgroundRefresh.denied"),
                                      action: .openAppSettings)
        case .restricted:
            // UIKit docs: don't warn when restricted (the user cannot enable it, e.g. parental controls).
            return ReminderHealthItem(kind: .backgroundRefresh, status: .info, titleKey: title,
                                      detail: LocalizedText(key: "health.backgroundRefresh.restricted"))
        }
    }

    /// Which tiers the user's enabled rules and item overrides ask for.
    public static func usage(in database: TabulaDatabase?) -> (any: Bool, timeSensitive: Bool, loudAlarms: Bool) {
        guard let database else { return (false, false, false) }
        let rules = database.reminderRules.filter { !$0.isDeleted && $0.isEnabled }
        let overrideTiers = database.tasks.filter { !$0.isDeleted && !$0.isCompleted }.compactMap { $0.reminderOverride }
            .filter(\.isEnabled).compactMap(\.tier)
            + database.exams.filter { !$0.isDeleted && !$0.isCompleted }.compactMap { $0.reminderOverride }
            .filter(\.isEnabled).compactMap(\.tier)
        let tiers = rules.map(\.tier) + overrideTiers
        let settings = database.settings
        let timeSensitive = settings.timeSensitivePolicy.isEnabled
            && tiers.contains { $0.effective == .timeSensitive || $0.effective == .alarm }
        let userAlarm = rules.contains { $0.tier.effective == .alarm && ($0.origin == .user || settings.alarmPolicy.allowsPresetRules) }
            || overrideTiers.contains { $0.effective == .alarm }
        return (!rules.isEmpty, timeSensitive, settings.alarmPolicy.isEnabled && userAlarm)
    }
}
