// Pure logic behind the reminder settings, the rule editor and the per-item override section (Phase 3 Stage B4).
// No SwiftUI: the screens only lay out what these types decide, so it is Linux-tested.
//
//   ReminderOffsetEditing   offset presets, kinds, text (catalog key + arguments, never concatenated)
//   FollowUpMenuKind/Editing  follow-up choices for rules (none / after N min / next morning) and overrides (+ inherit)
//   ReminderTierInfo        the three delivery tiers: catalog keys for title and honest explanation
//   ReminderRuleDefaults    the rule created the first time a kind is switched on (profile preset, else a fallback)
//   ReminderRuleEditing     "any edit makes the rule user-made" (origin == .user, DOMAIN_MODEL §3.11)
//   ReminderRuleSummary     one-line summary of a rule for list rows
//   ReminderKindList        which kinds the settings list offers (honours disabled lesson fields)
//   ReminderUIKeys          every dynamic catalog key of these screens (registered in DynamicL10nKeys.allKeys)
import Foundation
import TimetableCore

// MARK: - Offsets

/// The two kinds of offset the editor can create. Offsets of a newer app version are `nil` here (shown, not editable).
public enum ReminderOffsetKind: String, CaseIterable, Hashable, Sendable {
    case minutesBefore, daysBefore

    public var titleKey: String { "reminders.offsetKind." + rawValue }
}

public enum ReminderOffsetEditing {
    /// Allowed ranges of the steppers.
    public static let minutesRange = 0...(7 * 24 * 60)
    public static let daysRange = 0...60
    /// Default clock time of a "days before" offset.
    public static let defaultEvening = LocalTime(hour: 18, minute: 0) ?? .midnight
    public static let defaultMorning = LocalTime(hour: 7, minute: 0) ?? .midnight

    /// Quick-add presets, in menu order.
    public static let presets: [ReminderOffset] = [
        .minutesBefore(15),
        .minutesBefore(60),
        .daysBefore(0, at: defaultMorning),
        .daysBefore(1, at: defaultEvening),
        .daysBefore(3, at: defaultEvening),
        .daysBefore(7, at: defaultEvening),
    ]

    /// Presets not yet in `existing` (adding the same offset twice would plan duplicates).
    public static func availablePresets(excluding existing: [ReminderOffset]) -> [ReminderOffset] {
        presets.filter { !existing.contains($0) }
    }

    /// The kind of `offset`, `nil` for an offset kind from a newer version.
    public static func kind(of offset: ReminderOffset) -> ReminderOffsetKind? {
        switch offset {
        case .minutesBefore: return .minutesBefore
        case .daysBefore: return .daysBefore
        case .unknown: return nil
        }
    }

    /// `offset` converted to `kind`, keeping what carries over; unknown offsets are returned unchanged.
    public static func converting(_ offset: ReminderOffset, to kind: ReminderOffsetKind) -> ReminderOffset {
        switch (offset, kind) {
        case (.minutesBefore, .minutesBefore), (.daysBefore, .daysBefore), (.unknown, _): return offset
        case (.minutesBefore, .daysBefore): return .daysBefore(1, at: defaultEvening)
        case (.daysBefore, .minutesBefore): return .minutesBefore(30)
        }
    }

    /// Minutes, clamped to the stepper range (non-editable offsets give `nil`).
    public static func minutes(of offset: ReminderOffset) -> Int? {
        if case .minutesBefore(let minutes) = offset { return minutes }
        return nil
    }

    public static func days(of offset: ReminderOffset) -> Int? {
        if case .daysBefore(let days, _) = offset { return days }
        return nil
    }

    public static func time(of offset: ReminderOffset) -> LocalTime? {
        if case .daysBefore(_, let time) = offset { return time }
        return nil
    }

    /// The text of an offset: one catalog format per shape, so plural forms and word order stay translatable.
    /// Formats: `reminders.offset.atDue`, `.minutesBefore` (plural on arg 1), `.hoursBefore` (plural on arg 1),
    /// `.sameDay` (arg: time), `.daysBefore` (plural on arg 1, arg 2: time), `.unsupported`.
    public static func text(_ offset: ReminderOffset) -> LocalizedText {
        switch offset {
        case .minutesBefore(let minutes):
            if minutes <= 0 { return LocalizedText(key: "reminders.offset.atDue") }
            if minutes >= 60, minutes % 60 == 0 {
                return LocalizedText(key: "reminders.offset.hoursBefore", args: [.integer(minutes / 60)])
            }
            return LocalizedText(key: "reminders.offset.minutesBefore", args: [.integer(minutes)])
        case let .daysBefore(days, at):
            if days <= 0 { return LocalizedText(key: "reminders.offset.sameDay", args: [.time(at)]) }
            return LocalizedText(key: "reminders.offset.daysBefore", args: [.integer(days), .time(at)])
        case .unknown:
            return LocalizedText(key: "reminders.offset.unsupported")
        }
    }

