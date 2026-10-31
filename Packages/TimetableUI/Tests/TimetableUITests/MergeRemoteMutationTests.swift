import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

@Suite("mergeRemote (Phase 6 S1)")
struct MergeRemoteMutationTests {
    @Test func mergesIntoAnEmptyStoreAndReapplyingChangesNothing() throws {
        let remote = SampleScenarios.secondary().database
        let batch = CloudRecordBatch(try remote.cloudRecords())
        var clock = HybridLogicalClock(node: 0xC1)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let once = try DatabaseMutation.mergeRemote(batch.database).apply(to: DatabaseMutation.emptyBase, clock: &clock, now: now)
        #expect(once == remote.canonicalized())
        #expect(clock.last > remote.latestTimestamp)   // later local edits sort after the received data
        let twice = try DatabaseMutation.mergeRemote(batch.database).apply(to: once, clock: &clock, now: now)
        #expect(twice == once)
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: once) == .main)
    }
}
