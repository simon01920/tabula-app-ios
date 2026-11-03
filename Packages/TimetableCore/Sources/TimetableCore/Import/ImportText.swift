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
        String(fold(text).map { lookAlikes[$0] ?? $0 })
    }

    private static let lookAlikes: [Character: Character] = ["o": "0", "l": "1", "i": "1"]

    /// One character folded like `lookAlikeFold`, without trimming (so positions can be mapped back).
    private static func foldCharacter(_ character: Character) -> [Character] {
        let manual: [Character: Character] = ["ł": "l", "đ": "d", "ı": "i", "ø": "o"]
        return String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .map { manual[$0] ?? $0 }.map { lookAlikes[$0] ?? $0 }
    }

    /// The part of `text`, in `text`'s own spelling, that matches `needle` ignoring case, diacritics and O/0, l/1
    /// look-alikes; `nil` when absent or when `needle` folds to fewer than 2 characters.
    static func verbatimSpan(of needle: String, in text: String) -> String? {
        let source = Array(text)
        var folded: [Character] = [], owner: [Int] = []
        for (index, character) in source.enumerated() {
            for piece in foldCharacter(character) {
                folded.append(piece)
                owner.append(index)
            }
        }
        let target = needle.flatMap(foldCharacter)
        guard target.count >= 2, target.count <= folded.count else { return nil }
        for start in 0...(folded.count - target.count) where folded[start..<(start + target.count)].elementsEqual(target) {
            return String(source[owner[start]...owner[start + target.count - 1]])
        }
        return nil
    }
}
