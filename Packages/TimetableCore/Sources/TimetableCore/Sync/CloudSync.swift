import Foundation

// CloudKit sync, pure part (Phase 6 S1; PHASE6_PLAN decisions 2–3). Nothing here imports CloudKit: the app turns a
// `CloudRecord` into a `CKRecord` and back (App/Sources/Sync/CloudSyncController.swift, `#if TABULA_CLOUDKIT`).
//
// Layout: private database, one custom zone (`CloudSyncSchema.zoneName`), one record per entity:
//   record type = `EntityType.rawValue` (DOMAIN_MODEL §2.3), record name = the entity's JSON `id`,
//   field `payload` (bytes) = the entity's canonical JSON incl. `meta` and unknown keys, field `schemaVersion` (Int64).
// Tombstones are ordinary records whose payload has `meta.isDeleted = true`. Tabula never deletes a CKRecord: a delete
// must reach devices that are offline, and merge rule 3 needs the tombstone's clock. A CKRecord deletion seen on the
// server (CloudKit Console, a zone reset) is therefore not a delete; the record is simply sent again.
// Pending changes: `CloudSyncLedger.serverHashes` keeps the SHA-256 of the payload last known to be on the server (sent
// or fetched). A record is pending iff its current payload hash differs. It is derived from the database itself, so it
// is correct across restarts and crashes without an outbox; the engine's own pending list is only a cache of it.

/// Names and limits of the CloudKit layout.
public enum CloudSyncSchema {
    /// The custom record zone in the private database.
    public static let zoneName = "Tabula"
    /// Bytes field holding the entity JSON.
    public static let payloadField = "payload"
    /// Int64 field: the `TabulaDatabase.schemaVersion` the payload was written with.
    public static let schemaVersionField = "schemaVersion"
    /// A CKRecord holds at most 1 MB; the payload must leave room for the system fields and the version field.
    public static let maxPayloadBytes = 900_000
}

/// One entity as a CloudKit record, without CloudKit types.
public struct CloudRecord: Hashable, Sendable {
    public var type: EntityType
    public var name: String
    public var payload: Data
    public var schemaVersion: Int

    public init(type: EntityType, name: String, payload: Data, schemaVersion: Int) {
        self.type = type
        self.name = name
        self.payload = payload
        self.schemaVersion = schemaVersion
    }

    /// SHA-256 (hex) of the payload: the version the ledger compares.
    public var payloadHash: String { TabulaSHA256.hexDigest(payload) }
    /// `true` when the record cannot be saved (CloudKit's 1 MB record limit).
    public var isTooLarge: Bool { payload.count > CloudSyncSchema.maxPayloadBytes }
}

/// Why a fetched record was not applied.
public enum CloudRecordError: Error, Hashable, Sendable {
    /// Written by a newer app version (a record type or schema version this build does not know).
    case newerVersion
    /// Not a valid Tabula record (bad JSON, `id` ≠ record name, undecodable entity, over the size limit).
    case malformed(String)
}

extension TabulaDatabase {
    /// Every entity (tombstones included) and the settings singleton as records.
    public func cloudRecords() throws -> [CloudRecord] {
        var records = [try cloudRecord(settings)]
        func add<E: SyncEntity>(_ entities: [E]) throws {
            for entity in entities { records.append(try cloudRecord(entity)) }
        }
        try add(timetables)
        try add(subjects)
        try add(bellSchedules)
        try add(lessons)
        try add(terms)
        try add(breaks)
        try add(overrides)
        try add(tasks)
        try add(exams)
        try add(reminderRules)
        return records
    }

    /// The record of `entity`, with the unknown keys this database keeps for it.
    func cloudRecord<E: SyncEntity>(_ entity: E) throws -> CloudRecord {
        let object = (unknownFields.fields(of: entity) ?? EntityUnknownFields())
            .applied(to: try SyncJSON.object(entity), type: E.entityType)
        return CloudRecord(type: E.entityType, name: try SyncJSON.id(of: object),
                           payload: try TabulaJSON.makeEncoder().encode(JSONValue.object(object)),
                           schemaVersion: schemaVersion)
    }

    /// `true` when any entity (other than the settings singleton) is not deleted.
    public var hasLiveContent: Bool {
        timetables.contains { !$0.isDeleted } || subjects.contains { !$0.isDeleted }
            || bellSchedules.contains { !$0.isDeleted } || lessons.contains { !$0.isDeleted }
            || terms.contains { !$0.isDeleted } || breaks.contains { !$0.isDeleted }
            || overrides.contains { !$0.isDeleted } || tasks.contains { !$0.isDeleted }
            || exams.contains { !$0.isDeleted } || reminderRules.contains { !$0.isDeleted }
    }
}

