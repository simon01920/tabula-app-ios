// Pure logic behind the Phase 4U U5a settings screens (Linux-tested, no SwiftUI):
//   - `TimeSensitiveAvailability`  H9/D7: the Time Sensitive tier is offered only where the system reports support.
//   - `ReminderHealthTriage`       H9/M4/M28: which health rows are user-fixable warnings and which are technical.
//   - `PaletteRemap`               M26: "Apply to All Subjects" maps subject colours onto the chosen palette by index.
//   - `SettingsSummaries`          the trailing values of the Settings list rows.
// No schema change: everything reads the existing entities and writes through `DatabaseMutation`.
import Foundation
import TimetableCore

// MARK: - Time Sensitive (H9 / D7)

public enum TimeSensitiveAvailability {
    /// `true` when the system reports Time Sensitive support for the app (`.enabled` / `.disabled`). `.notSupported`
    /// (no entitlement in the build, e.g. every xtool build), `.unknown` and "health not read yet" (`nil`) are all
    /// "not available": the tier is hidden and nothing is promised.
    public static func isAvailable(_ state: NotificationSettingState?) -> Bool {
        switch state {
        case .enabled?, .disabled?: return true
        case .notSupported?, .unknown?, nil: return false
        }
    }

    /// The tiers the delivery picker offers, quietest first. Loud alarms are a separate gate (`alarmsOffered`).
    public static func offeredTiers(timeSensitiveAvailable: Bool) -> [DeliveryTier] {
        ReminderTierInfo.choices.filter { $0 != .timeSensitive || timeSensitiveAvailable }
    }

    /// The tier a rule is DISPLAYED with. A rule that saved Time Sensitive keeps working (no data change); where the
    /// tier is unavailable it is shown, and planned by the system, as Standard.
    public static func displayedTier(_ stored: DeliveryTier, timeSensitiveAvailable: Bool) -> DeliveryTier {
        let effective = stored.effective
        return effective == .timeSensitive && !timeSensitiveAvailable ? .standard : effective
    }

    /// `true` when the footnote "was Time Sensitive, shown as Standard" applies.
    public static func needsDowngradeFootnote(stored: DeliveryTier, timeSensitiveAvailable: Bool) -> Bool {
        stored.effective == .timeSensitive && !timeSensitiveAvailable
    }

    static let keys = ["reminders.tier.timeSensitive.unavailable"]
}

// MARK: - Health triage (H9 / M4 / M28)

public enum ReminderHealthTriage {
    /// A warning or problem the user can do something about: a permission, a system setting or Low Power Mode. Rows that
    /// are only app-side limits (reminder cap, alarm cap, unsupported tier) carry no action and are not counted.
    public static func isUserFixable(_ item: ReminderHealthItem) -> Bool {
        guard item.status >= .warning else { return false }
        return item.kind == .lowPower || item.action != nil
    }

    /// The Time Sensitive row of a build or device without support: nothing to show at all (tier hidden, D7).
    public static func isHidden(_ item: ReminderHealthItem) -> Bool {
        item.kind == .timeSensitive && item.status == .warning && item.action == nil
    }

    /// Informational rows for the collapsed "Technical details" group.
    public static func isTechnical(_ item: ReminderHealthItem) -> Bool {
        switch item.kind {
        case .pending, .saturation, .alarmOverflow, .hiddenApp, .silentMode: return true
        case .alarms: return item.status == .warning && item.action == nil   // "not available on this device"
        default: return false
        }
    }

    /// The rows of the main list (everything that is neither hidden nor technical), in display order.
    public static func checks(_ items: [ReminderHealthItem]) -> [ReminderHealthItem] {
        items.filter { !isHidden($0) && !isTechnical($0) }
    }

    /// The rows of the collapsed "Technical details" group, in display order.
    public static func technical(_ items: [ReminderHealthItem]) -> [ReminderHealthItem] {
        items.filter { !isHidden($0) && isTechnical($0) }
    }

    /// The status of the summary: the worst user-fixable row, else `.ok`. App-side limits never raise it.
    public static func summaryStatus(_ items: [ReminderHealthItem]) -> ReminderHealthStatus {
        items.filter(isUserFixable).map(\.status).max() ?? .ok
    }

    /// `true` when the Reminders list should show the attention banner.
    public static func needsAttention(_ items: [ReminderHealthItem]) -> Bool { summaryStatus(items) >= .warning }

