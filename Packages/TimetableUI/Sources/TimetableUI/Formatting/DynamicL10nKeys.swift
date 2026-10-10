// Every String Catalog key the app builds at runtime from an enum value (key families). The App target must obtain
// such keys here and wrap them with `LocalizedStringKey(String)` of a variable — never with an interpolated literal
// (`LocalizedStringKey("a.\(x)")` becomes the format key "a.%@", which is not in the catalog and shows raw).
// `DynamicL10nKeyTests` enumerates `allKeys` and asserts that each exists in Resources/Localizable.xcstrings.
import Foundation
import TimetableCore

public enum DynamicL10nKeys {
    public static func profile(_ value: UserProfile) -> String { "settings.profile." + value.rawValue }
    public static func periodKind(_ value: PeriodKind) -> String { "editor.bell.kind." + value.rawValue }
    public static func breakKind(_ value: BreakKind) -> String { "editor.breaks.kind." + value.rawValue }
    public static func rotationKind(_ value: TimetableDraft.RotationKind) -> String { "editor.rotation.kind." + value.rawValue }
    public static func lessonField(_ value: LessonField) -> String { "editor.field." + value.rawValue }
    public static func defaultView(_ value: TimetableViewKind) -> String { "editor.view." + value.rawValue }
    public static func reminderTarget(_ value: ReminderTarget) -> String { "onboarding.reminders.target." + value.rawValue }
    /// Catalog key of a lesson field's name in the lesson detail list (`LessonDetailView`).
    public static func lessonDetailField(_ field: LessonField) -> String {
        switch field {
        case .room: return "timetable.detail.field.room"
        case .building: return "timetable.detail.field.building"
        case .teacher: return "timetable.detail.field.teacher"
        case .lessonType: return "timetable.detail.field.lessonType"
        case .notes: return "timetable.detail.field.notes"
        default: return "timetable.detail.field.bringList"
        }
    }

    /// Titles of the timetable-level editors listed in the options menu (`ManagementSheet.entries`).
    public static let managementTitleKeys: [String] = [
        "editor.timetable.title", "editor.bell.title", "editor.subjects.title", "editor.terms.title",
    ]

    /// `base` + the profile's terminology suffix (selects between two complete catalog strings).
    public static func term(_ base: String, _ terminology: ProfilePreset.Terminology) -> String {
        base + "." + terminology.rawValue
    }

    /// Bases passed to `term(_:_:)` by the onboarding screens.
    public static let termBases: [String] = [
        "onboarding.time.title", "onboarding.time.length", "onboarding.time.firstStart", "onboarding.time.count",
        "onboarding.time.longBreak", "onboarding.time.preview.row", "onboarding.reminders.target",
    ]

    /// All keys of all families, for every possible value.
    public static var allKeys: [String] {
        var keys: [String] = []
        keys += UserProfile.knownValues.map(profile)
        keys += PeriodKind.knownValues.map(periodKind)
        keys += BreakKind.knownValues.map(breakKind)
        keys += TimetableDraft.RotationKind.allCases.map(rotationKind)
        keys += LessonField.knownValues.map(lessonField)
        keys += TimetableViewKind.knownValues.map(defaultView)
        keys += ReminderTarget.knownValues.map(reminderTarget)
        for base in termBases {
            keys += ProfilePreset.Terminology.allCases.map { term(base, $0) }
        }
        // Keys produced by model types.
        keys += TimetableViewKind.knownValues.map(TimetableViewChoice.nameKey)
        keys += DayChangeDraft.Kind.allCases.map(\.l10nKey)
        keys += DayChangeDraft.Issue.allCases.map(\.l10nKey)
        keys += SlotDraft.Issue.allCases.map(\.l10nKey)
        keys += LessonDraft.Issue.allCases.map(\.l10nKey)
        keys += SubjectDraft.Issue.allCases.map(\.l10nKey)
        keys += TimetableDraft.Issue.allCases.map(\.l10nKey)
        keys += ProfilePreset.Terminology.allCases.map(\.l10nKey)
        keys += ProfileChoices.offered.map(ProfileChoices.terminologyKey(for:))
        keys += LessonField.knownValues.map(lessonDetailField)
        keys += managementTitleKeys
        // Known lesson types only: an unknown type has no key and shows its raw text (user / newer-version data).
        keys += LessonType.knownValues.compactMap(VisibleLessonFields.nameKey(of:))
        keys += ["timetable.cycle.namedWeek", "timetable.cycle.numberedWeek", "timetable.cycle.namedDay",
                 "timetable.cycle.numberedDay"]
        return Array(Set(keys)).sorted()
    }
}