    /// Adds `offset` unless it is already there.
    public static func adding(_ offset: ReminderOffset, to offsets: [ReminderOffset]) -> [ReminderOffset] {
        offsets.contains(offset) ? offsets : offsets + [offset]
    }

    /// Catalog keys that `text` can produce.
    static let textKeys = ["reminders.offset.atDue", "reminders.offset.hoursBefore", "reminders.offset.minutesBefore",
                           "reminders.offset.sameDay", "reminders.offset.daysBefore", "reminders.offset.unsupported"]
}

// MARK: - Follow-up

/// The follow-up choices of a menu. Rules never use `.inherit`; items overriding a rule do.
public enum FollowUpMenuKind: String, CaseIterable, Hashable, Sendable {
    case inherit, none, afterMinutes, nextMorning
    /// A follow-up kind from a newer app version: shown only while it is the current value.
    case unsupported

    public var titleKey: String { "reminders.followUp.kind." + rawValue }
}

public enum FollowUpEditing {
    /// Delays offered for "after N minutes".
    public static let minuteOptions = [30, 60, 120, 180, 240, 360]
    public static let defaultMinutes = 120
    public static let defaultMorning = ReminderOffsetEditing.defaultMorning

    public static func kind(of followUp: FollowUp?) -> FollowUpMenuKind {
        switch followUp {
        case nil: return .none
        case .afterMinutes?: return .afterMinutes
        case .nextMorning?: return .nextMorning
        case .unknown?: return .unsupported
        }
    }

    public static func kind(of override: FollowUpOverride) -> FollowUpMenuKind {
        switch override {
        case .inherit: return .inherit
        case .none: return .none
        case .custom(let followUp): return kind(of: followUp)
        }
    }

    /// The choices to offer given the current one.
    public static func options(forOverride: Bool, current: FollowUpMenuKind) -> [FollowUpMenuKind] {
        var kinds: [FollowUpMenuKind] = forOverride ? [.inherit, .none, .afterMinutes, .nextMorning]
                                                    : [.none, .afterMinutes, .nextMorning]
        if current == .unsupported { kinds.append(.unsupported) }
        return kinds
    }

    /// The rule's follow-up after choosing `kind`; the payload is kept when the kind does not change.
    public static func followUp(choosing kind: FollowUpMenuKind, current: FollowUp?) -> FollowUp? {
        switch kind {
        case .inherit, .none: return nil
        case .afterMinutes:
            if case .afterMinutes? = current { return current }
            return .afterMinutes(defaultMinutes)
        case .nextMorning:
            if case .nextMorning? = current { return current }
            return .nextMorning(at: defaultMorning)
        case .unsupported: return current
        }
    }

    /// The override's follow-up after choosing `kind`.
    public static func override(choosing kind: FollowUpMenuKind, current: FollowUpOverride) -> FollowUpOverride {
        switch kind {
        case .inherit: return .inherit
        case .none: return .none
        case .afterMinutes, .nextMorning:
            var previous: FollowUp?
            if case .custom(let followUp) = current { previous = followUp }
            return followUp(choosing: kind, current: previous).map(FollowUpOverride.custom) ?? .none
        case .unsupported: return current
        }
    }

    /// The custom follow-up of an override (`nil` for inherit / none).
    public static func followUp(of override: FollowUpOverride) -> FollowUp? {
        if case .custom(let followUp) = override { return followUp }
        return nil
    }

    public static func minutes(of followUp: FollowUp?) -> Int? {
        if case .afterMinutes(let minutes)? = followUp { return minutes }
        return nil
    }

    public static func time(of followUp: FollowUp?) -> LocalTime? {
        if case .nextMorning(let time)? = followUp { return time }
        return nil
    }

    /// Delay options including the stored value (a value from a sync or an older preset stays selectable).
    public static func minuteOptions(including current: Int?) -> [Int] {
        guard let current, !minuteOptions.contains(current) else { return minuteOptions }
        return (minuteOptions + [current]).sorted()
    }

    /// `afterMinutes` delay text: `reminders.followUp.afterMinutes` (plural on arg 1) or `.afterHours`.
    public static func delayText(minutes: Int) -> LocalizedText {
        if minutes >= 60, minutes % 60 == 0 {
            return LocalizedText(key: "reminders.followUp.afterHours", args: [.integer(minutes / 60)])
        }
        return LocalizedText(key: "reminders.followUp.afterMinutes", args: [.integer(minutes)])
    }

