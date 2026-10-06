import Foundation
import Testing
@testable import TimetableCore

/// One simulated device: its state, its HLC and its (possibly misbehaving) wall clock.
private struct SyncSimDevice<State> {
    var state: State
    var clock: HybridLogicalClock
    var wall: Int64
    var ids: SequentialIDGenerator

    var now: Date { SyncFixture.at(wall) }

    /// Mostly small steps forward; sometimes the same millisecond, sometimes a jump backwards.
    mutating func advance(_ rng: inout TestRNG) {
        switch UInt8.random(in: 0...9, using: &rng) {
        case 0: wall -= Int64.random(in: 1...5_000, using: &rng)
        case 1, 2: break
        default: wall += Int64.random(in: 1...400, using: &rng)
        }
    }

    /// Merges a received state and lets the clock observe it.
    mutating func receive(_ other: State, merge: (State, State) throws -> State,
                          latest: (State) -> HLCTimestamp) rethrows {
        let current = now
        state = try merge(state, other)
        clock.receive(latest(other), now: current)
    }
}

extension SyncSimDevice where State == TaskItem {
    /// A random local edit through the stamper.
    mutating func edit(rng: inout TestRNG) throws {
        let current = now
        let old = state
        let edited = SyncSim.randomEdit(of: old, ids: &ids, now: current, rng: &rng)
        state = try MutationStamper.stamp(old: old, new: edited, clock: &clock, now: current)
    }

    mutating func receive(_ other: TaskItem) throws {
        try receive(other, merge: { try SyncMerge.merge(local: $0, remote: $1) }, latest: SyncSim.latest)
    }
}

extension SyncSimDevice where State == TabulaDatabase {
    mutating func receive(_ other: TabulaDatabase) throws {
        try receive(other, merge: { try SyncMerge.merge(local: $0, remote: $1) }, latest: { $0.latestTimestamp })
    }
}

private enum SyncSim {
    static let taskID = SyncFixture.taskID(1)

    static func latest(_ task: TaskItem) -> HLCTimestamp {
        var latest = SyncJSON.latest(in: task.meta)
        for child in task.subtasks { latest = max(latest, SyncJSON.latest(in: child.meta)) }
        for child in task.attachments { latest = max(latest, SyncJSON.latest(in: child.meta)) }
        return latest
    }

    /// A random local edit of a task, as a UI would produce it (UIs may or may not pass tombstoned children).
    static func randomEdit(of task: TaskItem, ids: inout SequentialIDGenerator, now: Date,
                           rng: inout TestRNG) -> TaskItem {
        var copy = task
        switch UInt8.random(in: 0...9, using: &rng) {
        case 0...3:
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                switch UInt8.random(in: 0...5, using: &rng) {
                case 0: copy.title = ["a", "b", "c", "d"].randomElement(using: &rng)!
                case 1: copy.notes = [nil, "x", "y"].randomElement(using: &rng)!
                case 2: copy.priority = [.low, .normal, .high, .urgent].randomElement(using: &rng)!
                case 3: copy.completedAt = Bool.random(using: &rng) ? now : nil
                case 4: copy.kind = [.homework, .todo, .assignment].randomElement(using: &rng)!
                default: copy.due = Bool.random(using: &rng) ? .date(Fixture.date("2026-10-0\(Int.random(in: 1...9, using: &rng))")) : nil
                }
            }
        case 4:
            copy.subtasks.append(Subtask(id: ids.next(), meta: Fixture.meta(), title: "new",
                                         sortIndex: Int.random(in: 0...3, using: &rng)))
        case 5:
            let live = copy.subtasks.indices.filter { !copy.subtasks[$0].meta.isDeleted }
            if let index = live.randomElement(using: &rng) {
                switch UInt8.random(in: 0...2, using: &rng) {
                case 0: copy.subtasks[index].title += "+"
                case 1: copy.subtasks[index].completedAt = copy.subtasks[index].completedAt == nil ? now : nil
                default: copy.subtasks[index].sortIndex = Int.random(in: 0...3, using: &rng)
                }
            }
        case 6:
            let live = copy.subtasks.indices.filter { !copy.subtasks[$0].meta.isDeleted }
            if let index = live.randomElement(using: &rng) { copy.subtasks.remove(at: index) }
            if Bool.random(using: &rng) { copy.subtasks.removeAll { $0.meta.isDeleted } }
        case 7:
            if Bool.random(using: &rng) {
                copy.attachments.append(AttachmentRef(id: ids.next(), meta: Fixture.meta(), kind: .link,
                                                      url: "https://example.com/\(Int.random(in: 0...9, using: &rng))"))
            } else if !copy.attachments.isEmpty {
                copy.attachments.remove(at: Int.random(in: 0..<copy.attachments.count, using: &rng))
            }
        default:
            copy.meta.isDeleted.toggle()          // delete or restore
        }
        return copy
    }

    /// Three devices editing one task with random interleaved merges; returns their final states.
    static func taskHistory(seed: UInt64) throws -> [TaskItem] {
        var rng = TestRNG(seed: seed)
        var creator = HybridLogicalClock(node: 1)
        let base = try SyncFixture.task(taskID, title: "base", clock: &creator, at: 0,
                                        subtasks: [SyncFixture.subtask(1, "s1"), SyncFixture.subtask(2, "s2", sortIndex: 1)])
        var devices = (0..<3).map { index in
            SyncSimDevice(state: base, clock: HybridLogicalClock(randomNodeUsing: &rng, last: base.meta.updatedAt),
                          wall: Int64.random(in: -1_000...1_000, using: &rng),
                          ids: SequentialIDGenerator(namespace: 0xD0 + UInt32(index)))
        }
        for _ in 0..<Int.random(in: 4...18, using: &rng) {
            let index = Int.random(in: 0..<devices.count, using: &rng)
            var device = devices[index]
            device.advance(&rng)
            if UInt8.random(in: 0...3, using: &rng) == 0 {
                let other = devices[(index + Int.random(in: 1..<devices.count, using: &rng)) % devices.count].state
                try device.receive(other)
            } else {
                try device.edit(rng: &rng)
            }
            devices[index] = device
        }
        return devices.map(\.state)
    }
}

