import Foundation

/// The result of `ReminderPlanner.plan(_:)`: what to schedule now, what could not be scheduled, and when to
/// plan again. Codable so the adapter can persist the last applied plan and diff against it.
public struct ReminderPlan: Hashable, Sendable, Codable {
    /// `PlannerInput.now`.
    public var generatedAt: Date
    /// Last instant covered (`horizonDays` calendar days after `now`, same wall-clock time).
    public var horizonEnd: Date
    /// Local notifications to keep pending, ascending by (`fireDate`, tier descending, `id`).
    /// `count ≤ budget.available`.
    public var notifications: [PlannedNotification]
    /// Loud alarms (AlarmKit) to keep scheduled, same order. `count ≤ alarmSoftLimit`.
    public var alarms: [PlannedAlarm]
    /// Reminders inside the horizon that will **not** be delivered, with the reason. Never silent.
    public var dropped: [DroppedReminder]
    /// `true` when at least one reminder was dropped because the notification budget is full.
    public var isSaturated: Bool
    /// Alarm-tier reminders over `alarmSoftLimit`, delivered as notifications instead (ascending).
    public var alarmOverflow: [ReminderID]
    /// When the app should plan again at the latest (also re-plan on launch, foreground, data change,
    /// time-zone change and background refresh).
    public var nextReplanDate: Date

    /// Creates a plan.
    public init(generatedAt: Date, horizonEnd: Date, notifications: [PlannedNotification], alarms: [PlannedAlarm],
                dropped: [DroppedReminder], isSaturated: Bool, alarmOverflow: [ReminderID], nextReplanDate: Date) {
        self.generatedAt = generatedAt
        self.horizonEnd = horizonEnd
        self.notifications = notifications
        self.alarms = alarms
        self.dropped = dropped
        self.isSaturated = isSaturated
        self.alarmOverflow = alarmOverflow
        self.nextReplanDate = nextReplanDate
    }

    /// `true` when some alarm-tier reminders had to fall back to notifications.
    public var isAlarmSaturated: Bool { !alarmOverflow.isEmpty }

    /// Number of reminders dropped because the notification budget is full.
    public var budgetDroppedCount: Int { dropped.filter { $0.reason == .budget }.count }

    /// The gentle in-app notice for a saturated window (`reminder.notice.saturated`, arg: dropped count),
    /// or `nil` when nothing was dropped for budget reasons.
    public var saturationNotice: LocalizedText? {
        isSaturated ? LocalizedText(key: ReminderL10n.noticeSaturated, args: [.integer(budgetDroppedCount)]) : nil
    }

    /// The in-app notice for alarm overflow (`reminder.notice.alarmLimit`, arg: count), or `nil`.
    public var alarmOverflowNotice: LocalizedText? {
        isAlarmSaturated ? LocalizedText(key: ReminderL10n.noticeAlarmLimit, args: [.integer(alarmOverflow.count)]) : nil
    }
}

