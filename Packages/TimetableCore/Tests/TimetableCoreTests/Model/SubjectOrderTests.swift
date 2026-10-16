import Foundation
import Testing
@testable import TimetableCore

// Phase 4 C1 (P3-2, approved 2026-10-16): `Subject.sortIndex`, the canonical subject order, reordering through the
// stamper, concurrent reorders in the sync merge, the share codec (`s[i].o`) and backups.

/// Shared helpers of the subject-order suites (prefixed to avoid collisions in the single test module).
enum SubjectOrderFixture {
    /// A real locale (ICU collation). Not `en_US_POSIX`: its collation orders by code point, so upper- and lower-case
    /// letters differ at the primary level and case-insensitive comparison does not fold them.
    static let english = Locale(identifier: "en_US")
    static let timetable: Timetable.ID = SyncFixture.id(1, namespace: 0x7A)
    static let otherTimetable: Timetable.ID = SyncFixture.id(2, namespace: 0x7A)

    static func id(_ n: UInt64) -> Subject.ID { SyncFixture.id(n, namespace: 0x5C) }

    static func subject(_ n: UInt64, _ name: String, _ index: Int?, timetable: Timetable.ID = timetable,
                        deleted: Bool = false) -> Subject {
        var meta = Fixture.meta()
        meta.isDeleted = deleted
        return Subject(id: id(n), meta: meta, timetableID: timetable, name: name, color: .black, sortIndex: index)
    }

    static func database(_ subjects: [Subject]) -> TabulaDatabase {
        var db = TabulaDatabase(settings: .untouchedDefaults)
        db.subjects = subjects
        return db
    }

    static func names(_ subjects: [Subject]) -> [String] { subjects.map(\.name) }

    static func liveNames(_ db: TabulaDatabase, timetable: Timetable.ID = timetable) -> [String] {
        names(SubjectOrder.live(db, timetableID: timetable, locale: english))
    }

    /// Applies a reorder like the app does: one stamped upsert per changed subject.
    static func reorder(_ db: inout TabulaDatabase, _ order: [Subject.ID], clock: inout HybridLogicalClock,
                        at millis: Int64) throws {
        for edited in SubjectOrder.reordered(order, in: db, timetableID: timetable, locale: english) {
            let index = try #require(db.subjects.firstIndex { $0.id == edited.id })
            db.subjects[index] = try MutationStamper.stamp(old: db.subjects[index], new: edited, clock: &clock,
                                                           now: SyncFixture.at(millis))
        }
    }

    /// Creates a subject like the app does: the insertion plan (renumbering first), then the new subject.
    static func add(_ db: inout TabulaDatabase, _ subject: Subject, clock: inout HybridLogicalClock, at millis: Int64) throws {
        let plan = SubjectOrder.insertion(in: db, timetableID: subject.timetableID, locale: english)
        for edited in plan.renumbered {
            let index = try #require(db.subjects.firstIndex { $0.id == edited.id })
            db.subjects[index] = try MutationStamper.stamp(old: db.subjects[index], new: edited, clock: &clock,
                                                           now: SyncFixture.at(millis))
        }
        var draft = subject
        draft.sortIndex = plan.sortIndex
        db.subjects.append(try MutationStamper.stamp(old: nil, new: draft, clock: &clock, now: SyncFixture.at(millis)))
    }

    /// Live subject IDs in display order.
    static func order(_ db: TabulaDatabase) -> [Subject.ID] {
        SubjectOrder.live(db, timetableID: timetable, locale: english).map(\.id)
    }
}

@Suite("Subject.sortIndex: schema (P3-2)")
struct SubjectSortIndexSchemaTests {
    /// A subject exactly as schema version 1 wrote it before P3-2 (canonical encoder output, no `sortIndex`).
    static let oldSubjectJSON = ##"{"color":"#E53935","colorName":{"kind":"key","value":"palette.classic.color.red"},"##
        + #""defaultRoom":"101","id":"000000F1-0000-4000-8000-000000000007","#
        + #""meta":{"createdAt":"001759744800000-0000000000-0000000000c0ffee","fieldClocks":{},"isDeleted":false,"#
        + #""updatedAt":"001759744800000-0000000000-0000000000c0ffee"},"#
        + #""name":"Matematika","shortName":"MAT","symbol":{"kind":"emoji","value":"➗"},"#
        + #""timetableID":"000000F1-0000-4000-8000-000000000001"}"#