    static let textKeys = ["reminders.followUp.afterMinutes", "reminders.followUp.afterHours"]
}

// MARK: - Tiers

public enum ReminderTierInfo {
    /// Tiers a user can pick, quietest first.
    public static let choices: [DeliveryTier] = [.standard, .timeSensitive, .alarm]

    /// A tier the picker can show; an unknown value is planned as Standard (DOMAIN_MODEL §7).
    public static func displayed(_ tier: DeliveryTier) -> DeliveryTier { tier.effective }

    public static func titleKey(_ tier: DeliveryTier) -> String {
        switch tier.effective {
        case .timeSensitive: return "settings.reminders.timesensitive.title"
        case .alarm: return "settings.reminders.alarm.title"
        default: return "settings.reminders.standard.title"
        }
    }

    public static func detailKey(_ tier: DeliveryTier) -> String {
        switch tier.effective {
        case .timeSensitive: return "settings.reminders.timesensitive.detail"
        case .alarm: return "settings.reminders.alarm.detail"
        default: return "settings.reminders.standard.detail"
        }
    }

    public static func symbol(_ tier: DeliveryTier) -> String {
        switch tier.effective {
        case .timeSensitive: return "bell.badge"
        case .alarm: return "alarm"
        default: return "bell"
        }
    }

    /// Time Sensitive: when it is actually used. `reminders.tier.timeSensitive.policy` (plural on arg 1) or
    /// `reminders.tier.timeSensitive.off` when the policy is switched off.
    public static func timeSensitivePolicyText(_ policy: TimeSensitivePolicy) -> LocalizedText {
        policy.isEnabled
            ? LocalizedText(key: "reminders.tier.timeSensitive.policy", args: [.integer(policy.maxLeadMinutes)])
            : LocalizedText(key: "reminders.tier.timeSensitive.off")
    }

    /// Lead minutes offered by the Time Sensitive stepper.
    public static let leadRange = 5...240
    public static let leadStep = 5
}

// MARK: - Defaults and editing

public enum ReminderRuleDefaults {
    /// The kinds the settings list can switch on.
    public static let targets: [ReminderTarget] = [.homework, .assignment, .exam, .lesson, .packTonight, .todo]

    /// The rule created when the user first switches `target` on: the profile preset's rule when it has one, else a
    /// sensible default. Enabled, `origin == .user` is set by the first edit (`ReminderRuleEditing.touched`).
    public static func rule(for target: ReminderTarget, profile: UserProfile, id: ReminderRule.ID) -> ReminderRule {
        let meta = EntityMeta(createdAt: .zero, updatedAt: .zero)
        if let preset = ProfilePreset.for(profile).reminderRules.first(where: { $0.target == target }) {
            return preset.makeRule(id: id, meta: meta, isEnabled: true)
        }
        let offsets: [ReminderOffset]
        switch target {
        case .lesson: offsets = [.minutesBefore(10)]
        case .packTonight: offsets = [.daysBefore(1, at: LocalTime(hour: 20, minute: 0) ?? .midnight)]
        case .exam: offsets = [.daysBefore(3, at: ReminderOffsetEditing.defaultEvening),
                               .daysBefore(1, at: ReminderOffsetEditing.defaultEvening)]
        default: offsets = [.daysBefore(1, at: ReminderOffsetEditing.defaultEvening)]
        }
        return ReminderRule(id: id, meta: meta, target: target, offsets: offsets, followUp: nil, tier: .standard,
                            quietHours: nil, isEnabled: true, origin: .preset)
    }

    /// The live rule of `target` (the first by ID when sync produced several).
    public static func rule(for target: ReminderTarget, in rules: [ReminderRule]) -> ReminderRule? {
        rules.filter { !$0.isDeleted && $0.target == target }.min { $0.id < $1.id }
    }
}

public enum ReminderRuleEditing {
    /// `rule` marked user-made: the planner only lets user rules ring (DOMAIN_MODEL §3.11, decision D7).
    public static func touched(_ rule: ReminderRule) -> ReminderRule {
        var copy = rule
        copy.origin = .user
        return copy
    }

    /// Quiet hours offered for a new window (22:00–07:00).
    public static let defaultQuietHours = QuietHours(start: LocalTime(hour: 22, minute: 0) ?? .midnight,
                                                     end: LocalTime(hour: 7, minute: 0) ?? .midnight)

    /// `true` when an enabled rule would plan nothing.
    public static func isIncomplete(_ rule: ReminderRule) -> Bool {
        rule.isEnabled && !rule.offsets.contains { ReminderOffsetEditing.kind(of: $0) != nil }
    }
}

