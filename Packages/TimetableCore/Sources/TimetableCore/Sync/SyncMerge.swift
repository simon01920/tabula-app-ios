import Foundation

/// State-based merge of two replicas (devices, a backup, a CloudKit record) — a join-semilattice: the merge
/// is commutative, associative and idempotent, so replicas that exchange state in any order converge.
///
/// **Conflict rules** (also DOMAIN_MODEL §2.2 / B4):
/// 1. **Fields — last writer wins per field.** Every top-level JSON key of an entity (except `id`/`meta`) is
///    a field with clock `meta.clock(for: key)` (explicit field clock, else `createdAt`). The greater HLC
///    wins; HLC order is (physical ms, logical counter, node), so a tie between devices is decided by the
///    higher node ID. An absent (nil) field is a value like any other. `BellSchedule.periods`,
///    `Lesson.bringList`, `Exam.topics` etc. are single fields (whole-value LWW).
/// 2. **Child collections** (`TaskItem.subtasks`, `TaskItem.attachments`) are set-merged by child `id`;
///    children on both sides are merged with rules 1 and 3; child tombstones stay in the array.
/// 3. **Tombstones — the newer of (delete, latest write) wins.** A tombstone's delete clock is its
///    `updatedAt`; a live replica asserts liveness at its `updatedAt` (its latest field write or restore).
///    The result is deleted iff the greatest delete clock ≥ the greatest liveness clock: an edit made after
///    the delete (on a device that had not seen it) resurrects the entity with all merged fields; an edit
///    made before it stays deleted; an exact tie keeps the delete. A restore is a liveness assertion
///    (`MutationStamper.restore`). Field values are merged even while deleted, so a later restore shows the
///    newest data.
/// 4. **Metadata:** `updatedAt` = later, `fieldClocks` = per-field later clock, `createdAt` = later (equal on
///    both sides for real replicas; "later" keeps the merge a join for hand-made data — see `SyncRecordMerger`),
///    written canonically (entries equal to `createdAt` omitted). Merge never issues new timestamps.
/// 5. **Unknown keys** (from newer app versions) are merged with the same field rules, using the field
///    clocks the newer version wrote. Unknown root arrays of records (`id` + `meta`) are set-merged like
///    child collections; other unknown root values: equal values stay, different values keep the one with
///    the greater canonical bytes (deterministic, rarely meaningful).
///
/// Requirements: every local mutation goes through `MutationStamper`; after merging remote data call
/// `clock.receive(remote.latestTimestamp, now:)` so later local edits sort after what was received.
public enum SyncMerge {
    /// Merges two versions of the same entity. Throws `SyncError.idMismatch` for different IDs.
    public static func merge<E: SyncEntity>(local: E, remote: E) throws -> E {
        let merged = try SyncRecordMerger.merge(SyncJSON.object(local), SyncJSON.object(remote),
                                                childCollections: childCollections(of: E.self))
        return try SyncJSON.decode(merged, as: E.self)
    }

    /// Merges two versions of the same child record (subtask, attachment).
    public static func merge<C: ChildEntity>(local: C, remote: C) throws -> C {
        let merged = try SyncRecordMerger.merge(SyncJSON.object(local), SyncJSON.object(remote), childCollections: [])
        return try SyncJSON.decode(merged, as: C.self)
    }

    /// Merges two databases: every entity array by ID, the settings singleton field by field, unknown keys
    /// included. Entities present on one side are kept as they are; identical entities are kept unchanged.
    /// The result is canonical (`canonicalized()`) and has the greater `schemaVersion` of the two
    /// (callers merge only databases of the current version; the repository migrates first).
    public static func merge(local: TabulaDatabase, remote: TabulaDatabase) throws -> TabulaDatabase {
        var unknown = UnknownFields()
        let settings = try mergeSettings(local, remote, into: &unknown)
        var result = TabulaDatabase(schemaVersion: max(local.schemaVersion, remote.schemaVersion), settings: settings)
        result.timetables = try mergeCollection(local.timetables, remote.timetables, local, remote, &unknown)
        result.subjects = try mergeCollection(local.subjects, remote.subjects, local, remote, &unknown)
        result.bellSchedules = try mergeCollection(local.bellSchedules, remote.bellSchedules, local, remote, &unknown)
        result.lessons = try mergeCollection(local.lessons, remote.lessons, local, remote, &unknown)
        result.terms = try mergeCollection(local.terms, remote.terms, local, remote, &unknown)
        result.breaks = try mergeCollection(local.breaks, remote.breaks, local, remote, &unknown)
        result.overrides = try mergeCollection(local.overrides, remote.overrides, local, remote, &unknown)
        result.tasks = try mergeCollection(local.tasks, remote.tasks, local, remote, &unknown)
        result.exams = try mergeCollection(local.exams, remote.exams, local, remote, &unknown)
        result.reminderRules = try mergeCollection(local.reminderRules, remote.reminderRules, local, remote, &unknown)
        unknown.root = try mergeRoot(local.unknownFields.root, remote.unknownFields.root)
        result.unknownFields = unknown
        return result.canonicalized()
    }

    // MARK: - Internals