    /// A whole database file written by the Phase 1–3 app (schema version 1, before P3-2).
    static let oldDatabaseJSON = #"{"bellSchedules":[],"breaks":[],"exams":[],"lessons":[],"overrides":[],"#
        + #""reminderRules":[],"schemaVersion":1,"#
        + #""settings":{"alarmPolicy":{"allowsPresetRules":false,"isEnabled":false},"appearance":"auto","hourCycle":"auto","#
        + #""id":"7AB01A00-5E77-4000-8000-000000000001","#
        + #""meta":{"createdAt":"000000000000000-0000000000-0000000000000000","fieldClocks":{},"isDeleted":false,"#
        + #""updatedAt":"000000000000000-0000000000-0000000000000000"},"#
        + #""palettePackID":"classic","profile":"secondary","syncEnabled":true,"#
        + #""timeSensitivePolicy":{"isEnabled":true,"maxLeadMinutes":60},"timeZoneMode":{"kind":"followDevice"}},"#
        + #""subjects":["# + oldSubjectJSON + #","#
        + ##"{"color":"#1E88E5","id":"000000F1-0000-4000-8000-000000000008","##
        + #""meta":{"createdAt":"001759744800000-0000000000-0000000000c0ffee","fieldClocks":{},"isDeleted":false,"#
        + #""updatedAt":"001759744800000-0000000000-0000000000c0ffee"},"#
        + #""name":"Fyzika","timetableID":"000000F1-0000-4000-8000-000000000001"}],"#
        + #""tasks":[],"terms":[],"timetables":[]}"#

    @Test func oldSubjectJSONDecodesUnchanged() throws {
        let subject = try Fixture.decode(Subject.self, Self.oldSubjectJSON)
        #expect(subject.sortIndex == nil)
        #expect(subject.name == "Matematika" && subject.shortName == "MAT" && subject.defaultRoom == "101")
        // nil is omitted, so re-encoding writes the old bytes exactly (byte stability for old data).
        #expect(try Fixture.json(subject) == Self.oldSubjectJSON)
    }

    @Test func oldDatabaseFileDecodesAndReencodesByteForByte() throws {
        let db = try TabulaDatabase.decode(from: Data(Self.oldDatabaseJSON.utf8))
        #expect(db.schemaVersion == 1)
        #expect(db.subjects.map(\.sortIndex) == [nil, nil])
        #expect(db.unknownFields.isEmpty)
        #expect(String(decoding: try db.encoded(), as: UTF8.self) == Self.oldDatabaseJSON)
        // Never ordered: alphabetical, as before P3-2.
        #expect(SubjectOrder.live(db, timetableID: db.subjects[0].timetableID, locale: SubjectOrderFixture.english)
            .map(\.name) == ["Fyzika", "Matematika"])
    }

    @Test func sortIndexIsWrittenAndRoundTrips() throws {
        var subject = try Fixture.decode(Subject.self, Self.oldSubjectJSON)
        subject.sortIndex = 3
        let json = try Fixture.json(subject)
        #expect(json.contains(#""sortIndex":3,"symbol""#)) // sorted keys: after shortName, before symbol
        #expect(try Fixture.roundTrip(subject) == subject)
        #expect(try Fixture.decode(Subject.self, json).sortIndex == 3)
    }

    @Test func sortIndexIsAKnownFieldNotAnUnknownKey() throws {
        #expect(EntityFieldCatalog.fieldKeys(for: .subject).contains("sortIndex"))
        var tree = try JSONValue(encoding: try TabulaDatabase.decode(from: Data(Self.oldDatabaseJSON.utf8)))
        tree = SyncJSONPatch.set(tree, [.key("subjects"), .index(1), .key("sortIndex")], .integer(0))
        let db = try TabulaDatabase.decode(from: try TabulaJSON.makeEncoder().encode(tree))
        #expect(db.subjects[1].sortIndex == 0)
        #expect(db.unknownFields.isEmpty)
    }

    /// What an older app (Phase 1–3 build) sees in a newer file: `sortIndex` is not in its field catalog, so it is
    /// kept as an unknown key and written back unchanged (DOMAIN_MODEL §7.3). Simulated with a key the current build
    /// does not know, on the same entity type.
    @Test func olderReadersKeepAnUnknownSubjectKey() throws {
        var tree = try JSONValue(encoding: try TabulaDatabase.decode(from: Data(Self.oldDatabaseJSON.utf8)))
        tree = SyncJSONPatch.set(tree, [.key("subjects"), .index(0), .key("sortIndexFromTheFuture")], .integer(4))
        let bytes = try TabulaJSON.makeEncoder().encode(tree)
        let db = try TabulaDatabase.decode(from: bytes)
        #expect(db.unknownFields.fields(of: db.subjects[0])?.fields["sortIndexFromTheFuture"] == .integer(4))
        #expect(try db.encoded() == bytes)
    }

    @Test func schemaVersionStaysOne() {
        #expect(TabulaDatabase.currentSchemaVersion == 1)
        #expect(TimetableCoreInfo.schemaVersion == 1)
    }

    @Test func sampleSubjectsAreNumberedInSeedOrder() {
        var ids = SequentialIDGenerator(namespace: 0x5A)
        var clock = TestClock()
        let timetable = Fixture.fullDatabase().timetables[0]
        let content = SampleData.make(profile: .secondary, timetable: timetable, bellSchedule: nil, today: Fixture.date("2026-10-06"),
                                      localize: { $0.key }, ids: &ids, clock: &clock, now: Fixture.now)
        #expect(content.subjects.map(\.sortIndex) == Array(0..<content.subjects.count).map { Optional($0) })
        #expect(SubjectOrder.sorted(content.subjects.reversed(), locale: SubjectOrderFixture.english).map(\.id)
                == content.subjects.map(\.id))
    }
}

