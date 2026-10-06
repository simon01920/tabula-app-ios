/// Every String Catalog key TimetableCore can emit, so that docs and the catalog can be checked against the
/// code. DOMAIN_MODEL Appendix A lists each key (`DomainModelDocTests`), and `Resources/Localizable.xcstrings`
/// holds an English source value for each (`StringCatalogTests`).
public enum CoreL10n {
    /// Model, validation, conflict, preset, palette and sample-data keys (Stage 1, plus the validation codes
    /// added in Stage 3) — Appendix A.1–A.6.
    public static var modelKeys: [String] {
        var keys = EntityType.allCases.map(\.l10nKey)
        keys += ValidationIssue.Code.allCases.map(\.l10nKey)
        keys += Conflict.Kind.allCases.map(\.l10nKey)
        keys += ProfilePreset.Terminology.allCases.map(\.l10nKey)
        for pack in PalettePack.all {
            keys.append(pack.nameKey)
            keys += pack.colors.map(\.nameKey)
        }
        keys += SampleData.allKeys
        return keys
    }

    /// Share codec keys (Stage 2D) — Appendix A.9.
    public static var shareKeys: [String] { ShareError.allL10nKeys + ShareWarning.allL10nKeys }

    /// Every key, in Appendix A order: model (A.1–A.6), schedule (A.7), reminders (A.8), share (A.9).
    public static var allKeys: [String] {
        modelKeys + ScheduleL10n.allKeys + ReminderL10n.allKeys + shareKeys
    }
}
