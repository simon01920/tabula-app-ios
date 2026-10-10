// Turns the planner's `PlannedNotification` / `PlannedAlarm` into client specs: renders the catalog keys + arguments
// through `LocalizedTextRenderer` (one catalog format per line, never concatenated), maps the effective tier to an
// interruption level and carries the ids the action handler needs in `userInfo`. Also builds snooze and test
// requests and the category/action set. Pure Swift + Foundation, Linux-tested.
import Foundation
import TimetableCore

/// `userInfo` keys of every request the app schedules (plist-safe strings only).
public enum ReminderUserInfo {
    /// The planner reminder id (`rem.…`), also on snoozes (the reminder that was snoozed).
    public static let reminderID = "tabula.reminderID"
    /// `ReminderSource.rawValue` (`task/<UUID>`, `exam/<UUID>`, `lesson/<id>`, `packTonight/<date>`).
    public static let source = "tabula.source"
    /// `planned`, `snooze` or `test`.
    public static let kind = "tabula.kind"

    public static let kindPlanned = "planned"
    public static let kindSnooze = "snooze"
    public static let kindTest = "test"
}

/// Identifier schemes of requests the adapter adds outside the plan. None of them passes `ReminderID.isPlannerID`,
/// so the plan diff never touches them (TimetableCore `ReminderDiff.reconciling`).
public enum ReminderRequestID {
    /// Prefix of snooze requests: `snooze.` + the snoozed planner id (`snooze.rem.0123456789abcdef`). One snooze per
    /// reminder: snoozing again replaces the pending one (same id).
    public static let snoozePrefix = "snooze."
    /// Prefix of the health check's test notification.
    public static let testPrefix = "tabula.test."

    /// The snooze id for `reminderID` (a planner id or, when snoozing a snooze, the id it was derived from).
    public static func snooze(for reminderID: String) -> String {
        snoozePrefix + (reminderID.hasPrefix(snoozePrefix) ? String(reminderID.dropFirst(snoozePrefix.count)) : reminderID)
    }

    /// `true` for ids created by `snooze(for:)`.
    public static func isSnooze(_ id: String) -> Bool { id.hasPrefix(snoozePrefix) }
}

/// The text and behaviour of a delivered notification, extracted from `UNNotificationResponse` (Sendable copy).
public struct DeliveredNotification: Hashable, Sendable {
    public var requestID: String
    public var title: String
    public var subtitle: String?
    public var body: String
    public var interruption: NotificationInterruption
    public var threadID: String
    public var categoryID: String
    public var userInfo: [String: String]

    public init(requestID: String, title: String, subtitle: String?, body: String, interruption: NotificationInterruption,
                threadID: String, categoryID: String, userInfo: [String: String]) {
        self.requestID = requestID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.interruption = interruption
        self.threadID = threadID
        self.categoryID = categoryID
        self.userInfo = userInfo
    }

    /// The source item (`userInfo[source]`), if any.
    public var source: ReminderSource? { userInfo[ReminderUserInfo.source].flatMap(ReminderSource.init(rawValue:)) }
}

/// Builds client specs from plans.
public struct ReminderRequestBuilder: Sendable {
    /// Snooze length of loud alarms (post-alert countdown). 9 minutes, the iOS Clock default.
    public static let alarmSnoozeSeconds: TimeInterval = 9 * 60

    /// Catalog keys owned by the adapter (the planner's own keys are `ReminderL10n.allKeys`).
    public enum Keys {
        /// "Snoozed: %@" — countdown title of a snoozed loud alarm. Arg: the alarm title.
        public static let alarmSnoozedTitle = "alarm.snoozed.title"
        /// "Test reminder" / body — health check test notification.
        public static let testTitle = "reminder.test.title"
        public static let testBody = "reminder.test.body"
        /// "Tabula test alarm" — health check test alarm.
        public static let testAlarmTitle = "reminder.test.alarmTitle"
    }

    public let renderer: LocalizedTextRenderer
    public let context: CalendarContext

    public init(renderer: LocalizedTextRenderer, context: CalendarContext) {
        self.renderer = renderer
        self.context = context
    }