@Suite("Subject order: canonical sort (P3-2)")
struct SubjectCanonicalOrderTests {
    typealias F = SubjectOrderFixture

    @Test func indexedFirstThenNilsAlphabetically() {
        let subjects = [F.subject(1, "Zoology", nil), F.subject(2, "art", nil), F.subject(3, "Physics", 1),
                        F.subject(4, "Biology", 0), F.subject(5, "Chemistry", nil)]
        #expect(F.names(SubjectOrder.sorted(subjects, locale: F.english))
                == ["Biology", "Physics", "art", "Chemistry", "Zoology"])
    }

    @Test func equalIndicesFallBackToNameThenID() {
        let subjects = [F.subject(9, "Math", 2), F.subject(3, "math", 2), F.subject(5, "Biology", 2), F.subject(1, "Art", 1)]
        // "Math" and "math" compare equal case-insensitively: the smaller ID (3) first.
        #expect(SubjectOrder.sorted(subjects, locale: F.english).map(\.id) == [F.id(1), F.id(5), F.id(3), F.id(9)])
    }

    @Test func caseInsensitiveNameOrder() {
        let subjects = [F.subject(1, "banana", nil), F.subject(2, "Apple", nil), F.subject(3, "cherry", nil)]
        #expect(F.names(subjects.sortedForDisplay(locale: F.english)) == ["Apple", "banana", "cherry"])
    }

    @Test func negativeAndLargeIndicesOrderNumerically() {
        let subjects = [F.subject(1, "A", Int.max), F.subject(2, "B", -5), F.subject(3, "C", 0), F.subject(4, "D", Int.min)]
        #expect(F.names(SubjectOrder.sorted(subjects, locale: F.english)) == ["D", "B", "C", "A"])
    }

    /// Property: the order is total and independent of the input order (random indices, nils, equal names).
    @Test func orderIsIndependentOfInputPermutation() {
        var rng = TestRNG(seed: 0x50_27)
        let pool = ["Math", "math", "Art", "Biology", "biology", "Chemistry", "Ético", "Zed"]
        for _ in 0..<300 {
            let count = Int.random(in: 0...12, using: &rng)
            let subjects = (0..<count).map { n in
                F.subject(UInt64(n + 1), pool.randomElement(using: &rng)!,
                          Bool.random(using: &rng) ? nil : Int.random(in: -2...4, using: &rng))
            }
            let reference = SubjectOrder.sorted(subjects, locale: F.english).map(\.id)
            #expect(SubjectOrder.sorted(subjects.shuffled(using: &rng), locale: F.english).map(\.id) == reference)
            #expect(Set(reference).count == count)
            // Consistent with `precedes`: strictly increasing, nils after every index.
            let sorted = SubjectOrder.sorted(subjects, locale: F.english)
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                #expect(SubjectOrder.precedes(a, b, locale: F.english) && !SubjectOrder.precedes(b, a, locale: F.english))
            }
            if let firstNil = sorted.firstIndex(where: { $0.sortIndex == nil }) {
                #expect(sorted[firstNil...].allSatisfy { $0.sortIndex == nil })
            }
        }
    }

    @Test func liveFiltersByTimetableAndSkipsTombstones() {
        let db = F.database([F.subject(1, "B", 1), F.subject(2, "A", 0, deleted: true), F.subject(3, "C", 0),
                             F.subject(4, "Other", 0, timetable: F.otherTimetable)])
        #expect(F.liveNames(db) == ["C", "B"])
        #expect(F.liveNames(db, timetable: F.otherTimetable) == ["Other"])
    }

    @Test func mixedTimetablesGroupByTimetableOrder() {
        let unknown: Timetable.ID = SyncFixture.id(9, namespace: 0x7A)
        let subjects = [F.subject(1, "B", 0, timetable: F.otherTimetable), F.subject(2, "Z", 1),
                        F.subject(3, "Q", nil, timetable: unknown), F.subject(4, "A", 0), F.subject(5, "C", nil, timetable: F.otherTimetable)]
        let sorted = SubjectOrder.sorted(subjects, timetableOrder: [F.otherTimetable, F.timetable], locale: F.english)
        #expect(F.names(sorted) == ["B", "C", "A", "Z", "Q"])
        // Repeated timetable IDs in the order use the first position.
        let repeated = SubjectOrder.sorted(subjects, timetableOrder: [F.timetable, F.otherTimetable, F.timetable], locale: F.english)
        #expect(F.names(repeated) == ["A", "Z", "B", "C", "Q"])
    }

    @Test func denseRanksShareTiesAndSkipNils() {
        let subjects = [F.subject(1, "A", 5), F.subject(2, "B", 5), F.subject(3, "C", 9), F.subject(4, "D", nil),
                        F.subject(5, "E", -1)]
        #expect(SubjectOrder.denseRanks(subjects) == [F.id(1): 1, F.id(2): 1, F.id(3): 2, F.id(5): 0])
        #expect(SubjectOrder.denseRanks([Subject]()).isEmpty)
    }
}

