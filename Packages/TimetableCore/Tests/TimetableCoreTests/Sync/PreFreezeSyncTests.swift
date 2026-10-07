import Foundation
import Testing
@testable import TimetableCore

/// Pre-freeze QA fixes in the sync/storage layer.
@Suite("Sync: duplicate IDs and durable rename")
struct PreFreezeSyncTests {
    /// Two copies of one task ID in one replica (invalid data) used to collapse to whichever came first in the
    /// array; now they are folded with the merge join, so array order never decides.
    @Test func duplicateIDsAreFoldedIndependentlyOfArrayOrder() throws {
        var clock = HybridLogicalClock(node: 0xA)
        let older = try SyncFixture.task(SyncFixture.taskID(1), title: "Old", clock: &clock, at: 0)
        var edited = older
        edited.title = "New"
        edited.notes = "only on the newer copy"
        let newer = try MutationStamper.stamp(old: older, new: edited, clock: &clock, now: SyncFixture.at(1_000))
        let other = try SyncFixture.task(SyncFixture.taskID(2), title: "Other", clock: &clock, at: 2_000)

        let oldFirst = TabulaDatabase(settings: .untouchedDefaults, tasks: [older, newer])
        let newFirst = TabulaDatabase(settings: .untouchedDefaults, tasks: [newer, older])
        let remote = TabulaDatabase(settings: .untouchedDefaults, tasks: [other])

        let results = try [
            SyncMerge.merge(local: oldFirst, remote: remote), SyncMerge.merge(local: newFirst, remote: remote),
            SyncMerge.merge(local: remote, remote: oldFirst), SyncMerge.merge(local: remote, remote: newFirst),
        ].map { try $0.encoded() }
        #expect(Set(results).count == 1)
        let merged = try SyncMerge.merge(local: oldFirst, remote: remote)
        #expect(merged.tasks.map(\.id) == [SyncFixture.taskID(1), SyncFixture.taskID(2)])
        let task = try #require(merged.tasks.first)
        #expect(task.title == "New" && task.notes == "only on the newer copy")
        #expect(!merged.validate().contains { $0.code == .duplicateID })
        #expect(try SyncMerge.merge(local: oldFirst, remote: newFirst).tasks == [task])
    }

    @Test func replaceItemSyncsTheDirectoryAndNeverThrowsForIt() throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        let fs = FoundationFileSystem()
        try fs.write(Data("old".utf8), to: dir.file("tabula.json"))
        try fs.write(Data("new".utf8), to: dir.file("tabula.json.tmp"))
        try fs.replaceItem(at: dir.file("tabula.json"), withItemAt: dir.file("tabula.json.tmp"))
        #expect(dir.read("tabula.json") == Data("new".utf8))
        #expect(!dir.exists("tabula.json.tmp"))
        // The directory fsync itself: succeeds on a real directory (ext4/tmpfs on Linux, APFS on Darwin) and is
        // a silent `false`, never a throw or trap, when the directory cannot be opened.
        #expect(FoundationFileSystem.syncDirectory(containing: dir.file("tabula.json")))
        #expect(!FoundationFileSystem.syncDirectory(containing: dir.url.appendingPathComponent("missing/x.json")))
        // A failed rename still reports the rename error (the fsync is only attempted after success).
        #expect(throws: RepositoryFileSystemError.self) {
            try fs.replaceItem(at: dir.file("tabula.json"), withItemAt: dir.file("does-not-exist.tmp"))
        }
    }
}
