import Foundation
import Testing
@testable import TimetableCore

@Suite("HybridLogicalClock")
struct HybridLogicalClockTests {
    private let base = TabulaJSON.milliseconds(from: Fixture.now)

    private func ts(_ offset: Int64, _ logical: UInt32, node: UInt64 = 7) -> HLCTimestamp {
        HLCTimestamp(physicalMillis: base + offset, logical: logical, node: node)
    }

    @Test func tickFollowsWallClockAndCountsWithinAMillisecond() {
        var clock = HybridLogicalClock(node: 7)
        #expect(clock.tick(now: SyncFixture.at(0)) == ts(0, 0))
        #expect(clock.tick(now: SyncFixture.at(0)) == ts(0, 1))
        #expect(clock.tick(now: SyncFixture.at(0)) == ts(0, 2))
        #expect(clock.tick(now: SyncFixture.at(5)) == ts(5, 0))
        #expect(clock.last == ts(5, 0))
    }

    @Test func monotonicWhenWallClockJumpsBackwards() {
        var clock = HybridLogicalClock(node: 7)
        #expect(clock.tick(now: SyncFixture.at(10_000)) == ts(10_000, 0))
        // The user sets the device clock back one hour.
        #expect(clock.tick(now: SyncFixture.at(-3_590_000)) == ts(10_000, 1))
        #expect(clock.tick(now: SyncFixture.at(-3_589_000)) == ts(10_000, 2))
        #expect(clock.tick(now: SyncFixture.at(10_001)) == ts(10_001, 0))
    }

    /// Property: strictly increasing over 20 000 random wall-clock readings with jumps both ways, and
    /// interleaved receives of random remote timestamps.
    @Test func strictlyIncreasingUnderRandomWallClock() {
        var rng = TestRNG(seed: 0x41C)
        var clock = HybridLogicalClock(node: 3)
        var wall: Int64 = 0
        var previous = HLCTimestamp.zero
        var budget = FailureBudget()
        for _ in 0..<20_000 {
            switch UInt8.random(in: 0...9, using: &rng) {
            case 0: wall -= Int64.random(in: 1...86_400_000, using: &rng)      // backwards jump
            case 1: wall += Int64.random(in: 1...86_400_000, using: &rng)      // forwards jump
            case 2, 3: break                                                   // same millisecond
            default: wall += Int64.random(in: 0...5, using: &rng)
            }
            let now = SyncFixture.at(wall)
            let next: HLCTimestamp
            if UInt8.random(in: 0...4, using: &rng) == 0 {
                let remote = HLCTimestamp(physicalMillis: base + wall + Int64.random(in: -5_000...5_000, using: &rng),
                                          logical: UInt32.random(in: 0...3, using: &rng),
                                          node: UInt64.random(in: 0...10, using: &rng))
                next = clock.receive(remote, now: now)
                if next <= remote { budget.record("receive \(next) not after remote \(remote)") }
            } else {
                next = clock.tick(now: now)
            }
            if next <= previous { budget.record("\(next) not after \(previous)") }
            if next.node != 3 { budget.record("foreign node in \(next)") }
            previous = next
        }
        #expect(budget.count == 0)
    }

    @Test func receiveTakesTheMaximumAndIncrements() {
        var clock = HybridLogicalClock(node: 7, last: ts(100, 4))
        // Remote ahead of both wall clock and local clock: continue after the remote.
        #expect(clock.receive(ts(500, 9, node: 2), now: SyncFixture.at(200)) == ts(500, 10))
        // Remote behind: like a local tick.
        #expect(clock.receive(ts(50, 99, node: 2), now: SyncFixture.at(200)) == ts(500, 11))
        // Same physical as local and remote: max logical + 1.
        #expect(clock.receive(ts(500, 30, node: 2), now: SyncFixture.at(0)) == ts(500, 31))
        // Wall clock ahead of everything: reset the counter.
        #expect(clock.receive(ts(600, 3, node: 2), now: SyncFixture.at(700)) == ts(700, 0))
    }

    @Test func logicalOverflowCarriesIntoPhysical() {
        var clock = HybridLogicalClock(node: 7, last: ts(100, .max))
        #expect(clock.tick(now: SyncFixture.at(100)) == ts(101, 0))
        #expect(clock.tick(now: SyncFixture.at(50)) == ts(101, 1))

        var receiver = HybridLogicalClock(node: 7, last: ts(100, 5))
        let remote = ts(100, .max, node: 9)
        let received = receiver.receive(remote, now: SyncFixture.at(0))
        #expect(received == ts(101, 0))
        #expect(received > remote)

        var both = HybridLogicalClock(node: 7, last: ts(100, .max))
        #expect(both.receive(ts(100, .max, node: 1), now: SyncFixture.at(100)) == ts(101, 0))
    }

    @Test func nodeComesFromInjectedRandomnessAndIsNeverZero() {
        struct ZeroThenFive: RandomNumberGenerator {
            var values: [UInt64] = [0, 0, 5]
            mutating func next() -> UInt64 { values.isEmpty ? 1 : values.removeFirst() }
        }
        var zeros = ZeroThenFive()
        #expect(HybridLogicalClock(randomNodeUsing: &zeros).node == 5)
        var a = TestRNG(seed: 11), b = TestRNG(seed: 11)
        #expect(HybridLogicalClock(randomNodeUsing: &a).node == HybridLogicalClock(randomNodeUsing: &b).node)
    }

    @Test func wallClockIsClampedToTheEncodableRange() {
        var clock = HybridLogicalClock(node: 1)
        // Clamped to 0 ms; still strictly after the fresh clock's `.zero`.
        #expect(clock.tick(now: Date(timeIntervalSince1970: -1_000)) == HLCTimestamp(physicalMillis: 0, logical: 1, node: 1))
        #expect(clock.tick(now: Date(timeIntervalSince1970: 1e15)).physicalMillis == HLCTimestamp.maxPhysicalMillis)
        #expect(HybridLogicalClock.driftMillis(of: ts(1_500, 0), now: SyncFixture.at(1_000)) == 500)
    }

    @Test func codableAndUsableAsTimestampClock() throws {
        var clock = HybridLogicalClock(node: 0xABC, last: ts(1, 2))
        #expect(try Fixture.roundTrip(clock) == clock)
        func issue(_ clock: inout some TimestampClock) -> HLCTimestamp { clock.tick(now: SyncFixture.at(0)) }
        #expect(issue(&clock) == ts(1, 3, node: 0xABC))
    }

    /// Resuming after the database's latest timestamp keeps a restarted app monotonic.
    @Test func resumesAfterDatabaseLatestTimestamp() throws {
        var db = Fixture.fullDatabase()
        db.tasks[0].meta.fieldClocks["notes"] = ts(9_000, 4, node: 99)
        db.tasks[0].meta.updatedAt = ts(9_000, 5, node: 99)
        db.tasks[0].subtasks[0].meta.updatedAt = ts(9_500, 0, node: 98)
        #expect(db.latestTimestamp == ts(9_500, 0, node: 98))
        var clock = HybridLogicalClock(node: 7, last: db.latestTimestamp)
        #expect(clock.tick(now: SyncFixture.at(0)) > db.latestTimestamp)
    }
}