@Suite("Subject order: reorder and insertion plans (P3-2)")
struct SubjectReorderPlanTests {
    typealias F = SubjectOrderFixture

    @Test func reorderAssignsDenseIndicesAndReturnsOnlyChanges() {
        let db = F.database([F.subject(1, "A", 0), F.subject(2, "B", 1), F.subject(3, "C", 2)])
        let changed = SubjectOrder.reordered([F.id(1), F.id(3), F.id(2)], in: db, timetableID: F.timetable, locale: F.english)
        #expect(changed.map(\.id) == [F.id(3), F.id(2)])
        #expect(changed.map(\.sortIndex) == [1, 2])
        #expect(SubjectOrder.reordered(F.order(db), in: db, timetableID: F.timetable, locale: F.english).isEmpty)
    }

    @Test func reorderNumbersNeverOrderedSubjects() {
        let db = F.database([F.subject(1, "C", nil), F.subject(2, "A", nil), F.subject(3, "B", nil)])
        let changed = SubjectOrder.reordered([F.id(1)], in: db, timetableID: F.timetable, locale: F.english)
        // C moved to the top; the rest keep their (alphabetical) canonical order behind it.
        #expect(F.names(changed) == ["C", "A", "B"] && changed.map(\.sortIndex) == [0, 1, 2])
    }

    @Test func reorderIgnoresForeignDeletedAndRepeatedIDs() {
        let db = F.database([F.subject(1, "A", 0), F.subject(2, "B", 1), F.subject(3, "C", 2),
                             F.subject(4, "Gone", 3, deleted: true), F.subject(5, "Other", 0, timetable: F.otherTimetable)])
        let order = [F.id(5), F.id(3), F.id(4), F.id(3), F.id(99), F.id(1)]
        let changed = SubjectOrder.reordered(order, in: db, timetableID: F.timetable, locale: F.english)
        #expect(changed.map(\.id) == [F.id(3), F.id(1), F.id(2)])  // C, A, then B (not named) behind
        #expect(changed.map(\.sortIndex) == [0, 1, 2])
        #expect(!changed.contains { $0.id == F.id(4) || $0.id == F.id(5) })
    }

    @Test func reorderCompactsGapsAndTies() {
        let db = F.database([F.subject(1, "A", 7), F.subject(2, "B", 7), F.subject(3, "C", 40)])
        let changed = SubjectOrder.reordered(F.order(db), in: db, timetableID: F.timetable, locale: F.english)
        #expect(changed.map(\.sortIndex) == [0, 1, 2])
    }

    @Test func insertionIntoAnEmptyTimetableStartsAtZero() {
        let plan = SubjectOrder.insertion(in: F.database([]), timetableID: F.timetable, locale: F.english)
        #expect(plan == SubjectOrder.Insertion(sortIndex: 0, renumbered: []))
    }

