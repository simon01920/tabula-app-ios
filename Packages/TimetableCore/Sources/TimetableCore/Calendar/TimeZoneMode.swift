import Foundation

/// How Tabula picks the time zone that wall-clock school times are interpreted in.
///
/// JSON: `{"kind":"followDevice"}` or `{"kind":"fixed","identifier":"Europe/Bratislava"}`.
public enum TimeZoneMode: Hashable, Sendable {
    /// Use the device's current zone (default). School times are wall-clock times, so a lesson at 08:00
    /// stays at 08:00 local time after travelling; reminders must be re-planned on a zone change.
    case followDevice
    /// Always use this IANA zone (e.g. while abroad but following the home school's clock).
    case fixed(identifier: String)

    /// The zone to use. `.fixed` with an unknown identifier falls back to `deviceTimeZone`
    /// (`TabulaDatabase.validate()` reports the bad identifier).
    public func resolve(deviceTimeZone: TimeZone) -> TimeZone {
        switch self {
        case .followDevice: return deviceTimeZone
        case .fixed(let identifier): return TimeZone(identifier: identifier) ?? deviceTimeZone
        }
    }
}

extension TimeZoneMode: Codable {
    private enum CodingKeys: String, CodingKey { case kind, identifier }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "followDevice": self = .followDevice
        case "fixed": self = .fixed(identifier: try container.decode(String.self, forKey: .identifier))
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "TimeZoneMode")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .followDevice:
            try container.encode("followDevice", forKey: .kind)
        case .fixed(let identifier):
            try container.encode("fixed", forKey: .kind)
            try container.encode(identifier, forKey: .identifier)
        }
    }
}
