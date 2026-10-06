import Foundation
import Testing
@testable import TimetableCore

@Suite("InMemoryRepository")
struct InMemoryRepositoryTests {
    @Test func notFoundThenRoundTrip() async throws {
        let repository = InMemoryRepository()
        await #expect(throws: RepositoryError.notFound) { try await repository.load() }
        var db = Fixture.fullDatabase()
        db.tasks.reverse()
        try await repository.save(db)
        #expect(try await repository.load() == db.canonicalized())
        #expect(await repository.saveCount == 1)
    }

    @Test func rejectsOtherSchemaVersions() async throws {
        let repository = InMemoryRepository(Fixture.fullDatabase())
        var newer = Fixture.fullDatabase()
        newer.schemaVersion = 2
        await #expect(throws: RepositoryError.unsupportedSchemaVersion(2)) { try await repository.save(newer) }
        #expect(try await repository.load() == Fixture.fullDatabase().canonicalized())
    }
}

@Suite("FileRepository")
struct FileRepositoryTests {
    private static func edited(_ title: String) -> TabulaDatabase {
        var db = Fixture.fullDatabase()
        db.tasks[0].title = title
        return db
    }

    @Test func emptyDirectoryIsNotFound() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        let repository = FileRepository(directory: dir.url.appendingPathComponent("missing/nested"))
        await #expect(throws: RepositoryError.notFound) { try await repository.load() }
    }

    @Test func saveLoadRoundTripAndBackupRotation() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        let repository = FileRepository(directory: dir.url)
        let first = Self.edited("first"), second = Self.edited("second")
        try await repository.save(first)
        #expect(dir.read("tabula.json") == (try first.encoded()))
        #expect(!dir.exists("tabula.backup.json"), "no backup before there is a previous good file")
        try await repository.save(second)
        #expect(dir.read("tabula.json") == (try second.encoded()))
        #expect(dir.read("tabula.backup.json") == (try first.encoded()))
        #expect(!dir.exists(".tabula.json.tmp") && !dir.exists(".tabula.backup.json.tmp"))

        let fresh = FileRepository(directory: dir.url)
        #expect(try await fresh.load() == second.canonicalized())
        let report = try #require(await fresh.lastLoadReport)
        #expect(report == LoadReport(source: .primary, fileSchemaVersion: 1))
        #expect(await !fresh.isReadOnly)
    }

    @Test func unknownFieldsSurviveTheRepository() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        var tree = try JSONValue(encoding: Fixture.fullDatabase())
        tree = SyncJSONPatch.set(tree, [.key("lessons"), .index(0), .key("futureField")], .string("keep me"))
        tree = SyncJSONPatch.set(tree, [.key("diary")], .array([]))
        try dir.write(TabulaJSON.makeEncoder().encode(tree), to: "tabula.json")
        let repository = FileRepository(directory: dir.url)
        var db = try await repository.load()
        db.settings.syncEnabled = false
        try await repository.save(db)
        let saved = try TabulaJSON.makeDecoder().decode(JSONValue.self, from: #require(dir.read("tabula.json")))
        #expect(SyncJSONPatch.get(saved, [.key("lessons"), .index(0), .key("futureField")]) == .string("keep me"))
        #expect(saved["diary"] == .array([]))
        #expect(saved["settings"]?["syncEnabled"] == .bool(false))
    }

    // MARK: Atomicity

    /// A crash at each step of a save leaves the previous state loadable. Save steps: write temp (write 1),
    /// copy the good file to the backup temp (write 2), rename backup (replace 1), rename temp (replace 2).
    @Test(arguments: [(nil, 1), (nil, 2), (1, nil), (2, nil)] as [(Int?, Int?)])
    func interruptedSaveKeepsPreviousState(crashOnReplace: Int?, crashOnWrite: Int?) async throws {
        let dir = SyncTempDirectory("crash\(crashOnReplace ?? 0)\(crashOnWrite ?? 0)")
        defer { dir.remove() }
        let before = Self.edited("before"), after = Self.edited("after")
        try await FileRepository(directory: dir.url).save(Self.edited("older"))
        try await FileRepository(directory: dir.url).save(before)

        let crashing = FileRepository(directory: dir.url,
                                      fileSystem: SyncCrashingFileSystem(crashOnReplace: crashOnReplace, crashOnWrite: crashOnWrite))
        _ = try await crashing.load()
        await #expect(throws: RepositoryError.self) { try await crashing.save(after) }

        // "Next launch".
        let relaunched = FileRepository(directory: dir.url)
        #expect(try await relaunched.load() == before.canonicalized())
        let report = try #require(await relaunched.lastLoadReport)
        #expect(report.source == .primary)
        #expect(!dir.exists(".tabula.json.tmp") && !dir.exists(".tabula.backup.json.tmp"))
        // The next save works normally.
        try await relaunched.save(after)
        #expect(try await FileRepository(directory: dir.url).load() == after.canonicalized())
    }

    @Test func leftoverTemporaryFileIsReportedAndDiscarded() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        try await FileRepository(directory: dir.url).save(Self.edited("good"))
        try dir.write(Data("{\"half".utf8), to: ".tabula.json.tmp")
        let repository = FileRepository(directory: dir.url)
        #expect(try await repository.load() == Self.edited("good").canonicalized())
        #expect(await repository.lastLoadReport?.events == [.discardedIncompleteWrite(fileName: ".tabula.json.tmp")])
        #expect(!dir.exists(".tabula.json.tmp"))
    }

    @Test func crashDuringTheVeryFirstSaveMeansNotFound() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        let crashing = FileRepository(directory: dir.url, fileSystem: SyncCrashingFileSystem(crashOnReplace: 1))
        await #expect(throws: RepositoryError.self) { try await crashing.save(Fixture.fullDatabase()) }
        await #expect(throws: RepositoryError.notFound) { try await FileRepository(directory: dir.url).load() }
    }

    // MARK: Corruption

    @Test(arguments: ["garbage", "", "{\"schemaVersion\":1,\"settings\":", "[1,2,3]", "{\"settings\":{}}",
                      "{\"schemaVersion\":1,\"settings\":{\"profile\":\"x\"}}"])
    func corruptPrimaryRecoversFromBackup(content: String) async throws {
        let dir = SyncTempDirectory("corrupt\(content.count)")
        defer { dir.remove() }
        let good = Self.edited("good")
        try await FileRepository(directory: dir.url).save(Self.edited("older"))
        try await FileRepository(directory: dir.url).save(good)       // backup = "older"
        try dir.write(Data(content.utf8), to: "tabula.json")

        let repository = FileRepository(directory: dir.url)
        let loaded = try await repository.load()
        #expect(loaded == Self.edited("older").canonicalized())
        let report = try #require(await repository.lastLoadReport)
        #expect(report.source == .backup)
        guard case .restoredFromBackup(let problem)? = report.events.first else {
            Issue.record("missing recovery event: \(report.events)")
            return
        }
        switch (content, problem) {
        case ("", .empty), ("garbage", .invalidJSON), ("{\"schemaVersion\":1,\"settings\":", .invalidJSON),
             ("[1,2,3]", .invalidJSON), ("{\"settings\":{}}", .missingSchemaVersion), (_, .decodingFailed): break
        default: Issue.record("unexpected reason \(problem) for \(content)")
        }
        #expect(report.events.contains(.quarantinedCorruptFile(fileName: "tabula.corrupt.json")))
        #expect(dir.read("tabula.corrupt.json") == Data(content.utf8))
        // The backup was written back as the database: the next launch is clean.
        let next = FileRepository(directory: dir.url)
        #expect(try await next.load() == loaded)
        #expect(await next.lastLoadReport?.events == [])
    }

    @Test func missingPrimaryWithBackupRecovers() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        try await FileRepository(directory: dir.url).save(Self.edited("one"))
        try await FileRepository(directory: dir.url).save(Self.edited("two"))
        try FileManager.default.removeItem(at: dir.file("tabula.json"))
        let repository = FileRepository(directory: dir.url)
        #expect(try await repository.load() == Self.edited("one").canonicalized())
        #expect(await repository.lastLoadReport?.events == [.restoredFromBackup(primaryProblem: .missing)])
    }

    @Test func bothCorruptIsATypedErrorAndTouchesNothing() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        try dir.write(Data("nope".utf8), to: "tabula.json")
        try dir.write(Data().self, to: "tabula.backup.json")
        let repository = FileRepository(directory: dir.url)
        do {
            _ = try await repository.load()
            Issue.record("load must not succeed")
        } catch let RepositoryError.unrecoverable(primary, backup) {
            if case .invalidJSON = primary {} else { Issue.record("primary reason \(primary)") }
            #expect(backup == .empty)
        }
        #expect(dir.read("tabula.json") == Data("nope".utf8))
        #expect(dir.read("tabula.backup.json") == Data())

        // Corrupt primary, no backup.
        try FileManager.default.removeItem(at: dir.file("tabula.backup.json"))
        await #expect(throws: RepositoryError.self) { try await FileRepository(directory: dir.url).load() }
    }

    /// Saving over a corrupt file without loading first keeps it for diagnostics and never rotates it into
    /// the backup.
    @Test func saveOverCorruptPrimaryKeepsBackup() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        try await FileRepository(directory: dir.url).save(Self.edited("a"))
        try await FileRepository(directory: dir.url).save(Self.edited("b"))   // backup = a
        try dir.write(Data("broken".utf8), to: "tabula.json")
        try await FileRepository(directory: dir.url).save(Self.edited("c"))
        #expect(dir.read("tabula.backup.json") == (try Self.edited("a").encoded()))
        #expect(dir.read("tabula.corrupt.json") == Data("broken".utf8))
        #expect(try await FileRepository(directory: dir.url).load() == Self.edited("c").canonicalized())
    }

    // MARK: Schema versions

    @Test func newerSchemaOpensReadOnlyAndIsNeverOverwritten() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        var newer = Fixture.fullDatabase()
        newer.schemaVersion = 2
        let bytes = try newer.encoded()
        try dir.write(bytes, to: "tabula.json")

        let repository = FileRepository(directory: dir.url)
        let loaded = try await repository.load()
        #expect(loaded.schemaVersion == 2 && loaded.tasks.count == newer.tasks.count)
        #expect(await repository.isReadOnly)
        #expect(await repository.lastLoadReport == LoadReport(source: .primary, fileSchemaVersion: 2, isReadOnly: true))
        await #expect(throws: RepositoryError.readOnly(fileSchemaVersion: 2)) { try await repository.save(Fixture.fullDatabase()) }
        #expect(dir.read("tabula.json") == bytes)

        // Saving without loading first is refused too.
        await #expect(throws: RepositoryError.readOnly(fileSchemaVersion: 2)) {
            try await FileRepository(directory: dir.url).save(Fixture.fullDatabase())
        }
        #expect(dir.read("tabula.json") == bytes)
        #expect(!dir.exists("tabula.backup.json"))
    }

    @Test func newerUnreadableSchemaIsATypedError() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        var tree = try JSONValue(encoding: Fixture.fullDatabase())
        tree = SyncJSONPatch.set(tree, [.key("schemaVersion")], .integer(3))
        tree = SyncJSONPatch.set(tree, [.key("settings"), .key("hourCycle")], .string("h36"))   // closed enum grew
        let bytes = try TabulaJSON.makeEncoder().encode(tree)
        try dir.write(bytes, to: "tabula.json")
        let repository = FileRepository(directory: dir.url)
        do {
            _ = try await repository.load()
            Issue.record("must not load")
        } catch let RepositoryError.newerSchemaUnreadable(version, _) {
            #expect(version == 3)
        }
        #expect(await repository.isReadOnly)
        #expect(dir.read("tabula.json") == bytes)
    }

    @Test func saveRejectsNonCurrentSchemaVersion() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        var old = Fixture.fullDatabase()
        old.schemaVersion = 0
        await #expect(throws: RepositoryError.unsupportedSchemaVersion(0)) { try await FileRepository(directory: dir.url).save(old) }
    }

    // MARK: Migrations

    /// A fake "version 0" schema: tasks were called `homework`, `syncEnabled` was `iCloud`.
    static let fakeChain = MigrationChain(targetVersion: 1, migrations: [
        SchemaMigration(from: 0) { root in
            guard case .object(var object) = root else { return root }
            object["tasks"] = object.removeValue(forKey: "homework")
            if case .object(var settings)? = object["settings"] {
                settings["syncEnabled"] = settings.removeValue(forKey: "iCloud")
                object["settings"] = .object(settings)
            }
            return .object(object)
        },
    ])

    static func versionZeroFile(of db: TabulaDatabase) throws -> Data {
        guard case .object(var object) = try JSONValue(encoding: db) else { throw SyncError.malformedRecord("root") }
        object["schemaVersion"] = .integer(0)
        object["homework"] = object.removeValue(forKey: "tasks")
        if case .object(var settings)? = object["settings"] {
            settings["iCloud"] = settings.removeValue(forKey: "syncEnabled")
            object["settings"] = .object(settings)
        }
        return try TabulaJSON.makeEncoder().encode(JSONValue.object(object))
    }

    @Test func migrationChainUpgradesOlderFiles() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        var db = Fixture.fullDatabase()
        db.settings.syncEnabled = false
        let v0 = try Self.versionZeroFile(of: db)
        try dir.write(v0, to: "tabula.json")

        let repository = FileRepository(directory: dir.url, migrations: Self.fakeChain)
        #expect(try await repository.load() == db.canonicalized())
        #expect(await repository.lastLoadReport == LoadReport(source: .primary, fileSchemaVersion: 0, migrated: true))
        #expect(dir.read("tabula.premigration-v0.json") == v0)
        try await repository.save(try await repository.load())
        #expect(dir.read("tabula.json") == (try db.encoded()))

        // The standard chain cannot read version 0 and has no backup to fall back to.
        let other = SyncTempDirectory("v0standard")
        defer { other.remove() }
        try other.write(v0, to: "tabula.json")
        do {
            _ = try await FileRepository(directory: other.url).load()
            Issue.record("must not load")
        } catch let RepositoryError.unrecoverable(primary, backup) {
            if case .migrationFailed(0, _) = primary {} else { Issue.record("reason \(primary)") }
            #expect(backup == .missing)
        }
    }

    @Test func migrationChainMechanics() throws {
        let v1 = try JSONValue(encoding: Fixture.fullDatabase())
        #expect(try MigrationChain.standard.migrate(v1) == v1, "version 1 is the identity")
        #expect(MigrationChain.standard.canMigrate(from: 1) && !MigrationChain.standard.canMigrate(from: 0))
        #expect(Self.fakeChain.canMigrate(from: 0) && !Self.fakeChain.canMigrate(from: 2))
        #expect(throws: MigrationError.noMigration(fromVersion: 0)) {
            try MigrationChain.standard.migrate(SyncJSONPatch.set(v1, [.key("schemaVersion")], .integer(0)))
        }
        #expect(throws: MigrationError.newerThanTarget(version: 2, target: 1)) {
            try MigrationChain.standard.migrate(SyncJSONPatch.set(v1, [.key("schemaVersion")], .integer(2)))
        }
        #expect(throws: MigrationError.missingSchemaVersion) { try MigrationChain.standard.migrate(.array([])) }
        let failing = MigrationChain(targetVersion: 1, migrations: [SchemaMigration(from: 0) { _ in .null }])
        #expect(throws: MigrationError.self) {
            try failing.migrate(SyncJSONPatch.set(v1, [.key("schemaVersion")], .integer(0)))
        }
        let migrated = try Self.fakeChain.migrate(TabulaJSON.makeDecoder().decode(JSONValue.self,
                                                                                    from: Self.versionZeroFile(of: Fixture.fullDatabase())))
        #expect(MigrationChain.schemaVersion(of: migrated) == 1)
        #expect(try migrated.decoded(as: TabulaDatabase.self) == Fixture.fullDatabase().canonicalized())
    }
}