    @Test func insertionAppendsAfterTheHighestIndex() {
        let db = F.database([F.subject(1, "A", 0), F.subject(2, "B", 4), F.subject(3, "Gone", 9, deleted: true),
                             F.subject(4, "Other", 20, timetable: F.otherTimetable)])
        #expect(SubjectOrder.insertion(in: db, timetableID: F.timetable, locale: F.english)
                == SubjectOrder.Insertion(sortIndex: 5, renumbered: []))
    }

    @Test func insertionWritesDownTheVisibleOrderWhenSomeSubjectsHaveNoIndex() {
        // Legacy (never ordered) timetable: alphabetical order is written down, the new subject goes last.
        let legacy = F.database([F.subject(1, "Chemistry", nil), F.subject(2, "Art", nil)])
        let plan = SubjectOrder.insertion(in: legacy, timetableID: F.timetable, locale: F.english)
        #expect(plan.sortIndex == 2)
        #expect(F.names(plan.renumbered) == ["Art", "Chemistry"] && plan.renumbered.map(\.sortIndex) == [0, 1])
        // Mixed (an older app version added "Zed" without an index): indexed first, then the nils.
        let mixed = F.database([F.subject(1, "B", 3), F.subject(2, "A", 1), F.subject(3, "Zed", nil)])
        let mixedPlan = SubjectOrder.insertion(in: mixed, timetableID: F.timetable, locale: F.english)
        #expect(mixedPlan.sortIndex == 3)
        #expect(F.names(mixedPlan.renumbered) == ["A", "B", "Zed"] && mixedPlan.renumbered.map(\.sortIndex) == [0, 1, 2])
    }

    /// Property: whatever the existing indices, a subject added through the insertion plan is shown last and the
    /// order of the existing subjects does not change.
    @Test func newSubjectsAreAlwaysLast() throws {
        var rng = TestRNG(seed: 0xADD)
        for _ in 0..<200 {
            let count = Int.random(in: 0...8, using: &rng)
            var db = F.database((0..<count).map { n in
                F.subject(UInt64(n + 1), ["A", "b", "C", "d"].randomElement(using: &rng)!,
                          Bool.random(using: &rng) ? nil : Int.random(in: 0...5, using: &rng),
                          deleted: Int.random(in: 0..<6, using: &rng) == 0)
            })
            let before = F.order(db)
            var clock = HybridLogicalClock(node: 3)
            try F.add(&db, F.subject(100, ["A", "Zz", "0"].randomElement(using: &rng)!, nil), clock: &clock, at: 10)
            #expect(F.order(db) == before + [F.id(100)])
        }
    }

    /// QA C1: `max + 1` must not trap on a stored `Int.max` (crafted backup or synced record).
    @Test func insertionAfterIntMaxRenumbersInsteadOfTrapping() {
        let db = F.database([F.subject(1, "A", 0), F.subject(2, "B", Int.max), F.subject(3, "C", 5)])
        let plan = SubjectOrder.insertion(in: db, timetableID: F.timetable, locale: F.english)
        #expect(plan.sortIndex == 3)
        #expect(F.names(plan.renumbered) == ["C", "B"] && plan.renumbered.map(\.sortIndex) == [1, 2])
        #expect(SubjectOrder.appendedIndex(after: [Int.max]) == nil)
        #expect(SubjectOrder.appendedIndex(after: [Int.max - 1]) == Int.max)
        #expect(SubjectOrder.appendedIndex(after: [Int]()) == 0)
        #expect(SubjectOrder.appendedIndex(after: [Int.min]) == Int.min + 1)
    }

    @Test func movingUpAndDown() {
        let ids = [F.id(1), F.id(2), F.id(3)]
        #expect(SubjectOrder.moving(F.id(2), by: -1, in: ids) == [F.id(2), F.id(1), F.id(3)])
        #expect(SubjectOrder.moving(F.id(2), by: 1, in: ids) == [F.id(1), F.id(3), F.id(2)])
        #expect(SubjectOrder.moving(F.id(1), by: 2, in: ids) == [F.id(2), F.id(3), F.id(1)])
        #expect(SubjectOrder.moving(F.id(1), by: -1, in: ids) == nil)
        #expect(SubjectOrder.moving(F.id(3), by: 1, in: ids) == nil)
        #expect(SubjectOrder.moving(F.id(2), by: 0, in: ids) == nil)
        #expect(SubjectOrder.moving(F.id(9), by: 1, in: ids) == nil)
    }
}

@Suite("Subject order: stamping and sync merge (P3-2)")
struct SubjectReorderSyncTests {
    typealias F = SubjectOrderFixture

    /// Three subjects X, Y, Z created at t0 with indices 0, 1, 2 (on a shared clock).
    static func base(count: Int = 3, indexed: Bool = true) throws -> TabulaDatabase {
        var clock = HybridLogicalClock(node: 1)
        let names = ["Xylophone", "Yarn", "Zinc", "Walnut", "Violet", "Umber", "Tin", "Sage"]
        var db = F.database([])
        for n in 0..<count {
            let draft = F.subject(UInt64(n + 1), names[n], indexed ? n : nil)
            db.subjects.append(try MutationStamper.stamp(old: nil, new: draft, clock: &clock, now: SyncFixture.at(0)))
        }
        return db
    }

    static func ids(_ db: TabulaDatabase, _ names: [String]) -> [Subject.ID] {
        names.map { name in db.subjects.first { $0.name == name }!.id }
    }

    @Test func reorderStampsOnlyTheMovedSubjects() throws {
        var db = try Self.base()
        let untouched = db.subjects[0]
        var clock = HybridLogicalClock(node: 0xA)
        try F.reorder(&db, Self.ids(db, ["Xylophone", "Zinc", "Yarn"]), clock: &clock, at: 100)
        #expect(db.subjects[0] == untouched)                         // index unchanged: not rewritten
        let moved = db.subjects.filter { $0.name != "Xylophone" }
        let stamp = try #require(moved.first?.meta.updatedAt)
        #expect(moved.allSatisfy { $0.meta.fieldClocks == ["sortIndex": $0.meta.updatedAt] })
        #expect(stamp > untouched.meta.updatedAt)
        #expect(F.liveNames(db) == ["Xylophone", "Zinc", "Yarn"])
    }

