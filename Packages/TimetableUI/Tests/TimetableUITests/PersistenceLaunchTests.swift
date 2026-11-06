import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 10 (WP1 finding, fixed in WP5): a launch without edits must not rewrite the store. A clean load counts as
// generation `PersistenceController.loadedGeneration` written; migrated or recovered loads still write on the first
// flush.

@Suite("PersistenceController launch generation")
struct PersistenceLaunchTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tabula-p10-launch-\(UUID().uuidString)")
    }

    @Test func cleanLoadThenFlushWritesNothing() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = FileRepository(directory: directory)
        let database = SampleScenarios.blank()
        try await seed.save(database)
        let before = try Data(contentsOf: seed.databaseURL)

        let controller = PersistenceController(repository: FileRepository(directory: directory))
        guard case .loaded(let loaded, _, false) = await controller.load() else {
            Issue.record("expected a writable load")
            return
        }
        #expect(await controller.lastSavedGeneration == PersistenceController.loadedGeneration)
        #expect(await controller.hasPendingChanges == false)
        // The flush on scene background / for sync with no edits: nothing is written, and it counts as on disk.
        #expect(await controller.save(loaded, generation: PersistenceController.loadedGeneration)
            == .skippedStale(generation: 0, lastSaved: 0))
        #expect(await controller.writeCount == 0)
        #expect(try Data(contentsOf: seed.databaseURL) == before)
        #expect(!FileManager.default.fileExists(atPath: seed.backupURL.path))   // no backup rotation either

        // The first edit is written as usual.
        var edited = loaded
        edited.timetables[0].name = "Edited"
        #expect(await controller.save(edited, generation: 1) == .saved(generation: 1))
        #expect(try await FileRepository(directory: directory).load().timetables[0].name == "Edited")
    }

    @Test func recoveredLoadIsWrittenOnTheFirstFlush() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let seed = FileRepository(directory: directory)
        let database = SampleScenarios.blank()
        try await seed.save(database)
        try await seed.save(database)   // rotates the first file into tabula.backup.json
        try Data("not json".utf8).write(to: seed.databaseURL)

        let controller = PersistenceController(repository: FileRepository(directory: directory))
        guard case .loaded(let loaded, _, _) = await controller.load() else {
            Issue.record("expected recovery from the backup")
            return
        }
        #expect(await controller.lastSavedGeneration == -1)
        #expect(await controller.save(loaded, generation: PersistenceController.loadedGeneration) == .saved(generation: 0))
        #expect(try await FileRepository(directory: directory).load() == database.canonicalized())
    }

    @Test func reportPolicy() {
        #expect(PersistenceController.isUnchangedOnDisk(LoadReport(source: .primary, fileSchemaVersion: 1)))
        #expect(!PersistenceController.isUnchangedOnDisk(LoadReport(source: .backup, fileSchemaVersion: 1)))
        #expect(!PersistenceController.isUnchangedOnDisk(LoadReport(source: .primary, fileSchemaVersion: 0, migrated: true)))
        #expect(!PersistenceController.isUnchangedOnDisk(LoadReport(source: .primary, fileSchemaVersion: 2, isReadOnly: true)))
        #expect(!PersistenceController.isUnchangedOnDisk(LoadReport(source: .primary, fileSchemaVersion: 1,
                                                                    events: [.discardedIncompleteWrite(fileName: "x")])))
    }

    @Test func inMemoryLoadKeepsTheOldBehaviour() async {
        let controller = PersistenceController(repository: InMemoryRepository(SampleScenarios.blank()))
        _ = await controller.load()
        #expect(await controller.lastSavedGeneration == -1)
    }
}
