import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 10 B11: the automatic-copies folder keeps the newest `keepPerLabel` archives per label.

@Suite("Backup folder pruning (Phase 10 B11)")
struct BackupFolderPruningTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("p10-b11-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func names(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    @Test func policyKeepsTheNewestPerLabelAndNeverTheProtectedName() {
        let names = [
            "20261101T080000Z-pre-restore.tabulabackup",
            "20261101T080000Z-pre-restore-2.tabulabackup",
            "20261101T080000Z-pre-restore-10.tabulabackup",
            "20261102T080000Z-pre-restore.tabulabackup",
            "20261103T080000Z-pre-restore.tabulabackup",
            "20261030T080000Z-pre-import.tabulabackup",
            "20261029T080000Z-pre-import.tabulabackup",
            "20261028T080000Z-pre-import.tabulabackup",
            "20261101T080000Z-pre-migration-group.tabulabackup",
            ".20261104T080000Z-pre-restore.tabulabackup.tmp",
            "20261101T080000Z-pre-restore-copy.tabulabackup",
            "notes.txt",
            "garbage-pre-restore.tabulabackup",
        ]
        // Newest first: 03, 02, 01-10, 01-2, 01 → keep 3 → delete 01-2 and 01.
        #expect(Set(BackupFolder.prunable(names: names, label: "pre-restore", keep: 3, protecting: "x"))
            == ["20261101T080000Z-pre-restore-2.tabulabackup", "20261101T080000Z-pre-restore.tabulabackup"])
        // The protected (oldest) name stays and counts as kept.
        #expect(Set(BackupFolder.prunable(names: names, label: "pre-restore", keep: 3,
                                          protecting: "20261101T080000Z-pre-restore.tabulabackup"))
            == ["20261101T080000Z-pre-restore-10.tabulabackup", "20261101T080000Z-pre-restore-2.tabulabackup"])
        #expect(BackupFolder.prunable(names: names, label: "pre-import", keep: 2, protecting: "x")
            == ["20261028T080000Z-pre-import.tabulabackup"])
        // A label that is a prefix of another label never touches it.
        #expect(BackupFolder.prunable(names: names, label: "pre-migration", keep: 1, protecting: "x").isEmpty)
        // keep < 1 still keeps one.
        #expect(BackupFolder.prunable(names: names, label: "pre-import", keep: 0, protecting: "x").count == 2)
    }

    @Test func writeKeepsTheNewestCopiesAndTheOneJustMade() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = SampleScenarios.blank()
        try Data("keep me".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        var written: [URL] = []
        for minute in 0..<8 {
            written.append(try BackupFolder.write(.make(from: database, createdAt: now + Double(minute * 60)),
                                                  label: "pre-restore", in: folder))
            let restores = BackupFolder.entries(in: folder).filter { $0.url.lastPathComponent.contains("pre-restore") }
            #expect(restores.count == min(minute + 1, BackupFolder.keepPerLabel))
            #expect(FileManager.default.fileExists(atPath: written.last!.path))
        }
        let imports = try (0..<2).map { minute in
            try BackupFolder.write(.make(from: database, createdAt: now + Double(minute * 60)), label: "pre-import", in: folder)
        }
        let restoreNames = Set(written.suffix(BackupFolder.keepPerLabel).map(\.lastPathComponent))
        #expect(try names(in: folder) == restoreNames.union(imports.map(\.lastPathComponent)).union(["notes.txt"]))

        // A copy stamped earlier than every kept one (clock moved back) is still kept; the oldest other one goes.
        let early = try BackupFolder.write(.make(from: database, createdAt: now - 3_600), label: "pre-restore", in: folder)
        let after = try names(in: folder)
        #expect(after.contains(early.lastPathComponent))
        #expect(after.filter { $0.contains("pre-restore") }.count == BackupFolder.keepPerLabel)
        #expect(!after.contains(written[3].lastPathComponent))
        #expect(after.contains(written[7].lastPathComponent))
        #expect(try BackupImport.read(contentsOf: early).1 == database.canonicalized())
    }

    @Test func sameSecondCopiesArePrunedByCounter() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = SampleScenarios.blank()
        let urls = try (0..<(BackupFolder.keepPerLabel + 2)).map { _ in
            try BackupFolder.write(.make(from: database, createdAt: now), label: "pre-import", in: folder)
        }
        let left = try names(in: folder)
        #expect(left == Set(urls.suffix(BackupFolder.keepPerLabel).map(\.lastPathComponent)))
    }
}