    @Test func aReorderSurvivesAMergeWithAnUntouchedReplica() throws {
        let base = try Self.base(indexed: false)                     // pre-P3-2 data on the other device
        var a = base
        var clock = HybridLogicalClock(node: 0xA)
        try F.reorder(&a, Self.ids(a, ["Zinc", "Xylophone", "Yarn"]), clock: &clock, at: 100)
        for merged in [try SyncMerge.merge(local: a, remote: base), try SyncMerge.merge(local: base, remote: a)] {
            #expect(F.liveNames(merged) == ["Zinc", "Xylophone", "Yarn"])
        }
    }

    @Test func theLaterOfTwoFullReordersWinsWhole() throws {
        let base = try Self.base()
        var a = base, b = base
        var clockA = HybridLogicalClock(node: 0xA), clockB = HybridLogicalClock(node: 0xB)
        try F.reorder(&a, Self.ids(a, ["Zinc", "Xylophone", "Yarn"]), clock: &clockA, at: 100) // every index changes
        try F.reorder(&b, Self.ids(b, ["Yarn", "Zinc", "Xylophone"]), clock: &clockB, at: 200) // every index changes
        let ab = try SyncMerge.merge(local: a, remote: b), ba = try SyncMerge.merge(local: b, remote: a)
        #expect(ab == ba)
        #expect(F.liveNames(ab) == ["Yarn", "Zinc", "Xylophone"])
    }

    /// Per-subject LWW (DOMAIN_MODEL §2.2): when the later reorder leaves a subject's index unchanged, that subject
    /// keeps the earlier device's index. Indices may then tie; the canonical order decides deterministically
    /// (name, then ID) on every device, and the next reorder writes dense indices again.
    @Test func partialConcurrentReordersMergeDeterministically() throws {
        let base = try Self.base()
        var a = base, b = base
        var clockA = HybridLogicalClock(node: 0xA), clockB = HybridLogicalClock(node: 0xB)
        try F.reorder(&a, Self.ids(a, ["Zinc", "Xylophone", "Yarn"]), clock: &clockA, at: 100) // Z0 X1 Y2
        try F.reorder(&b, Self.ids(b, ["Yarn", "Xylophone", "Zinc"]), clock: &clockB, at: 200) // Y0 X1 (Z stays 2)
        let ab = try SyncMerge.merge(local: a, remote: b), ba = try SyncMerge.merge(local: b, remote: a)
        #expect(ab == ba)
        let indices = Dictionary(uniqueKeysWithValues: ab.subjects.map { ($0.name, $0.sortIndex) })
        #expect(indices == ["Yarn": 0, "Xylophone": 1, "Zinc": 0])
        #expect(F.liveNames(ab) == ["Yarn", "Zinc", "Xylophone"])  // tie Yarn/Zinc broken by name
        var next = ab
        var clockC = HybridLogicalClock(node: 0xC)
        try F.reorder(&next, F.order(next), clock: &clockC, at: 300)
        #expect(next.subjects.sorted { $0.sortIndex! < $1.sortIndex! }.map(\.name) == ["Yarn", "Zinc", "Xylophone"])
        #expect(Set(next.subjects.compactMap(\.sortIndex)) == [0, 1, 2])
    }

    @Test func aConcurrentlyAddedSubjectStaysLast() throws {
        let base = try Self.base()
        var a = base, b = base
        var clockA = HybridLogicalClock(node: 0xA), clockB = HybridLogicalClock(node: 0xB)
        try F.reorder(&a, Self.ids(a, ["Zinc", "Xylophone", "Yarn"]), clock: &clockA, at: 100)
        try F.add(&b, F.subject(50, "Apple", nil), clock: &clockB, at: 150)
        let ab = try SyncMerge.merge(local: a, remote: b)
        #expect(ab == (try SyncMerge.merge(local: b, remote: a)))
        #expect(F.liveNames(ab) == ["Zinc", "Xylophone", "Yarn", "Apple"])
    }

