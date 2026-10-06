import Foundation
import Testing
@testable import TimetableCore

/// Decision 2 (orchestrator): unknown JSON keys survive an older app re-saving the database.
@Suite("Unknown-field preservation")
struct UnknownFieldsTests {
    typealias P = SyncJSONPatch

    private static let collections = ["timetables", "subjects", "bellSchedules", "lessons", "terms", "breaks",
                                      "overrides", "tasks", "exams", "reminderRules"]

    /// The full fixture as a "newer version" file: an extra key on the root, on settings, on the first element of
    /// every entity array, on a subtask and an attachment, plus a whole unknown entity array.
    private static func newerFile() throws -> (tree: JSONValue, injected: [([P.Step], JSONValue)]) {
        var tree = try JSONValue(encoding: Fixture.fullDatabase())
        var injected: [([P.Step], JSONValue)] = []
        func inject(_ path: [P.Step], _ value: JSONValue) {
            tree = P.set(tree, path, value)
            injected.append((path, value))
        }
        inject([.key("syncGeneration")], .integer(42))
        inject([.key("notes")], .array([
            .object(["id": .string("00000000-0000-4000-8000-0000000000AA"), "body": .string("Bring calculator"),
                     "meta": try JSONValue(encoding: Fixture.meta())]),
        ]))
        inject([.key("settings"), .key("widgetAccent")], .string("#FF0000"))
        for (index, collection) in collections.enumerated() {
            inject([.key(collection), .index(0), .key("futureField")],
                   .object(["n": .integer(Int64(index)), "flags": .array([.bool(true), .null, .double(1.5)])]))
        }
        inject([.key("tasks"), .index(0), .key("subtasks"), .index(0), .key("estimateMinutes")], .integer(25))
        inject([.key("tasks"), .index(0), .key("attachments"), .index(1), .key("thumbnailHash")], .string("abc"))
        return (tree, injected)
    }

    @Test func extraKeysAtEveryLevelSurviveDecodeMutateEncode() throws {
        let (tree, injected) = try Self.newerFile()
        let input = try TabulaJSON.makeEncoder().encode(tree)
        var db = try TabulaDatabase.decode(from: input)

        // Unmodified: byte-for-byte identical.
        #expect(try db.encoded() == input)
        #expect(db.unknownFields.root["syncGeneration"] == .integer(42))
        #expect(db.unknownFields.fields(of: db.settings)?.fields["widgetAccent"] == .string("#FF0000"))
        #expect(db.unknownFields.entities.count == Self.collections.count + 1)

        // Mutate known fields at every level the side table covers.
        db.settings.hourCycle = .h12
        for index in db.tasks.indices where db.unknownFields.fields(of: db.tasks[index]) != nil {
            db.tasks[index].title = "Renamed"
            db.tasks[index].subtasks = db.tasks[index].subtasks.map { var copy = $0; copy.title += "!"; return copy }
            db.tasks[index].attachments.reverse()
        }
        db.lessons = db.lessons.map { var copy = $0; copy.room = "B-12"; return copy }
        db.timetables.reverse()

        let output = try JSONValue(encoding: db)
        for (path, value) in injected {
            #expect(P.get(output, path) == value, "lost \(path)")
        }
        #expect(output["settings"]?["hourCycle"] == .string("h12"))
        // Decoding the output again keeps both the mutation and the unknown keys.
        let again = try TabulaDatabase.decode(from: TabulaJSON.makeEncoder().encode(output))
        #expect(again.settings.hourCycle == .h12)
        #expect(again.unknownFields == db.canonicalized().unknownFields)
        #expect(again == db.canonicalized())
    }

    @Test func unknownRootEntityArraysArePreserved() throws {
        let (tree, _) = try Self.newerFile()
        let db = try TabulaDatabase.decode(from: TabulaJSON.makeEncoder().encode(tree))
        guard case .array(let notes)? = db.unknownFields.root["notes"] else {
            Issue.record("unknown array missing")
            return
        }
        #expect(notes.count == 1)
        #expect(try JSONValue(encoding: db)["notes"] == tree["notes"])
    }

    @Test func knownKeysWinAndOrphansAreDropped() throws {
        var db = Fixture.fullDatabase()
        let task = db.tasks[0]
        db.unknownFields.setFields(EntityUnknownFields(fields: ["title": .string("shadow"), "extra": .integer(1)]),
                                   for: .task, id: task.id.uuid)
        db.unknownFields.setFields(EntityUnknownFields(fields: ["extra": .integer(2)]), for: .lesson,
                                   id: UUID(uuidString: "00000000-0000-4000-8000-00000000BEEF")!)
        db.unknownFields.root["timetables"] = .string("shadow")
        let tree = try JSONValue(encoding: db)
        guard case .array(let tasks)? = tree["tasks"],
              let encodedTask = tasks.first(where: { $0["id"]?.stringValue == task.id.uuidString }) else {
            Issue.record("task missing")
            return
        }
        #expect(encodedTask["title"] == .string(task.title))
        #expect(encodedTask["extra"] == .integer(1))
        guard case .array? = tree["timetables"] else {
            Issue.record("known root key overwritten")
            return
        }
        let decoded = try TabulaDatabase.decode(from: db.encoded())
        #expect(decoded == db.canonicalized())
        #expect(decoded.unknownFields.entities[.lesson] == nil)
        #expect(decoded.unknownFields.root.isEmpty)
    }

