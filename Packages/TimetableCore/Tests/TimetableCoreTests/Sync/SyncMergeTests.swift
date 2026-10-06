import Foundation
import Testing
@testable import TimetableCore

/// Two devices editing one task: helpers to keep scenarios short.
private struct SyncPair {
    var a = HybridLogicalClock(node: 0xA)
    var b = HybridLogicalClock(node: 0xB)
    let base: TaskItem

    init(subtasks: [Subtask] = []) throws {
        var clock = HybridLogicalClock(node: 0xA)
        base = try SyncFixture.task(SyncFixture.taskID(1), title: "Base", clock: &clock, at: 0, subtasks: subtasks)
        a = clock
        b.receive(base.meta.updatedAt, now: SyncFixture.at(0))
    }

    mutating func onA(_ task: TaskItem, at millis: Int64, _ edit: (inout TaskItem) -> Void) throws -> TaskItem {
        var copy = task
        edit(&copy)
        return try MutationStamper.stamp(old: task, new: copy, clock: &a, now: SyncFixture.at(millis))
    }

    mutating func onB(_ task: TaskItem, at millis: Int64, _ edit: (inout TaskItem) -> Void) throws -> TaskItem {
        var copy = task
        edit(&copy)
        return try MutationStamper.stamp(old: task, new: copy, clock: &b, now: SyncFixture.at(millis))
    }
}

@Suite("SyncMerge — rules")
struct SyncMergeTests {
    private func both(_ x: TaskItem, _ y: TaskItem) throws -> TaskItem {
        let xy = try SyncMerge.merge(local: x, remote: y)
        let yx = try SyncMerge.merge(local: y, remote: x)
        #expect(SyncFixture.json(xy) == SyncFixture.json(yx), "merge must be commutative")
        return xy
    }

    @Test func concurrentEditsOfDifferentFieldsAreBothKept() throws {
        var pair = try SyncPair()
        let a = try pair.onA(pair.base, at: 100) { $0.title = "A title" }
        let b = try pair.onB(pair.base, at: 50) { $0.notes = "B notes"; $0.priority = .high }
        let merged = try both(a, b)
        #expect(merged.title == "A title" && merged.notes == "B notes" && merged.priority == .high)
        #expect(merged.meta.updatedAt == a.meta.updatedAt)
    }

    @Test func sameFieldLaterWriteWins() throws {
        var pair = try SyncPair()
        let a = try pair.onA(pair.base, at: 100) { $0.title = "A" }
        let b = try pair.onB(pair.base, at: 200) { $0.title = "B" }
        #expect(try both(a, b).title == "B")
        // Clearing a field is a write like any other.
        let a1 = try pair.onA(pair.base, at: 100) { $0.notes = "n" }
        pair.b.receive(a1.meta.updatedAt, now: SyncFixture.at(150))
        let b1 = try pair.onB(a1, at: 400) { $0.notes = nil }
        let a2 = try pair.onA(a1, at: 300) { $0.title = "A2" }
        let merged = try both(a2, b1)
        #expect(merged.notes == nil && merged.title == "A2")
    }

    @Test func tieOnPhysicalTimeIsBrokenByNode() throws {
        var pair = try SyncPair()
        // Both devices edit within the same millisecond with the same logical counter: node 0xB > 0xA.
        let a = try pair.onA(pair.base, at: 100) { $0.title = "A" }
        let b = try pair.onB(pair.base, at: 100) { $0.title = "B" }
        #expect(a.meta.updatedAt.physicalMillis == b.meta.updatedAt.physicalMillis)
        #expect(a.meta.updatedAt.logical == b.meta.updatedAt.logical)
        #expect(try both(a, b).title == "B")
    }

    /// Identical clocks with different values only arise from hand-made data; the result is still
    /// deterministic and commutative.
    @Test func exactClockTieIsDeterministic() throws {
        let t = SyncFixture.hlc(5)
        let a = TaskItem(id: SyncFixture.taskID(1), meta: .created(at: t), title: "apple")
        let b = TaskItem(id: SyncFixture.taskID(1), meta: .created(at: t), title: "banana", notes: "x")
        let merged = try both(a, b)
        #expect(merged.title == "banana" && merged.notes == "x")
    }

    // MARK: Tombstones