/// Stable identifier of a planned reminder: `"rem."` + 16 lowercase hex digits (FNV-1a 64).
///
/// Hashed from the source kind and ID, the rule ID, the offset descriptor and a **wall-clock** key (the
/// nominal local fire date-time for `daysBefore`, the item's local date-time for `minutesBefore`), plus the
/// follow-up descriptor for follow-ups — never from an absolute instant. A time-zone or DST change therefore
/// re-maps `fireDate` under the same ID instead of producing a new one, and unrelated edits leave IDs alone.
/// Use it as the `UNNotificationRequest` identifier; alarms use `PlannedAlarm.alarmID`.
public struct ReminderID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The identifier string.
    public let rawValue: String

    /// Every planner identifier starts with this; the adapter must leave other pending requests alone.
    public static let prefix = "rem."

    /// Wraps a raw value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// `true` when `identifier` looks like a planner identifier (prefix + 16 lowercase hex digits).
    public static func isPlannerID(_ identifier: String) -> Bool {
        guard identifier.hasPrefix(prefix) else { return false }
        let hex = identifier.dropFirst(prefix.count)
        return hex.count == 16 && hex.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// The ID for a canonical reminder key.
    static func make(key: String) -> ReminderID {
        ReminderID(rawValue: prefix + StableHash.hex(StableHash.fnv1a64(key)))
    }

    public static func < (lhs: ReminderID, rhs: ReminderID) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Same as `rawValue`.
    public var description: String { rawValue }

    /// Single-value string coding.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// Single-value string coding.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What a reminder is about. Its `rawValue` is a plist-safe string for `userInfo` (tap routing, Mark done).
public enum ReminderSource: Hashable, Sendable {
    /// A task (homework, assignment, to-do).
    case task(TaskItem.ID)
    /// An exam.
    case exam(Exam.ID)
    /// A lesson occurrence.
    case lesson(OccurrenceID)
    /// The bring-list of the school day `date`.
    case packTonight(LocalDate)

    /// `"task/<UUID>"`, `"exam/<UUID>"`, `"lesson/<occurrence ID>"` or `"packTonight/<yyyy-MM-dd>"`.
    public var rawValue: String {
        switch self {
        case .task(let id): return "task/\(id.uuidString)"
        case .exam(let id): return "exam/\(id.uuidString)"
        case .lesson(let occurrence): return "lesson/\(occurrence.rawValue)"
        case .packTonight(let date): return "packTonight/\(date.isoString)"
        }
    }

    /// Parses `rawValue`; `nil` for anything malformed.
    public init?(rawValue: String) {
        guard let slash = rawValue.firstIndex(of: "/") else { return nil }
        let kind = rawValue[..<slash]
        let value = String(rawValue[rawValue.index(after: slash)...])
        switch kind {
        case "task":
            guard let id = TaskItem.ID(uuidString: value) else { return nil }
            self = .task(id)
        case "exam":
            guard let id = Exam.ID(uuidString: value) else { return nil }
            self = .exam(id)
        case "lesson":
            guard !value.isEmpty else { return nil }
            self = .lesson(OccurrenceID(rawValue: value))
        case "packTonight":
            guard let date = LocalDate(value) else { return nil }
            self = .packTonight(date)
        default:
            return nil
        }
    }

    /// `true` for sources the user can complete (tasks, exams): only these get follow-ups and Mark done.
    public var isCompletable: Bool {
        switch self {
        case .task, .exam: return true
        case .lesson, .packTonight: return false
        }
    }
}

extension ReminderSource: Codable {
    /// Decodes `rawValue`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = ReminderSource(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ReminderSource '\(raw)'")
        }
        self = value
    }

    /// Encodes `rawValue`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Notification text as catalog keys + arguments. User text (titles, subject names, rooms) only appears as
/// `.string` arguments. Relative-day wording ("today", "tomorrow", "in 3 days") is chosen relative to the
/// reminder's own local fire date, so it stays correct no matter when the plan was made.
public struct ReminderContent: Hashable, Sendable, Codable {
    /// Title line.
    public var title: LocalizedText
    /// Optional subtitle (room).
    public var subtitle: LocalizedText?
    /// Body line.
    public var body: LocalizedText

    /// Creates content.
    public init(title: LocalizedText, subtitle: LocalizedText? = nil, body: LocalizedText) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}

/// Why a reminder's delivery tier differs from the requested one (in the order the rules were applied).
public enum TierChangeReason: String, CaseIterable, Hashable, Sendable, Codable {
    /// A preset rule asked for a loud alarm; alarms come only from user rules (decision D7) → Time Sensitive.
    case presetRuleAlarm
    /// Loud alarms are switched off in settings (`alarmPolicy.isEnabled == false`) → Time Sensitive.
    case alarmsDisabled
    /// AlarmKit is not authorised or the entitlement is missing (`canScheduleAlarms == false`) → Time Sensitive.
    case alarmsUnavailable
    /// Follow-ups are never loud alarms → Time Sensitive.
    case followUpNeverAlarm
    /// More alarms than `alarmSoftLimit`; this one falls back → Time Sensitive.
    case alarmLimitReached
    /// Time Sensitive is switched off in settings → Standard.
    case timeSensitiveDisabled
    /// Fires more than `timeSensitivePolicy.maxLeadMinutes` before the item (decision D6, HIG) → Standard.
    case leadTimeTooLong