public enum ReminderRuleSummary {
    /// The lines of a list row: the offsets (the single offset's text, or "N reminders") and the tier when it is not
    /// Standard. Disabled rules give an empty list (the row says "Off" itself).
    public static func lines(_ rule: ReminderRule) -> [LocalizedText] {
        guard rule.isEnabled else { return [] }
        var lines: [LocalizedText] = []
        let known = rule.offsets.filter { ReminderOffsetEditing.kind(of: $0) != nil }
        if known.count == 1, let only = known.first {
            lines.append(ReminderOffsetEditing.text(only))
        } else if known.count > 1 {
            lines.append(LocalizedText(key: "reminders.summary.multiple", args: [.integer(known.count)]))
        } else {
            lines.append(LocalizedText(key: "reminders.summary.incomplete"))
        }
        if rule.tier.effective != .standard {
            lines.append(LocalizedText(key: ReminderTierInfo.titleKey(rule.tier)))
        }
        return lines
    }

    static let textKeys = ["reminders.summary.multiple", "reminders.summary.incomplete"]
}

/// Which kinds the settings list shows.
public enum ReminderKindList {
    /// All kinds; "pack tonight" only while the bring list is an enabled lesson field of the active timetable
    /// (field rule: a disabled field is hidden everywhere), or while such a rule is already switched on.
    public static func visibleTargets(bringListVisible: Bool, rules: [ReminderRule]) -> [ReminderTarget] {
        ReminderRuleDefaults.targets.filter { target in
            guard target == .packTonight else { return true }
            if bringListVisible { return true }
            return rules.contains { !$0.isDeleted && $0.target == .packTonight && $0.isEnabled }
        }
    }

    /// Catalog key of a kind's name; "lesson" follows the profile's terminology (lesson / class).
    public static func titleKey(_ target: ReminderTarget, terminology: ProfilePreset.Terminology) -> String {
        target == .lesson ? DynamicL10nKeys.term("onboarding.reminders.target", terminology)
                          : DynamicL10nKeys.reminderTarget(target)
    }
}

// MARK: - Health status text

public enum ReminderHealthPresentation {
    /// Spoken/visible word of a status, so that colour is never the only carrier.
    public static func statusKey(_ status: ReminderHealthStatus) -> String {
        switch status {
        case .ok: return "health.status.ok"
        case .info: return "health.status.info"
        case .warning: return "health.status.warning"
        case .problem: return "health.status.problem"
        }
    }

    /// SF Symbol of a status (distinct shapes, not only colours).
    public static func symbol(_ status: ReminderHealthStatus) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    /// Overall summary key of the health screen's top row (worst status of the rows).
    public static func summaryKey(_ status: ReminderHealthStatus) -> String {
        switch status {
        case .ok, .info: return "health.summary.ok"
        case .warning: return "health.summary.warning"
        case .problem: return "health.summary.problem"
        }
    }

    /// Outcome messages of the test buttons.
    public static func testNotificationKey(_ outcome: NotificationAddOutcome) -> String {
        switch outcome {
        case .added: return "health.test.notification.sent"
        case .failed: return "health.test.notification.failed"
        }
    }

    public static func testAlarmKey(_ outcome: AlarmScheduleOutcome) -> String {
        switch outcome {
        case .scheduled: return "health.test.alarm.sent"
        case .limitReached: return "health.test.alarm.limit"
        case .notAuthorized: return "health.test.alarm.notAuthorized"
        case .failed: return "health.test.alarm.failed"
        }
    }

    static let keys = ["health.status.ok", "health.status.info", "health.status.warning", "health.status.problem",
                       "health.summary.ok", "health.summary.warning", "health.summary.problem",
                       "health.test.notification.sent", "health.test.notification.failed", "health.test.alarm.sent",
                       "health.test.alarm.limit", "health.test.alarm.notAuthorized", "health.test.alarm.failed"]
}

// MARK: - Keys

public enum ReminderUIKeys {
    /// Every key the reminder screens build at runtime (checked against the catalog by `DynamicL10nKeyTests`).
    public static var allKeys: [String] {
        var keys: [String] = []
        keys += ReminderOffsetKind.allCases.map(\.titleKey)
        keys += FollowUpMenuKind.allCases.map(\.titleKey)
        keys += ReminderOffsetEditing.textKeys
        keys += FollowUpEditing.textKeys
        keys += ReminderRuleSummary.textKeys
        keys += ReminderHealthPresentation.keys
        keys += ReminderTierInfo.choices.flatMap { [ReminderTierInfo.titleKey($0), ReminderTierInfo.detailKey($0)] }
        keys += ["reminders.tier.timeSensitive.policy", "reminders.tier.timeSensitive.off"]
        keys += ReminderHealthCheck.allKeys
        return Array(Set(keys)).sorted()
    }
}
