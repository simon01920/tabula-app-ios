/// The text policy of the share format (docs/specs/SHARE_FORMAT.md §5.3).
///
/// Shared text is user data: it is stored verbatim and never interpreted (no format specifiers, markup or
/// catalog keys). To keep hostile payloads from spoofing the UI, some scalars are forbidden:
/// - C0 controls U+0000–U+001F (multi-line text may contain TAB U+0009 and LF U+000A), DEL and C1 controls
///   U+007F–U+009F;
/// - line/paragraph separators U+2028, U+2029;
/// - bidi embeddings/overrides U+202A–U+202E and isolates U+2066–U+2069 (marks such as U+200E/U+200F stay
///   allowed);
/// - interlinear annotation U+FFF9–U+FFFB and noncharacters (U+FDD0–U+FDEF, U+xxFFFE, U+xxFFFF).
///
/// Import rejects such text (`ShareError.invalidCharacters`); export removes the characters (line breaks in
/// single-line text become spaces; CR LF / CR in notes become LF) and shortens over-long text.
enum ShareText {
    /// Whether line breaks and tabs are allowed.
    enum Kind: Sendable {
        /// Names, labels, rooms, list items: no line breaks or tabs.
        case singleLine
        /// Notes: LF and TAB allowed.
        case multiLine
    }

    /// `true` when `scalar` may not appear in shared text of `kind`.
    static func isForbidden(_ scalar: Unicode.Scalar, kind: Kind) -> Bool {
        let value = scalar.value
        switch value {
        case 0x09, 0x0A: return kind == .singleLine
        case 0x00...0x1F, 0x7F...0x9F: return true
        case 0x2028, 0x2029: return true
        case 0x202A...0x202E, 0x2066...0x2069: return true
        case 0xFFF9...0xFFFB: return true
        case 0xFDD0...0xFDEF: return true
        default: return value & 0xFFFE == 0xFFFE
        }
    }

    /// Length as counted by every limit: Unicode scalars.
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    /// Import check: throws when `text` is longer than `limit` scalars or contains a forbidden scalar.
    static func check(_ text: String, path: @autoclosure () -> String, limit: Int,
                      kind: Kind = .singleLine) throws(ShareError) {
        var count = 0
        for scalar in text.unicodeScalars {
            count += 1
            if isForbidden(scalar, kind: kind) { throw .invalidCharacters(path: path()) }
        }
        if count > limit { throw .stringTooLong(path: path(), length: count) }
    }

    /// Import check for an open-vocabulary raw value: 1…`ShareLimits.maxVocabularyLength` ASCII characters from
    /// `A–Z a–z 0–9 _ . -`.
    static func checkVocabulary(_ raw: String, path: @autoclosure () -> String) throws(ShareError) {
        guard isValidVocabulary(raw) else { throw .invalidValue(path: path()) }
    }

    /// `true` for a well-formed open-vocabulary raw value.
    static func isValidVocabulary(_ raw: String) -> Bool {
        let bytes = raw.utf8
        guard (1...ShareLimits.maxVocabularyLength).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "-"):
                return true
            default:
                return false
            }
        }
    }

    /// `true` for a well-formed SF Symbol name: 1…`ShareLimits.maxSystemImageLength` of `a–z 0–9 .`.
    static func isValidSystemImage(_ name: String) -> Bool {
        let bytes = name.utf8
        guard (1...ShareLimits.maxSystemImageLength).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: ".")
        }
    }

    /// `true` for an acceptable emoji value: 1…`ShareLimits.maxEmojiLength` scalars, no forbidden scalar.
    static func isValidEmoji(_ text: String) -> Bool {
        let count = length(text)
        return (1...ShareLimits.maxEmojiLength).contains(count)
            && !text.unicodeScalars.contains { isForbidden($0, kind: .singleLine) }
    }

    /// Export: the text with forbidden scalars removed and shortened to at most `limit` scalars without
    /// splitting a grapheme cluster.
    static func sanitize(_ text: String, limit: Int, kind: Kind = .singleLine)
        -> (text: String, removedCharacters: Bool, shortened: Bool) {
        var removed = false
        var cleaned = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            defer { previousWasCR = value == 0x0D }
            switch (kind, value) {
            case (.multiLine, 0x0A) where previousWasCR:
                continue // CR LF → the LF already emitted for the CR
            case (.multiLine, 0x0D), (.multiLine, 0x2028), (.multiLine, 0x2029):
                cleaned.append("\n")
                removed = true
            case (.singleLine, 0x09), (.singleLine, 0x0A), (.singleLine, 0x0D), (.singleLine, 0x2028),
                 (.singleLine, 0x2029):
                cleaned.append(" ")
                removed = true
            default:
                if isForbidden(scalar, kind: kind) {
                    removed = true
                } else {
                    cleaned.append(scalar)
                }
            }
        }
        let result = String(cleaned)
        guard result.unicodeScalars.count > limit else { return (result, removed, false) }
        var shortened = ""
        var count = 0
        for character in result {
            let scalars = character.unicodeScalars.count
            if count + scalars > limit { break }
            shortened.append(character)
            count += scalars
        }
        return (shortened, removed, true)
    }
}
