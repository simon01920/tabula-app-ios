import Foundation

/// A lossless, `Codable` representation of an arbitrary JSON value.
///
/// Used to preserve values this app version does not understand (for example an unknown
/// `OverrideChange` kind written by a newer version) and by the sync layer to diff fields.
/// Integers and floating-point numbers are kept apart so 64-bit integers survive a round trip.
public enum JSONValue: Hashable, Sendable {
    /// JSON `null`.
    case null
    /// JSON `true` / `false`.
    case bool(Bool)
    /// A JSON number without a fractional part that fits in `Int64`.
    case integer(Int64)
    /// Any other JSON number.
    case double(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array.
    case array([JSONValue])
    /// A JSON object. Encoded with sorted keys by `TabulaJSON`.
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    /// Decodes any JSON value. Booleans are tried before numbers so `true` never becomes `1`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    /// Encodes the value unchanged.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    /// Converts any `Encodable` value into its JSON tree using `TabulaJSON` settings.
    public init(encoding value: some Encodable) throws {
        let data = try TabulaJSON.makeEncoder().encode(value)
        self = try TabulaJSON.makeDecoder().decode(JSONValue.self, from: data)
    }

    /// Decodes this JSON tree as `type` using `TabulaJSON` settings.
    public func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try TabulaJSON.makeEncoder().encode(self)
        return try TabulaJSON.makeDecoder().decode(type, from: data)
    }

    /// The member for `key` when this is an object, else `nil`.
    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    /// The string payload when this is `.string`, else `nil`.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
