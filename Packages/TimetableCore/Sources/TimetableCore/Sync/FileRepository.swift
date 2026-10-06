import Foundation

/// Classifies and decodes stored database bytes (database file, backup file, backup archive).
enum DatabaseFileDecoder {
    enum Outcome {
        /// Current version, decoded.
        case current(TabulaDatabase)
        /// Older version, migrated with the chain and decoded.
        case migrated(TabulaDatabase, fromVersion: Int)
        /// Newer version; decoded if this version can read it.
        case newer(version: Int, database: TabulaDatabase?, detail: String)
        /// Unusable.
        case corrupt(CorruptionReason)
    }

    static func decode(_ data: Data, migrations: MigrationChain) -> Outcome {
        guard !data.isEmpty else { return .corrupt(.empty) }
        let target = migrations.targetVersion
        // Fast path: the common case is a current-version file.
        var typedError = ""
        do {
            let database = try TabulaDatabase.decode(from: data)
            if database.schemaVersion == target { return .current(database) }
            if database.schemaVersion > target {
                return .newer(version: database.schemaVersion, database: database, detail: "")
            }
        } catch {
            typedError = String(describing: error)
        }
        // Classify through the raw JSON tree (older version, newer unreadable version, or corruption).
        let root: JSONValue
        do {
            root = try TabulaJSON.makeDecoder().decode(JSONValue.self, from: data)
        } catch {
            return .corrupt(.invalidJSON(String(describing: error)))
        }
        guard case .object = root else { return .corrupt(.invalidJSON("root is not an object")) }
        guard let version = MigrationChain.schemaVersion(of: root) else { return .corrupt(.missingSchemaVersion) }
        if version > target { return .newer(version: version, database: nil, detail: typedError) }
        if version == target { return .corrupt(.decodingFailed(typedError)) }
        do {
            let migrated = try migrations.migrate(root)
            return .migrated(try migrated.decoded(as: TabulaDatabase.self), fromVersion: version)
        } catch {
            return .corrupt(.migrationFailed(fromVersion: version, detail: String(describing: error)))
        }
    }
}

