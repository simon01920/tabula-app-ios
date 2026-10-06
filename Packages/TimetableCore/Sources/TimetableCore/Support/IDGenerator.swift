import Foundation

/// Source of new identifiers. Injected into every API that creates entities so core logic never calls `UUID()`.
///
/// Follows the standard library's `RandomNumberGenerator` pattern: APIs take `inout some IDGenerator`.
public protocol IDGenerator {
    /// Returns a new UUID. Implementations must not repeat a value within their lifetime.
    mutating func nextUUID() -> UUID
}

extension IDGenerator {
    /// Returns a new typed identifier.
    public mutating func next<Entity>(_ type: Entity.Type = Entity.self) -> EntityID<Entity> {
        EntityID(nextUUID())
    }
}

/// Production generator: random (version 4) UUIDs from the system.
public struct SystemIDGenerator: IDGenerator, Sendable {
    /// Creates a system generator.
    public init() {}

    /// A fresh random UUID.
    public mutating func nextUUID() -> UUID { UUID() }
}

/// Deterministic generator for tests, previews and golden files.
///
/// Produces `NNNNNNNN-0000-4000-8000-CCCCCCCCCCCC`, where `N` is the 32-bit `namespace` and `C` is a
/// 48-bit counter starting at `start`, both in uppercase hex. The UUIDs carry valid version-4 /
/// RFC 4122 variant bits. Two generators with different namespaces never collide.
public struct SequentialIDGenerator: IDGenerator, Sendable {
    /// The namespace written into the first group.
    public let namespace: UInt32
    /// The counter value of the next UUID.
    public private(set) var counter: UInt64

    /// The largest counter value that fits the 48-bit field.
    public static let maxCounter: UInt64 = (1 << 48) - 1

    /// Creates a generator. `start` must be ≤ `maxCounter`.
    public init(namespace: UInt32 = 0, start: UInt64 = 1) {
        precondition(start <= Self.maxCounter, "SequentialIDGenerator start exceeds 48 bits")
        self.namespace = namespace
        self.counter = start
    }

    /// The next UUID in the sequence. Traps when the 48-bit counter is exhausted.
    public mutating func nextUUID() -> UUID {
        precondition(counter <= Self.maxCounter, "SequentialIDGenerator exhausted")
        let string = "\(PaddedNumber.hex(UInt64(namespace), width: 8))-0000-4000-8000-\(PaddedNumber.hex(counter, width: 12))"
        counter += 1
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("SequentialIDGenerator produced an invalid UUID string \(string)")
        }
        return uuid
    }
}

/// Zero-padded number formatting without `String(format:)` (locale-independent, Linux-safe).
enum PaddedNumber {
    /// `value` in hexadecimal, left-padded with zeros to `width` digits.
    static func hex(_ value: UInt64, width: Int, uppercase: Bool = true) -> String {
        pad(String(value, radix: 16, uppercase: uppercase), width: width)
    }

    /// Non-negative `value` in decimal, left-padded with zeros to `width` digits.
    /// Generic so 64-bit values never pass through `Int` (32-bit on arm64_32 watches).
    static func decimal<T: BinaryInteger>(_ value: T, width: Int) -> String {
        precondition(value >= 0, "PaddedNumber.decimal expects a non-negative value")
        return pad(String(value), width: width)
    }

    private static func pad(_ raw: String, width: Int) -> String {
        raw.count >= width ? raw : String(repeating: "0", count: width - raw.count) + raw
    }
}
