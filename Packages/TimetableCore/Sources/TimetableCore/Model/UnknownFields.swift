import Foundation

// Forward compatibility for object keys (DOMAIN_MODEL Appendix B4).
//
// A newer app version may add top-level fields to an entity or child, or whole new entity arrays to the
// database root. An older version must keep those keys when it re-saves the database, otherwise every save
// by an older device would erase a newer device's data. `TabulaDatabase` therefore records every key that
// this version's entity encoding does not produce in a side table (`UnknownFields`) while decoding, and
// merges the keys back while encoding (the entity's own keys win on conflict).
//
// Scope: the database root, every entity (including `settings`) and every child record (`subtasks`,
// `attachments`). Keys *inside* embedded value objects (e.g. inside `rotation` or `timeSensitivePolicy`) are
// not preserved: a schema change there needs a version bump (DOMAIN_MODEL B4).

/// The JSON keys this app version knows, per entity type. Everything else is preserved as an unknown field.
///
/// The lists equal the entities' `CodingKeys` (= Swift property names, DOMAIN_MODEL §3). A test checks them
/// against the types via reflection, so adding a field without updating this catalog fails the build's tests.
/// The sync layer also uses the catalog to know which keys of an entity hold child collections.
public enum EntityFieldCatalog {
    /// Keys every entity and child record carries besides its fields.
    public static let identityKeys: Set<String> = ["id", "meta"]

    /// The field keys (excluding `id` and `meta`) of a top-level entity of `type`.
    public static func fieldKeys(for type: EntityType) -> Set<String> {
        switch type {
        case .settings:
            return ["profile", "onboardingCompletedAt", "activeTimetableID", "weekStartOverride", "hourCycle",
                    "timeZoneMode", "appearance", "palettePackID", "globalQuietHours", "timeSensitivePolicy",
                    "alarmPolicy", "syncEnabled"]
        case .timetable:
            return ["name", "emoji", "enabledDays", "rotation", "timeStructure", "fieldVisibility", "defaultView",
                    "density", "palettePackID", "sortIndex"]
        case .subject:
            return ["timetableID", "name", "shortName", "color", "colorName", "symbol", "defaultRoom",
                    "defaultBuilding", "defaultTeacher", "notes"]
        case .bellSchedule:
            return ["timetableID", "name", "periods"]
        case .lesson:
            return ["timetableID", "subjectID", "occurrence", "slot", "validity", "room", "building", "teacher",
                    "lessonType", "notes", "bringList"]
        case .term:
            return ["timetableID", "name", "range"]
        case .calendarBreak:
            return ["timetableID", "name", "range", "kind"]
        case .scheduleOverride:
            return ["timetableID", "date", "change"]
        case .task:
            return ["title", "kind", "subjectID", "timetableID", "due", "linkedLesson", "priority", "notes",
                    "repeatRule", "completedAt", "subtasks", "attachments", "reminderOverride"]
        case .exam:
            return ["timetableID", "subjectID", "title", "kind", "date", "start", "end", "room", "building",
                    "topics", "notes", "reminderOverride", "completedAt"]
        case .reminderRule:
            return ["target", "offsets", "followUp", "tier", "quietHours", "isEnabled", "origin"]
        }
    }

    /// The child collections of `type`: collection JSON key → field keys of its child records (excluding
    /// `id` and `meta`). Child collections are set-merged by child `id` during sync.
    public static func childCollections(for type: EntityType) -> [String: Set<String>] {
        switch type {
        case .task:
            return ["subtasks": ["title", "completedAt", "sortIndex"],
                    "attachments": ["kind", "title", "fileName", "url", "contentType", "byteCount", "sortIndex"]]
        default:
            return [:]
        }
    }

    /// `fieldKeys(for:)` plus `identityKeys`.
    static func knownKeys(for type: EntityType) -> Set<String> {
        fieldKeys(for: type).union(identityKeys)
    }
}

/// Unknown keys of one entity (and of its child records), preserved for re-encoding.
public struct EntityUnknownFields: Hashable, Sendable {
    /// Unknown top-level keys of the entity object.
    public var fields: [String: JSONValue]
    /// Unknown keys of child records: collection key (`"subtasks"`) → child ID → unknown keys.
    public var children: [String: [UUID: [String: JSONValue]]]

    /// Creates a record of unknown keys.
    public init(fields: [String: JSONValue] = [:], children: [String: [UUID: [String: JSONValue]]] = [:]) {
        self.fields = fields
        self.children = children
    }

    /// `true` when nothing is recorded.
    public var isEmpty: Bool {
        fields.isEmpty && children.values.allSatisfy { $0.values.allSatisfy(\.isEmpty) }
    }

