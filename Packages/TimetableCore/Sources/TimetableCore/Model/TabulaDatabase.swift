import Foundation

/// The persisted schema root: every entity of the app plus the settings singleton.
///
/// - `schemaVersion` is `TabulaDatabase.currentSchemaVersion` (1) for data written by this version.
///   Decoding does **not** reject other versions; the repository decides (migration / read-only mode).
/// - **Deterministic encoding:** every entity array is written sorted by `id`, every set sorted, every
///   object's keys sorted (via `TabulaJSON`). The same logical database always yields the same bytes,
///   regardless of the order arrays were built in. (Duplicate IDs — reported by `validate()` — are the
///   one case where ordering is not total.)
/// - Missing arrays decode as empty.
/// - Tombstoned entities (`meta.isDeleted`) are part of the database.
/// - **Unknown keys survive** (DOMAIN_MODEL B4): keys of the root object, of entities and of child records
///   that this version does not know are kept in `unknownFields` and written back on encode.
public struct TabulaDatabase: Hashable, Sendable {
    /// The schema version written by this app version.
    public static let currentSchemaVersion = TimetableCoreInfo.schemaVersion

    /// Schema version of this data.
    public var schemaVersion: Int
    /// The settings singleton.
    public var settings: AppSettings
    /// Timetables.
    public var timetables: [Timetable]
    /// Subjects.
    public var subjects: [Subject]
    /// Bell schedules.
    public var bellSchedules: [BellSchedule]
    /// Recurring lessons.
    public var lessons: [Lesson]
    /// Terms / semesters.
    public var terms: [Term]
    /// Holidays and other breaks.
    public var breaks: [CalendarBreak]
    /// One-off schedule overrides.
    public var overrides: [ScheduleOverride]
    /// Tasks.
    public var tasks: [TaskItem]
    /// Exams.
    public var exams: [Exam]
    /// Reminder rules.
    public var reminderRules: [ReminderRule]
    /// JSON keys written by a newer app version that this version does not understand. Preserved so that
    /// re-saving the database does not erase them (DOMAIN_MODEL B4). Entries of entities that are no longer
    /// in the database are ignored on encode.
    public var unknownFields: UnknownFields

    /// Creates a database (empty collections by default).
    public init(schemaVersion: Int = TabulaDatabase.currentSchemaVersion, settings: AppSettings,
                timetables: [Timetable] = [], subjects: [Subject] = [], bellSchedules: [BellSchedule] = [],
                lessons: [Lesson] = [], terms: [Term] = [], breaks: [CalendarBreak] = [],
                overrides: [ScheduleOverride] = [], tasks: [TaskItem] = [], exams: [Exam] = [],
                reminderRules: [ReminderRule] = [], unknownFields: UnknownFields = UnknownFields()) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.timetables = timetables
        self.subjects = subjects
        self.bellSchedules = bellSchedules
        self.lessons = lessons
        self.terms = terms
        self.breaks = breaks
        self.overrides = overrides
        self.tasks = tasks
        self.exams = exams
        self.reminderRules = reminderRules
        self.unknownFields = unknownFields
    }

    /// A copy with every entity array sorted by `id`, task children in canonical order and `unknownFields`
    /// restricted to what encoding writes — the value that decoding the canonical encoding produces.
    /// `canonicalized() == decode(encode(self))`.
    public func canonicalized() -> TabulaDatabase {
        var copy = self
        copy.timetables.sort { $0.id < $1.id }
        copy.subjects.sort { $0.id < $1.id }
        copy.bellSchedules.sort { $0.id < $1.id }
        copy.lessons.sort { $0.id < $1.id }
        copy.terms.sort { $0.id < $1.id }
        copy.breaks.sort { $0.id < $1.id }
        copy.overrides.sort { $0.id < $1.id }
        copy.tasks.sort { $0.id < $1.id }
        for index in copy.tasks.indices {
            copy.tasks[index].subtasks.sort { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
            copy.tasks[index].attachments.sort { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
        }
        copy.exams.sort { $0.id < $1.id }
        copy.reminderRules.sort { $0.id < $1.id }
        copy.unknownFields = prunedUnknownFields()
        return copy
    }

    /// Canonical JSON bytes (`TabulaJSON.makeEncoder(pretty:)`).
    public func encoded(pretty: Bool = false) throws -> Data {
        try TabulaJSON.makeEncoder(pretty: pretty).encode(self)
    }

    /// Decodes a database from JSON produced by `encoded()` (or any compatible writer).
    public static func decode(from data: Data) throws -> TabulaDatabase {
        try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: data)
    }
}

