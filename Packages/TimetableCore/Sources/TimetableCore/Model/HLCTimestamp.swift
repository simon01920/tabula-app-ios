import Foundation

/// A hybrid-logical-clock timestamp: physical milliseconds, a logical counter and the writing node.
///
/// Ordering is lexicographic on `(physicalMillis, logical, node)`; the node breaks ties deterministically.
/// This is the data type only — the clock algorithm (`tick`, `receive`) lives in the sync layer.
///
/// JSON: a fixed-width string whose **byte order equals time order**:
/// `PPPPPPPPPPPPPPP-LLLLLLLLLL-NNNNNNNNNNNNNNNN` = 15 decimal digits of physical milliseconds since 1970
/// (valid until the year 33658), 10 decimal digits of the logical counter, 16 lowercase hex digits of the
/// node. Example: `"001791273600000-0000000003-00000000cafebabe"`.
public struct HLCTimestamp: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Milliseconds since 1970-01-01T00:00:00Z, 0…`maxPhysicalMillis`.
    public let physicalMillis: Int64
    /// Logical counter for events within the same millisecond.
    public let logical: UInt32
    /// Identifier of the device/process that produced the timestamp.
    public let node: UInt64

    /// Largest physical time representable in the 15-digit encoding.
    public static let maxPhysicalMillis: Int64 = 999_999_999_999_999

    /// The smallest timestamp (`0`, `0`, `0`); sorts before every real timestamp.
    public static let zero = HLCTimestamp(physicalMillis: 0, logical: 0, node: 0)

    /// Length of the string encoding.
    public static let stringLength = 43

    /// Creates a timestamp. Traps unless `0 ≤ physicalMillis ≤ maxPhysicalMillis`.
    public init(physicalMillis: Int64, logical: UInt32, node: UInt64) {
        precondition((0...Self.maxPhysicalMillis).contains(physicalMillis), "HLCTimestamp physicalMillis out of range")
        self.physicalMillis = physicalMillis
        self.logical = logical
        self.node = node
    }

    /// Parses the fixed-width string form; `nil` for any other string.
    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == Self.stringLength, bytes[15] == UInt8(ascii: "-"), bytes[26] == UInt8(ascii: "-"),
              let physical = Self.decimal(bytes[0..<15]), let logical = Self.decimal(bytes[16..<26]),
              logical <= UInt64(UInt32.max), let node = Self.lowerHex(bytes[27..<43]) else { return nil }
        self.init(physicalMillis: Int64(physical), logical: UInt32(logical), node: node)
    }

    /// The fixed-width string form (see type documentation).
    public var stringValue: String {
        PaddedNumber.decimal(physicalMillis, width: 15) + "-" +
            PaddedNumber.decimal(logical, width: 10) + "-" +
            PaddedNumber.hex(node, width: 16, uppercase: false)
    }

    /// Same as `stringValue`.
    public var description: String { stringValue }

    public static func < (lhs: HLCTimestamp, rhs: HLCTimestamp) -> Bool {
        (lhs.physicalMillis, lhs.logical, lhs.node) < (rhs.physicalMillis, rhs.logical, rhs.node)
    }

    private static func decimal(_ bytes: ArraySlice<UInt8>) -> UInt64? {
        var value: UInt64 = 0
        for byte in bytes {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            value = value * 10 + UInt64(byte - UInt8(ascii: "0"))
        }
        return value
    }

    private static func lowerHex(_ bytes: ArraySlice<UInt8>) -> UInt64? {
        var value: UInt64 = 0
        for byte in bytes {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            default: return nil
            }
            value = value << 4 | UInt64(digit)
        }
        return value
    }
}

extension HLCTimestamp: Codable {
    /// Decodes the fixed-width string; anything else is a `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = HLCTimestamp(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid HLCTimestamp '\(string)'")
        }
        self = value
    }

    /// Encodes the fixed-width string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}