    /// Copies the unknown keys into `object` (the JSON object of an entity of `type`). Keys the entity
    /// already has, and keys this version knows, are never overwritten (known keys win).
    public func applied(to object: [String: JSONValue], type: EntityType) -> [String: JSONValue] {
        var object = object
        let known = EntityFieldCatalog.knownKeys(for: type)
        for (key, value) in fields where !known.contains(key) && object[key] == nil {
            object[key] = value
        }
        let collections = EntityFieldCatalog.childCollections(for: type)
        for (collection, byID) in children where !byID.isEmpty {
            guard let childFields = collections[collection], case .array(var items)? = object[collection] else {
                continue
            }
            let childKnown = childFields.union(EntityFieldCatalog.identityKeys)
            for index in items.indices {
                guard case .object(var child) = items[index], let idString = child["id"]?.stringValue,
                      let id = UUID(uuidString: idString), let extra = byID[id] else { continue }
                for (key, value) in extra where !childKnown.contains(key) && child[key] == nil {
                    child[key] = value
                }
                items[index] = .object(child)
            }
            object[collection] = .array(items)
        }
        return object
    }

    /// The unknown keys of `object` (the full JSON object of an entity of `type`, e.g. a merge result).
    public static func extracted(from object: [String: JSONValue], type: EntityType) -> EntityUnknownFields {
        var result = EntityUnknownFields()
        let known = EntityFieldCatalog.knownKeys(for: type)
        for (key, value) in object where !known.contains(key) {
            result.fields[key] = value
        }
        for (collection, childFields) in EntityFieldCatalog.childCollections(for: type) {
            guard case .array(let items)? = object[collection] else { continue }
            let childKnown = childFields.union(EntityFieldCatalog.identityKeys)
            for item in items {
                guard case .object(let child) = item, let idString = child["id"]?.stringValue,
                      let id = UUID(uuidString: idString) else { continue }
                let extra = child.filter { !childKnown.contains($0.key) }
                if !extra.isEmpty { result.children[collection, default: [:]][id] = extra }
            }
        }
        return result
    }

    /// Reads the unknown keys of the entity object `decoder` points at (called next to the entity's own
    /// `init(from:)` on the same decoder, so the object is parsed only once).
    static func scan(_ decoder: any Decoder, type: EntityType) throws -> EntityUnknownFields {
        let container = try decoder.container(keyedBy: UnknownFieldsCodingKey.self)
        let known = EntityFieldCatalog.knownKeys(for: type)
        var result = EntityUnknownFields()
        for key in container.allKeys where !known.contains(key.stringValue) {
            result.fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        for (collection, childFields) in EntityFieldCatalog.childCollections(for: type) {
            let collectionKey = UnknownFieldsCodingKey(collection)
            guard container.contains(collectionKey), try !container.decodeNil(forKey: collectionKey) else { continue }
            let childKnown = childFields.union(EntityFieldCatalog.identityKeys)
            var items = try container.nestedUnkeyedContainer(forKey: collectionKey)
            while !items.isAtEnd {
                let child = try items.nestedContainer(keyedBy: UnknownFieldsCodingKey.self)
                let extra = child.allKeys.filter { !childKnown.contains($0.stringValue) }
                guard !extra.isEmpty else { continue }
                let idKey = UnknownFieldsCodingKey("id")
                let idString = try child.decode(String.self, forKey: idKey)
                guard let id = UUID(uuidString: idString) else {
                    throw DecodingError.dataCorruptedError(forKey: idKey, in: child,
                                                           debugDescription: "Invalid UUID '\(idString)'")
                }
                var fields: [String: JSONValue] = [:]
                for key in extra { fields[key.stringValue] = try child.decode(JSONValue.self, forKey: key) }
                result.children[collection, default: [:]][id] = fields
            }
        }
        return result
    }

    /// A copy without keys that this version knows, without empty child entries and without entries for
    /// child IDs that are not in `childIDs` (collection → live child IDs).
    func pruned(type: EntityType, childIDs: [String: Set<UUID>]) -> EntityUnknownFields {
        let known = EntityFieldCatalog.knownKeys(for: type)
        var copy = EntityUnknownFields(fields: fields.filter { !known.contains($0.key) })
        let collections = EntityFieldCatalog.childCollections(for: type)
        for (collection, byID) in children {
            guard let childFields = collections[collection] else { continue }
            let childKnown = childFields.union(EntityFieldCatalog.identityKeys)
            let present = childIDs[collection] ?? []
            var kept: [UUID: [String: JSONValue]] = [:]
            for (id, extra) in byID where present.contains(id) {
                let filtered = extra.filter { !childKnown.contains($0.key) }
                if !filtered.isEmpty { kept[id] = filtered }
            }
            if !kept.isEmpty { copy.children[collection] = kept }
        }
        return copy
    }
}

/// Every JSON key of a database this app version does not understand, kept so that re-encoding writes it
/// back unchanged (DOMAIN_MODEL Appendix B4).
public struct UnknownFields: Hashable, Sendable {
    /// Unknown keys of the database root object, e.g. an entity array added by a newer version.
    public var root: [String: JSONValue]
    /// Unknown keys per entity: entity type → entity ID → keys. `settings` is keyed by its ID as well.
    public var entities: [EntityType: [UUID: EntityUnknownFields]]

