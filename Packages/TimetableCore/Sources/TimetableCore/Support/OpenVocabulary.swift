// Open (forward-compatible) string vocabularies.
//
// A persisted vocabulary that may grow in a later app version must not break decoding of the whole
// database when an older app meets a value it does not know (PHASE1_PLAN §0). Such vocabularies are
// string-backed structs instead of enums: any string decodes, unknown values round-trip unchanged and
// `isKnown` tells consumers to fall back to a neutral presentation.

/// A string-backed, open set of values that round-trips unknown members unchanged.
///
/// Conforming types are structs with a single `rawValue` and `static let` members for the known values.
/// JSON encoding is the plain raw string (the standard library's `RawRepresentable` `Codable` defaults).
public protocol OpenVocabulary: RawRepresentable, Codable, Hashable, Comparable, Sendable, CustomStringConvertible
where RawValue == String {
    /// Creates a value from any string. Never fails: unknown strings are preserved.
    init(rawValue: String)

    /// The values this app version understands, in a stable presentation order.
    static var knownValues: [Self] { get }
}

extension OpenVocabulary {
    /// `true` when this app version understands the value. Unknown values must be preserved, never rewritten.
    public var isKnown: Bool { Self.knownValues.contains(self) }

    /// The raw string.
    public var description: String { rawValue }

    /// Orders by raw value (byte order), which keeps sorted encodings deterministic.
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
