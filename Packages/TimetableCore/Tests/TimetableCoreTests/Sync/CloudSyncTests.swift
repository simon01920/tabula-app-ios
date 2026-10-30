import Foundation
import Testing
@testable import TimetableCore

// Phase 6 S1: the pure CloudKit mapping, the ledger and the first-sync logic, driven through an in-memory fake of the
// CloudKit private database (change tags + serverRecordChanged conflicts), the way the app adapter uses them.

/// A fake private-database zone: saves succeed only with the current change tag (else `serverRecordChanged` with the
/// server's record, like CloudKit); fetches return everything changed after a change token.
private final class FakeCloudZone {
    private(set) var records: [String: (record: CloudRecord, tag: Int, change: Int)] = [:]
    private var changeCounter = 0

    enum SaveResult { case saved(tag: Data), conflict(server: CloudRecord, tag: Data) }

    func save(_ record: CloudRecord, knownTag: Data?) -> SaveResult {
        let tag = knownTag.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
        if let current = records[record.name], current.tag != tag {
            return .conflict(server: current.record, tag: Data(String(current.tag).utf8))
        }
        changeCounter += 1
        let newTag = (records[record.name]?.tag ?? 0) + 1
        records[record.name] = (record, newTag, changeCounter)
        return .saved(tag: Data(String(newTag).utf8))
    }

    func changes(since token: Int) -> (records: [(CloudRecord, Data)], token: Int) {
        let changed = records.values.filter { $0.change > token }.sorted { $0.change < $1.change }
        return (changed.map { ($0.record, Data(String($0.tag).utf8)) }, changeCounter)
    }
}

/// One device: its database, ledger and clock; `pull`/`push` do what the app adapter does with CKSyncEngine events.
private struct FakeDevice {
    var database: TabulaDatabase
    var ledger = CloudSyncLedger()
    var clock: HybridLogicalClock
    var token = 0

    init(_ database: TabulaDatabase, node: UInt64) {
        self.database = database
        clock = HybridLogicalClock(node: node)
        clock.receive(database.latestTimestamp, now: SyncFixture.at(0))
    }

    mutating func apply(_ fetched: [(CloudRecord, Data)]) throws {
        let batch = CloudRecordBatch(fetched.map(\.0))
        database = try SyncMerge.merge(local: database, remote: batch.database)
        clock.receive(batch.database.latestTimestamp, now: SyncFixture.at(0))
        for (record, tag) in fetched where batch.hashes[record.name] != nil {
            ledger.serverHashes[record.name] = batch.hashes[record.name]
            ledger.systemFields[record.name] = tag
        }
    }

    mutating func pull(_ zone: FakeCloudZone) throws {
        let (fetched, token) = zone.changes(since: token)
        try apply(fetched)
        self.token = token
    }

    /// Sends every pending record; a conflict merges the server copy and sends again (bounded).
    mutating func push(_ zone: FakeCloudZone) throws {
        for _ in 0..<3 {
            let pending = ledger.pending(try database.cloudRecords())
            if pending.isEmpty { return }
            for record in pending {
                switch zone.save(record, knownTag: ledger.systemFields[record.name]) {
                case .saved(let tag):
                    ledger.serverHashes[record.name] = record.payloadHash
                    ledger.systemFields[record.name] = tag
                case .conflict(let server, let tag):
                    try apply([(server, tag)])
                }
            }
        }
        Issue.record("push did not settle")
    }

    mutating func edit<E: SyncEntity>(_ path: WritableKeyPath<TabulaDatabase, [E]>, at index: Int, millis: Int64,
                                      _ change: (inout E) -> Void) throws {
        let old = database[keyPath: path][index]
        var new = old
        change(&new)
        database[keyPath: path][index] = try MutationStamper.stamp(old: old, new: new, clock: &clock, now: SyncFixture.at(millis))
    }
}

@Suite("Cloud sync mapping (Phase 6 S1)")
struct CloudSyncTests {
    private static func withUnknownKey(_ database: TabulaDatabase) throws -> TabulaDatabase {
        var records = try database.cloudRecords()
        let index = try #require(records.firstIndex { $0.type == .task })
        guard case .object(var object) = try SyncJSONParser.parse(records[index].payload) else { throw SyncError.malformedRecord("") }
        object["futureField"] = .string("from a newer app")
        records[index].payload = try TabulaJSON.makeEncoder().encode(JSONValue.object(object))
        let batch = CloudRecordBatch(records)
        #expect(batch.rejected.isEmpty)
        return batch.database
    }

