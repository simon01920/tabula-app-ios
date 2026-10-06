import Foundation

/// A timetable ("School", "Sport", "College"): its days, rotation, time structure and presentation.
public struct Timetable: SyncEntity {
    public typealias ID = EntityID<Timetable>
    public static let entityType: EntityType = .timetable

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// User-visible name (user text).
    public var name: String
    /// Optional emoji shown next to the name.
    public var emoji: String?
    /// Weekdays shown and scheduled (5/6/7-day week). JSON: ascending ISO numbers.
    public var enabledDays: Set<Weekday>
    /// Week/day rotation.
    public var rotation: RotationScheme
    /// Bell schedule or free-form times.
    public var timeStructure: TimeStructure
    /// Which optional lesson fields are shown (disabled → hidden everywhere, including the editor).
    public var fieldVisibility: FieldVisibility
    /// View the timetable opens in.
    public var defaultView: TimetableViewKind
    /// Compact or comfortable layout.
    public var density: Density
    /// Palette pack for this timetable; `nil` → `AppSettings.palettePackID`.
    public var palettePackID: PalettePackID?
    /// Position among timetables (ascending).
    public var sortIndex: Int

    /// Creates a timetable.
    public init(id: ID, meta: EntityMeta, name: String, emoji: String? = nil,
                enabledDays: Set<Weekday> = Weekday.workweek, rotation: RotationScheme = .none,
                timeStructure: TimeStructure, fieldVisibility: FieldVisibility = FieldVisibility(),
                defaultView: TimetableViewKind = .grid, density: Density = .comfortable,
                palettePackID: PalettePackID? = nil, sortIndex: Int = 0) {
        self.id = id
        self.meta = meta
        self.name = name
        self.emoji = emoji
        self.enabledDays = enabledDays
        self.rotation = rotation
        self.timeStructure = timeStructure
        self.fieldVisibility = fieldVisibility
        self.defaultView = defaultView
        self.density = density
        self.palettePackID = palettePackID
        self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id, meta, name, emoji, enabledDays, rotation, timeStructure, fieldVisibility, defaultView, density,
             palettePackID, sortIndex
    }

    /// Encodes with `enabledDays` as an ascending array.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(meta, forKey: .meta)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(emoji, forKey: .emoji)
        try container.encodeSorted(enabledDays, forKey: .enabledDays)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(timeStructure, forKey: .timeStructure)
        try container.encode(fieldVisibility, forKey: .fieldVisibility)
        try container.encode(defaultView, forKey: .defaultView)
        try container.encode(density, forKey: .density)
        try container.encodeIfPresent(palettePackID, forKey: .palettePackID)
        try container.encode(sortIndex, forKey: .sortIndex)
    }
}

/// How lesson times are defined for a timetable.
///
/// JSON: `{"kind":"bellSchedule","defaultID":"…","perWeekday":{"5":"…"}}` (keys are ISO weekday numbers) or
/// `{"kind":"freeForm","defaultDurationMinutes":90}`. Closed union.
public enum TimeStructure: Hashable, Sendable {
    /// Fixed periods from a bell schedule, with optional per-weekday schedules (e.g. a short Friday).
    case bellSchedule(defaultID: BellSchedule.ID, perWeekday: [Weekday: BellSchedule.ID])
    /// Free start/end times; new lessons default to `defaultDurationMinutes`.
    case freeForm(defaultDurationMinutes: Int)

    /// The bell schedule that applies on `weekday` before overrides (`nil` for free-form).
    public func bellScheduleID(for weekday: Weekday) -> BellSchedule.ID? {
        switch self {
        case let .bellSchedule(defaultID, perWeekday): return perWeekday[weekday] ?? defaultID
        case .freeForm: return nil
        }
    }

    /// Every bell schedule referenced (default first, then per-weekday ones by weekday).
    public var referencedBellScheduleIDs: [BellSchedule.ID] {
        switch self {
        case let .bellSchedule(defaultID, perWeekday):
            return [defaultID] + perWeekday.sorted { $0.key < $1.key }.map(\.value)
        case .freeForm:
            return []
        }
    }
}

extension TimeStructure: Codable {
    private enum CodingKeys: String, CodingKey { case kind, defaultID, perWeekday, defaultDurationMinutes }

    /// Decodes the tagged union; an unknown kind or a bad weekday key is a decoding error.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "bellSchedule":
            let raw = try container.decodeIfPresent([String: BellSchedule.ID].self, forKey: .perWeekday) ?? [:]
            var perWeekday: [Weekday: BellSchedule.ID] = [:]
            for (key, value) in raw {
                guard let number = Int(key), let weekday = Weekday(rawValue: number) else {
                    throw DecodingError.dataCorruptedError(forKey: .perWeekday, in: container,
                                                           debugDescription: "Invalid weekday key '\(key)'")
                }
                perWeekday[weekday] = value
            }
            self = .bellSchedule(defaultID: try container.decode(BellSchedule.ID.self, forKey: .defaultID),
                                 perWeekday: perWeekday)
        case "freeForm":
            self = .freeForm(defaultDurationMinutes: try container.decode(Int.self, forKey: .defaultDurationMinutes))
        default:
            throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "TimeStructure")
        }
    }

    /// Encodes the tagged union (`perWeekday` keyed by ISO weekday number strings; sorted by the encoder).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bellSchedule(defaultID, perWeekday):
            try container.encode("bellSchedule", forKey: .kind)
            try container.encode(defaultID, forKey: .defaultID)
            let raw = Dictionary(uniqueKeysWithValues: perWeekday.map { (String($0.key.rawValue), $0.value) })
            try container.encode(raw, forKey: .perWeekday)
        case .freeForm(let minutes):
            try container.encode("freeForm", forKey: .kind)
            try container.encode(minutes, forKey: .defaultDurationMinutes)
        }
    }
}

/// The set of optional lesson fields a timetable shows. JSON: an ascending array of field names.
///
/// Field rule (PRODUCT.md): a disabled field is hidden everywhere including the editor; an enabled but
/// empty field is simply absent from the UI. Visibility is applied by the UI, never by storing placeholders.
public struct FieldVisibility: Hashable, Sendable {
    /// The enabled fields.
    public var visibleFields: Set<LessonField>

    /// Creates a visibility set (empty = all optional fields off).
    public init(_ visibleFields: Set<LessonField> = []) {
        self.visibleFields = visibleFields
    }

    /// Every known field enabled.
    public static let all = FieldVisibility(Set(LessonField.knownValues))

    /// `true` when `field` is enabled.
    public func isVisible(_ field: LessonField) -> Bool { visibleFields.contains(field) }
}

extension FieldVisibility: Codable {
    /// Decodes an array of field names (unknown names are preserved).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.visibleFields = Set(try container.decode([LessonField].self))
    }

    /// Encodes an ascending array of field names.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(visibleFields.sorted())
    }
}