@Suite("SyncMerge — properties")
struct SyncMergePropertyTests {
    private func json(_ task: TaskItem) -> String { SyncFixture.json(task) }

    /// ≥ 500 seeded random histories: the merge is commutative, associative, idempotent and absorbing.
    @Test func taskMergeIsASemilattice() throws {
        var budget = FailureBudget()
        var deletedOutcomes = 0, childTombstones = 0
        for seed in UInt64(1)...600 {
            let states = try SyncSim.taskHistory(seed: seed)
            let (a, b, c) = (states[0], states[1], states[2])
            let ab = try SyncMerge.merge(local: a, remote: b)
            if json(ab) != json(try SyncMerge.merge(local: b, remote: a)) { budget.record("seed \(seed): not commutative") }
            let left = try SyncMerge.merge(local: ab, remote: c)
            let right = try SyncMerge.merge(local: a, remote: SyncMerge.merge(local: b, remote: c))
            if json(left) != json(right) { budget.record("seed \(seed): not associative") }
            if json(try SyncMerge.merge(local: a, remote: a)) != json(a) { budget.record("seed \(seed): not idempotent") }
            if json(try SyncMerge.merge(local: a, remote: ab)) != json(ab) { budget.record("seed \(seed): not absorbing") }
            if left.isDeleted { deletedOutcomes += 1 }
            childTombstones += left.subtasks.filter(\.meta.isDeleted).count
        }
        #expect(budget.count == 0)
        // The generator really exercised tombstones (sanity check of the property test itself).
        #expect(deletedOutcomes > 20 && childTombstones > 50, "deleted \(deletedOutcomes), child tombstones \(childTombstones)")
    }

    /// Two devices edit independently and exchange **snapshots in random order** (stale, duplicated,
    /// out of order). After a final exchange both are identical, and equal to the merge of every snapshot
    /// ever taken in any order (states only grow in the lattice).
    @Test func twoReplicasConverge() throws {
        var budget = FailureBudget()
        for seed in UInt64(1_000)..<UInt64(1_150) {
            var rng = TestRNG(seed: seed)
            var creator = HybridLogicalClock(node: 1)
            let base = try SyncFixture.task(SyncSim.taskID, clock: &creator, at: 0, subtasks: [SyncFixture.subtask(1, "s")])
            var devices = (0..<2).map { index in
                SyncSimDevice(state: base, clock: HybridLogicalClock(node: UInt64(10 + index), last: base.meta.updatedAt),
                              wall: 0, ids: SequentialIDGenerator(namespace: 0xE0 + UInt32(index)))
            }
            var snapshots: [[TaskItem]] = [[base], [base]]
            for _ in 0..<Int.random(in: 5...25, using: &rng) {
                let index = Int.random(in: 0...1, using: &rng)
                var device = devices[index]
                device.advance(&rng)
                if Bool.random(using: &rng), let delivered = snapshots[1 - index].randomElement(using: &rng) {
                    try device.receive(delivered)
                } else {
                    try device.edit(rng: &rng)
                }
                devices[index] = device
                snapshots[index].append(device.state)
            }
            let finalA = try SyncMerge.merge(local: devices[0].state, remote: devices[1].state)
            let finalB = try SyncMerge.merge(local: devices[1].state, remote: devices[0].state)
            if json(finalA) != json(finalB) { budget.record("seed \(seed): replicas diverge") }
            var all = (snapshots[0] + snapshots[1]).shuffled(using: &rng)
            var folded = all.removeFirst()
            for snapshot in all { folded = try SyncMerge.merge(local: folded, remote: snapshot) }
            if json(folded) != json(finalA) { budget.record("seed \(seed): fold of all snapshots differs") }
        }
        #expect(budget.count == 0)
    }