    /// Catalog key of an explanation for the rule editor / health check.
    public var l10nKey: String { "reminder.tierChange.\(rawValue)" }
}

/// Why a reminder inside the horizon is not delivered.
public enum DropReason: String, CaseIterable, Hashable, Sendable, Codable {
    /// Later than the budget allows (`ReminderPlan.isSaturated`).
    case budget
    /// Quiet hours moved it past the item's due/start time.
    case quietHoursAfterDue
    /// Its own time is already past the item's due/start time (e.g. a follow-up after the deadline).
    case afterDue
    /// Another reminder for the same item fires at the same instant (the higher tier is kept).
    case duplicate
    /// A negative offset or follow-up (rejected by validation as well).
    case invalidOffset
    /// An offset kind from a newer app version (`ReminderOffset.unknown`).
    case unsupportedOffset

    /// Catalog key of an explanation.
    public var l10nKey: String { "reminder.dropped.\(rawValue)" }
}

/// A reminder that will not be delivered.
public struct DroppedReminder: Hashable, Sendable, Codable {
    /// The reminder's ID (as it would have been scheduled).
    public var id: ReminderID
    /// What it is about.
    public var source: ReminderSource
    /// The rule it came from; `nil` for per-item override offsets without a matching rule.
    public var ruleID: ReminderRule.ID?
    /// The instant it would have fired (after quiet hours), if computable.
    public var fireDate: Date?
    /// `true` for a follow-up.
    public var isFollowUp: Bool
    /// Why it is dropped.
    public var reason: DropReason

    /// Creates a dropped entry.
    public init(id: ReminderID, source: ReminderSource, ruleID: ReminderRule.ID?, fireDate: Date?, isFollowUp: Bool,
                reason: DropReason) {
        self.id = id
        self.source = source
        self.ruleID = ruleID
        self.fireDate = fireDate
        self.isFollowUp = isFollowUp
        self.reason = reason
    }
}

/// A notification action identifier. The adapter registers these on the categories below.
public enum ReminderAction: String, CaseIterable, Hashable, Sendable, Codable {
    /// Marks the task/exam completed (then re-plan, which removes its follow-ups).
    case markDone = "tabula.action.markDone"
    /// Snoozes for one hour.
    case snoozeOneHour = "tabula.action.snoozeOneHour"
    /// Snoozes until tomorrow morning.
    case snoozeTomorrow = "tabula.action.snoozeTomorrow"

    /// Catalog key of the button title.
    public var l10nKey: String { "reminder.action.\(rawValue.dropFirst("tabula.action.".count))" }

    /// 07:00, the default time for `snoozeTomorrow`.
    public static let defaultSnoozeMorning = LocalTime(hour: 7, minute: 0)!

    /// When a snooze action should fire again: `now` + 1 h, or tomorrow (local) at `tomorrowAt` in `context`.
    /// `nil` for non-snooze actions.
    public func snoozeDate(now: Date, context: CalendarContext,
                           tomorrowAt: LocalTime = ReminderAction.defaultSnoozeMorning) -> Date? {
        switch self {
        case .markDone: return nil
        case .snoozeOneHour: return now.addingTimeInterval(3600)
        case .snoozeTomorrow: return context.date(context.localDate(of: now).adding(days: 1), tomorrowAt)
        }
    }
}

/// Notification category identifiers (which actions a notification offers).
public enum ReminderCategory: String, CaseIterable, Hashable, Sendable, Codable {
    /// Tasks: Mark done, Snooze 1 h, Snooze until tomorrow.
    case task = "tabula.reminder.task"
    /// Exams: Mark done, Snooze 1 h, Snooze until tomorrow.
    case exam = "tabula.reminder.exam"
    /// Lessons: no actions (informational).
    case lesson = "tabula.reminder.lesson"
    /// Pack tonight: Snooze 1 h.
    case packTonight = "tabula.reminder.packTonight"