/// Fetched records, decoded into a database that `SyncMerge.merge(local:remote:)` can take.
public struct CloudRecordBatch: Sendable {
    /// The accepted records. Settings stay `AppSettings.untouchedDefaults` (the merge's neutral element) unless a
    /// settings record arrived.
    public var database: TabulaDatabase
    /// Record name → payload hash of every accepted record, re-encoded by this build (what `cloudRecords()` will
    /// produce for it locally, so an applied record is not pending).
    public var hashes: [String: String]
    /// Record name → why it was skipped. Skipped records are never applied and never acknowledged.
    public var rejected: [String: CloudRecordError]

    /// Decodes `records`. Every record is untrusted input: size, schema version, JSON shape, `id` = record name and
    /// the entity decoding are checked; a bad record is skipped, never fatal for the batch.
    public init(_ records: [CloudRecord]) {
        database = TabulaDatabase(settings: .untouchedDefaults)
        hashes = [:]
        rejected = [:]
        var accepted: [String: EntityType] = [:]
        for record in records {
            do {
                try Self.decode(record, into: &database)
                accepted[record.name] = record.type
            } catch let error as CloudRecordError {
                rejected[record.name] = error
            } catch {
                rejected[record.name] = .malformed(String(describing: error))
            }
        }
        for record in (try? database.cloudRecords()) ?? [] where accepted[record.name] == record.type {
            hashes[record.name] = record.payloadHash
        }
    }

    private static func decode(_ record: CloudRecord, into database: inout TabulaDatabase) throws {
        guard record.schemaVersion <= TabulaDatabase.currentSchemaVersion else { throw CloudRecordError.newerVersion }
        guard !record.isTooLarge else { throw CloudRecordError.malformed("payload over \(CloudSyncSchema.maxPayloadBytes) bytes") }
        guard case .object(let object) = try SyncJSONParser.parse(record.payload) else {
            throw CloudRecordError.malformed("payload is not a JSON object")
        }
        guard object["id"]?.stringValue == record.name else { throw CloudRecordError.malformed("id differs from the record name") }
        switch record.type {
        case .settings: try add(object, \.settings, to: &database)
        case .timetable: try append(object, \.timetables, to: &database)
        case .subject: try append(object, \.subjects, to: &database)
        case .bellSchedule: try append(object, \.bellSchedules, to: &database)
        case .lesson: try append(object, \.lessons, to: &database)
        case .term: try append(object, \.terms, to: &database)
        case .calendarBreak: try append(object, \.breaks, to: &database)
        case .scheduleOverride: try append(object, \.overrides, to: &database)
        case .task: try append(object, \.tasks, to: &database)
        case .exam: try append(object, \.exams, to: &database)
        case .reminderRule: try append(object, \.reminderRules, to: &database)
        }
    }

    private static func append<E: SyncEntity>(_ object: [String: JSONValue], _ path: WritableKeyPath<TabulaDatabase, [E]>,
                                              to database: inout TabulaDatabase) throws {
        let value: E = try entity(object, unknown: &database.unknownFields)
        database[keyPath: path].append(value)
    }

    private static func add<E: SyncEntity>(_ object: [String: JSONValue], _ path: WritableKeyPath<TabulaDatabase, E>,
                                           to database: inout TabulaDatabase) throws {
        let value: E = try entity(object, unknown: &database.unknownFields)
        database[keyPath: path] = value
    }

    private static func entity<E: SyncEntity>(_ object: [String: JSONValue], unknown: inout UnknownFields) throws -> E {
        _ = try SyncJSON.meta(of: object)
        let value = try SyncJSON.decode(object, as: E.self)
        unknown.setFields(EntityUnknownFields.extracted(from: object, type: E.entityType), for: E.entityType, id: value.id.uuid)
        return value
    }
}

/// What the device keeps about the server, in its own file next to the store (`cloudsync.json`); the persisted
/// database schema is untouched. Losing or corrupting this file is safe: a fresh ledger means "first sync" again,
/// which merges by default and never drops data.
public struct CloudSyncLedger: Codable, Hashable, Sendable {
    /// Record name → payload hash last known to be on the server (sent or fetched).
    public var serverHashes: [String: String] = [:]
    /// Record name → archived CKRecord system fields (change tag), opaque here.
    public var systemFields: [String: Data] = [:]
    /// The archived `CKSyncEngine.State.Serialization`, opaque here.
    public var engineState: Data?
    /// `true` once the first fetch for this account was applied (with the user's first-sync choice).
    public var initialSyncDone = false
    /// The end of the last successful fetch or send.
    public var lastSyncedAt: Date?

    public init() {}