    /// Known edge (tombstone rule, DOMAIN_MODEL §2.2): a reorder on a device that has not yet seen a delete
    /// rewrites the index of every subject it moves; a moved subject's newer write resurrects it, an unmoved one
    /// stays deleted. Reported in RISKS.md.
    @Test func reorderAfterAnUnseenDeleteResurrectsOnlyMovedSubjects() throws {
        let base = try Self.base(count: 4)                            // X0 Y1 Z2 W3
        var a = base, b = base
        var clockA = HybridLogicalClock(node: 0xA), clockB = HybridLogicalClock(node: 0xB)
        for name in ["Walnut", "Xylophone"] {
            let index = try #require(a.subjects.firstIndex { $0.name == name })
            a.subjects[index] = try MutationStamper.delete(a.subjects[index], clock: &clockA, now: SyncFixture.at(100))
        }
        // B swaps Y and Z: X and W keep their indices (not rewritten).
        try F.reorder(&b, Self.ids(b, ["Xylophone", "Zinc", "Yarn", "Walnut"]), clock: &clockB, at: 200)
        let merged = try SyncMerge.merge(local: a, remote: b)
        #expect(F.liveNames(merged) == ["Zinc", "Yarn"])               // X and W stay deleted
        // Moving W on B (it was deleted on A before) resurrects it.
        var c = base
        try F.reorder(&c, Self.ids(c, ["Walnut", "Xylophone", "Yarn", "Zinc"]), clock: &clockB, at: 200)
        #expect(F.liveNames(try SyncMerge.merge(local: a, remote: c)).contains("Walnut"))
    }

    /// Property: random concurrent reorders, additions and deletions on two devices merge to the same database in
    /// either direction; the merge is idempotent and absorbs each side; the merged display order is a total order of
    /// the live subjects; a reorder on one side only survives the merge.
    @Test func randomConcurrentReordersConverge() throws {
        for seed in UInt64(1)...150 {
            var rng = TestRNG(seed: seed)
            let base = try Self.base(count: Int.random(in: 2...8, using: &rng), indexed: Bool.random(using: &rng))
            var a = base, b = base
            var clockA = HybridLogicalClock(node: 0xA), clockB = HybridLogicalClock(node: 0xB)
            var nextID: UInt64 = 100
            func act(_ db: inout TabulaDatabase, _ clock: inout HybridLogicalClock, allowEdits: Bool) throws {
                for _ in 0..<Int.random(in: 1...3, using: &rng) {
                    let millis = Int64.random(in: 10...400, using: &rng)
                    switch allowEdits ? Int.random(in: 0..<6, using: &rng) : 0 {
                    case 0...3:
                        try F.reorder(&db, F.order(db).shuffled(using: &rng), clock: &clock, at: millis)
                    case 4:
                        nextID += 1
                        try F.add(&db, F.subject(nextID, "New \(nextID)", nil), clock: &clock, at: millis)
                    default:
                        if let victim = db.subjects.indices.filter({ !db.subjects[$0].isDeleted }).randomElement(using: &rng) {
                            db.subjects[victim] = try MutationStamper.delete(db.subjects[victim], clock: &clock,
                                                                             now: SyncFixture.at(millis))
                        }
                    }
                }
            }
            try act(&a, &clockA, allowEdits: true)
            let onlyA = try SyncMerge.merge(local: a, remote: base)
            #expect(F.order(onlyA) == F.order(a), "seed \(seed): a one-sided reorder survives")
            try act(&b, &clockB, allowEdits: true)

            let ab = try SyncMerge.merge(local: a, remote: b), ba = try SyncMerge.merge(local: b, remote: a)
            #expect(ab == ba, "seed \(seed)")
            #expect(try SyncMerge.merge(local: ab, remote: ab) == ab, "seed \(seed): idempotent")
            #expect(try SyncMerge.merge(local: ab, remote: a) == ab, "seed \(seed): absorbs A")
            #expect(try SyncMerge.merge(local: ab, remote: b) == ab, "seed \(seed): absorbs B")
            let order = F.order(ab)
            #expect(Set(order) == Set(ab.subjects.filter { !$0.isDeleted }.map(\.id)), "seed \(seed)")
            #expect(Set(order).count == order.count)
            // The next reorder (keeping the merged order) writes dense indices and does not change the order.
            var dense = ab
            var clockC = HybridLogicalClock(node: 0xC)
            try F.reorder(&dense, order, clock: &clockC, at: 1_000)
            #expect(F.order(dense) == order, "seed \(seed)")
            #expect(dense.subjects.filter { !$0.isDeleted }.compactMap(\.sortIndex).sorted() == Array(0..<order.count))
        }
    }
}

@Suite("Subject order: share codec and backup (P3-2)")
struct SubjectOrderShareBackupTests {
    typealias F = SubjectOrderFixture

    @Test func exportWritesDenseRanksAndImportRestoresTheOrder() throws {
        var db = ShareFixture.secondary()
        // Gaps and a tie in the source: ranks are dense, the tie stays a tie, nil stays absent.
        let indices: [Int?] = [10, 10, 30, nil, 2, 50, 51, 52, 53, 54, 55, 56, 57, nil]
        for (index, value) in indices.enumerated() { db.subjects[index].sortIndex = value }
        let payload = try ShareFixture.payload(db, ShareFixture.secondaryTimetableID)
        let byName = Dictionary(uniqueKeysWithValues: payload.subjects.map { ($0.name, $0.sortIndex) })
        #expect(byName[db.subjects[0].name] == 1 && byName[db.subjects[1].name] == 1)
        #expect(byName[db.subjects[4].name] == 0 && byName[db.subjects[2].name] == 2)
        #expect(byName[db.subjects[3].name] == .some(nil) && byName[db.subjects[13].name] == .some(nil))
        #expect(Set(payload.subjects.compactMap(\.sortIndex)) == Set(0...10))

        let (imported, timetableID) = try ShareFixture.importIntoEmptyDatabase(payload)
        let sourceOrder = SubjectOrder.live(db, timetableID: ShareFixture.secondaryTimetableID, locale: F.english).map(\.name)
        #expect(SubjectOrder.live(imported, timetableID: timetableID, locale: F.english).map(\.name) == sourceOrder)
    }

