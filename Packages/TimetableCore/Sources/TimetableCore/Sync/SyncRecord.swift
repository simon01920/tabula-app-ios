import Foundation

/// Errors of the sync primitives.
public enum SyncError: Error, Hashable, Sendable {
    /// Two records with different IDs were passed where the same record was expected.
    case idMismatch(local: String, remote: String)
    /// A record's JSON is not an object, lacks `id`, or has a malformed `meta`.
    case malformedRecord(String)
}

/// JSON-level helpers. The sync layer works on the JSON form of entities because field clocks are keyed by
/// JSON key (DOMAIN_MODEL §2.2), and because the same code then also handles keys this version does not know.
enum SyncJSON {
    /// The JSON object of `value` (canonical `TabulaJSON` encoding).
    static func object(_ value: some Encodable) throws -> [String: JSONValue] {
        guard case .object(let object) = try SyncJSONParser.parse(TabulaJSON.makeEncoder().encode(value)) else {
            throw SyncError.malformedRecord("value does not encode as a JSON object")
        }
        return object
    }

    /// Decodes a JSON object as `type`.
    static func decode<T: Decodable>(_ object: [String: JSONValue], as type: T.Type) throws -> T {
        try TabulaJSON.makeDecoder().decode(type, from: SyncJSONParser.serialize(.object(object)))
    }

    /// Parses the `meta` member of a record (same shape as `EntityMeta`'s `Codable` form).
    static func meta(of record: [String: JSONValue]) throws -> EntityMeta {
        guard case .object(let meta)? = record["meta"],
              let createdString = meta["createdAt"]?.stringValue, let createdAt = HLCTimestamp(createdString),
              let updatedString = meta["updatedAt"]?.stringValue, let updatedAt = HLCTimestamp(updatedString) else {
            throw SyncError.malformedRecord("missing or malformed meta")
        }
        var isDeleted = false
        if let flag = meta["isDeleted"] {
            guard case .bool(let value) = flag else { throw SyncError.malformedRecord("meta.isDeleted is not a Bool") }
            isDeleted = value
        }
        var clocks: [String: HLCTimestamp] = [:]
        if case .object(let members)? = meta["fieldClocks"] {
            for (key, value) in members {
                guard let string = value.stringValue, let clock = HLCTimestamp(string) else {
                    throw SyncError.malformedRecord("malformed field clock '\(key)'")
                }
                clocks[key] = clock
            }
        }
        return EntityMeta(createdAt: createdAt, updatedAt: updatedAt, isDeleted: isDeleted, fieldClocks: clocks)
    }

    /// The JSON form of `meta` (identical to its `Codable` encoding).
    static func json(_ meta: EntityMeta) -> JSONValue {
        .object([
            "createdAt": .string(meta.createdAt.stringValue),
            "updatedAt": .string(meta.updatedAt.stringValue),
            "isDeleted": .bool(meta.isDeleted),
            "fieldClocks": .object(meta.fieldClocks.mapValues { .string($0.stringValue) }),
        ])
    }

    /// The `id` member as a string.
    static func id(of record: [String: JSONValue]) throws -> String {
        guard let id = record["id"]?.stringValue else { throw SyncError.malformedRecord("missing id") }
        return id
    }

    /// Canonical bytes of a value, used only to break exact clock ties deterministically.
    static func canonicalBytes(_ value: JSONValue) -> [UInt8] {
        (try? Array(TabulaJSON.makeEncoder().encode(value))) ?? []
    }

    /// The latest timestamp in `meta`.
    static func latest(in meta: EntityMeta) -> HLCTimestamp {
        meta.fieldClocks.values.reduce(max(meta.createdAt, meta.updatedAt), max)
    }
}

