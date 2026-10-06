import Foundation
import Testing
@testable import TimetableCore

@Suite("MutationStamper")
struct MutationStamperTests {
    private let id = SyncFixture.taskID(1)

    @Test func creationStampsEntityAndChildren() throws {
        var clock = HybridLogicalClock(node: 1)
        let task = try SyncFixture.task(id, clock: &clock, at: 10, subtasks: [SyncFixture.subtask(1, "a")])
        let t = SyncFixture.hlc(10)
        #expect(task.meta == EntityMeta.created(at: t))
        #expect(task.subtasks[0].meta == EntityMeta.created(at: t))
        #expect(clock.last == t)
    }

    /// Only changed keys get the new clock; every other field keeps its previous clock (absent → `createdAt`),
    /// including absent (nil) fields. Canonical form: only keys written after creation are listed.
    @Test func onlyChangedKeysAreBumped() throws {
        var clock = HybridLogicalClock(node: 1)
        let created = try SyncFixture.task(id, clock: &clock, at: 0)
        var edited = created
        edited.title = "New title"
        let first = try MutationStamper.stamp(old: created, new: edited, clock: &clock, now: SyncFixture.at(100))
        let t0 = SyncFixture.hlc(0), t1 = SyncFixture.hlc(100)
        #expect(first.meta.updatedAt == t1 && first.meta.createdAt == t0)
        #expect(first.meta.clock(for: "title") == t1)
        for key in EntityFieldCatalog.fieldKeys(for: .task) where key != "title" {
            #expect(first.meta.clock(for: key) == t0, "\(key)")
        }
        #expect(first.meta.fieldClocks == ["title": t1], "canonical: only the written key; the rest is at createdAt")

        var second = first
        second.notes = "p. 12"
        second.priority = .urgent
        let stamped = try MutationStamper.stamp(old: first, new: second, clock: &clock, now: SyncFixture.at(200))
        let t2 = SyncFixture.hlc(200)
        #expect(stamped.meta.clock(for: "notes") == t2 && stamped.meta.clock(for: "priority") == t2)
        #expect(stamped.meta.clock(for: "title") == t1)
        #expect(stamped.meta.clock(for: "due") == t0)
        #expect(stamped.meta.fieldClocks == ["title": t1, "notes": t2, "priority": t2])
    }

    @Test func noChangeReturnsOldWithoutTicking() throws {
        var clock = HybridLogicalClock(node: 1)
        let created = try SyncFixture.task(id, clock: &clock, at: 0)
        var same = created
        same.meta = Fixture.meta()          // metadata in `new` is ignored
        let before = clock
        #expect(try MutationStamper.stamp(old: created, new: same, clock: &clock, now: SyncFixture.at(50)) == created)
        #expect(clock == before)
    }

    @Test func metadataOfNewIsIgnoredExceptTombstone() throws {
        var clock = HybridLogicalClock(node: 1)
        let created = try SyncFixture.task(id, clock: &clock, at: 0)
        var edited = created
        edited.title = "x"
        edited.meta = EntityMeta(createdAt: .zero, updatedAt: .zero, fieldClocks: ["bogus": .zero])
        let stamped = try MutationStamper.stamp(old: created, new: edited, clock: &clock, now: SyncFixture.at(5))
        #expect(stamped.meta.createdAt == created.meta.createdAt)
        #expect(stamped.meta.fieldClocks["bogus"] == nil)
    }