    /// The actions to register for this category, in display order.
    public var actions: [ReminderAction] {
        switch self {
        case .task, .exam: return [.markDone, .snoozeOneHour, .snoozeTomorrow]
        case .lesson: return []
        case .packTonight: return [.snoozeOneHour]
        }
    }
}

/// A local notification to schedule.
public struct PlannedNotification: Identifiable, Hashable, Sendable, Codable {
    /// Stable ID (the request identifier).
    public var id: ReminderID
    /// When to deliver (absolute instant, computed in the plan's `CalendarContext`).
    public var fireDate: Date
    /// The same moment as wall-clock time in the plan's zone.
    public var localFireTime: LocalDateTime
    /// Tier the rule or override asked for.
    public var requestedTier: DeliveryTier
    /// Tier to deliver with (`.standard` or `.timeSensitive`; never `.alarm`).
    public var effectiveTier: DeliveryTier
    /// Why `effectiveTier` differs from `requestedTier`, in application order (empty when equal).
    public var tierChanges: [TierChangeReason]
    /// Text.
    public var content: ReminderContent
    /// Notification thread (groups an item's reminders).
    public var threadID: String
    /// Category (actions).
    public var categoryID: ReminderCategory
    /// What it is about (for `userInfo`).
    public var source: ReminderSource
    /// The rule it came from; `nil` for per-item override offsets without a matching rule.
    public var ruleID: ReminderRule.ID?
    /// `true` for a follow-up ("still not done").
    public var isFollowUp: Bool
    /// `true` when quiet hours moved it later.
    public var movedByQuietHours: Bool

    /// Creates a planned notification.
    public init(id: ReminderID, fireDate: Date, localFireTime: LocalDateTime, requestedTier: DeliveryTier,
                effectiveTier: DeliveryTier, tierChanges: [TierChangeReason], content: ReminderContent,
                threadID: String, categoryID: ReminderCategory, source: ReminderSource, ruleID: ReminderRule.ID?,
                isFollowUp: Bool, movedByQuietHours: Bool) {
        self.id = id
        self.fireDate = fireDate
        self.localFireTime = localFireTime
        self.requestedTier = requestedTier
        self.effectiveTier = effectiveTier
        self.tierChanges = tierChanges
        self.content = content
        self.threadID = threadID
        self.categoryID = categoryID
        self.source = source
        self.ruleID = ruleID
        self.isFollowUp = isFollowUp
        self.movedByQuietHours = movedByQuietHours
    }
}

/// A loud alarm (AlarmKit) to schedule with `Alarm.Schedule.fixed(fireDate)`.
public struct PlannedAlarm: Identifiable, Hashable, Sendable, Codable {
    /// Stable reminder ID (same scheme as notifications).
    public var id: ReminderID
    /// Deterministic `Alarm.ID` derived from the same key (RFC 9562 version 8).
    public var alarmID: UUID
    /// When to ring (absolute; `.fixed` alarms do not follow time-zone changes — re-plan on a zone change).
    public var fireDate: Date
    /// The same moment as wall-clock time in the plan's zone.
    public var localFireTime: LocalDateTime
    /// Text (title for `AlarmPresentation.Alert`; body for the app's own UI).
    public var content: ReminderContent
    /// What it is about.
    public var source: ReminderSource
    /// The rule it came from; `nil` for per-item override offsets without a matching rule.
    public var ruleID: ReminderRule.ID?
    /// `true` when quiet hours (the rule's own; global quiet hours never apply to alarms) moved it.
    public var movedByQuietHours: Bool

    /// Creates a planned alarm.
    public init(id: ReminderID, alarmID: UUID, fireDate: Date, localFireTime: LocalDateTime, content: ReminderContent,
                source: ReminderSource, ruleID: ReminderRule.ID?, movedByQuietHours: Bool) {
        self.id = id
        self.alarmID = alarmID
        self.fireDate = fireDate
        self.localFireTime = localFireTime
        self.content = content
        self.source = source
        self.ruleID = ruleID
        self.movedByQuietHours = movedByQuietHours
    }
}
