// Catalog keys of the Tasks feature that are built from enum values (see DynamicL10nKeys for why they live in
// code). `allKeys` is merged into `DynamicL10nKeys.allKeys`, so `DynamicL10nKeyTests` checks each exists in
// Resources/Localizable.xcstrings.
import Foundation
import TimetableCore

public enum TaskL10nKeys {
    /// Name of a known task kind. Unknown (newer-version) kinds have no key: show the raw value.
    public static func kind(_ kind: TaskKind) -> String? {
        TaskKind.knownValues.contains(kind) ? "tasks.kind." + kind.rawValue : nil
    }

    public static func priority(_ priority: TaskPriority) -> String { "tasks.priority." + priority.rawValue }

    /// "high priority" / "urgent priority" for VoiceOver (only High and Urgent are announced).
    public static func priorityAccessibility(_ priority: TaskPriority) -> String { "a11y.task.priority." + priority.rawValue }

    public static func dueMode(_ mode: TaskDraft.DueMode) -> String { "tasks.editor.due.mode." + mode.rawValue }

    public static func repeatMode(_ mode: TaskDraft.RepeatMode) -> String { "tasks.editor.repeat.mode." + mode.rawValue }

    /// "Every day" (plain, interval 1) or "Every %lld days" (plural on the interval) for a known repeat frequency.
    public static func repeatEvery(frequency: RepeatFrequency, interval: Int) -> String {
        (interval == 1 ? "tasks.repeat.every1." : "tasks.repeat.every.") + frequency.rawValue
    }

    /// One-line description of a known task type, shown under the type picker (D5). Unknown kinds have none.
    public static func kindHint(_ kind: TaskKind) -> String? {
        TaskKind.knownValues.contains(kind) ? "tasks.kind." + kind.rawValue + ".hint" : nil
    }

    /// Keys of the relative due phrases.
    public static var dueKeys: [String] { TaskDueDescription.allKeys }

    /// All keys of all families.
    public static var allKeys: [String] {
        var keys: [String] = []
        keys += TaskKind.knownValues.compactMap(kind)
        keys += TaskPriority.allCases.map(priority)
        keys += [TaskPriority.high, .urgent].map(priorityAccessibility)
        keys += ["tasks.repeat.summary.weeklyOn", "tasks.repeat.summary.everyWeeksOn"]
        keys += TaskKind.knownValues.compactMap(kindHint)
        keys += TaskSection.allCases.map(\.titleKey)
        keys += TaskSort.allCases.map(\.titleKey)
        keys += TaskDraft.DueMode.allCases.map(dueMode)
        keys += TaskDraft.RepeatMode.allCases.map(repeatMode)
        for frequency in RepeatFrequency.knownValues {
            keys += [repeatEvery(frequency: frequency, interval: 1), repeatEvery(frequency: frequency, interval: 2)]
        }
        keys += TaskDraft.Issue.allCases.map(\.l10nKey)
        keys += dueKeys
        return Array(Set(keys)).sorted()
    }
}
