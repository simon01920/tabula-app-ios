// The real `NotificationCenterClient` (Phase 3 Stage A): a thin mapping from TimetableUI's Sendable specs to
// UserNotifications. No decisions here (the planner and `ReminderEngine` make them).
// APIs (developer.apple.com DocC JSON, checked 2026-10-10; docs/ENVIRONMENT.md §21):
//   UNUserNotificationCenter.current(), pendingNotificationRequests() async, add(_:) async throws,
//   removePendingNotificationRequests(withIdentifiers:), removeDeliveredNotifications(withIdentifiers:),
//   notificationSettings() async, requestAuthorization(options:) async throws -> Bool, setNotificationCategories(_:);
//   UNMutableNotificationContent (title, subtitle, body, sound, interruptionLevel (iOS 15), threadIdentifier,
//   categoryIdentifier, userInfo (plist types only), targetContentIdentifier); UNNotificationSound.default;
//   UNCalendarNotificationTrigger(dateMatching:repeats:) + nextTriggerDate(); UNTimeIntervalNotificationTrigger;
//   UNNotificationRequest(identifier:content:trigger:); UNNotificationCategory(identifier:actions:intentIdentifiers:options:);
//   UNNotificationAction(identifier:title:options:icon:) + UNNotificationActionIcon(systemImageName:) (iOS 15);
//   UNNotificationSettings (.authorizationStatus, .timeSensitiveSetting (iOS 15), .alertSetting, .soundSetting).
//
// Trigger time zone: Apple's docs do not say how `UNCalendarNotificationTrigger` treats `DateComponents.timeZone`.
// We pass year…second together with an explicit Gregorian `calendar` and `timeZone` (the plan's zone), so the
// components denote one absolute instant (see `NotificationRequestSpec`). Wall-clock times that occur twice (the DST
// fall-back hour) cannot be expressed by components alone: when the components do not map back to the planned
// instant, a `UNTimeIntervalNotificationTrigger` for the exact interval is used instead.
//
// Concurrency: UNUserNotificationCenter / UNNotificationRequest / UNNotificationSettings are not documented as
// Sendable, so every call happens inside these nonisolated methods and only Sendable values leave them.
import Foundation
import TimetableCore
import TimetableUI
import UserNotifications

struct LiveNotificationCenterClient: NotificationCenterClient {
    func pendingRequests() async -> [PendingNotificationInfo] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.map { request in
            PendingNotificationInfo(id: request.identifier,
                                    nextTriggerDate: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                                    userInfo: Self.strings(request.content.userInfo))
        }
    }

    func add(_ spec: NotificationRequestSpec) async -> NotificationAddOutcome {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        if let subtitle = spec.subtitle { content.subtitle = subtitle }
        content.body = spec.body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = spec.interruption == .timeSensitive ? .timeSensitive : .active
        content.threadIdentifier = spec.threadID
        content.categoryIdentifier = spec.categoryID
        content.userInfo = spec.userInfo
        content.targetContentIdentifier = spec.userInfo[ReminderUserInfo.source]
        let request = UNNotificationRequest(identifier: spec.id, content: content, trigger: Self.trigger(for: spec))
        do {
            try await UNUserNotificationCenter.current().add(request)
            return .added
        } catch {
            return .failed(String(describing: error))
        }
    }

    func removePending(ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeDelivered(ids: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func settings() async -> NotificationSettingsSnapshot {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationSettingsSnapshot(authorization: Self.map(settings.authorizationStatus),
                                            timeSensitive: Self.map(settings.timeSensitiveSetting),
                                            alert: Self.map(settings.alertSetting),
                                            sound: Self.map(settings.soundSetting))
    }

    /// Alert + sound only ("Request only the authorization options that you plan to use"; no badges). The deprecated
    /// `.timeSensitive` option is never requested (ALARMKIT.md F27).
    func requestAuthorization() async -> NotificationAuthorization {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await settings().authorization
    }

    func registerCategories(_ categories: [NotificationCategorySpec]) async {
        let set = Set(categories.map { category in
            UNNotificationCategory(
                identifier: category.id,
                actions: category.actions.map { action in
                    UNNotificationAction(identifier: action.id, title: action.title,
                                         options: action.opensApp ? [.foreground] : [],
                                         icon: UNNotificationActionIcon(systemImageName: action.systemImage))
                },
                intentIdentifiers: [])
        })
        UNUserNotificationCenter.current().setNotificationCategories(set)
    }

    // MARK: Mapping

    static func trigger(for spec: NotificationRequestSpec) -> UNNotificationTrigger {
        let parts = spec.trigger
        if parts.instant == spec.fireDate, let zone = TimeZone(identifier: parts.timeZoneIdentifier) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let components = DateComponents(calendar: calendar, timeZone: zone, year: parts.year, month: parts.month,
                                            day: parts.day, hour: parts.hour, minute: parts.minute, second: parts.second)
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        // Ambiguous wall-clock time (DST fall-back) or unknown zone: the exact interval (must be > 0).
        return UNTimeIntervalNotificationTrigger(timeInterval: max(1, spec.fireDate.timeIntervalSinceNow), repeats: false)
    }

    static func strings(_ info: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in info {
            if let key = key as? String, let value = value as? String { result[key] = value }
        }
        return result
    }

    static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    static func map(_ setting: UNNotificationSetting) -> NotificationSettingState {
        switch setting {
        case .enabled: return .enabled
        case .disabled: return .disabled
        case .notSupported: return .notSupported
        @unknown default: return .unknown
        }
    }
}

extension DeliveredNotification {
    /// The Sendable copy of a delivered notification (called synchronously inside the delegate callbacks).
    init(_ notification: UNNotification) {
        let request = notification.request
        let content = request.content
        self.init(requestID: request.identifier, title: content.title, subtitle: content.subtitle.isEmpty ? nil : content.subtitle,
                  body: content.body,
                  interruption: content.interruptionLevel == .timeSensitive ? .timeSensitive : .active,
                  threadID: content.threadIdentifier, categoryID: content.categoryIdentifier,
                  userInfo: LiveNotificationCenterClient.strings(content.userInfo))
    }
}
