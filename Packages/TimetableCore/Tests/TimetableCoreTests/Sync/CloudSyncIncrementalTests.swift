import Foundation
import Testing
@testable import TimetableCore

// Phase 10 C1: the cheaper record building must produce exactly the records (bytes, names, order) of the Phase 6 path,
// because the CloudKit record format is frozen: a changed byte changes the hash and re-uploads the record.

@Suite("Cloud sync incremental records (Phase 10 C1)")
struct CloudSyncIncrementalTests {
    /// Every entity of `database` (settings first, then `cloudRecords()` order) through `body`.
    private static func forEachEntity(_ database: TabulaDatabase, _ body: (any SyncEntity) throws -> Void) rethrows {
        try body(database.settings)
        for entity in database.timetables { try body(entity) }
        for entity in database.subjects { try body(entity) }
        for entity in database.bellSchedules { try body(entity) }
        for entity in database.lessons { try body(entity) }
        for entity in database.terms { try body(entity) }
        for entity in database.breaks { try body(entity) }
        for entity in database.overrides { try body(entity) }
        for entity in database.tasks { try body(entity) }
        for entity in database.exams { try body(entity) }
        for entity in database.reminderRules { try body(entity) }
    }

    /// The fast path and the reference (tree) path give the same record for `entity`.
    private static func expectSameRecord<E: SyncEntity>(_ entity: E, in database: TabulaDatabase) throws -> Bool {
        let fast = try database.cloudRecord(entity)
        let reference = try database.cloudRecordThroughJSONTree(entity, unknown: database.unknownFields.fields(of: entity))
        #expect(fast == reference, "\(E.entityType) \(entity.id)")
        #expect(fast.payload == reference.payload)
        #expect(fast.name == reference.name)
        return fast == reference
    }

    private static func takesFastPath<E: SyncEntity>(_ entity: E) throws -> Bool {
        CloudRecordEncoding.reencodesIdentically(try TabulaJSON.makeEncoder().encode(entity))
    }

    /// The full fixture plus a tombstone, an edited entity with field clocks, unknown keys (entity and child) and
    /// `.unknown` override payloads holding numbers the fast path must hand to the tree path.
    private static func variedDatabase() throws -> TabulaDatabase {
        var database = Fixture.fullDatabase()
        var clock = HybridLogicalClock(node: 0xC1)
        clock.receive(database.latestTimestamp, now: SyncFixture.at(0))
        let first = database.tasks[0]
        var renamed = first
        renamed.title = "Úloha 3 – \"quoted\" \\ back/slash\n\u{0001} 🎒 e\u{0301}"
        database.tasks[0] = try MutationStamper.stamp(old: first, new: renamed, clock: &clock, now: SyncFixture.at(60_000))
        database.exams[1] = try MutationStamper.delete(database.exams[1], clock: &clock, now: SyncFixture.at(61_000))
        database.unknownFields.setFields(EntityUnknownFields(fields: ["futureField": .string("from a newer app")]),
                                         for: .subject, id: database.subjects[0].id.uuid)
        let subtaskID = try #require(database.tasks[0].subtasks.first).id.uuid
        database.unknownFields.setFields(EntityUnknownFields(children: ["subtasks": [subtaskID: ["futureChild": .integer(7)]]]),
                                         for: .task, id: database.tasks[0].id.uuid)
        let template = database.overrides[0]
        let payloads: [JSONValue] = [
            .object(["kind": .string("futureKind"), "ratio": .double(-0.0)]),
            .object(["kind": .string("futureKind"), "ratio": .double(0.5), "big": .double(1e300)]),
            .object(["kind": .string("futureKind"), "count": .integer(-12), "huge": .integer(Int64.max)]),
            .object(["kind": .string("futureKind"), "list": .array([.integer(0), .null, .bool(true), .string("-0")])]),
        ]
        for (offset, payload) in payloads.enumerated() {
            var copy = template
            copy.id = SyncFixture.id(UInt64(900 + offset))
            copy.change = .unknown(payload)
            database.overrides.append(copy)
        }
        return database
    }