/// The on-disk repository: one JSON file in a directory the app injects (the App Group container).
///
/// Files (with the default base name `tabula`):
/// - `tabula.json` — the database (canonical compact JSON);
/// - `tabula.backup.json` — the **last good** database: the previous `tabula.json`, rotated in on every save
///   but only from a file known to be good (never a corrupt or newer-version file);
/// - `.tabula.json.tmp`, `.tabula.backup.json.tmp` — temporary files of an in-progress save;
/// - `tabula.corrupt.json` — the last corrupt database file, kept for diagnostics after recovery;
/// - `tabula.premigration-v<N>.json` — a copy taken before the first migration from version N.
///
/// **Atomic save:** write the new bytes to the temporary file in the same directory and `fsync`, hard-link
/// (or copy) the current good file to the backup's temporary name and rename it onto the backup, then
/// `rename(2)` the temporary file onto `tabula.json`. Files are never modified in place. A crash at any point leaves `tabula.json` either completely old or completely new.
///
/// **Load:** the database file, else (missing/corrupt) the backup — which is then written back as the
/// database and reported as `RecoveryEvent.restoredFromBackup` — else a typed error (never an empty
/// database). An older file is migrated (`MigrationChain`); a newer file is opened **read-only** (`save`
/// throws `RepositoryError.readOnly`; the file is never overwritten).
///
/// Single writer: only the main app should save (extensions read snapshots). File protection and
/// cross-process coordination are the app's job.
public actor FileRepository: TabulaRepository {
    private enum PrimaryState: Equatable {
        case unknown
        case good
        case corrupt
        case missing
        case newer(Int)
    }

    /// The directory holding the files.
    public nonisolated let directory: URL
    /// Base name of the files (`tabula`).
    public nonisolated let baseName: String
    private let fileSystem: any RepositoryFileSystem
    private let migrations: MigrationChain
    private var primaryState: PrimaryState = .unknown
    /// What the last `load()` found (`nil` before the first load or after a failed one).
    public private(set) var lastLoadReport: LoadReport?

    /// Creates a repository for `directory`. `migrations.targetVersion` must be the current schema version.
    public init(directory: URL, baseName: String = "tabula",
                fileSystem: any RepositoryFileSystem = FoundationFileSystem(),
                migrations: MigrationChain = .standard) {
        precondition(migrations.targetVersion == TabulaDatabase.currentSchemaVersion,
                     "migration chain must end at the current schema version")
        self.directory = directory
        self.baseName = baseName
        self.fileSystem = fileSystem
        self.migrations = migrations
    }

    /// `tabula.json`.
    public nonisolated var databaseURL: URL { directory.appendingPathComponent("\(baseName).json") }
    /// `tabula.backup.json`.
    public nonisolated var backupURL: URL { directory.appendingPathComponent("\(baseName).backup.json") }
    /// `tabula.corrupt.json`.
    public nonisolated var quarantineURL: URL { directory.appendingPathComponent("\(baseName).corrupt.json") }
    /// `.tabula.json.tmp`.
    nonisolated var temporaryURL: URL { directory.appendingPathComponent(".\(baseName).json.tmp") }
    /// `.tabula.backup.json.tmp`.
    nonisolated var backupTemporaryURL: URL { directory.appendingPathComponent(".\(baseName).backup.json.tmp") }
    /// `tabula.premigration-v<N>.json`.
    public nonisolated func preMigrationURL(fromVersion version: Int) -> URL {
        directory.appendingPathComponent("\(baseName).premigration-v\(version).json")
    }

    /// `true` while the stored file is from a newer app version (after `load()` or a refused `save`).
    public var isReadOnly: Bool {
        if case .newer = primaryState { return true }
        return false
    }

    // MARK: - Load

    /// Loads the database (see type documentation). Details are in `lastLoadReport`.
    public func load() throws -> TabulaDatabase {
        lastLoadReport = nil
        var events: [RecoveryEvent] = []
        let (_, primaryOutcome) = read(databaseURL)

        switch primaryOutcome {
        case .current(let database):
            primaryState = .good
            discardTemporaryFiles(&events)
            lastLoadReport = LoadReport(source: .primary, fileSchemaVersion: database.schemaVersion, events: events)
            return database
        case let .migrated(database, version):
            primaryState = .good
            discardTemporaryFiles(&events)
            let copy = preMigrationURL(fromVersion: version)
            if !fileSystem.fileExists(at: copy) { try? fileSystem.copyItem(at: databaseURL, to: copy) }
            lastLoadReport = LoadReport(source: .primary, fileSchemaVersion: version, migrated: true, events: events)
            return database
        case let .newer(version, database, detail):
            primaryState = .newer(version)
            guard let database else {
                throw RepositoryError.newerSchemaUnreadable(fileSchemaVersion: version, detail: detail)
            }
            lastLoadReport = LoadReport(source: .primary, fileSchemaVersion: version, isReadOnly: true)
            return database
        case .corrupt(let problem):
            return try recoverFromBackup(primaryProblem: problem, primaryExists: problem != .missing, events: &events)
        }
    }

    private func recoverFromBackup(primaryProblem: CorruptionReason, primaryExists: Bool,
                                   events: inout [RecoveryEvent]) throws -> TabulaDatabase {
        let (backupData, backupOutcome) = read(backupURL)
        let database: TabulaDatabase
        let fileVersion: Int
        var migrated = false
        switch backupOutcome {
        case .current(let value):
            database = value
            fileVersion = value.schemaVersion
        case let .migrated(value, version):
            database = value
            fileVersion = version
            migrated = true
        case let .newer(version, value, detail):
            // A newer backup next to a broken database: show it read-only, touch nothing.
            primaryState = .newer(version)
            guard let value else {
                throw RepositoryError.newerSchemaUnreadable(fileSchemaVersion: version, detail: detail)
            }
            lastLoadReport = LoadReport(source: .backup, fileSchemaVersion: version, isReadOnly: true,
                                        events: [.restoredFromBackup(primaryProblem: primaryProblem)])
            return value
        case .corrupt(let backupProblem):
            discardTemporaryFiles(&events)
            primaryState = primaryExists ? .corrupt : .missing
            if primaryProblem == .missing && backupProblem == .missing { throw RepositoryError.notFound }
            throw RepositoryError.unrecoverable(primary: primaryProblem, backup: backupProblem)
        }

        discardTemporaryFiles(&events)
        if primaryExists {
            do {
                try fileSystem.replaceItem(at: quarantineURL, withItemAt: databaseURL)
                events.append(.quarantinedCorruptFile(fileName: quarantineURL.lastPathComponent))
            } catch {
                // Keeping the corrupt file is best effort; it is overwritten below either way.
            }
        }
        // Write the backup back as the database so the next launch is clean. The backup itself stays.
        if let backupData {
            do {
                try fileSystem.write(backupData, to: temporaryURL)
                try fileSystem.replaceItem(at: databaseURL, withItemAt: temporaryURL)
                primaryState = .good
            } catch {
                primaryState = .missing
            }
        }
        events.insert(.restoredFromBackup(primaryProblem: primaryProblem), at: 0)
        lastLoadReport = LoadReport(source: .backup, fileSchemaVersion: fileVersion, migrated: migrated, events: events)
        return database
    }

    private func read(_ url: URL) -> (Data?, DatabaseFileDecoder.Outcome) {
        let data: Data?
        do {
            data = try fileSystem.contents(of: url)
        } catch {
            return (nil, .corrupt(.unreadable(String(describing: error))))
        }
        guard let data else { return (nil, .corrupt(.missing)) }
        return (data, DatabaseFileDecoder.decode(data, migrations: migrations))
    }

    private func discardTemporaryFiles(_ events: inout [RecoveryEvent]) {
        for url in [temporaryURL, backupTemporaryURL] where fileSystem.fileExists(at: url) {
            try? fileSystem.removeItem(at: url)
            if url == temporaryURL { events.append(.discardedIncompleteWrite(fileName: url.lastPathComponent)) }
        }
    }

    // MARK: - Save

    /// Atomically replaces the stored database (see type documentation).
    public func save(_ database: TabulaDatabase) throws {
        guard database.schemaVersion == TabulaDatabase.currentSchemaVersion else {
            throw RepositoryError.unsupportedSchemaVersion(database.schemaVersion)
        }
        if primaryState == .unknown { inspectPrimary() }
        if case .newer(let version) = primaryState { throw RepositoryError.readOnly(fileSchemaVersion: version) }

        let data: Data
        do {
            data = try database.encoded()
        } catch {
            throw RepositoryError.writeFailed("encoding: \(error)")
        }
        do {
            try fileSystem.createDirectory(at: directory)
            try fileSystem.write(data, to: temporaryURL)
            switch primaryState {
            case .good:
                if fileSystem.fileExists(at: databaseURL) {
                    try fileSystem.linkItem(at: databaseURL, to: backupTemporaryURL)
                    try fileSystem.replaceItem(at: backupURL, withItemAt: backupTemporaryURL)
                }
            case .corrupt:
                if fileSystem.fileExists(at: databaseURL) {
                    try fileSystem.replaceItem(at: quarantineURL, withItemAt: databaseURL)
                }
            case .missing, .unknown, .newer:
                break
            }
            try fileSystem.replaceItem(at: databaseURL, withItemAt: temporaryURL)
        } catch {
            throw RepositoryError.writeFailed(String(describing: error))
        }
        primaryState = .good
    }

    /// Classifies the database file when `save` runs before any `load`.
    private func inspectPrimary() {
        switch read(databaseURL).1 {
        case .current, .migrated: primaryState = .good
        case .newer(let version, _, _): primaryState = .newer(version)
        case .corrupt(let problem): primaryState = problem == .missing ? .missing : .corrupt
        }
    }
}
