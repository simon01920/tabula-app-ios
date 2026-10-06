import Foundation

/// A localisable message: a String Catalog key plus typed arguments.
///
/// `TimetableCore` never contains user-facing strings. Anything a person reads is returned as a
/// `LocalizedText` and rendered by the UI layer (which owns the catalog, plural rules and formatters).
/// User-entered text is data and is passed as `.string` arguments, never as a key.
public struct LocalizedText: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The String Catalog key, e.g. `"validation.danglingReference"`.
    public var key: String
    /// Positional arguments, in the order the catalog entry expects them.
    public var args: [LocalizedArgument]

    /// Creates a message for `key` with `args`.
    public init(key: String, args: [LocalizedArgument] = []) {
        self.key = key
        self.args = args
    }

    /// Debug rendering (`key(arg, …)`), never shown to users.
    public var description: String {
        args.isEmpty ? key : "\(key)(\(args.map(\.description).joined(separator: ", ")))"
    }
}

/// A typed argument of a `LocalizedText`. Formatting (numbers, dates, times) is the UI's job.
public indirect enum LocalizedArgument: Hashable, Sendable, CustomStringConvertible {
    /// Verbatim text (usually user-entered data such as a subject name).
    case string(String)
    /// An integer; plural variations in the catalog select on it.
    case integer(Int)
    /// A calendar date, formatted by the UI with the user's locale.
    case date(LocalDate)
    /// A wall-clock time, formatted by the UI honouring the 12/24 h setting.
    case time(LocalTime)
    /// A nested localised message (e.g. an entity-type name inside a validation message).
    case text(LocalizedText)

    /// Debug rendering.
    public var description: String {
        switch self {
        case .string(let value): return "\"\(value)\""
        case .integer(let value): return String(value)
        case .date(let value): return value.description
        case .time(let value): return value.description
        case .text(let value): return value.description
        }
    }
}

extension LocalizedArgument: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case string, integer, date, time, text }

    /// Decodes `{"kind": …, "value": …}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .date: self = .date(try container.decode(LocalDate.self, forKey: .value))
        case .time: self = .time(try container.decode(LocalTime.self, forKey: .value))
        case .text: self = .text(try container.decode(LocalizedText.self, forKey: .value))
        }
    }

    /// Encodes `{"kind": …, "value": …}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .integer(let value):
            try container.encode(Kind.integer, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode(Kind.date, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .time(let value):
            try container.encode(Kind.time, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

/// Persisted display text that is either a catalog key (follows the app language) or literal user text.
///
/// Used where the app pre-fills a value the user may later overwrite, e.g. a subject's colour name
/// (`.key("palette.classic.color.red")` until the user types their own `.literal("Brick")`).
/// JSON: `{"kind":"key","value":"…"}` or `{"kind":"literal","value":"…"}`.
public enum TextValue: Hashable, Sendable {
    /// A String Catalog key resolved by the UI.
    case key(String)
    /// Verbatim user text.
    case literal(String)
}

extension TextValue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case key, literal }

    /// Decodes `{"kind": "key"|"literal", "value": …}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .key: self = .key(value)
        case .literal: self = .literal(value)
        }
    }

    /// Encodes `{"kind": "key"|"literal", "value": …}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let value):
            try container.encode(Kind.key, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .literal(let value):
            try container.encode(Kind.literal, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
