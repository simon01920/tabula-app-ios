import Foundation

/// A stable, phantom-typed UUID identifier. JSON: the plain uppercase UUID string.
///
/// The `Entity` parameter only exists at compile time, so a `Lesson.ID` cannot be passed where a
/// `Subject.ID` is expected. Decoding accepts lower- or uppercase; encoding is always uppercase.
/// Ordering (used for deterministic array order) is the byte order of the UUID.
public struct EntityID<Entity>: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The underlying UUID.
    public let uuid: UUID

    /// Wraps an existing UUID.
    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    /// Parses a UUID string, or `nil` if it is not a valid UUID.
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.uuid = uuid
    }

    /// The canonical uppercase string (`8-4-4-4-12`).
    public var uuidString: String { uuid.uuidString }

    /// Same as `uuidString`.
    public var description: String { uuidString }

    /// Re-types the identifier (e.g. for generic storage). Use sparingly.
    public func retyped<Other>(as _: Other.Type = Other.self) -> EntityID<Other> { EntityID<Other>(uuid) }

    /// Byte order of the UUID (equals the order of the uppercase hex strings).
    public static func < (lhs: EntityID, rhs: EntityID) -> Bool { lhs.uuidString < rhs.uuidString }
}

extension EntityID: Codable {
    /// Decodes a UUID string; anything else is a `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid UUID '\(string)'")
        }
        self.uuid = uuid
    }

    /// Encodes the uppercase UUID string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuidString)
    }
}