    @Test func fastPathIsByteIdenticalForEveryEntityType() throws {
        let database = try Self.variedDatabase()
        var types: Set<EntityType> = []
        var fast = 0, total = 0
        try Self.forEachEntity(database) { entity in
            func check<E: SyncEntity>(_ typed: E) throws {
                #expect(try Self.expectSameRecord(typed, in: database))
                types.insert(E.entityType)
                total += 1
                if database.unknownFields.fields(of: typed) == nil, try Self.takesFastPath(typed) { fast += 1 }
            }
            try check(entity)
        }
        #expect(types == Set(EntityType.allCases))
        // The fast path is the normal case: everything except the two entities with unknown keys and the `.unknown`
        // overrides with non-integer or out-of-range numbers.
        #expect(fast >= total - 2 - 4)
        #expect(fast > total / 2)
        // The whole list equals what the reference path builds, in order.
        let reference = try Self.referenceRecords(database)
        #expect(try database.cloudRecords() == reference)
    }

    @Test func fastPathIsByteIdenticalOnTheLargeDatabase() throws {
        let database = SyncPerformanceTests.largeDatabase()
        #expect(try database.cloudRecords() == (try Self.referenceRecords(database)))
    }

    /// The Phase 6 `cloudRecords()`: every record through the tree path.
    private static func referenceRecords(_ database: TabulaDatabase) throws -> [CloudRecord] {
        var records: [CloudRecord] = []
        try forEachEntity(database) { entity in
            func build<E: SyncEntity>(_ typed: E) throws {
                records.append(try database.cloudRecordThroughJSONTree(typed, unknown: database.unknownFields.fields(of: typed)))
            }
            try build(entity)
        }
        return records
    }

    @Test(arguments: [
        ("{\"a\":1,\"b\":[0,-2,345],\"c\":\"-0 1.5 \\\"x\\\" \\\\\",\"d\":null,\"e\":true,\"f\":{}}", true),
        ("{\"a\":-9223372036854775}", true),
        ("{\"a\":-0}", false),
        ("{\"a\":1.5}", false),
        ("{\"a\":1e5}", false),
        ("{\"a\":1E+5}", false),
        ("{\"a\":12345678901234567890}", false),
        ("{\"a\":1234567890123456789}", false),
        ("{\"a\":01}", false),
    ])
    func reencodeCheck(json: String, expected: Bool) throws {
        let bytes = Data(json.utf8)
        #expect(CloudRecordEncoding.reencodesIdentically(bytes) == expected)
        if expected {
            // What the check accepts really round-trips (the claim the fast path rests on).
            let again = try TabulaJSON.makeEncoder().encode(try SyncJSONParser.parse(bytes))
            #expect(again == bytes)
        }
    }