    @Test func deleteAfterConcurrentEditWins() throws {
        var pair = try SyncPair()
        let deleted = try pair.onA(pair.base, at: 500) { $0.meta.isDeleted = true }
        let edited = try pair.onB(pair.base, at: 300) { $0.title = "edited earlier" }
        let merged = try both(deleted, edited)
        #expect(merged.isDeleted)
        #expect(merged.title == "edited earlier", "fields still merge while deleted (visible after a restore)")
    }

    @Test func editAfterDeleteResurrects() throws {
        var pair = try SyncPair()
        let deleted = try pair.onA(pair.base, at: 300) { $0.meta.isDeleted = true }
        let edited = try pair.onB(pair.base, at: 500) { $0.notes = "still needed" }
        let merged = try both(deleted, edited)
        #expect(!merged.isDeleted && merged.notes == "still needed")
    }

    @Test func restoreBeatsOlderTombstoneAndLaterDeleteBeatsRestore() throws {
        var pair = try SyncPair()
        let deleted = try pair.onA(pair.base, at: 100) { $0.meta.isDeleted = true }
        let restored = try MutationStamper.restore(deleted, clock: &pair.a, now: SyncFixture.at(200))
        // B still has only the tombstone.
        #expect(try !both(restored, deleted).isDeleted)
        // B receives the restore, then deletes again later.
        pair.b.receive(restored.meta.updatedAt, now: SyncFixture.at(250))
        let deletedAgain = try MutationStamper.delete(restored, clock: &pair.b, now: SyncFixture.at(300))
        #expect(try both(restored, deletedAgain).isDeleted)
        #expect(try both(deletedAgain, deleted).isDeleted)
    }

    @Test func deleteAndEditInTheSameStampStaysDeleted() throws {
        var pair = try SyncPair()
        let combined = try pair.onA(pair.base, at: 100) { $0.title = "last words"; $0.meta.isDeleted = true }
        let merged = try SyncMerge.merge(local: combined, remote: pair.base)
        #expect(merged.isDeleted && merged.title == "last words")
    }

    // MARK: Children

    @Test func childrenAreSetMergedByID() throws {
        var pair = try SyncPair(subtasks: [SyncFixture.subtask(1, "shared")])
        let a = try pair.onA(pair.base, at: 100) {
            $0.subtasks.append(SyncFixture.subtask(2, "from A", sortIndex: 1))
            $0.subtasks[0].completedAt = SyncFixture.at(100)
        }
        let b = try pair.onB(pair.base, at: 200) {
            $0.subtasks.append(SyncFixture.subtask(3, "from B", sortIndex: 2))
            $0.subtasks[0].title = "shared, renamed"
        }
        let merged = try both(a, b)
        #expect(merged.subtasks.map(\.title) == ["shared, renamed", "from A", "from B"])
        #expect(merged.subtasks[0].completedAt == SyncFixture.at(100))
    }

    @Test func childTombstoneVersusChildEdit() throws {
        var pair = try SyncPair(subtasks: [SyncFixture.subtask(1, "one"), SyncFixture.subtask(2, "two", sortIndex: 1)])
        let removedOnA = try pair.onA(pair.base, at: 300) { $0.subtasks.removeAll() }
        #expect(removedOnA.subtasks.count == 2 && removedOnA.subtasks.allSatisfy { $0.meta.isDeleted })
        let editedOnB = try pair.onB(pair.base, at: 200) { $0.subtasks[0].title = "one (earlier edit)" }
        let editedLaterOnB = try pair.onB(pair.base, at: 400) { $0.subtasks[1].title = "two (later edit)" }

        let early = try both(removedOnA, editedOnB)
        #expect(early.subtasks.allSatisfy { $0.meta.isDeleted })
        let late = try both(removedOnA, editedLaterOnB)
        #expect(late.subtasks.first { $0.title == "two (later edit)" }?.meta.isDeleted == false)
        #expect(late.subtasks.first { $0.title == "one" }?.meta.isDeleted == true)
    }