extension TabulaDatabase: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, settings, timetables, subjects, bellSchedules, lessons, terms, breaks, overrides,
             tasks, exams, reminderRules
    }

    /// `true` when `key` is a root key this version knows.
    static func isRootKey(_ key: String) -> Bool { CodingKeys(stringValue: key) != nil }

    /// Decodes a database; absent arrays become empty; unknown keys go to `unknownFields`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var unknown = UnknownFields()

        func collection<E: SyncEntity>(_ key: CodingKeys) throws -> [E] {
            guard let envelopes = try c.decodeIfPresent([UnknownFieldsEnvelope<E>].self, forKey: key) else {
                return []
            }
            for envelope in envelopes where !envelope.unknown.isEmpty {
                unknown.setFields(envelope.unknown, for: E.entityType, id: envelope.entity.id.uuid)
            }
            return envelopes.map(\.entity)
        }

        let schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        let settings = try c.decode(UnknownFieldsEnvelope<AppSettings>.self, forKey: .settings)
        unknown.setFields(settings.unknown, for: .settings, id: settings.entity.id.uuid)
        let timetables: [Timetable] = try collection(.timetables)
        let subjects: [Subject] = try collection(.subjects)
        let bellSchedules: [BellSchedule] = try collection(.bellSchedules)
        let lessons: [Lesson] = try collection(.lessons)
        let terms: [Term] = try collection(.terms)
        let breaks: [CalendarBreak] = try collection(.breaks)
        let overrides: [ScheduleOverride] = try collection(.overrides)
        let tasks: [TaskItem] = try collection(.tasks)
        let exams: [Exam] = try collection(.exams)
        let reminderRules: [ReminderRule] = try collection(.reminderRules)

        let all = try decoder.container(keyedBy: UnknownFieldsCodingKey.self)
        for key in all.allKeys where !Self.isRootKey(key.stringValue) {
            unknown.root[key.stringValue] = try all.decode(JSONValue.self, forKey: key)
        }

        self.init(schemaVersion: schemaVersion, settings: settings.entity, timetables: timetables,
                  subjects: subjects, bellSchedules: bellSchedules, lessons: lessons, terms: terms, breaks: breaks,
                  overrides: overrides, tasks: tasks, exams: exams, reminderRules: reminderRules,
                  unknownFields: unknown)
    }

    /// Encodes every array sorted by `id` (deterministic output), with unknown keys merged back in
    /// (keys this version knows always win).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let unknown = unknownFields

        func encodeCollection<E: SyncEntity>(_ entities: [E], _ key: CodingKeys) throws {
            let byID = unknown.entities[E.entityType]
            try c.encode(entities.sorted { $0.id < $1.id }.map {
                UnknownFieldsEnvelope(entity: $0, unknown: byID?[$0.id.uuid])
            }, forKey: key)
        }

        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(UnknownFieldsEnvelope(entity: settings, unknown: unknown.fields(of: settings)),
                     forKey: .settings)
        try encodeCollection(timetables, .timetables)
        try encodeCollection(subjects, .subjects)
        try encodeCollection(bellSchedules, .bellSchedules)
        try encodeCollection(lessons, .lessons)
        try encodeCollection(terms, .terms)
        try encodeCollection(breaks, .breaks)
        try encodeCollection(overrides, .overrides)
        try encodeCollection(tasks, .tasks)
        try encodeCollection(exams, .exams)
        try encodeCollection(reminderRules, .reminderRules)

        let extraRootKeys = unknown.root.filter { !Self.isRootKey($0.key) }
        if !extraRootKeys.isEmpty {
            var extra = encoder.container(keyedBy: UnknownFieldsCodingKey.self)
            for (key, value) in extraRootKeys {
                try extra.encode(value, forKey: UnknownFieldsCodingKey(key))
            }
        }
    }
}
