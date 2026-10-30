import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let now = Date(timeIntervalSince1970: 1_793_000_000)

private func tempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("p6s2-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func load(_ directory: URL) async throws -> TabulaDatabase {
    try await FileRepository(directory: directory).load()
}

/// A fallback + group directory pair; the fallback holds `fallback` and one attachment folder.
private func makeStores(fallback: TabulaDatabase?, group: TabulaDatabase?) async throws -> (URL, URL) {
    let base = try tempDirectory()
    let fallbackDir = base.appendingPathComponent("Support/Tabula", isDirectory: true)
    let groupDir = base.appendingPathComponent("Group/Tabula", isDirectory: true)
    if let fallback { try await FileRepository(directory: fallbackDir).save(fallback) }
    if let group { try await FileRepository(directory: groupDir).save(group) }
    let attachment = FileAttachmentStore.root(forStoreDirectory: fallbackDir).appendingPathComponent("A1", isDirectory: true)
    try FileManager.default.createDirectory(at: attachment, withIntermediateDirectories: true)
    try Data("photo".utf8).write(to: attachment.appendingPathComponent("photo.jpg"))
    return (fallbackDir, groupDir)
}

@Suite("Stranded store migration (RISKS #47/#56)")
struct StrandedStoreMigrationTests {
    @Test func emptyGroupReceivesTheFallback() async throws {
        let data = SampleScenarios.secondary().database
        let (fallback, group) = try await makeStores(fallback: data, group: nil)
        let outcome = await StrandedStoreMigration.run(fallbackDirectory: fallback, groupDirectory: group, now: now)
        #expect(outcome == .movedIn)
        #expect(try await load(group) == data.canonicalized())
        #expect(BackupFolder.entries(in: BackupFolder.url(forStoreDirectory: group)).count == 1)
        let copied = FileAttachmentStore.root(forStoreDirectory: group).appendingPathComponent("A1/photo.jpg")
        #expect(try Data(contentsOf: copied) == Data("photo".utf8))
        #expect(FileManager.default.fileExists(atPath: fallback.appendingPathComponent("tabula.json").path))  // kept
    }

    @Test func nonEmptyGroupIsMergedNeverOverwritten() async throws {
        let fallbackData = SampleScenarios.secondary().database
        let groupData = SampleScenarios.university()
        let (fallback, group) = try await makeStores(fallback: fallbackData, group: groupData)
        let outcome = await StrandedStoreMigration.run(fallbackDirectory: fallback, groupDirectory: group, now: now)
        #expect(outcome == .merged)
        let merged = try await load(group)
        #expect(merged == (try SyncMerge.merge(local: groupData, remote: fallbackData)).canonicalized())
        #expect(Set(groupData.timetables.map(\.id)).isSubset(of: Set(merged.timetables.map(\.id))))
        #expect(Set(fallbackData.timetables.map(\.id)).isSubset(of: Set(merged.timetables.map(\.id))))
        #expect(BackupFolder.entries(in: BackupFolder.url(forStoreDirectory: group)).count == 2)
    }

    @Test func corruptFallbackChangesNothing() async throws {
        let groupData = SampleScenarios.university()
        let (fallback, group) = try await makeStores(fallback: nil, group: groupData)
        try Data("{not json".utf8).write(to: fallback.appendingPathComponent("tabula.json"))
        let outcome = await StrandedStoreMigration.run(fallbackDirectory: fallback, groupDirectory: group, now: now)
        guard case .skipped = outcome else { Issue.record("expected skipped, got \(outcome)"); return }
        #expect(try await load(group) == groupData.canonicalized())
        #expect(!FileManager.default.fileExists(atPath: fallback.appendingPathComponent(StrandedStoreMigration.markerName).path))
        #expect(!FileManager.default.fileExists(atPath: FileAttachmentStore.root(forStoreDirectory: group).path))
    }