    @Test func childMergeAPI() throws {
        let t1 = SyncFixture.hlc(1), t2 = SyncFixture.hlc(2)
        let id: Subtask.ID = SyncFixture.id(9, namespace: 0x5B)
        let a = Subtask(id: id, meta: EntityMeta(createdAt: t1, updatedAt: t2, fieldClocks: ["title": t1, "sortIndex": t1]),
                        title: "a", completedAt: SyncFixture.at(2))
        let b = Subtask(id: id, meta: EntityMeta(createdAt: t1, updatedAt: t2, fieldClocks: ["completedAt": t1, "sortIndex": t1]),
                        title: "b")
        let merged = try SyncMerge.merge(local: a, remote: b)
        #expect(merged.title == "b" && merged.completedAt == SyncFixture.at(2))
    }

    @Test func mismatchedIDsThrow() throws {
        var clock = HybridLogicalClock(node: 1)
        let a = try SyncFixture.task(SyncFixture.taskID(1), clock: &clock)
        let b = try SyncFixture.task(SyncFixture.taskID(2), clock: &clock)
        #expect(throws: SyncError.self) { try SyncMerge.merge(local: a, remote: b) }
    }

    // MARK: Databases

    @Test func settingsCreatedOnTwoDevicesMergeFieldByField() throws {
        var a = HybridLogicalClock(node: 1), b = HybridLogicalClock(node: 2)
        let draft = AppSettings(meta: Fixture.meta())
        let onA = try MutationStamper.stamp(old: nil, new: draft, clock: &a, now: SyncFixture.at(0))
        let onB = try MutationStamper.stamp(old: nil, new: draft, clock: &b, now: SyncFixture.at(10))
        var editedA = onA
        editedA.hourCycle = .h24
        editedA = try MutationStamper.stamp(old: onA, new: editedA, clock: &a, now: SyncFixture.at(20))
        var editedB = onB
        editedB.appearance = .dark
        editedB = try MutationStamper.stamp(old: onB, new: editedB, clock: &b, now: SyncFixture.at(30))
        let merged = try SyncMerge.merge(local: TabulaDatabase(settings: editedA), remote: TabulaDatabase(settings: editedB))
        #expect(merged.settings.hourCycle == .h24 && merged.settings.appearance == .dark)
        #expect(merged.settings.meta.createdAt == onA.meta.createdAt)
    }

    /// Stage 3 decision (default field clock = `createdAt`, settings singleton at `createdAt == .zero`):
    /// untouched defaults created later on another device — a fresh install, or an onboarding that keeps a
    /// default — never beat an earlier real edit. Under the old rule ("missing clock = `updatedAt`") device B's
    /// later onboarding put every settings field at B's time and erased A's 24 h / dark choices.
    @Test func untouchedSettingsDefaultsNeverBeatAnEarlierRealEdit() throws {
        var a = HybridLogicalClock(node: 0xA), b = HybridLogicalClock(node: 0xB), c = HybridLogicalClock(node: 0xC)
        var idsA = SequentialIDGenerator(namespace: 0x51), idsB = SequentialIDGenerator(namespace: 0x52)
        let onboardedA = OnboardingBuilder.makeInitialDatabase(
            answers: OnboardingAnswers(profile: .secondary, timetableName: "School", bellScheduleName: "Normal"),
            ids: &idsA, clock: &a, now: SyncFixture.at(0))
        var editedSettings = onboardedA.settings
        editedSettings.hourCycle = .h24
        editedSettings.appearance = .dark
        var dbA = onboardedA
        dbA.settings = try MutationStamper.stamp(old: onboardedA.settings, new: editedSettings, clock: &a,
                                                 now: SyncFixture.at(100))
        // Device B never synced; it onboards much later, keeping every default except the profile.
        let dbB = OnboardingBuilder.makeInitialDatabase(
            answers: OnboardingAnswers(profile: .university, timetableName: "Uni", bellScheduleName: "Normal"),
            ids: &idsB, clock: &b, now: SyncFixture.at(50_000))
        #expect(dbB.settings.meta.createdAt == .zero)
        #expect(Set(dbB.settings.meta.fieldClocks.keys) == ["profile", "onboardingCompletedAt", "activeTimetableID"])

        let merged = try SyncMerge.merge(local: dbA, remote: dbB)
        #expect(try merged.encoded() == SyncMerge.merge(local: dbB, remote: dbA).encoded())
        #expect(merged.settings.hourCycle == .h24 && merged.settings.appearance == .dark,
                "A's real edits survive B's later, untouched defaults")
        #expect(merged.settings.profile == .university, "B's later real choice wins")
        #expect(merged.settings.activeTimetableID == dbB.settings.activeTimetableID)
        #expect(merged.settings.meta.createdAt == .zero)