    /// The records whose current payload is not the one on the server.
    public func pending(_ records: [CloudRecord]) -> [CloudRecord] {
        records.filter { serverHashes[$0.name] != $0.payloadHash }
    }

    /// The ledger stored at `url`; a fresh one when the file is missing or unreadable.
    public static func load(from url: URL) -> CloudSyncLedger {
        guard let data = try? Data(contentsOf: url),
              let ledger = try? JSONDecoder().decode(CloudSyncLedger.self, from: data) else { return CloudSyncLedger() }
        return ledger
    }

    /// Writes the ledger atomically (write to a temporary file, then rename).
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

/// What the sync status line says (Settings › iCloud).
public enum CloudSyncStatus: Hashable, Sendable {
    case off
    case notSyncedYet
    case syncing
    case synced(Date)
    case noAccount
    case quotaExceeded
    case itemsTooLarge
    case newerAppVersion
    case iCloudDataDeleted
}

/// The user's answer when this device and iCloud both hold data on the first sync (ARCHITECTURE "iCloud sync").
public enum FirstSyncChoice: String, CaseIterable, Sendable {
    /// Keep everything from both sides (field-level merge). The default.
    case merge
    /// This device's data wins: iCloud-only entities are deleted, shared ones take this device's values.
    case keepThisDevice
    /// iCloud's data wins: device-only entities are deleted (kept as tombstones), shared ones take iCloud's values.
    case useICloud
}

/// First-sync decision logic.
public enum CloudFirstSync {
    /// Ask only when both sides hold live user data (the settings singleton alone does not count).
    public static func needsChoice(local: TabulaDatabase?, remote: TabulaDatabase) -> Bool {
        (local?.hasLiveContent ?? false) && remote.hasLiveContent
    }

    /// The database after applying `choice`. `.merge` is `SyncMerge.merge`. The other two re-stamp the losing side
    /// toward the winner (`MutationStamper.stamp(old: loser, new: winner)`, so the winner's values carry the newest
    /// clocks, and a delete for entities only the loser has) and merge that with the winner: every device that merges
    /// the uploaded result converges on the winner's data, and nothing is dropped without a tombstone.
    public static func resolve(_ choice: FirstSyncChoice, local: TabulaDatabase, remote: TabulaDatabase,
                               clock: inout HybridLogicalClock, now: Date) throws -> TabulaDatabase {
        switch choice {
        case .merge:
            return try SyncMerge.merge(local: local, remote: remote)
        case .keepThisDevice:
            return try SyncMerge.merge(local: local, remote: restamped(remote, toward: local, clock: &clock, now: now))
        case .useICloud:
            return try SyncMerge.merge(local: restamped(local, toward: remote, clock: &clock, now: now), remote: remote)
        }
    }

    private static func restamped(_ loser: TabulaDatabase, toward winner: TabulaDatabase,
                                  clock: inout HybridLogicalClock, now: Date) throws -> TabulaDatabase {
        var result = loser
        // Untouched settings on the winning side (e.g. no settings record in iCloud) have nothing to impose.
        if winner.settings.meta.updatedAt > .zero {
            var target = winner.settings
            target.id = loser.settings.id
            result.settings = try MutationStamper.stamp(old: loser.settings, new: target, clock: &clock, now: now)
        }
        result.timetables = try restamped(loser.timetables, toward: winner.timetables, clock: &clock, now: now)
        result.subjects = try restamped(loser.subjects, toward: winner.subjects, clock: &clock, now: now)
        result.bellSchedules = try restamped(loser.bellSchedules, toward: winner.bellSchedules, clock: &clock, now: now)
        result.lessons = try restamped(loser.lessons, toward: winner.lessons, clock: &clock, now: now)
        result.terms = try restamped(loser.terms, toward: winner.terms, clock: &clock, now: now)
        result.breaks = try restamped(loser.breaks, toward: winner.breaks, clock: &clock, now: now)
        result.overrides = try restamped(loser.overrides, toward: winner.overrides, clock: &clock, now: now)
        result.tasks = try restamped(loser.tasks, toward: winner.tasks, clock: &clock, now: now)
        result.exams = try restamped(loser.exams, toward: winner.exams, clock: &clock, now: now)
        result.reminderRules = try restamped(loser.reminderRules, toward: winner.reminderRules, clock: &clock, now: now)
        return result
    }

    private static func restamped<E: SyncEntity>(_ loser: [E], toward winner: [E], clock: inout HybridLogicalClock,
                                                 now: Date) throws -> [E] {
        let winners = Dictionary(winner.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try loser.map { entity in
            if let target = winners[entity.id] { return try MutationStamper.stamp(old: entity, new: target, clock: &clock, now: now) }
            return entity.isDeleted ? entity : try MutationStamper.delete(entity, clock: &clock, now: now)
        }
    }
}