    /// Whole databases (every entity type, settings, children): commutative, associative, idempotent, and
    /// convergent under random exchange among three devices.
    @Test func databaseMergeIsASemilatticeAndConverges() throws {
        var budget = FailureBudget()
        for seed in UInt64(5_000)..<UInt64(5_040) {
            var rng = TestRNG(seed: seed)
            let base = Fixture.fullDatabase()
            var devices = (0..<3).map { index in
                SyncSimDevice(state: base, clock: HybridLogicalClock(node: UInt64(20 + index), last: base.latestTimestamp),
                              wall: Int64(index * 7), ids: SequentialIDGenerator(namespace: 0xF0 + UInt32(index)))
            }
            for _ in 0..<Int.random(in: 6...20, using: &rng) {
                let index = Int.random(in: 0..<3, using: &rng)
                var device = devices[index]
                device.advance(&rng)
                if UInt8.random(in: 0...3, using: &rng) == 0 {
                    try device.receive(devices[(index + Int.random(in: 1...2, using: &rng)) % 3].state)
                } else {
                    try Self.randomDatabaseEdit(&device, rng: &rng)
                }
                devices[index] = device
            }
            let (a, b, c) = (devices[0].state, devices[1].state, devices[2].state)
            let ab = try SyncMerge.merge(local: a, remote: b)
            if try ab.encoded() != SyncMerge.merge(local: b, remote: a).encoded() { budget.record("seed \(seed): not commutative") }
            let left = try SyncMerge.merge(local: ab, remote: c)
            let right = try SyncMerge.merge(local: a, remote: SyncMerge.merge(local: b, remote: c))
            if try left.encoded() != right.encoded() { budget.record("seed \(seed): not associative") }
            if try SyncMerge.merge(local: a, remote: a).encoded() != a.canonicalized().encoded() {
                budget.record("seed \(seed): not idempotent")
            }
            // Gossip until everyone has everything: all three end identical.
            var states = [a, b, c]
            for (i, j) in [(0, 1), (1, 2), (2, 0), (0, 1)] {
                states[i] = try SyncMerge.merge(local: states[i], remote: states[j])
                states[j] = try SyncMerge.merge(local: states[j], remote: states[i])
            }
            let encodedStates = try states.map { try $0.encoded() }
            if Set(encodedStates).count != 1 { budget.record("seed \(seed): gossip did not converge") }
            if try encodedStates[0] != left.encoded() { budget.record("seed \(seed): gossip result differs from merge") }
        }
        #expect(budget.count == 0)
    }

    private static func randomDatabaseEdit(_ device: inout SyncSimDevice<TabulaDatabase>, rng: inout TestRNG) throws {
        let now = device.now
        var db = device.state
        switch UInt8.random(in: 0...5, using: &rng) {
        case 0:
            var settings = db.settings
            settings.hourCycle = [.auto, .h12, .h24].randomElement(using: &rng)!
            if Bool.random(using: &rng) { settings.appearance = [.auto, .light, .dark].randomElement(using: &rng)! }
            db.settings = try MutationStamper.stamp(old: db.settings, new: settings, clock: &device.clock, now: now)
        case 1, 2:
            let index = Int.random(in: 0..<db.lessons.count, using: &rng)
            var lesson = db.lessons[index]
            switch UInt8.random(in: 0...3, using: &rng) {
            case 0: lesson.room = ["101", "Lab", nil].randomElement(using: &rng)!
            case 1: lesson.bringList = Bool.random(using: &rng) ? ["Book"] : []
            case 2: lesson.teacher = ["T1", "T2"].randomElement(using: &rng)!
            default: lesson.meta.isDeleted.toggle()
            }
            db.lessons[index] = try MutationStamper.stamp(old: db.lessons[index], new: lesson, clock: &device.clock, now: now)
        case 3:
            let index = Int.random(in: 0..<db.tasks.count, using: &rng)
            var ids = device.ids
            let edited = SyncSim.randomEdit(of: db.tasks[index], ids: &ids, now: now, rng: &rng)
            device.ids = ids
            db.tasks[index] = try MutationStamper.stamp(old: db.tasks[index], new: edited, clock: &device.clock, now: now)
        case 4:
            let draft = TaskItem(id: device.ids.next(), meta: Fixture.meta(), title: "new task")
            db.tasks.append(try MutationStamper.stamp(old: nil, new: draft, clock: &device.clock, now: now))
        default:
            let index = Int.random(in: 0..<db.exams.count, using: &rng)
            var exam = db.exams[index]
            exam.topics.append("topic")
            db.exams[index] = try MutationStamper.stamp(old: db.exams[index], new: exam, clock: &device.clock, now: now)
        }
        device.state = db
    }
}