        // Device C: a fresh install that has not onboarded yet — its settings are exactly the untouched defaults.
        let freshC = try MutationStamper.stamp(old: nil, new: AppSettings(meta: Fixture.meta()), clock: &c,
                                               now: SyncFixture.at(90_000))
        #expect(freshC == .untouchedDefaults)
        let withC = try SyncMerge.merge(local: merged, remote: TabulaDatabase(settings: freshC))
        #expect(withC.settings == merged.settings, "untouched defaults change nothing, however late they were created")
    }

    @Test func databaseMergeUnionsEntitiesAndIsCanonical() throws {
        var a = Fixture.fullDatabase()
        var b = Fixture.fullDatabase()
        var clockA = HybridLogicalClock(node: 1), clockB = HybridLogicalClock(node: 2)
        let extra = try SyncFixture.task(SyncFixture.taskID(77), title: "Only on A", clock: &clockA, at: 5)
        a.tasks.append(extra)
        var lesson = b.lessons[0]
        lesson.room = "Moved"
        b.lessons[0] = try MutationStamper.stamp(old: a.lessons[0], new: lesson, clock: &clockB, now: SyncFixture.at(9))
        b.exams[0] = try MutationStamper.delete(b.exams[0], clock: &clockB, now: SyncFixture.at(10))
        var rng = TestRNG(seed: 5)
        b.reminderRules.shuffle(using: &rng)

        let ab = try SyncMerge.merge(local: a, remote: b)
        let ba = try SyncMerge.merge(local: b, remote: a)
        #expect(try ab.encoded() == ba.encoded())
        #expect(ab == ab.canonicalized())
        #expect(ab.tasks.contains { $0.id == extra.id })
        #expect(ab.lessons.first { $0.id == lesson.id }?.room == "Moved")
        #expect(ab.exams.first { $0.id == b.exams[0].id }?.isDeleted == true)
        #expect(try SyncMerge.merge(local: ab, remote: ab) == ab)
        #expect(try TabulaDatabase.decode(from: ab.encoded()) == ab)
        #expect(ab.validate().filter { $0.severity == .error }.isEmpty)
    }

    /// Unknown keys from a newer version merge with the field clocks that version wrote.
    @Test func unknownFieldsMergeByTheirClocks() throws {
        let base = Fixture.fullDatabase()
        let task = base.tasks[0]
        func withFuture(_ value: JSONValue, clock: HLCTimestamp, extraArray: JSONValue) -> TabulaDatabase {
            var db = base
            db.tasks[0].meta.fieldClocks["futureField"] = clock
            db.tasks[0].meta.updatedAt = max(db.tasks[0].meta.updatedAt, clock)
            db.unknownFields.setFields(EntityUnknownFields(fields: ["futureField": value]), for: .task, id: task.id.uuid)
            db.unknownFields.root["notes"] = extraArray
            return db
        }
        func note(_ id: String, _ body: String, _ clock: HLCTimestamp) throws -> JSONValue {
            .object(["id": .string(id), "body": .string(body), "meta": try JSONValue(encoding: EntityMeta.created(at: clock))])
        }
        let older = withFuture(.string("old"), clock: SyncFixture.hlc(1), extraArray: .array([
            try note("N1", "first", SyncFixture.hlc(1)), try note("N2", "only older", SyncFixture.hlc(1)),
        ]))
        let newer = withFuture(.string("new"), clock: SyncFixture.hlc(2), extraArray: .array([
            try note("N1", "first, edited", SyncFixture.hlc(3)),
        ]))
        let merged = try SyncMerge.merge(local: older, remote: newer)
        #expect(try merged.encoded() == SyncMerge.merge(local: newer, remote: older).encoded())
        #expect(merged.unknownFields.fields(of: merged.tasks.first { $0.id == task.id }!)?.fields["futureField"] == .string("new"))
        guard case .array(let notes)? = merged.unknownFields.root["notes"] else {
            Issue.record("unknown array lost")
            return
        }
        #expect(notes.compactMap { $0["body"]?.stringValue } == ["first, edited", "only older"])
    }
}
