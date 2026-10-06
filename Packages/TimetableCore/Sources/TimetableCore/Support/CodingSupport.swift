import Foundation

// Internal helpers shared by the hand-written `Codable` implementations.
//
// Conventions for persisted JSON (see docs/specs/DOMAIN_MODEL.md):
// - Tagged unions are objects with a `"kind"` discriminator plus named payload keys.
// - `Set`s are encoded as arrays sorted ascending, so encoding is independent of hash seeds.
// - `nil` optionals are omitted (synthesised `encodeIfPresent`).

extension KeyedEncodingContainer {
    /// Encodes a set as an ascending array (deterministic regardless of the per-process hash seed).
    mutating func encodeSorted<T: Encodable & Comparable>(_ value: Set<T>, forKey key: Key) throws {
        try encode(value.sorted(), forKey: key)
    }

    /// Encodes an optional set as an ascending array; omits the key when `nil`.
    mutating func encodeSortedIfPresent<T: Encodable & Comparable>(_ value: Set<T>?, forKey key: Key) throws {
        if let value { try encode(value.sorted(), forKey: key) }
    }
}

extension KeyedDecodingContainer {
    /// Decodes the `"kind"` discriminator of a tagged union as a raw string.
    func decodeKind(forKey key: Key) throws -> String {
        try decode(String.self, forKey: key)
    }
}

/// Errors thrown by Tabula's hand-written decoders.
enum TabulaCodingError {
    /// A `DecodingError` for an unknown discriminator of a *closed* union.
    static func unknownKind<K: CodingKey>(_ kind: String, key: K, in container: KeyedDecodingContainer<K>,
                                          type: String) -> DecodingError {
        DecodingError.dataCorruptedError(forKey: key, in: container,
                                         debugDescription: "Unknown \(type) kind '\(kind)'")
    }
}
