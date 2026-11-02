import Foundation

/// String Catalog keys of the import review (Phase 9), part of `CoreL10n.allKeys` (DOMAIN_MODEL Appendix A.10;
/// the 12-language entries came with stage I2).
public enum ImportL10n {
    /// `"%1$@: “%2$@” or “%3$@”?"` — field name (nested `import.field.*`), current reading, other reading.
    public static let questionOCRReading = "import.question.ocrReading"
    /// `"Is “%1$@” %2$@?"` — the abbreviation, the known subject it may stand for.
    public static let questionAbbreviation = "import.question.abbreviation"
    /// `"Which is the subject in “%1$@”?"` — the cell text.
    public static let questionSplit = "import.question.split"
    /// `"%1$@ in “%2$@”: which is right?"` — field name (nested), the cell text. Tier A alternatives.
    public static let questionSuggestion = "import.question.suggestion"

    public static var questionKeys: [String] { [questionOCRReading, questionAbbreviation, questionSplit, questionSuggestion] }

    public static var allKeys: [String] {
        questionKeys + ImportField.allCases.map(\.l10nKey) + ImportConfidenceReason.allCases.map(\.l10nKey)
            + ImportNotice.allCases.map(\.l10nKey)
    }
}