    /// Creates a side table (empty by default).
    public init(root: [String: JSONValue] = [:], entities: [EntityType: [UUID: EntityUnknownFields]] = [:]) {
        self.root = root
        self.entities = entities
    }

    /// `true` when nothing is recorded.
    public var isEmpty: Bool {
        root.isEmpty && entities.values.allSatisfy { $0.values.allSatisfy(\.isEmpty) }
    }

    /// The unknown keys recorded for the entity of `type` with `id`, if any.
    public func fields(for type: EntityType, id: UUID) -> EntityUnknownFields? {
        entities[type]?[id]
    }

    /// The unknown keys recorded for `entity`, if any.
    public func fields<E: SyncEntity>(of entity: E) -> EntityUnknownFields? {
        fields(for: E.entityType, id: entity.id.uuid)
    }

    /// Records `value` for the entity of `type` with `id`; `nil` or an empty value removes the entry.
    public mutating func setFields(_ value: EntityUnknownFields?, for type: EntityType, id: UUID) {
        if let value, !value.isEmpty {
            entities[type, default: [:]][id] = value
        } else {
            entities[type]?[id] = nil
            if entities[type]?.isEmpty == true { entities[type] = nil }
        }
    }
}

/// A coding key for arbitrary JSON object keys.
struct UnknownFieldsCodingKey: CodingKey, Hashable {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Codes one entity object together with its unknown keys. Encoding without unknown keys produces exactly
/// the entity's own bytes.
struct UnknownFieldsEnvelope<Entity: SyncEntity>: Codable {
    var entity: Entity
    var unknown: EntityUnknownFields

    init(entity: Entity, unknown: EntityUnknownFields?) {
        self.entity = entity
        self.unknown = unknown ?? EntityUnknownFields()
    }

    init(from decoder: any Decoder) throws {
        entity = try Entity(from: decoder)
        unknown = try EntityUnknownFields.scan(decoder, type: Entity.entityType)
    }

    func encode(to encoder: any Encoder) throws {
        if unknown.isEmpty {
            try entity.encode(to: encoder)
        } else if unknown.children.isEmpty {
            // Fast path: the entity's keyed container plus a second keyed container on the same encoder;
            // both write into the same JSON object (sorted by the encoder).
            try entity.encode(to: encoder)
            let known = EntityFieldCatalog.knownKeys(for: Entity.entityType)
            var container = encoder.container(keyedBy: UnknownFieldsCodingKey.self)
            for (key, value) in unknown.fields where !known.contains(key) {
                try container.encode(value, forKey: UnknownFieldsCodingKey(key))
            }
        } else {
            // Child keys must go inside the entity's child arrays: go through the JSON tree.
            guard case .object(let object) = try JSONValue(encoding: entity) else {
                throw EncodingError.invalidValue(entity, .init(codingPath: encoder.codingPath,
                                                               debugDescription: "Entity is not a JSON object"))
            }
            try JSONValue.object(unknown.applied(to: object, type: Entity.entityType)).encode(to: encoder)
        }
    }
}

extension TabulaDatabase {
    /// The IDs of the entities of `type` in this database (`settings`: its single ID).
    func entityIDs(of type: EntityType) -> Set<UUID> {
        switch type {
        case .settings: return [settings.id.uuid]
        case .timetable: return Set(timetables.map(\.id.uuid))
        case .subject: return Set(subjects.map(\.id.uuid))
        case .bellSchedule: return Set(bellSchedules.map(\.id.uuid))
        case .lesson: return Set(lessons.map(\.id.uuid))
        case .term: return Set(terms.map(\.id.uuid))
        case .calendarBreak: return Set(breaks.map(\.id.uuid))
        case .scheduleOverride: return Set(overrides.map(\.id.uuid))
        case .task: return Set(tasks.map(\.id.uuid))
        case .exam: return Set(exams.map(\.id.uuid))
        case .reminderRule: return Set(reminderRules.map(\.id.uuid))
        }
    }

    /// The side table restricted to what encoding would write: entries of entities and children that exist,
    /// without keys this version knows.
    func prunedUnknownFields() -> UnknownFields {
        var result = UnknownFields(root: unknownFields.root.filter { !Self.isRootKey($0.key) })
        var childIDsByTask: [UUID: [String: Set<UUID>]] = [:]
        if unknownFields.entities[.task] != nil {
            for task in tasks {
                childIDsByTask[task.id.uuid] = ["subtasks": Set(task.subtasks.map(\.id.uuid)),
                                                "attachments": Set(task.attachments.map(\.id.uuid))]
            }
        }
        for (type, byID) in unknownFields.entities {
            let present = entityIDs(of: type)
            for (id, fields) in byID where present.contains(id) {
                let childIDs = type == .task ? (childIDsByTask[id] ?? [:]) : [:]
                result.setFields(fields.pruned(type: type, childIDs: childIDs), for: type, id: id)
            }
        }
        return result
    }
}