    @Test func secondaryFixtureKeepsItsManualOrderThroughALink() throws {
        let db = ShareFixture.secondary()
        let envelope = try ShareExport.encode(from: db, timetableID: ShareFixture.secondaryTimetableID, includeTasks: false).envelope
        let payload = try ShareCodec.decode(envelope.text)
        let (imported, timetableID) = try ShareFixture.importIntoEmptyDatabase(payload)
        let expected = SubjectOrder.live(db, timetableID: ShareFixture.secondaryTimetableID, locale: F.english).map(\.name)
        #expect(expected.first == "Slovenský jazyk a literatúra")      // manual (list) order, not alphabetical
        #expect(SubjectOrder.live(imported, timetableID: timetableID, locale: F.english).map(\.name) == expected)
    }

    /// A payload written before P3-2 (the golden v1 shape without `o`) still imports; its subjects have no index.
    @Test func oldPayloadWithoutOrderImports() throws {
        let json = #"{"b":[{"n":"Normal","p":[{"a":"08:00","k":0,"z":"08:45"},{"a":"08:55","k":1,"z":"09:40"}]}],"#
            + #""l":[{"p":0,"s":0,"w":1}],"#
            + ##""s":[{"c":"#E53935","ck":"palette.classic.color.red","n":"Math","se":"➗"},{"c":"#1E88E5","n":"Art"}],"##
            + #""t":{"d":[1,2],"de":"comfortable","dv":"grid","n":"Mini","ts":{"d":0,"k":"b"}},"v":1}"#
        let payload = try ShareCodec.decode(ShareFixture.envelope(json: json))
        #expect(payload.subjects.map(\.sortIndex) == [nil, nil])
        let (imported, timetableID) = try ShareFixture.importIntoEmptyDatabase(payload)
        #expect(imported.subjects.map(\.sortIndex) == [nil, nil])
        #expect(SubjectOrder.live(imported, timetableID: timetableID, locale: F.english).map(\.name) == ["Art", "Math"])
    }

    @Test func orderKeyIsOptionalAndOmittedWhenNil() throws {
        var payload = ShareFixture.minimalPayload()
        #expect(!(try ShareFixture.unvalidatedJSON(payload)).contains(#""o":"#))
        payload.subjects[0].sortIndex = 0
        let json = try ShareFixture.unvalidatedJSON(payload)
        #expect(json.contains(#""n":"Math","o":0"#))
        #expect(try ShareCodec.decode(ShareCodec.encode(payload).text) == payload)
    }

    @Test func orderOutsideTheSubjectLimitIsRejected() throws {
        for (value, error) in [(-1, ShareError.invalidValue(path: "s[0].o")), (ShareLimits.maxSubjects, .invalidValue(path: "s[0].o")),
                               (Int.max, .invalidValue(path: "s[0].o"))] {
            var payload = ShareFixture.minimalPayload()
            payload.subjects[0].sortIndex = value
            #expect(ShareFixture.error(validating: payload) == error, "\(value)")
            #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: ShareFixture.unvalidatedJSON(payload))) == error)
        }
        var edge = ShareFixture.minimalPayload()
        edge.subjects[0].sortIndex = ShareLimits.maxSubjects - 1
        #expect(ShareFixture.error(validating: edge) == nil)
        // Not an integer: malformed.
        let text = try ShareFixture.unvalidatedJSON(ShareFixture.minimalPayload())
            .replacingOccurrences(of: #""n":"Math""#, with: #""n":"Math","o":"first""#)
        #expect(ShareFixture.error(decoding: try ShareFixture.envelope(json: text)) == .malformedPayload(path: "s[0].o"))
    }

    @Test func backupKeepsTheOrder() throws {
        var db = Fixture.fullDatabase()
        db.subjects[2].sortIndex = 7
        let restored = try BackupArchive.decode(from: try BackupArchive.make(from: db, createdAt: Fixture.now).encoded()).database()
        #expect(restored == db.canonicalized())
        #expect(restored.subjects.map(\.sortIndex) == db.canonicalized().subjects.map(\.sortIndex))
        #expect(restored.subjects.contains { $0.sortIndex == 7 })
    }
}
