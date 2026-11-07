import Foundation

// Cheaper record building for CloudKit sync (Phase 10 C1). The layout and the bytes are unchanged (CloudSync.swift):
//   CloudRecordSource         one record by name, for the send batch (only the records the engine asks for are built)
//   CloudRecordIndex          `cloudRecords()` with the previous call's records and hashes kept for unchanged entities
//   CloudRecordEncoding       the byte check behind the `cloudRecord` fast path (no parse + second encode)
// Equivalence tests: CloudSyncIncrementalTests.

/// Builds single records by name without encoding the others (C1, the send batch). The lookup costs one UUID hash
/// per entity; each record is encoded only when asked for.
public struct CloudRecordSource: Sendable {
    private struct Location: Sendable {
        var type: EntityType
        var index: Int
    }

    private let database: TabulaDatabase
    private let locations: [UUID: Location]

    /// A source over `database` (a value: later changes to the app's database are not seen).
    public init(database: TabulaDatabase) {
        self.database = database
        var locations: [UUID: Location] = [:]
        locations.reserveCapacity(database.entityCount)
        // Same order as `cloudRecords()`; the first entity per ID wins, like the first record per name there.
        func addAll<E: SyncEntity>(_ entities: [E]) {
            for (index, entity) in entities.enumerated() where locations[entity.id.uuid] == nil {
                locations[entity.id.uuid] = Location(type: E.entityType, index: index)
            }
        }
        addAll([database.settings])
        addAll(database.timetables)
        addAll(database.subjects)
        addAll(database.bellSchedules)
        addAll(database.lessons)
        addAll(database.terms)
        addAll(database.breaks)
        addAll(database.overrides)
        addAll(database.tasks)
        addAll(database.exams)
        addAll(database.reminderRules)
        self.locations = locations
    }

    /// The record named `name`, or `nil` when no entity has that name. Record names are canonical uppercase UUID
    /// strings (`EntityID.uuidString`), so any other spelling names nothing, exactly as in `cloudRecords()`.
    public func record(named name: String) throws -> CloudRecord? {
        guard let uuid = UUID(uuidString: name), uuid.uuidString == name, let location = locations[uuid] else { return nil }
        let index = location.index
        switch location.type {
        case .settings: return try database.cloudRecord(database.settings)
        case .timetable: return try database.cloudRecord(database.timetables[index])
        case .subject: return try database.cloudRecord(database.subjects[index])
        case .bellSchedule: return try database.cloudRecord(database.bellSchedules[index])
        case .lesson: return try database.cloudRecord(database.lessons[index])
        case .term: return try database.cloudRecord(database.terms[index])
        case .calendarBreak: return try database.cloudRecord(database.breaks[index])
        case .scheduleOverride: return try database.cloudRecord(database.overrides[index])
        case .task: return try database.cloudRecord(database.tasks[index])
        case .exam: return try database.cloudRecord(database.exams[index])
        case .reminderRule: return try database.cloudRecord(database.reminderRules[index])
        }
    }
}

/// A record with its payload hash, as `CloudRecordIndex` returns it.
public struct HashedCloudRecord: Hashable, Sendable {
    public var record: CloudRecord
    /// `record.payloadHash`, computed once.
    public var hash: String

    public init(record: CloudRecord, hash: String) {
        self.record = record
        self.hash = hash
    }
}

/// `cloudRecords()` built incrementally (C1). The records of the previous call are kept together with the entity value
/// and unknown keys they were built from; only entities that differ (`!=`) are encoded and hashed again. A record is a
/// pure function of (entity, its unknown keys, `schemaVersion`), so a kept record is the one `cloudRecords()` builds.
///
/// One caveat of `==`: Swift treats canonically equivalent strings (NFC vs NFD) and ±0 as equal. Such a change carries
/// no new clock (the stamper compares the same way), and the earlier, equivalent bytes are kept until the next launch.
/// Nothing is lost and nothing loops: the ledger compares the hash of the bytes actually sent.
///
/// A value. The sync adapter keeps one and hands a copy to its off-main scan; any index is valid for any database
/// (it is only a cache), so overlapping scans may store their results in any order.
public struct CloudRecordIndex: Sendable {
    private struct Key: Hashable, Sendable {
        var type: EntityType
        var id: UUID
    }

    private struct Entry: Sendable {
        var entity: any SyncEntity
        var unknown: EntityUnknownFields?
        var record: HashedCloudRecord
    }

    private var entries: [Key: Entry] = [:]
    private var schemaVersion: Int?
    /// How many records the last `records(for:)` call encoded (the others were kept). Diagnostics and tests.
    public private(set) var lastEncodedCount = 0

    public init() {}

