import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 10 B11 + QA fix (decision P10-6): the automatic-copies folder always keeps the newest `keepPerLabel` archives
// per label, and deletes an older one only once it is more than 30 days older than the write.

@Suite("Backup folder pruning (Phase 10 B11, P10-6)")
struct BackupFolderPruningTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private let day: TimeInterval = 24 * 60 * 60

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

    /// A UTC instant, e.g. `utc("2026-12-02T08:00:00Z")`.
    private func utc(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    private let sample = [
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

    @Test func oldCopiesBeyondTheNewestAreDeletedAndNeverTheProtectedName() throws {
        // Two months later every sample is older than 30 days: only the "beyond the newest" rule decides.
        let later = try utc("2027-01-15T08:00:00Z")
        // Newest first: 03, 02, 01-10, 01-2, 01 → keep 3 → delete 01-2 and 01.
        #expect(Set(BackupFolder.prunable(names: sample, label: "pre-restore", keep: 3, protecting: "x", now: later))
            == ["20261101T080000Z-pre-restore-2.tabulabackup", "20261101T080000Z-pre-restore.tabulabackup"])
        // The protected (oldest) name stays and counts as kept.
        #expect(Set(BackupFolder.prunable(names: sample, label: "pre-restore", keep: 3,
                                          protecting: "20261101T080000Z-pre-restore.tabulabackup", now: later))
            == ["20261101T080000Z-pre-restore-10.tabulabackup", "20261101T080000Z-pre-restore-2.tabulabackup"])
        #expect(BackupFolder.prunable(names: sample, label: "pre-import", keep: 2, protecting: "x", now: later)
            == ["20261028T080000Z-pre-import.tabulabackup"])
        // A label that is a prefix of another label never touches it.
        #expect(BackupFolder.prunable(names: sample, label: "pre-migration", keep: 1, protecting: "x", now: later).isEmpty)
        // keep < 1 still keeps one.
        #expect(BackupFolder.prunable(names: sample, label: "pre-import", keep: 0, protecting: "x", now: later).count == 2)
    }

    @Test func copiesYoungerThan30DaysAreKeptEvenBeyondTheNewest() throws {
        // Within 30 days of every stamp: nothing goes, however many copies there are.
        let soon = try utc("2026-11-15T08:00:00Z")
        #expect(BackupFolder.prunable(names: sample, label: "pre-restore", keep: 1, protecting: "x", now: soon).isEmpty)
        #expect(BackupFolder.prunable(names: sample, label: "pre-import", keep: 1, protecting: "x", now: soon).isEmpty)
        // Exactly 30 days after 11-02 08:00: 11-02 is not older than 30 days yet (kept); the 11-01 ones are.
        let cutoff = try utc("2026-12-02T08:00:00Z")
        #expect(Set(BackupFolder.prunable(names: sample, label: "pre-restore", keep: 1, protecting: "x", now: cutoff))
            == ["20261101T080000Z-pre-restore-10.tabulabackup", "20261101T080000Z-pre-restore-2.tabulabackup",
                "20261101T080000Z-pre-restore.tabulabackup"])
        // A shorter age is honoured too (the policy is pure; the default is 30 days).
        #expect(BackupFolder.prunable(names: sample, label: "pre-import", keep: 1, protecting: "x", now: soon,
                                      minimumAge: 17 * day)
            == ["20261028T080000Z-pre-import.tabulabackup"])
        #expect(BackupFolder.minimumAge == 30 * day)
    }

    /// The QA scenario: Replace writes a pre-restore copy of the original data; five more restores of the same label
    /// the same week must not delete it (the alert promised it is in Automatic copies). A restore 31 days later prunes.
    @Test func thePreRestoreCopySurvivesABurstOfRestoresAndIsPrunedAfter30Days() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = SampleScenarios.blank()
        try Data("keep me".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        var written: [URL] = []
        for minute in 0..<8 {
            written.append(try BackupFolder.write(.make(from: database, createdAt: now + Double(minute * 60)),
                                                  label: "pre-restore", in: folder))
            let restores = BackupFolder.entries(in: folder).filter { $0.url.lastPathComponent.contains("pre-restore") }
            #expect(restores.count == minute + 1)              // nothing is 30 days old yet: every copy stays
            #expect(FileManager.default.fileExists(atPath: written.last!.path))
        }
        #expect(FileManager.default.fileExists(atPath: written[0].path))   // the original data's copy is still there
        let imports = try (0..<2).map { minute in
            try BackupFolder.write(.make(from: database, createdAt: now + Double(minute * 60)), label: "pre-import", in: folder)
        }
        #expect(try names(in: folder)
                == Set(written.map(\.lastPathComponent)).union(imports.map(\.lastPathComponent)).union(["notes.txt"]))

        // 31 days later: the new copy + the 4 newest stay; the 4 older ones (all > 30 days old) go. Other labels and
        // other files are untouched.
        let late = now + 31 * day
        let next = try BackupFolder.write(.make(from: database, createdAt: late), label: "pre-restore", in: folder)
        let restoreNames = Set(written.suffix(BackupFolder.keepPerLabel - 1).map(\.lastPathComponent))
            .union([next.lastPathComponent])
        #expect(try names(in: folder) == restoreNames.union(imports.map(\.lastPathComponent)).union(["notes.txt"]))
    }

    @Test func aCopyStampedEarlierIsStillProtectedAndTheWriteTimeComesFromNow() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = SampleScenarios.blank()
        let written = try (0..<6).map { minute in
            try BackupFolder.write(.make(from: database, createdAt: now + Double(minute * 60)), label: "pre-restore",
                                   in: folder)
        }
        #expect(try names(in: folder).count == 6)
        // A copy stamped earlier than every other one (clock moved back), written with `now` 31 days later: it is kept
        // and counts as one of the newest; the 4 newest others stay, the oldest other one (> 30 days) goes.
        let early = try BackupFolder.write(.make(from: database, createdAt: now - 3_600), label: "pre-restore",
                                           in: folder, now: now + 31 * day)
        let after = try names(in: folder)
        #expect(after.contains(early.lastPathComponent))
        #expect(after.count == BackupFolder.keepPerLabel)
        #expect(!after.contains(written[0].lastPathComponent))
        #expect(!after.contains(written[1].lastPathComponent))
        #expect(after.isSuperset(of: written.suffix(4).map(\.lastPathComponent)))
        #expect(try BackupImport.read(contentsOf: early).1 == database.canonicalized())
    }

    @Test func sameSecondCopiesArePrunedByCounterOnceOldEnough() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let database = SampleScenarios.blank()
        let urls = try (0..<(BackupFolder.keepPerLabel + 2)).map { _ in
            try BackupFolder.write(.make(from: database, createdAt: now), label: "pre-import", in: folder)
        }
        #expect(try names(in: folder) == Set(urls.map(\.lastPathComponent)))   // all younger than 30 days
        let late = try BackupFolder.write(.make(from: database, createdAt: now + 31 * day), label: "pre-import",
                                          in: folder)
        let left = try names(in: folder)
        #expect(left == Set(urls.suffix(BackupFolder.keepPerLabel - 1).map(\.lastPathComponent))
            .union([late.lastPathComponent]))
    }
}