    @Test func idMismatchThrows() throws {
        var clock = HybridLogicalClock(node: 1)
        let a = try SyncFixture.task(id, clock: &clock)
        let b = try SyncFixture.task(SyncFixture.taskID(2), clock: &clock)
        #expect(throws: MutationStamper.StamperError.idMismatch) {
            try MutationStamper.stamp(old: a, new: b, clock: &clock, now: SyncFixture.at(1))
        }
    }

    @Test func childrenAreCreatedEditedAndTombstoned() throws {
        var clock = HybridLogicalClock(node: 1)
        let created = try SyncFixture.task(id, clock: &clock, at: 0,
                                           subtasks: [SyncFixture.subtask(1, "a"), SyncFixture.subtask(2, "b", sortIndex: 1)])
        // Add one, edit one, remove one.
        var edited = created
        edited.subtasks[0].completedAt = SyncFixture.at(1)
        edited.subtasks.remove(at: 1)
        edited.subtasks.append(SyncFixture.subtask(3, "c", sortIndex: 2))
        let stamped = try MutationStamper.stamp(old: created, new: edited, clock: &clock, now: SyncFixture.at(100))
        let t0 = SyncFixture.hlc(0), t1 = SyncFixture.hlc(100)
        #expect(stamped.meta.updatedAt == t1 && stamped.meta.clock(for: "subtasks") == t1)
        #expect(stamped.meta.clock(for: "attachments") == t0)
        let byTitle = Dictionary(uniqueKeysWithValues: stamped.subtasks.map { ($0.title, $0) })
        #expect(byTitle["a"]?.meta.clock(for: "completedAt") == t1)
        #expect(byTitle["a"]?.meta.clock(for: "title") == t0)
        #expect(byTitle["b"]?.meta.isDeleted == true && byTitle["b"]?.meta.updatedAt == t1)
        #expect(byTitle["c"]?.meta == EntityMeta.created(at: t1))

        // A UI that hides tombstones passes the array without "b": the tombstone is carried over, no change.
        var visible = stamped
        visible.subtasks.removeAll { $0.meta.isDeleted }
        let before = clock
        #expect(try MutationStamper.stamp(old: stamped, new: visible, clock: &clock, now: SyncFixture.at(200)) == stamped)
        #expect(clock == before)

        // Restoring a child.
        var restored = stamped
        if let index = restored.subtasks.firstIndex(where: { $0.title == "b" }) { restored.subtasks[index].meta.isDeleted = false }
        let back = try MutationStamper.stamp(old: stamped, new: restored, clock: &clock, now: SyncFixture.at(300))
        #expect(back.subtasks.first { $0.title == "b" }?.meta.isDeleted == false)
        #expect(back.subtasks.first { $0.title == "b" }?.meta.updatedAt == SyncFixture.hlc(300))
    }

    @Test func deleteAndRestore() throws {
        var clock = HybridLogicalClock(node: 1)
        let created = try SyncFixture.task(id, clock: &clock, at: 0)
        let deleted = try MutationStamper.delete(created, clock: &clock, now: SyncFixture.at(10))
        #expect(deleted.isDeleted && deleted.meta.updatedAt == SyncFixture.hlc(10))
        #expect(deleted.meta.clock(for: "title") == SyncFixture.hlc(0))
        let restored = try MutationStamper.restore(deleted, clock: &clock, now: SyncFixture.at(20))
        #expect(!restored.isDeleted && restored.meta.updatedAt == SyncFixture.hlc(20))
        #expect(restored.meta.clock(for: "title") == SyncFixture.hlc(0))
    }

    /// The issued timestamp is after everything in `old`, even if the clock lags (another device wrote it).
    @Test func timestampIsAlwaysAfterOld() throws {
        var remote = HybridLogicalClock(node: 9)
        let created = try SyncFixture.task(id, clock: &remote, at: 60_000)
        var edited = created
        edited.title = "late"

        var hlc = HybridLogicalClock(node: 1)                       // knows nothing of the remote write
        let viaHLC = try MutationStamper.stamp(old: created, new: edited, clock: &hlc, now: SyncFixture.at(0))
        #expect(viaHLC.meta.updatedAt > created.meta.updatedAt)
        #expect(hlc.last == viaHLC.meta.updatedAt, "the HLC learned the old clock via receive")

        var simple = TestClock(node: 2)
        let viaSimple = try MutationStamper.stamp(old: created, new: edited, clock: &simple, now: SyncFixture.at(0))
        #expect(viaSimple.meta.updatedAt > created.meta.updatedAt)
        #expect(viaSimple.meta.updatedAt.node == 2)
    }

    /// Regression for the implicit-clock trap: device B sets `notes` (absent on A) while A edits `title`.
    /// A's absent `notes` must stay at its old clock (`createdAt`), not move to A's new `updatedAt` and erase
    /// B's note (the reason the default field clock is `createdAt`, not `updatedAt`).
    @Test func absentFieldDoesNotOverwriteConcurrentRemoteSet() throws {
        var a = HybridLogicalClock(node: 1), b = HybridLogicalClock(node: 2)
        let base = try SyncFixture.task(id, clock: &a, at: 0)
        b.receive(base.meta.updatedAt, now: SyncFixture.at(0))
        var onB = base
        onB.notes = "from B"
        onB = try MutationStamper.stamp(old: base, new: onB, clock: &b, now: SyncFixture.at(100))
        var onA = base
        onA.title = "from A"
        onA = try MutationStamper.stamp(old: base, new: onA, clock: &a, now: SyncFixture.at(200))
        let merged = try SyncMerge.merge(local: onA, remote: onB)
        #expect(merged.notes == "from B")
        #expect(merged.title == "from A")
    }

    /// Unknown keys (from a newer version) need no hint: their clock is `createdAt` (or their explicit entry)
    /// and a mutation of other fields never moves it.
    @Test func unknownFieldClocksNeverMove() throws {
        var clock = HybridLogicalClock(node: 1)
        var created = try SyncFixture.task(id, clock: &clock, at: 0)
        created.meta.fieldClocks["laterField"] = SyncFixture.hlc(5)
        created.meta.updatedAt = SyncFixture.hlc(5)
        var edited = created
        edited.title = "t"
        let stamped = try MutationStamper.stamp(old: created, new: edited, clock: &clock, now: SyncFixture.at(9))
        #expect(stamped.meta.clock(for: "futureField") == SyncFixture.hlc(0))
        #expect(stamped.meta.clock(for: "laterField") == SyncFixture.hlc(5))
        #expect(stamped.meta.fieldClocks == ["laterField": SyncFixture.hlc(5), "title": SyncFixture.hlc(9)])
    }

    /// The fixed-ID settings singleton is created on top of the untouched defaults: `createdAt == .zero` and
    /// clocks only for fields that differ from the defaults; a draft equal to the defaults stays untouched.
    @Test func settingsAreCreatedOnTopOfUntouchedDefaults() throws {
        var clock = HybridLogicalClock(node: 7)
        let untouched = try MutationStamper.stamp(old: nil, new: AppSettings(meta: Fixture.meta()), clock: &clock,
                                                  now: SyncFixture.at(50))
        #expect(untouched == .untouchedDefaults)
        #expect(clock.last == .zero, "no change from the defaults, no tick")

        let draft = AppSettings(meta: Fixture.meta(), hourCycle: .h24, syncEnabled: true)
        let stamped = try MutationStamper.stamp(old: nil, new: draft, clock: &clock, now: SyncFixture.at(60))
        let t = SyncFixture.hlc(60, node: 7)
        #expect(stamped.meta == EntityMeta(createdAt: .zero, updatedAt: t, fieldClocks: ["hourCycle": t]))
        #expect(stamped.meta.clock(for: "appearance") == .zero)
    }

    @Test func worksForEveryEntityType() throws {
        var clock = HybridLogicalClock(node: 3)
        let db = Fixture.fullDatabase()
        var settings = db.settings
        settings.appearance = .light
        let stampedSettings = try MutationStamper.stamp(old: db.settings, new: settings, clock: &clock, now: SyncFixture.at(1))
        #expect(stampedSettings.meta.clock(for: "appearance") == stampedSettings.meta.updatedAt)
        #expect(stampedSettings.meta.clock(for: "profile") == db.settings.meta.clock(for: "profile"))
        #expect(stampedSettings.meta.fieldClocks == db.settings.meta.fieldClocks.merging(
            ["appearance": stampedSettings.meta.updatedAt]) { $1 })

        var bell = db.bellSchedules[0]
        bell.periods.removeLast()
        let stampedBell = try MutationStamper.stamp(old: db.bellSchedules[0], new: bell, clock: &clock, now: SyncFixture.at(2))
        #expect(stampedBell.meta.fieldClocks.keys.sorted() == ["periods"])
    }
}
