import Foundation

/// The deterministic parser: `RecognizedTable` → `ImportCandidate` (PHASE9_PLAN decision 4).
public enum TimetableImportParser {
    /// Parses `table`. Never invents lessons: every lesson comes from a non-empty cell.
    public static func parse(_ table: RecognizedTable, options: ImportParserOptions = .init()) -> ImportCandidate {
        ImportCandidate(notices: [.emptyInput], languages: table.languages) // I1 step 2 fills this in
    }
}