    @Test func reencodeCheckRejectsTooDeepNesting() {
        let depth = TabulaJSON.maxNestingDepth + 1
        let bytes = Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
        #expect(!CloudRecordEncoding.reencodesIdentically(bytes))
        let atLimit = TabulaJSON.maxNestingDepth
        #expect(CloudRecordEncoding.reencodesIdentically(
            Data((String(repeating: "[", count: atLimit) + String(repeating: "]", count: atLimit)).utf8)))
    }

    @Test func namedRecordsEqualTheMatchingSubsetOfTheFullBuild() throws {
        let database = try Self.variedDatabase()
        let full = try database.cloudRecords()
        let wanted = Set(full.enumerated().filter { $0.offset % 3 == 0 }.map(\.element.name))
        let lowercase = try #require(full.last).name.lowercased()
        let names = Array(wanted) + ["not-a-uuid", UUID().uuidString, lowercase]
        let expected = Dictionary(full.filter { wanted.contains($0.name) }.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(try database.cloudRecords(named: names) == expected)

        let source = CloudRecordSource(database: database)
        for record in full {
            #expect(try source.record(named: record.name) == record)
        }
        #expect(try source.record(named: lowercase) == nil)   // record names are the canonical uppercase strings
        #expect(try source.record(named: "") == nil)
    }

    @Test func indexEqualsTheFullBuildAndEncodesOnlyWhatChanged() throws {
        var database = try Self.variedDatabase()
        var index = CloudRecordIndex()
        let first = try index.records(for: database)
        #expect(first.map(\.record) == (try database.cloudRecords()))
        #expect(first.allSatisfy { $0.hash == $0.record.payloadHash })
        #expect(index.lastEncodedCount == first.count)

        #expect(try index.records(for: database) == first)
        #expect(index.lastEncodedCount == 0)

        // One edited entity, one changed unknown-keys entry, one new entity.
        var clock = HybridLogicalClock(node: 0xC2)
        clock.receive(database.latestTimestamp, now: SyncFixture.at(0))
        let lesson = database.lessons[2]
        var moved = lesson
        moved.room = "B 12"
        database.lessons[2] = try MutationStamper.stamp(old: lesson, new: moved, clock: &clock, now: SyncFixture.at(70_000))
        database.unknownFields.setFields(EntityUnknownFields(fields: ["futureField": .string("changed")]),
                                         for: .subject, id: database.subjects[0].id.uuid)
        database.tasks.append(try SyncFixture.task(SyncFixture.taskID(4242), clock: &clock, at: 71_000))
        let third = try index.records(for: database)
        #expect(third.map(\.record) == (try database.cloudRecords()))
        #expect(index.lastEncodedCount == 3)

        // Removed entities leave the index; a schema version change rebuilds everything.
        database.tasks.removeLast()
        #expect(try index.records(for: database).map(\.record) == (try database.cloudRecords()))
        #expect(index.lastEncodedCount == 0)
        database.schemaVersion = TabulaDatabase.currentSchemaVersion + 1
        let rebuilt = try index.records(for: database)
        #expect(index.lastEncodedCount == rebuilt.count)
        #expect(rebuilt.allSatisfy { $0.record.schemaVersion == database.schemaVersion })
    }

    @Test func hashedPendingEqualsThePlainPending() throws {
        let database = try Self.variedDatabase()
        var index = CloudRecordIndex()
        let hashed = try index.records(for: database)
        var ledger = CloudSyncLedger()
        for item in hashed.enumerated() where item.offset % 2 == 0 { ledger.serverHashes[item.element.record.name] = item.element.hash }
        let skipping: Set<String> = [hashed[1].record.name]
        #expect(ledger.pending(hashed: hashed, skipping: skipping) == ledger.pending(try database.cloudRecords(), skipping: skipping))
    }

    /// 5 000 tasks + 2 000 lessons, all on the server; one task edited → the incremental scan returns exactly that
    /// record, without encoding the others.
    @Test func oneEditInALargeDatabaseIsOneIncrementalRecord() throws {
        let database = SyncPerformanceTests.largeDatabase()
        var index = CloudRecordIndex()
        let clock = ContinuousClock()
        var all: [HashedCloudRecord] = []
        let fullScan = try clock.measure { all = try index.records(for: database) }
        var ledger = CloudSyncLedger()
        for item in all { ledger.serverHashes[item.record.name] = item.hash }
        #expect(ledger.pending(hashed: all).isEmpty)

        var edited = database
        var hlc = HybridLogicalClock(node: 0xC3)
        hlc.receive(database.latestTimestamp, now: SyncFixture.at(0))
        let old = edited.tasks[2_500]
        var new = old
        new.title = "Edited on this iPhone"
        edited.tasks[2_500] = try MutationStamper.stamp(old: old, new: new, clock: &hlc, now: SyncFixture.at(90_000))

        var pending: [CloudRecord] = []
        let incremental = try clock.measure {
            pending = ledger.pending(hashed: try index.records(for: edited))
        }
        #expect(pending.map(\.name) == [old.id.uuidString])
        #expect(pending == (try edited.cloudRecords(named: [old.id.uuidString])).map(\.value))
        #expect(index.lastEncodedCount == 1)
        print("CloudRecordIndex: \(all.count) records; first scan \(fullScan), incremental scan after one edit \(incremental)")
        #if DEBUG
        #expect(incremental < .seconds(3))
        #else
        #expect(incremental < .seconds(1))
        #endif
    }
}