    @Test func secondRunIsANoOp() async throws {
        let (fallback, group) = try await makeStores(fallback: SampleScenarios.secondary().database, group: nil)
        #expect(await StrandedStoreMigration.run(fallbackDirectory: fallback, groupDirectory: group, now: now) == .movedIn)
        let later = SampleScenarios.university()
        try await FileRepository(directory: group).save(later)  // the user carries on in the group store
        #expect(await StrandedStoreMigration.run(fallbackDirectory: fallback, groupDirectory: group, now: now) == .nothingToDo)
        #expect(try await load(group) == later.canonicalized())
        #expect(BackupFolder.entries(in: BackupFolder.url(forStoreDirectory: group)).count == 1)
    }

    @Test func noFallbackDatabaseIsNothingToDo() async throws {
        let (fallback, group) = try await makeStores(fallback: nil, group: nil)
        #expect(await StrandedStoreMigration.run(fallbackDirectory: fallback, groupDirectory: group, now: now) == .nothingToDo)
        #expect(!FileManager.default.fileExists(atPath: group.path))
    }
}

@Suite("Backup import, folder and restore")
struct BackupSupportTests {
    @Test func importRoundTripAndPlainProblems() throws {
        let data = SampleScenarios.secondary().database
        let bytes = try BackupArchive.make(from: data, createdAt: now).encoded()
        let (manifest, database) = try BackupImport.read(bytes)
        #expect(manifest.createdAt == now)
        #expect(database == data.canonicalized())

        #expect(throws: BackupImportProblem.notABackup) { try BackupImport.read(Data("hello".utf8)) }
        var damaged = bytes
        damaged[damaged.count - 2] ^= 0x01
        #expect(throws: BackupImportProblem.damaged) { try BackupImport.read(damaged) }
        #expect(throws: BackupImportProblem.damaged) { try BackupImport.read(bytes.dropLast(10)) }
        let newer = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":9")
        #expect(throws: BackupImportProblem.newerVersion) { try BackupImport.read(Data(newer.utf8)) }
        #expect(throws: BackupImportProblem.unreadableFile) {
            try BackupImport.read(contentsOf: URL(fileURLWithPath: "/nonexistent/x.tabulabackup"))
        }
    }

    @Test func folderNeverOverwritesAndListsNewestFirst() throws {
        let folder = try tempDirectory().appendingPathComponent("Backups", isDirectory: true)
        let database = SampleScenarios.blank()
        let first = try BackupFolder.write(.make(from: database, createdAt: now), label: "pre-restore", in: folder)
        let second = try BackupFolder.write(.make(from: database, createdAt: now), label: "pre-restore", in: folder)
        let third = try BackupFolder.write(.make(from: database, createdAt: now + 60), label: "pre-restore", in: folder)
        #expect(Set([first, second, third]).count == 3)
        let entries = BackupFolder.entries(in: folder)
        #expect(Set(entries.map(\.url.lastPathComponent)) == Set([first, second, third].map(\.lastPathComponent)))
        #expect(entries.first?.url.lastPathComponent == third.lastPathComponent)
        #expect(entries.first?.createdAt == now + 60)
        #expect(try BackupImport.read(contentsOf: first).1 == database.canonicalized())
    }

    @Test func restoreMutationReplacesAndMerges() throws {
        let current = SampleScenarios.secondary().database
        let backup = SampleScenarios.university()
        var clock = HybridLogicalClock(node: 0xB4C)
        clock.receive(current.latestTimestamp, now: now)
        let replaced = try DatabaseMutation.restore(backup, mode: .replace).apply(to: current, clock: &clock, now: now)
        #expect(Set(replaced.timetables.filter { !$0.isDeleted }.map(\.id)) == Set(backup.timetables.map(\.id)))
        #expect(clock.last >= backup.latestTimestamp)
        let merged = try DatabaseMutation.restore(backup, mode: .merge).apply(to: current, clock: &clock, now: now)
        #expect(Set(merged.timetables.filter { !$0.isDeleted }.map(\.id))
            == Set(current.timetables.map(\.id)).union(backup.timetables.map(\.id)))
    }
}
