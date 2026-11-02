import Foundation

/// Text folding shared by the import parser and reconciliation.
enum ImportText {
    /// Lower-cased, without diacritics, trimmed (`"Štvrtok"` → `"stvrtok"`, `"Środa"` → `"sroda"`).
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let manual: [Character: Character] = ["ł": "l", "đ": "d", "ı": "i", "ø": "o"]
        return String(folded.map { manual[$0] ?? $0 }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `fold` plus OCR look-alikes mapped to digits (o → 0, l/i → 1), for "is this text in the cell" checks.
    static func lookAlikeFold(_ text: String) -> String {
        let map: [Character: Character] = ["o": "0", "l": "1", "i": "1"]
        return String(fold(text).map { map[$0] ?? $0 })
    }
}