/// Field-level last-writer-wins merge of two versions of one record (an entity or a child record) in JSON form.
///
/// Rules (documented in `SyncMerge`):
/// - Every top-level key except `id`/`meta` is a field. Its clock is `meta.clock(for:)` (explicit field clock,
///   else `createdAt`). The value with the greater clock wins; an absent key is a value ("unset"). Equal
///   clocks with different values (only possible for hand-made data) are decided by the canonical bytes of
///   the value (an absent value loses), so the merge stays commutative.
/// - Keys in `childCollections` are set-merged by child `id` with the same rules per child.
/// - Tombstones: a deleted version's delete clock is its `updatedAt`; a live version asserts liveness at its
///   `updatedAt`. The merged record is deleted iff the greatest delete clock is ≥ the greatest liveness
///   clock (a later edit or restore resurrects; an exact tie keeps the delete).
/// - Merged meta: `updatedAt` = max, `fieldClocks` = per-key max of the effective clocks, `createdAt` = **max**,
///   written canonically (entries equal to the merged `createdAt` omitted, since a missing key means "at
///   `createdAt`"). Replicas of one entity share `createdAt` (it is set once, at creation), so max = min in
///   practice; for differing values (hand-made data, or settings written before the singleton got a zero
///   `createdAt`) max is the only choice that keeps the merge a join: a key mentioned by neither side then
///   sits at max(createdAtA, createdAtB) = the per-key max of its effective clocks, and every explicit clock
///   is kept (a clock below the merged `createdAt` stays explicit).
enum SyncRecordMerger {
    static func merge(_ a: [String: JSONValue], _ b: [String: JSONValue],
                      childCollections: Set<String>) throws -> [String: JSONValue] {
        let idA = try SyncJSON.id(of: a), idB = try SyncJSON.id(of: b)
        guard idA == idB else { throw SyncError.idMismatch(local: idA, remote: idB) }
        let metaA = try SyncJSON.meta(of: a), metaB = try SyncJSON.meta(of: b)

        var keys = Set(a.keys).union(b.keys).union(metaA.fieldClocks.keys).union(metaB.fieldClocks.keys)
        keys.subtract(EntityFieldCatalog.identityKeys)

        var merged: [String: JSONValue] = ["id": .string(idA)]
        var clocks: [String: HLCTimestamp] = [:]
        for key in keys {
            let clockA = metaA.clock(for: key), clockB = metaB.clock(for: key)
            clocks[key] = max(clockA, clockB)
            if childCollections.contains(key) {
                merged[key] = try mergeRecordArrays(a[key], b[key])
            } else if let value = pick(a[key], clockA, b[key], clockB) {
                merged[key] = value
            }
        }

        let updatedAt = max(metaA.updatedAt, metaB.updatedAt)
        let isDeleted: Bool
        switch (metaA.isDeleted, metaB.isDeleted) {
        case (true, true): isDeleted = true
        case (false, false): isDeleted = false
        case (true, false): isDeleted = metaA.updatedAt >= metaB.updatedAt
        case (false, true): isDeleted = metaB.updatedAt >= metaA.updatedAt
        }
        let createdAt = max(metaA.createdAt, metaB.createdAt)
        let meta = EntityMeta(createdAt: createdAt, updatedAt: updatedAt, isDeleted: isDeleted,
                              fieldClocks: clocks.filter { $0.value != createdAt })
        merged["meta"] = SyncJSON.json(meta)
        return merged
    }

    /// Set-merge of two arrays of records by `id` (missing or non-array values count as empty). Records
    /// present on one side are kept verbatim; records on both sides are merged. Output is in canonical child
    /// order: by integer `sortIndex` when present, then by `id`.
    static func mergeRecordArrays(_ a: JSONValue?, _ b: JSONValue?) throws -> JSONValue {
        let left = try recordsByID(a), right = try recordsByID(b)
        var result: [(sortIndex: Int64, id: String, record: [String: JSONValue])] = []
        for id in Set(left.keys).union(right.keys) {
            let record: [String: JSONValue]
            switch (left[id], right[id]) {
            case let (x?, y?): record = try merge(x, y, childCollections: [])
            case let (x?, nil): record = x
            case let (nil, y?): record = y
            case (nil, nil): continue
            }
            var sortIndex = Int64.min
            if case .integer(let value)? = record["sortIndex"] { sortIndex = value }
            result.append((sortIndex, id, record))
        }
        result.sort { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
        return .array(result.map { .object($0.record) })
    }

    /// `true` when `value` is an array whose elements all look like records (`id` string + `meta` object).
    static func isRecordArray(_ value: JSONValue) -> Bool {
        guard case .array(let items) = value else { return false }
        return items.allSatisfy { item in
            guard case .object(let object) = item, object["id"]?.stringValue != nil,
                  case .object? = object["meta"] else { return false }
            return (try? SyncJSON.meta(of: object)) != nil
        }
    }

    private static func recordsByID(_ value: JSONValue?) throws -> [String: [String: JSONValue]] {
        guard case .array(let items)? = value else { return [:] }
        var byID: [String: [String: JSONValue]] = [:]
        for item in items {
            guard case .object(let record) = item else { throw SyncError.malformedRecord("child is not an object") }
            let id = try SyncJSON.id(of: record)
            // Duplicate IDs (a validation error) are folded together.
            byID[id] = try byID[id].map { try merge($0, record, childCollections: []) } ?? record
        }
        return byID
    }

    /// Last-writer-wins choice between two values of one field.
    private static func pick(_ a: JSONValue?, _ clockA: HLCTimestamp,
                             _ b: JSONValue?, _ clockB: HLCTimestamp) -> JSONValue? {
        if clockA != clockB { return clockA > clockB ? a : b }
        if a == b { return a }
        guard let a else { return b }
        guard let b else { return a }
        return SyncJSON.canonicalBytes(a).lexicographicallyPrecedes(SyncJSON.canonicalBytes(b)) ? b : a
    }
}
