import Foundation
import Testing
@testable import TimetableCore

@Suite("TabulaDatabase coding")
struct TabulaDatabaseTests {
    private struct PatchError: Error {}

    @Test func schemaVersionIsOne() {
        #expect(TabulaDatabase.currentSchemaVersion == 1)
        #expect(TabulaDatabase.currentSchemaVersion == TimetableCoreInfo.schemaVersion)
        #expect(Fixture.fullDatabase().schemaVersion == 1)
    }

    @Test func fullDatabaseRoundTripsAndIsCanonical() throws {
        let db = Fixture.fullDatabase()
        let data = try db.encoded()
        let decoded = try TabulaDatabase.decode(from: data)
        #expect(decoded == db.canonicalized())
        #expect(try decoded.encoded() == data)   // decode → encode is byte-stable
        let pretty = try db.encoded(pretty: true)
        #expect(try TabulaDatabase.decode(from: pretty) == decoded)
    }

    /// Byte-identical output for permuted entity arrays, children and sets.
    @Test func encodingIsDeterministicUnderPermutation() throws {
        let original = Fixture.fullDatabase()
        let reference = try original.encoded()
        var rng = TestRNG(seed: 99)
        for _ in 0..<25 {
            var db = original
            db.timetables.shuffle(using: &rng)
            db.subjects.shuffle(using: &rng)
            db.bellSchedules.shuffle(using: &rng)
            db.lessons.shuffle(using: &rng)
            db.terms.shuffle(using: &rng)
            db.breaks.shuffle(using: &rng)
            db.overrides.shuffle(using: &rng)
            db.tasks.shuffle(using: &rng)
            db.exams.shuffle(using: &rng)
            db.reminderRules.shuffle(using: &rng)
            for index in db.tasks.indices {
                db.tasks[index].subtasks.shuffle(using: &rng)
                db.tasks[index].attachments.shuffle(using: &rng)
            }
            // Rebuild sets with different capacities so their iteration order differs.
            for index in db.timetables.indices {
                var days = Set<Weekday>(minimumCapacity: Int.random(in: 8...512, using: &rng))
                for day in db.timetables[index].enabledDays.shuffled(using: &rng) { days.insert(day) }
                db.timetables[index].enabledDays = days
            }
            #expect(try db.encoded() == reference)
            #expect(db.canonicalized() == original.canonicalized())
        }
    }

    @Test func entityArraysAreSortedByID() throws {
        let tree = try JSONValue(encoding: Fixture.fullDatabase())
        guard case .array(let lessons)? = tree["lessons"] else {
            Issue.record("lessons missing")
            return
        }
        let ids = lessons.compactMap { $0["id"]?.stringValue }
        #expect(ids.count == lessons.count && ids == ids.sorted())
    }

    @Test func missingArraysDecodeAsEmpty() throws {
        let settings = try Fixture.json(AppSettings(meta: Fixture.meta()))
        let db = try TabulaDatabase.decode(from: Data(#"{"schemaVersion":1,"settings":\#(settings)}"#.utf8))
        #expect(db.timetables.isEmpty && db.lessons.isEmpty && db.reminderRules.isEmpty)
        #expect(db.settings.id == AppSettings.singletonID)
        #expect(db.validate().isEmpty)
    }

    @Test func otherSchemaVersionsStillDecode() throws {
        var db = Fixture.fullDatabase()
        db.schemaVersion = 2
        let decoded = try TabulaDatabase.decode(from: db.encoded())
        #expect(decoded.schemaVersion == 2)
    }

    @Test func datesAreIntegerMilliseconds() throws {
        let tree = try JSONValue(encoding: Fixture.fullDatabase())
        #expect(TabulaJSON.milliseconds(from: Fixture.now) == 1_791_280_800_000)   // 2026-10-06T10:00:00Z
        #expect(tree["settings"]?["onboardingCompletedAt"] == .integer(1_791_280_800_000))
        guard case .array(let tasks)? = tree["tasks"] else {
            Issue.record("tasks missing")
            return
        }
        #expect(tasks.contains { $0["completedAt"] == .integer(1_759_750_000_123) })
    }

    /// An older app must preserve values it does not know: an unknown override kind, an unknown lesson
    /// type, an unknown reminder offset, an unknown period kind and an unknown visible field.
    @Test func unknownValuesSurviveDecodeAndReencode() throws {
        var tree = try JSONValue(encoding: Fixture.fullDatabase())
        tree = try patch(tree, collection: "overrides", index: 0, field: "change",
                         value: .object(["kind": .string("swapRooms"), "roomA": .string("101"), "roomB": .string("B2"),
                                         "weights": .array([.integer(1), .double(2.5), .bool(true), .null])]))
        tree = try patch(tree, collection: "lessons", index: 0, field: "lessonType", value: .string("colloquium"))
        tree = try patch(tree, collection: "reminderRules", index: 0, field: "offsets",
                         value: .array([.object(["kind": .string("weekdayBefore"), "weekday": .integer(3)]),
                                        .object(["kind": .string("minutesBefore"), "minutes": .integer(10)])]))
        tree = try patch(tree, collection: "timetables", index: 0, field: "fieldVisibility",
                         value: .array([.string("onlineLink"), .string("room")]))
        tree = try patch(tree, collection: "timetables", index: 0, field: "defaultView", value: .string("kanban"))
        let input = try TabulaJSON.makeEncoder().encode(tree)

        let db = try TabulaDatabase.decode(from: input)
        #expect(db.overrides.contains { $0.change.isUnknown })
        #expect(db.lessons.contains { $0.lessonType == LessonType(rawValue: "colloquium") })
        #expect(db.reminderRules.contains { $0.offsets.contains { if case .unknown = $0 { return true } else { return false } } })
        #expect(db.timetables.contains { $0.fieldVisibility.isVisible(LessonField(rawValue: "onlineLink")) })

        let output = try db.encoded()
        #expect(output == input, "re-encoding must reproduce the input byte for byte")

        let infos = db.validate().filter { $0.code == .unknownValue }
        #expect(infos.count == 5)
        #expect(infos.allSatisfy { $0.severity == .info })
        #expect(Set(infos.compactMap(\.value)) == ["swapRooms", "colloquium", "weekdayBefore", "onlineLink", "kanban"])
        #expect(db.isValid)
    }

    private func patch(_ tree: JSONValue, collection: String, index: Int, field: String, value: JSONValue) throws -> JSONValue {
        guard case .object(var root) = tree, case .array(var items)? = root[collection],
              index < items.count, case .object(var item) = items[index] else {
            throw PatchError()
        }
        item[field] = value
        items[index] = .object(item)
        root[collection] = .array(items)
        return .object(root)
    }
}