    /// The fast path (second keyed container) and the JSON-tree path produce identical bytes.
    @Test func encodingPathsAgree() throws {
        var db = Fixture.fullDatabase()
        let task = db.tasks[0]
        let extra: [String: JSONValue] = ["zeta": .string("z"), "alpha": .array([.integer(1)])]
        db.unknownFields.setFields(EntityUnknownFields(fields: extra), for: .task, id: task.id.uuid)
        let fast = try db.encoded()
        let viaTree = try TabulaJSON.makeEncoder().encode(
            JSONValue.object(EntityUnknownFields(fields: extra).applied(to: SyncJSON.object(task), type: .task)))
        let fastTree = try TabulaJSON.makeDecoder().decode(JSONValue.self, from: fast)
        guard case .array(let tasks)? = fastTree["tasks"],
              let encoded = tasks.first(where: { $0["id"]?.stringValue == task.id.uuidString }) else {
            Issue.record("task missing")
            return
        }
        #expect(try TabulaJSON.makeEncoder().encode(encoded) == viaTree)
    }

    @Test func encodingWithUnknownFieldsIsDeterministic() throws {
        let (tree, _) = try Self.newerFile()
        let original = try TabulaDatabase.decode(from: TabulaJSON.makeEncoder().encode(tree))
        let reference = try original.encoded()
        var rng = TestRNG(seed: 4)
        for _ in 0..<10 {
            var db = original
            db.tasks.shuffle(using: &rng)
            db.lessons.shuffle(using: &rng)
            for index in db.tasks.indices { db.tasks[index].subtasks.shuffle(using: &rng) }
            #expect(try db.encoded() == reference)
        }
    }

    /// The catalog equals the stored properties of every type, and covers every key the encoders write.
    @Test func catalogMatchesTheModelTypes() throws {
        let db = Fixture.fullDatabase()
        func labels(_ value: Any) -> Set<String> {
            Set(Mirror(reflecting: value).children.compactMap(\.label))
        }
        func check<E: SyncEntity>(_ entities: [E]) throws {
            guard let sample = entities.first else {
                Issue.record("no sample of \(E.entityType)")
                return
            }
            let catalog = EntityFieldCatalog.fieldKeys(for: E.entityType)
            #expect(labels(sample) == catalog.union(EntityFieldCatalog.identityKeys), "\(E.entityType)")
            for entity in entities {
                let keys = Set(try SyncJSON.object(entity).keys)
                #expect(keys.isSubset(of: catalog.union(EntityFieldCatalog.identityKeys)), "\(E.entityType): \(keys)")
            }
        }
        try check([db.settings])
        try check(db.timetables)
        try check(db.subjects)
        try check(db.bellSchedules)
        try check(db.lessons)
        try check(db.terms)
        try check(db.breaks)
        try check(db.overrides)
        try check(db.tasks)
        try check(db.exams)
        try check(db.reminderRules)
        #expect(Set(EntityType.allCases.map { EntityFieldCatalog.fieldKeys(for: $0).isEmpty }) == [false])

        let children = EntityFieldCatalog.childCollections(for: .task)
        #expect(Set(children.keys) == ["subtasks", "attachments"])
        let task = try #require(db.tasks.first { !$0.subtasks.isEmpty && !$0.attachments.isEmpty })
        #expect(labels(task.subtasks[0]) == children["subtasks"]!.union(EntityFieldCatalog.identityKeys))
        #expect(labels(task.attachments[0]) == children["attachments"]!.union(EntityFieldCatalog.identityKeys))
        for type in EntityType.allCases where type != .task {
            #expect(EntityFieldCatalog.childCollections(for: type).isEmpty)
        }
    }

    @Test func extractedAndAppliedAreInverse() throws {
        let task = Fixture.fullDatabase().tasks.first { !$0.subtasks.isEmpty }!
        let unknown = EntityUnknownFields(fields: ["x": .integer(1)],
                                          children: ["subtasks": [task.subtasks[0].id.uuid: ["y": .bool(true)]]])
        let object = unknown.applied(to: try SyncJSON.object(task), type: .task)
        #expect(EntityUnknownFields.extracted(from: object, type: .task) == unknown)
        #expect(EntityUnknownFields.extracted(from: try SyncJSON.object(task), type: .task).isEmpty)
    }
}