    /// Extra button for rows that only point to a system screen (Focus lives in iOS Settings).
    public static func fallbackAction(for item: ReminderHealthItem) -> ReminderHealthAction? {
        item.action ?? (item.kind == .focus ? .openAppSettings : nil)
    }

    /// Keys the accessible status labels use (the visible words were dropped, M28).
    static let keys = ["health.status.ok", "health.status.info", "health.status.warning", "health.status.problem"]
}

// MARK: - "Apply to All Subjects" (M26)

public enum PaletteRemap {
    /// Index of `subject`'s colour in the first built-in pack that contains it; `nil` for custom colours.
    static func packIndex(of subject: Subject) -> Int? {
        for pack in PalettePack.all {
            if let index = pack.colors.firstIndex(where: { $0.value == subject.color }) { return index }
        }
        return nil
    }

    /// The subjects whose colour changes when every live subject takes `pack`'s colour at the same index (a subject
    /// with a custom colour uses its position in the timetable's display order). Returns the NEW versions only.
    /// Only timetables that follow the app's palette: one with its own palette (`Timetable.palettePackID`) keeps it.
    public static func remapped(in database: TabulaDatabase, to pack: PalettePack, locale: Locale) -> [Subject] {
        guard !pack.colors.isEmpty else { return [] }
        var changed: [Subject] = []
        for timetable in database.timetables where !timetable.isDeleted && timetable.palettePackID == nil {
            let ordered = SubjectOrder.live(database, timetableID: timetable.id, locale: locale)
            for (position, subject) in ordered.enumerated() {
                let index = (packIndex(of: subject) ?? position) % pack.colors.count
                let target = pack.colors[index]
                guard target.value != subject.color else { continue }
                var updated = subject
                updated.color = target.value
                switch subject.colorName {
                case nil, .key?: updated.colorName = .key(target.nameKey)   // a palette-name key follows the colour
                case .literal?: break                                       // a name the user wrote stays
                }
                changed.append(updated)
            }
        }
        return changed
    }

    /// Undo of a remap: the CURRENT live subjects with only `color` and `colorName` set back from `originals`
    /// (edits made since, e.g. a rename, are kept; subjects deleted since are skipped). Unchanged ones are left out.
    public static func restored(_ originals: [Subject], in database: TabulaDatabase) -> [Subject] {
        originals.compactMap { original in
            guard var current = database.subjects.first(where: { $0.id == original.id && !$0.isDeleted }),
                  current.color != original.color || current.colorName != original.colorName else { return nil }
            current.color = original.color
            current.colorName = original.colorName
            return current
        }
    }

    /// One batch of stamped upserts (the app's normal write path); `nil` when nothing changes.
    public static func mutation(for subjects: [Subject], label: String = "apply palette") -> DatabaseMutation? {
        subjects.isEmpty ? nil : DatabaseMutation.batch(subjects.map { DatabaseMutation.upsert($0) }, label: label)
    }
}

// MARK: - Row summaries

public enum SettingsSummaries {
    /// Catalog key of a time-format value ("System", "12-hour", "24-hour").
    public static func hourCycleKey(_ hourCycle: HourCycle) -> String {
        switch HourCycleChoice(hourCycle) {
        case .system: return "settings.calendar.hourcycle.system"
        case .h12: return "settings.calendar.hourcycle.h12"
        case .h24: return "settings.calendar.hourcycle.h24"
        }
    }

    /// Number of periods of the timetable's bell schedule (the default one), `nil` for a timetable without a bell
    /// schedule (field rule: the row then has no value).
    public static func periodCount(of timetable: Timetable, in database: TabulaDatabase) -> Int? {
        guard case let .bellSchedule(defaultID, _) = timetable.timeStructure,
              let schedule = database.bellSchedules.first(where: { $0.id == defaultID && !$0.isDeleted }) else { return nil }
        return schedule.periods.count
    }

    /// Live subjects of one timetable.
    public static func subjectCount(of timetableID: Timetable.ID, in database: TabulaDatabase) -> Int {
        database.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }.count
    }

    /// Reminder kinds with an enabled rule.
    public static func enabledReminderKinds(_ rules: [ReminderRule]) -> Int {
        ReminderRuleDefaults.targets.filter { target in
            ReminderRuleDefaults.rule(for: target, in: rules)?.isEnabled ?? false
        }.count
    }

    static let keys = ["settings.calendar.hourcycle.system", "settings.calendar.hourcycle.h12",
                       "settings.calendar.hourcycle.h24"]
}
