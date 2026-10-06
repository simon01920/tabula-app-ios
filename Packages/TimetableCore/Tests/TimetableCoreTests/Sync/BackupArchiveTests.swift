import Foundation
import Testing
@testable import TimetableCore

@Suite("TabulaSHA256")
struct TabulaSHA256Tests {
    /// FIPS 180-4 / NIST CSRC example vectors.
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
        ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
    ])
    func nistVectors(message: String, digest: String) {
        #expect(TabulaSHA256.hexDigest(Data(message.utf8)) == digest)
    }

    @Test func oneMillionA() {
        #expect(TabulaSHA256.hexDigest(Data(repeating: UInt8(ascii: "a"), count: 1_000_000))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    /// Lengths around the padding boundaries (55/56/63/64 bytes) are self-consistent and distinct.
    @Test func paddingBoundaries() {
        let digests = (50...70).map { TabulaSHA256.hexDigest(Data(repeating: 0x61, count: $0)) }
        #expect(Set(digests).count == digests.count)
        #expect(digests.allSatisfy { $0.count == 64 })
        #expect(TabulaSHA256.digest(Data(repeating: 0x61, count: 64)).count == 32)
    }
}

@Suite("BackupArchive")
struct BackupArchiveTests {
    @Test func roundTripWithManifest() throws {
        var db = Fixture.fullDatabase()
        var clock = HybridLogicalClock(node: 1)
        db.exams[0] = try MutationStamper.delete(db.exams[0], clock: &clock, now: Fixture.now)
        let archive = try BackupArchive.make(from: db, createdAt: Fixture.now)
        let data = try archive.encoded()
        #expect(String(decoding: data.prefix(14), as: UTF8.self) == "TABULA-BACKUP\n")

        let decoded = try BackupArchive.decode(from: data)
        #expect(decoded == archive)
        #expect(decoded.manifest.schemaVersion == 1 && decoded.manifest.createdAt == Fixture.now)
        #expect(decoded.manifest.sha256 == TabulaSHA256.hexDigest(decoded.databaseData))
        #expect(decoded.manifest.entityCounts["exam"] == db.exams.count - 1)
        #expect(decoded.manifest.entityCounts["lesson"] == db.lessons.count)
        #expect(decoded.manifest.entityCounts["settings"] == 1)
        #expect(try decoded.database() == db.canonicalized())
    }

    @Test func checksumMismatchIsRejected() throws {
        let data = try BackupArchive.make(from: Fixture.fullDatabase(), createdAt: Fixture.now).encoded()
        var tampered = data
        let index = tampered.count - 40
        tampered[index] = tampered[index] == UInt8(ascii: "a") ? UInt8(ascii: "b") : UInt8(ascii: "a")
        do {
            _ = try BackupArchive.decode(from: tampered)
            Issue.record("tampered archive accepted")
        } catch BackupArchiveError.checksumMismatch(let expected, let actual) {
            #expect(expected != actual)
        }
        #expect(throws: BackupArchiveError.self) { try BackupArchive.decode(from: data.dropLast(10)) }
        #expect(throws: BackupArchiveError.notABackup) { try BackupArchive.decode(from: Data("hello\n{}\n{}".utf8)) }
        #expect(throws: BackupArchiveError.notABackup) { try BackupArchive.decode(from: Data()) }
        #expect(throws: BackupArchiveError.self) { try BackupArchive.decode(from: Data("TABULA-BACKUP\n{bad}\n{}".utf8)) }
    }

    @Test func truncatedDatabaseIsAByteCountMismatch() throws {
        let data = try BackupArchive.make(from: Fixture.fullDatabase(), createdAt: Fixture.now).encoded()
        do {
            _ = try BackupArchive.decode(from: data.dropLast(3))
            Issue.record("truncated archive accepted")
        } catch BackupArchiveError.byteCountMismatch(let expected, let actual) {
            #expect(expected == actual + 3)
        }
    }

    @Test func newerDatabaseInArchiveNeedsAnUpdate() throws {
        var db = Fixture.fullDatabase()
        db.schemaVersion = 2
        let archive = try BackupArchive.decode(from: BackupArchive.make(from: db, createdAt: Fixture.now).encoded())
        #expect(throws: BackupArchiveError.newerSchema(2)) { try archive.database() }
    }

    @Test func exportFromRepository() async throws {
        let repository = InMemoryRepository(Fixture.fullDatabase())
        let archive = try await repository.exportBackup(createdAt: Fixture.now)
        #expect(try archive.database() == Fixture.fullDatabase().canonicalized())
    }

    /// "Replace" restores exactly the backup's content and still wins after syncing with a device whose
    /// clocks are newer than the backup's; "merge" keeps newer data.
    @Test func restoreModes() throws {
        var device = HybridLogicalClock(node: 1)
        let backup = Fixture.fullDatabase()
        // Since the backup: a lesson edited, a task deleted, a new exam added.
        var current = backup
        var lesson = current.lessons[0]
        lesson.room = "Changed later"
        current.lessons[0] = try MutationStamper.stamp(old: current.lessons[0], new: lesson, clock: &device, now: SyncFixture.at(10))
        current.tasks[1] = try MutationStamper.delete(current.tasks[1], clock: &device, now: SyncFixture.at(20))
        let newExam = try MutationStamper.stamp(old: nil, new: Exam(id: SyncFixture.id(500), meta: Fixture.meta(), title: "New",
                                                                    date: Fixture.date("2026-12-01")),
                                                clock: &device, now: SyncFixture.at(30))
        current.exams.append(newExam)

        let merged = try BackupRestore.apply(backup, to: current, mode: .merge, clock: &device, now: SyncFixture.at(40))
        #expect(merged.lessons.first { $0.id == lesson.id }?.room == "Changed later")
        #expect(merged.tasks.first { $0.id == backup.tasks[1].id }?.isDeleted == true)
        #expect(merged.exams.contains { $0.id == newExam.id })

        let replaced = try BackupRestore.apply(backup, to: current, mode: .replace, clock: &device, now: SyncFixture.at(50))
        #expect(replaced.lessons.first { $0.id == lesson.id }?.room == backup.lessons[0].room)
        #expect(replaced.tasks.first { $0.id == backup.tasks[1].id }?.isDeleted == false)
        #expect(replaced.exams.first { $0.id == newExam.id }?.isDeleted == true)

        // Another device still has the pre-restore state: after syncing, the restore wins everywhere.
        let synced = try SyncMerge.merge(local: current, remote: replaced)
        #expect(synced.lessons.first { $0.id == lesson.id }?.room == backup.lessons[0].room)
        #expect(synced.tasks.first { $0.id == backup.tasks[1].id }?.isDeleted == false)
        #expect(synced.exams.first { $0.id == newExam.id }?.isDeleted == true)
        func live(_ db: TabulaDatabase) throws -> Data {
            var copy = db
            copy.exams.removeAll(where: \.isDeleted)
            return try JSONEncoder().encode(copy.exams.map(\.title).sorted())
        }
        #expect(try live(synced) == live(backup))
    }
}
