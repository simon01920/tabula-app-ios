import Foundation

/// Loads and saves the whole database. Implementations are actors (shared mutable state).
public protocol TabulaRepository: Sendable {
    /// The stored database. Throws `RepositoryError.notFound` when nothing has been saved yet (first
    /// launch → onboarding) and never returns an empty database in place of unreadable data.
    func load() async throws -> TabulaDatabase
    /// Replaces the stored database. Only databases of `TabulaDatabase.currentSchemaVersion` are accepted.
    func save(_ database: TabulaDatabase) async throws
}

/// Why a stored file could not be used.
public enum CorruptionReason: Hashable, Sendable {
    /// The file does not exist.
    case missing
    /// The file is empty.
    case empty
    /// The file could not be read (I/O error).
    case unreadable(String)
    /// The bytes are not valid JSON, or the root is not an object.
    case invalidJSON(String)
    /// The root object has no integer `schemaVersion`.
    case missingSchemaVersion
    /// No migration path from the file's version, or a migration step failed.
    case migrationFailed(fromVersion: Int, detail: String)
    /// Valid JSON of the current version that does not decode as a `TabulaDatabase`.
    case decodingFailed(String)
}

/// Errors of `TabulaRepository` implementations.
public enum RepositoryError: Error, Hashable, Sendable {
    /// Nothing stored yet (no database file and no backup).
    case notFound
    /// Neither the database nor its backup can be used. Nothing was modified; the files are left for support.
    case unrecoverable(primary: CorruptionReason, backup: CorruptionReason)
    /// The stored file was written by a newer app version; the repository is read-only until the app updates.
    case readOnly(fileSchemaVersion: Int)
    /// The stored file was written by a newer app version and cannot even be read by this version.
    case newerSchemaUnreadable(fileSchemaVersion: Int, detail: String)
    /// `save` was called with a database whose `schemaVersion` is not the current one.
    case unsupportedSchemaVersion(Int)
    /// Writing failed; the previously stored state is intact.
    case writeFailed(String)
}

/// Something the repository did to recover while loading, for the app to surface ("Your data was restored
/// from a backup"). The UI owns the user-facing text (like vocabulary display names, DOMAIN_MODEL §8).
public enum RecoveryEvent: Hashable, Sendable {
    /// The database file was missing or corrupt; its last good backup was loaded and written back as the
    /// database. Changes saved after that backup are lost.
    case restoredFromBackup(primaryProblem: CorruptionReason)
    /// The corrupt database file was kept under `fileName` for diagnostics.
    case quarantinedCorruptFile(fileName: String)
    /// A save had been interrupted (temporary file left behind); it was discarded and the previous state
    /// loaded. The interrupted change is lost.
    case discardedIncompleteWrite(fileName: String)
}

/// What `FileRepository.load()` found.
public struct LoadReport: Hashable, Sendable {
    /// Where the database came from.
    public enum Source: Hashable, Sendable { case primary, backup }

    /// The file the returned database was read from.
    public var source: Source
    /// Schema version found in the file (before migration).
    public var fileSchemaVersion: Int
    /// `true` when the file was migrated to the current version on load (written on the next save).
    public var migrated: Bool
    /// `true` when the file is from a newer app version: the data is shown, but `save` throws.
    public var isReadOnly: Bool
    /// Recovery steps taken, in order.
    public var events: [RecoveryEvent]

    /// Creates a report.
    public init(source: Source, fileSchemaVersion: Int, migrated: Bool = false, isReadOnly: Bool = false,
                events: [RecoveryEvent] = []) {
        self.source = source
        self.fileSchemaVersion = fileSchemaVersion
        self.migrated = migrated
        self.isReadOnly = isReadOnly
        self.events = events
    }
}

/// A repository in memory (tests, previews, the share-extension sandbox). Stores the canonical form.
public actor InMemoryRepository: TabulaRepository {
    private var stored: TabulaDatabase?
    /// Number of successful saves (for tests).
    public private(set) var saveCount = 0

    /// Creates a repository, optionally pre-filled.
    public init(_ database: TabulaDatabase? = nil) {
        stored = database?.canonicalized()
    }

    /// The stored database, or `RepositoryError.notFound`.
    public func load() throws -> TabulaDatabase {
        guard let stored else { throw RepositoryError.notFound }
        return stored
    }

    /// Stores `database` (canonicalised). Rejects other schema versions like `FileRepository`.
    public func save(_ database: TabulaDatabase) throws {
        guard database.schemaVersion == TabulaDatabase.currentSchemaVersion else {
            throw RepositoryError.unsupportedSchemaVersion(database.schemaVersion)
        }
        stored = database.canonicalized()
        saveCount += 1
    }
}