    /// The request for a planned notification. Effective tier `.timeSensitive` → `.timeSensitive`, everything else
    /// `.active` (the planner never hands an `.alarm` tier to notifications).
    public func request(for planned: PlannedNotification) -> NotificationRequestSpec {
        NotificationRequestSpec(
            id: planned.id.rawValue,
            title: renderer.string(planned.content.title),
            subtitle: planned.content.subtitle.map(renderer.string),
            body: renderer.string(planned.content.body),
            interruption: planned.effectiveTier.effective == .timeSensitive ? .timeSensitive : .active,
            threadID: planned.threadID,
            categoryID: planned.categoryID.rawValue,
            userInfo: [ReminderUserInfo.reminderID: planned.id.rawValue,
                       ReminderUserInfo.source: planned.source.rawValue,
                       ReminderUserInfo.kind: ReminderUserInfo.kindPlanned],
            fireDate: planned.fireDate,
            trigger: NotificationTriggerTime(instant: planned.fireDate, zone: context.timeZone))
    }

    /// The spec for a planned loud alarm (fixed schedule, Snooze button with a 9-minute countdown).
    public func alarm(for planned: PlannedAlarm) -> AlarmSpec {
        let title = renderer.string(planned.content.title)
        return AlarmSpec(
            id: planned.alarmID,
            reminderID: planned.id.rawValue,
            fireDate: planned.fireDate,
            title: title,
            subtitle: renderer.string(planned.content.body),
            snoozedTitle: renderer.format(key: Keys.alarmSnoozedTitle, arguments: [.text(title)]),
            sourceRawValue: planned.source.rawValue,
            snoozeSeconds: Self.alarmSnoozeSeconds)
    }

    /// A one-off copy of `delivered` at `fireDate` with the snooze id (`snooze.<reminder id>`). Keeps the text,
    /// tier, thread and category (so the snoozed notification offers the same actions again).
    public func snooze(_ delivered: DeliveredNotification, until fireDate: Date) -> NotificationRequestSpec {
        let reminderID = delivered.userInfo[ReminderUserInfo.reminderID] ?? delivered.requestID
        var info = delivered.userInfo
        info[ReminderUserInfo.reminderID] = reminderID
        info[ReminderUserInfo.kind] = ReminderUserInfo.kindSnooze
        return NotificationRequestSpec(
            id: ReminderRequestID.snooze(for: reminderID), title: delivered.title, subtitle: delivered.subtitle,
            body: delivered.body, interruption: delivered.interruption, threadID: delivered.threadID,
            categoryID: delivered.categoryID, userInfo: info, fireDate: fireDate,
            trigger: NotificationTriggerTime(instant: fireDate, zone: context.timeZone))
    }

    /// The health check's test notification, `delay` seconds from `now` (Standard tier, no actions).
    public func testNotification(now: Date, delay: TimeInterval = 5) -> NotificationRequestSpec {
        let fire = now.addingTimeInterval(delay)
        return NotificationRequestSpec(
            id: ReminderRequestID.testPrefix + "notification", title: renderer.string(forKey: Keys.testTitle), subtitle: nil,
            body: renderer.string(forKey: Keys.testBody), interruption: .active, threadID: "tabula.test", categoryID: "",
            userInfo: [ReminderUserInfo.kind: ReminderUserInfo.kindTest], fireDate: fire,
            trigger: NotificationTriggerTime(instant: fire, zone: context.timeZone))
    }

    /// The health check's test alarm, `delay` seconds from `now`. Random id: it is never in the alarm ledger, so the
    /// plan diff never cancels it.
    public func testAlarm(now: Date, delay: TimeInterval = 60) -> AlarmSpec {
        let title = renderer.string(forKey: Keys.testAlarmTitle)
        return AlarmSpec(id: UUID(), reminderID: ReminderRequestID.testPrefix + "alarm", fireDate: now.addingTimeInterval(delay),
                         title: title, subtitle: nil,
                         snoozedTitle: renderer.format(key: Keys.alarmSnoozedTitle, arguments: [.text(title)]),
                         sourceRawValue: "", snoozeSeconds: Self.alarmSnoozeSeconds)
    }

    /// The categories to register (`ReminderCategory.allCases`), with localised action titles.
    public func categories() -> [NotificationCategorySpec] {
        ReminderCategory.allCases.map { category in
            NotificationCategorySpec(id: category.rawValue, actions: category.actions.map { action in
                NotificationActionSpec(id: action.rawValue, title: renderer.string(forKey: action.l10nKey),
                                       systemImage: Self.symbol(for: action))
            })
        }
    }

    static func symbol(for action: ReminderAction) -> String {
        switch action {
        case .markDone: return "checkmark.circle"
        case .snoozeOneHour: return "clock.arrow.circlepath"
        case .snoozeTomorrow: return "sunrise"
        }
    }
}