    static func childCollections<E: SyncEntity>(of type: E.Type) -> Set<String> {
        Set(EntityFieldCatalog.childCollections(for: E.entityType).keys)
    }

    /// Merges one entity pair including unknown keys; returns the entity and its unknown keys.
    static func mergeEntity<E: SyncEntity>(_ a: E, _ unknownA: EntityUnknownFields?, _ b: E,
                                           _ unknownB: EntityUnknownFields?) throws -> (E, EntityUnknownFields?) {
        let plainA = unknownA?.isEmpty ?? true, plainB = unknownB?.isEmpty ?? true
        if a == b && unknownA == unknownB { return (a, unknownA) }
        if plainA && plainB { return (try merge(local: a, remote: b), nil) }
        let type = E.entityType
        let objectA = (unknownA ?? EntityUnknownFields()).applied(to: try SyncJSON.object(a), type: type)
        let objectB = (unknownB ?? EntityUnknownFields()).applied(to: try SyncJSON.object(b), type: type)
        let merged = try SyncRecordMerger.merge(objectA, objectB, childCollections: childCollections(of: E.self))
        return (try SyncJSON.decode(merged, as: E.self), EntityUnknownFields.extracted(from: merged, type: type))
    }

    private static func mergeCollection<E: SyncEntity>(_ a: [E], _ b: [E], _ dbA: TabulaDatabase,
                                                        _ dbB: TabulaDatabase,
                                                        _ unknown: inout UnknownFields) throws -> [E] {
        let type = E.entityType
        let byIDA = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byIDB = Dictionary(b.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [E] = []
        result.reserveCapacity(max(byIDA.count, byIDB.count))
        for id in Set(byIDA.keys).union(byIDB.keys).sorted() {
            let unknownA = dbA.unknownFields.fields(for: type, id: id.uuid)
            let unknownB = dbB.unknownFields.fields(for: type, id: id.uuid)
            switch (byIDA[id], byIDB[id]) {
            case let (x?, y?):
                let (merged, extra) = try mergeEntity(x, unknownA, y, unknownB)
                result.append(merged)
                unknown.setFields(extra, for: type, id: id.uuid)
            case let (x?, nil):
                result.append(x)
                unknown.setFields(unknownA, for: type, id: id.uuid)
            case let (nil, y?):
                result.append(y)
                unknown.setFields(unknownB, for: type, id: id.uuid)
            case (nil, nil):
                break
            }
        }
        return result
    }

    /// Settings are a singleton: both sides are always merged. If the IDs differ (invalid data), the result
    /// uses `AppSettings.singletonID` when either side has it, else the smaller ID.
    private static func mergeSettings(_ a: TabulaDatabase, _ b: TabulaDatabase,
                                      into unknown: inout UnknownFields) throws -> AppSettings {
        var settingsA = a.settings, settingsB = b.settings
        let unknownA = a.unknownFields.fields(of: a.settings), unknownB = b.unknownFields.fields(of: b.settings)
        if settingsA.id != settingsB.id {
            let id = [settingsA.id, settingsB.id].contains(AppSettings.singletonID)
                ? AppSettings.singletonID : min(settingsA.id, settingsB.id)
            settingsA.id = id
            settingsB.id = id
        }
        let (merged, extra) = try mergeEntity(settingsA, unknownA, settingsB, unknownB)
        unknown.setFields(extra, for: .settings, id: merged.id.uuid)
        return merged
    }

    private static func mergeRoot(_ a: [String: JSONValue], _ b: [String: JSONValue]) throws -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for key in Set(a.keys).union(b.keys) where !TabulaDatabase.isRootKey(key) {
            switch (a[key], b[key]) {
            case let (x?, y?):
                if x == y {
                    result[key] = x
                } else if SyncRecordMerger.isRecordArray(x) && SyncRecordMerger.isRecordArray(y) {
                    result[key] = try SyncRecordMerger.mergeRecordArrays(x, y)
                } else {
                    result[key] = SyncJSON.canonicalBytes(x).lexicographicallyPrecedes(SyncJSON.canonicalBytes(y)) ? y : x
                }
            case let (x?, nil): result[key] = x
            case let (nil, y?): result[key] = y
            case (nil, nil): break
            }
        }
        return result
    }
}

extension TabulaDatabase {
    /// The greatest HLC timestamp anywhere in the database (entity and child metadata, field clocks).
    /// Resume the device's `HybridLogicalClock` after it at launch, and `receive` it after merging remote data.
    public var latestTimestamp: HLCTimestamp {
        var latest = SyncJSON.latest(in: settings.meta)
        func fold<E: SyncEntity>(_ entities: [E]) {
            for entity in entities { latest = max(latest, SyncJSON.latest(in: entity.meta)) }
        }
        fold(timetables)
        fold(subjects)
        fold(bellSchedules)
        fold(lessons)
        fold(terms)
        fold(breaks)
        fold(overrides)
        fold(tasks)
        fold(exams)
        fold(reminderRules)
        for task in tasks {
            for subtask in task.subtasks { latest = max(latest, SyncJSON.latest(in: subtask.meta)) }
            for attachment in task.attachments { latest = max(latest, SyncJSON.latest(in: attachment.meta)) }
        }
        return latest
    }
}