    @Test func roundTripKeepsEveryEntityAndUnknownKeys() throws {
        let database = try Self.withUnknownKey(Fixture.fullDatabase())
        let records = try database.cloudRecords()
        #expect(records.count == 1 + database.timetables.count + database.subjects.count + database.bellSchedules.count
                + database.lessons.count + database.terms.count + database.breaks.count + database.overrides.count
                + database.tasks.count + database.exams.count + database.reminderRules.count)
        #expect(Set(records.map(\.name)).count == records.count)
        #expect(records.allSatisfy { UUID(uuidString: $0.name) != nil && !$0.isTooLarge })
        let task = try #require(records.first { $0.type == .task })
        #expect(String(decoding: task.payload, as: UTF8.self).contains("\"futureField\":\"from a newer app\""))

        let batch = CloudRecordBatch(records)
        #expect(batch.rejected.isEmpty)
        #expect(batch.database.canonicalized() == database.canonicalized())
        // Applied records are not pending: the batch hashes are what this build encodes locally.
        var ledger = CloudSyncLedger()
        ledger.serverHashes = batch.hashes
        #expect(ledger.pending(try batch.database.cloudRecords()).isEmpty)
        #expect(ledger.pending(records).isEmpty)
    }

    @Test func tombstoneIsAnOrdinaryRecordAndWinsOverAnOlderEdit() throws {
        let zone = FakeCloudZone()
        var a = FakeDevice(Fixture.fullDatabase(), node: 0xA)
        try a.push(zone)
        var b = FakeDevice(Fixture.fullDatabase(), node: 0xB)
        try b.pull(zone)
        try b.edit(\.subjects, at: 0, millis: 1_000) { $0.name = "Edited before the delete" }
        let id = a.database.subjects[0].id
        a.database.subjects[0] = try MutationStamper.delete(a.database.subjects[0], clock: &a.clock, now: SyncFixture.at(2_000))
        try a.push(zone)
        let record = try #require(zone.records[id.uuidString]?.record)
        #expect(String(decoding: record.payload, as: UTF8.self).contains("\"isDeleted\":true"))
        try b.push(zone)   // conflict: B merges A's tombstone (newer) and sends the merged tombstone
        try b.pull(zone)
        try a.pull(zone)
        #expect(a.database.subjects.first { $0.id == id }?.isDeleted == true)
        #expect(b.database.subjects.first { $0.id == id }?.isDeleted == true)
        #expect(a.database == b.database)
    }

    @Test func concurrentEditsMergeInBothDirectionsAndConverge() throws {
        let zone = FakeCloudZone()
        var a = FakeDevice(Fixture.fullDatabase(), node: 0xA)
        try a.push(zone)
        var b = FakeDevice(Fixture.fullDatabase(), node: 0xB)
        try b.pull(zone)
        // Offline on both: different fields of the same task, and the same field of a subject (later write wins).
        try a.edit(\.tasks, at: 0, millis: 1_000) { $0.title = "Title from A" }
        try b.edit(\.tasks, at: 0, millis: 1_100) { $0.notes = "Notes from B" }
        try a.edit(\.subjects, at: 0, millis: 1_200) { $0.name = "Older name" }
        try b.edit(\.subjects, at: 0, millis: 1_300) { $0.name = "Newer name" }
        try b.push(zone)
        try a.push(zone)   // conflicts on both records: A merges B's copies, then sends the merge
        try b.pull(zone)
        try a.pull(zone)
        #expect(a.database == b.database)
        #expect(a.database.tasks[0].title == "Title from A")
        #expect(a.database.tasks[0].notes == "Notes from B")
        #expect(a.database.subjects[0].name == "Newer name")
        #expect(a.ledger.pending(try a.database.cloudRecords()).isEmpty)
        #expect(b.ledger.pending(try b.database.cloudRecords()).isEmpty)
    }

    @Test func reapplyingFetchedRecordsIsIdempotent() throws {
        let zone = FakeCloudZone()
        var a = FakeDevice(Fixture.fullDatabase(), node: 0xA)
        try a.edit(\.tasks, at: 0, millis: 500) { $0.title = "Sent" }
        try a.push(zone)
        var b = FakeDevice(TabulaDatabase(settings: .untouchedDefaults), node: 0xB)
        try b.pull(zone)
        let once = b.database
        try b.apply(zone.changes(since: 0).records)   // the same records again (lost token, retried fetch)
        try b.apply(zone.changes(since: 0).records)
        #expect(b.database == once)
        #expect(b.database.canonicalized() == a.database.canonicalized())
        #expect(b.ledger.pending(try b.database.cloudRecords()).isEmpty)
    }

    @Test func badRecordsAreSkippedNotFatal() throws {
        let good = try Fixture.fullDatabase().cloudRecords()
        let task = try #require(good.first { $0.type == .task })
        var newer = task
        newer.schemaVersion = TabulaDatabase.currentSchemaVersion + 1
        var renamed = task
        renamed.name = UUID().uuidString
        var huge = task
        huge.payload = Data(count: CloudSyncSchema.maxPayloadBytes + 1)
        var garbage = good[1]
        garbage.payload = Data("[1,2]".utf8)
        var wrongType = task
        wrongType.type = .exam
        let batch = CloudRecordBatch([newer, renamed, huge, garbage, wrongType])
        #expect(batch.rejected[task.name] != nil)
        #expect(batch.rejected[renamed.name] != nil)
        #expect(batch.rejected[garbage.name] != nil)
        #expect(batch.hashes.isEmpty)
        #expect(!batch.database.hasLiveContent)
        #expect(CloudRecordBatch([newer]).rejected[task.name] == .newerVersion)
        #expect(huge.isTooLarge && !task.isTooLarge)
    }

    @Test func ledgerPersistsAtomicallyAndAnUnreadableFileStartsFresh() throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        let url = dir.file("nested/cloudsync.json")
        #expect(CloudSyncLedger.load(from: url) == CloudSyncLedger())
        var ledger = CloudSyncLedger()
        ledger.serverHashes["x"] = "abc"
        ledger.systemFields["x"] = Data([1, 2, 3])
        ledger.engineState = Data("state".utf8)
        ledger.initialSyncDone = true
        ledger.lastSyncedAt = SyncFixture.at(0)
        try ledger.save(to: url)
        #expect(CloudSyncLedger.load(from: url) == ledger)
        try Data("{corrupt".utf8).write(to: url)
        #expect(CloudSyncLedger.load(from: url) == CloudSyncLedger())
    }

    @Test func firstSyncAsksOnlyWhenBothSidesHaveData() {
        let full = Fixture.fullDatabase()
        let empty = TabulaDatabase(settings: .untouchedDefaults)
        #expect(CloudFirstSync.needsChoice(local: full, remote: full))
        #expect(!CloudFirstSync.needsChoice(local: nil, remote: full))
        #expect(!CloudFirstSync.needsChoice(local: empty, remote: full))
        #expect(!CloudFirstSync.needsChoice(local: full, remote: empty))
    }

    /// iCloud holds A's data; device B has its own (one shared entity edited differently, one entity each side only).
    private static func firstSyncScenario() throws -> (cloud: FakeDevice, device: FakeDevice, sharedID: Subject.ID) {
        var cloud = FakeDevice(Fixture.fullDatabase(), node: 0xA)
        var device = FakeDevice(Fixture.fullDatabase(), node: 0xB)
        try cloud.edit(\.subjects, at: 0, millis: 1_000) { $0.name = "iCloud name" }
        try device.edit(\.subjects, at: 0, millis: 2_000) { $0.name = "Device name" }
        cloud.database.tasks.removeLast()
        device.database.exams.removeLast()
        return (cloud, device, cloud.database.subjects[0].id)
    }

    @Test(arguments: FirstSyncChoice.allCases)
    func firstSyncChoiceConvergesOnEveryDevice(_ choice: FirstSyncChoice) throws {
        let scenario = try Self.firstSyncScenario()
        var cloud = scenario.cloud, device = scenario.device
        let sharedID = scenario.sharedID
        let zone = FakeCloudZone()
        try cloud.push(zone)
        let local = device.database
        let fetched = zone.changes(since: 0)
        let remote = CloudRecordBatch(fetched.records.map(\.0))
        device.clock.receive(remote.database.latestTimestamp, now: SyncFixture.at(3_000))
        device.database = try CloudFirstSync.resolve(choice, local: local, remote: remote.database,
                                                    clock: &device.clock, now: SyncFixture.at(3_000))
        device.ledger.serverHashes = remote.hashes
        for (record, tag) in fetched.records { device.ledger.systemFields[record.name] = tag }
        device.token = fetched.token
        try device.push(zone)
        try cloud.pull(zone)
        #expect(cloud.database == device.database)

        let live = { (db: TabulaDatabase) in Set(db.tasks.filter { !$0.isDeleted }.map(\.id)) }
        let liveExams = { (db: TabulaDatabase) in Set(db.exams.filter { !$0.isDeleted }.map(\.id)) }
        let name = device.database.subjects.first { $0.id == sharedID }?.name
        switch choice {
        case .merge:
            #expect(name == "Device name")   // later field write
            #expect(live(device.database) == live(local).union(live(remote.database)))
            #expect(liveExams(device.database) == liveExams(local).union(liveExams(remote.database)))
        case .keepThisDevice:
            #expect(name == "Device name")
            #expect(live(device.database) == live(local))
            #expect(liveExams(device.database) == liveExams(local))
        case .useICloud:
            #expect(name == "iCloud name")   // although the device's edit was later
            #expect(live(device.database) == live(remote.database))
            #expect(liveExams(device.database) == liveExams(remote.database))
            // Nothing is dropped: the device-only task stays as a tombstone with its data.
            let dropped = try #require(local.tasks.first { !live(remote.database).contains($0.id) })
            let kept = try #require(device.database.tasks.first { $0.id == dropped.id })
            #expect(kept.isDeleted && kept.title == dropped.title)
        }
    }
}