    /// Every record of `database` with its hash, in `cloudRecords()` order and equal to it. Throws when an entity
    /// cannot be encoded (like `cloudRecords()`); the index is then unchanged. Entries of entities that are gone are
    /// dropped.
    public mutating func records(for database: TabulaDatabase) throws -> [HashedCloudRecord] {
        let previous = schemaVersion == database.schemaVersion ? entries : [:]
        var next: [Key: Entry] = [:]
        next.reserveCapacity(database.entityCount)
        var output: [HashedCloudRecord] = []
        output.reserveCapacity(database.entityCount)
        var encoded = 0
        func addOne<E: SyncEntity>(_ entity: E) throws {
            let key = Key(type: E.entityType, id: entity.id.uuid)
            let unknown = database.unknownFields.fields(of: entity)
            if let cached = next[key] ?? previous[key], let value = cached.entity as? E, value == entity,
               cached.unknown == unknown {
                next[key] = cached
                output.append(cached.record)
                return
            }
            let record = try database.cloudRecord(entity)
            let hashed = HashedCloudRecord(record: record, hash: record.payloadHash)
            encoded += 1
            next[key] = Entry(entity: entity, unknown: unknown, record: hashed)
            output.append(hashed)
        }
        func addAll<E: SyncEntity>(_ entities: [E]) throws {
            for entity in entities { try addOne(entity) }
        }
        try addOne(database.settings)
        try addAll(database.timetables)
        try addAll(database.subjects)
        try addAll(database.bellSchedules)
        try addAll(database.lessons)
        try addAll(database.terms)
        try addAll(database.breaks)
        try addAll(database.overrides)
        try addAll(database.tasks)
        try addAll(database.exams)
        try addAll(database.reminderRules)
        entries = next
        schemaVersion = database.schemaVersion
        lastEncodedCount = encoded
        return output
    }
}

/// The byte check behind the `cloudRecord` fast path.
enum CloudRecordEncoding {
    /// Most digits of an integer token the fast path accepts (`Int64.max` has 19; 18 always fits).
    static let maxIntegerDigits = 18

    /// `true` when `SyncJSONParser.parse(bytes)` followed by `TabulaJSON.makeEncoder().encode(JSONValue)` gives back
    /// exactly `bytes`, for `bytes` written by `TabulaJSON.makeEncoder()` (do not call it on other input).
    ///
    /// Argument, token by token, for encoder output that passes the check:
    /// - Objects: a keyed container never writes a key twice, the parser keeps every key, and both encodes sort the
    ///   same key strings with the same setting (`.sortedKeys`). Neither side writes whitespace.
    /// - Arrays keep their order. `true`/`false`/`null` stay (`.bool`; `.null` → `encodeNil`).
    /// - Strings: the parser decodes every escape the encoder writes (quote, backslash, `\b \f \n \r \t`, `\u00XX`;
    ///   slashes are not escaped), so the same Unicode scalars are encoded again by the same function: same bytes.
    /// - Numbers: the parser turns a token without `.`/`e`/`E` that fits `Int64` into `.integer`, re-encoded as its
    ///   canonical decimal, which equals the token iff the token is canonical. Integers of `Int`/`Int64`/smaller
    ///   types and dates (integer milliseconds, `TabulaJSON`) are canonical; the exceptions are `-0` (a `Double`
    ///   -0.0), digits beyond `Int64` (`UInt64`, a large `Double`) and leading zeros. A token with `.`/`e`/`E` comes
    ///   from a floating-point value, whose re-encoding depends on the formatter. So only integer tokens with at most
    ///   `maxIntegerDigits` digits, no leading zero and no `-0` pass; any other number rejects the whole payload.
    ///   Entities with such values (only `.unknown(JSONValue)` payloads from newer versions can hold one) take the
    ///   tree path, which is the reference.
    /// - Nesting deeper than `TabulaJSON.maxNestingDepth` makes the parser throw: rejected, so the tree path throws
    ///   exactly as before.
    static func reencodesIdentically(_ bytes: Data) -> Bool {
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let count = raw.count
            var index = 0
            var depth = 0
            var inString = false
            var escaped = false
            while index < count {
                let byte = raw[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == UInt8(ascii: "\\") {
                        escaped = true
                    } else if byte == UInt8(ascii: "\"") {
                        inString = false
                    }
                    index += 1
                    continue
                }
                switch byte {
                case UInt8(ascii: "\""):
                    inString = true
                case UInt8(ascii: "["), UInt8(ascii: "{"):
                    depth += 1
                    if depth > TabulaJSON.maxNestingDepth { return false }
                case UInt8(ascii: "]"), UInt8(ascii: "}"):
                    depth -= 1
                case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                    let negative = byte == UInt8(ascii: "-")
                    if negative { index += 1 }
                    let firstDigit = index
                    var digits = 0
                    while index < count, raw[index] >= UInt8(ascii: "0"), raw[index] <= UInt8(ascii: "9") {
                        digits += 1
                        index += 1
                    }
                    if index < count {
                        let next = raw[index]
                        if next == UInt8(ascii: ".") || next == UInt8(ascii: "e") || next == UInt8(ascii: "E")
                            || next == UInt8(ascii: "+") || next == UInt8(ascii: "-") {
                            return false
                        }
                    }
                    guard digits > 0, digits <= maxIntegerDigits else { return false }
                    if raw[firstDigit] == UInt8(ascii: "0"), digits > 1 || negative { return false }
                    continue   // `index` is already past the token
                default:
                    break
                }
                index += 1
            }
            return !inString && depth == 0
        }
    }
}

extension TabulaDatabase {
    /// Number of entities including the settings singleton (a capacity hint).
    var entityCount: Int {
        1 + timetables.count + subjects.count + bellSchedules.count + lessons.count + terms.count + breaks.count
            + overrides.count + tasks.count + exams.count + reminderRules.count
    }
}
