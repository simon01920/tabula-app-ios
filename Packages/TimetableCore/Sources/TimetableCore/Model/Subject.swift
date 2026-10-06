import Foundation

/// A subject (course) of a timetable, with its colour and default lesson fields.
public struct Subject: SyncEntity {
    public typealias ID = EntityID<Subject>
    public static let entityType: EntityType = .subject

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Owning timetable.
    public var timetableID: Timetable.ID
    /// Full name (user text).
    public var name: String
    /// Short name for tight grid cells; `nil` → the UI truncates `name`.
    public var shortName: String?
    /// Subject colour (opaque recommended; text colour is chosen with `ColorValue.preferredTextColor`).
    public var color: ColorValue
    /// Accessible colour name: a palette key until the user names it.
    public var colorName: TextValue?
    /// Emoji or SF Symbol shown with the subject.
    public var symbol: SubjectSymbol?
    /// Default room inherited by lessons that leave theirs empty.
    public var defaultRoom: String?
    /// Default building/faculty inherited by lessons.
    public var defaultBuilding: String?
    /// Default teacher inherited by lessons.
    public var defaultTeacher: String?
    /// Free-form notes.
    public var notes: String?

    /// Creates a subject.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID, name: String, shortName: String? = nil,
                color: ColorValue, colorName: TextValue? = nil, symbol: SubjectSymbol? = nil,
                defaultRoom: String? = nil, defaultBuilding: String? = nil, defaultTeacher: String? = nil,
                notes: String? = nil) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.name = name
        self.shortName = shortName
        self.color = color
        self.colorName = colorName
        self.symbol = symbol
        self.defaultRoom = defaultRoom
        self.defaultBuilding = defaultBuilding
        self.defaultTeacher = defaultTeacher
        self.notes = notes
    }
}

/// A subject's pictogram. JSON: `{"kind":"emoji","value":"📐"}` or `{"kind":"systemImage","value":"function"}`.
public enum SubjectSymbol: Hashable, Sendable {
    /// An emoji (user text).
    case emoji(String)
    /// An SF Symbol name; the UI falls back to no symbol if it does not exist on the running OS.
    case systemImage(String)
}

extension SubjectSymbol: Codable {
    private enum CodingKeys: String, CodingKey { case kind, value }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        switch kind {
        case "emoji": self = .emoji(value)
        case "systemImage": self = .systemImage(value)
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "SubjectSymbol")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let value):
            try container.encode("emoji", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .systemImage(let value):
            try container.encode("systemImage", forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
