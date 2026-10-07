import Foundation

/// A full backup: a manifest plus the database JSON, in one file.
///
/// File layout (UTF-8):
/// ```
/// TABULA-BACKUP\n
/// {"createdAt":…,"databaseByteCount":…,"entityCounts":{…},"format":"tabula.backup","formatVersion":1,"schemaVersion":1,"sha256":"…"}\n
/// <database JSON, pretty-printed, exactly databaseByteCount bytes>
/// ```
/// The manifest line is compact JSON (no raw newlines). `sha256` is the lowercase hex SHA-256 of the database
/// bytes; import verifies byte count and checksum before decoding anything. Attachment files are not part of
/// the archive (Phase 6/7 decision).
public struct BackupArchive: Hashable, Sendable {
    /// Archive metadata.
    public struct Manifest: Hashable, Sendable, Codable {
        /// Always `"tabula.backup"`.
        public var format: String
        /// Version of this container format (`BackupArchive.formatVersion`).
        public var formatVersion: Int
        /// `schemaVersion` of the contained database.
        public var schemaVersion: Int
        /// When the backup was made (injected).
        public var createdAt: Date
        /// Live (non-deleted) entities per `EntityType` raw value, for the import preview.
        public var entityCounts: [String: Int]
        /// Length of the database bytes.
        public var databaseByteCount: Int
        /// Lowercase hex SHA-256 of the database bytes.
        public var sha256: String
    }

    /// The first line of every archive.
    public static let magicLine = "TABULA-BACKUP"
    /// The container format version this app writes and reads.
    public static let formatVersion = 1
    /// `Manifest.format`.
    public static let formatName = "tabula.backup"

    /// The manifest.
    public let manifest: Manifest
    /// The database JSON bytes the checksum covers.
    public let databaseData: Data

    /// Builds an archive of `database` (pretty-printed canonical JSON).
    public static func make(from database: TabulaDatabase, createdAt: Date) throws -> BackupArchive {
        let data = try database.encoded(pretty: true)
        let manifest = Manifest(format: formatName, formatVersion: formatVersion, schemaVersion: database.schemaVersion,
                                createdAt: createdAt, entityCounts: liveCounts(database),
                                databaseByteCount: data.count, sha256: TabulaSHA256.hexDigest(data))
        return BackupArchive(manifest: manifest, databaseData: data)
    }

    /// The archive file bytes.
    public func encoded() throws -> Data {
        var data = Data((Self.magicLine + "\n").utf8)
        data.append(try TabulaJSON.makeEncoder().encode(manifest))
        data.append(0x0A)
        data.append(databaseData)
        return data
    }

    /// Parses an archive and verifies its integrity (format, byte count, SHA-256). Does not decode the database.
    public static func decode(from data: Data) throws -> BackupArchive {
        let bytes = [UInt8](data)
        guard let firstNewline = bytes.firstIndex(of: 0x0A),
              String(decoding: bytes[..<firstNewline], as: UTF8.self) == magicLine,
              let secondNewline = bytes[(firstNewline + 1)...].firstIndex(of: 0x0A) else {
            throw BackupArchiveError.notABackup
        }
        let manifest: Manifest
        do {
            manifest = try TabulaJSON.decodeUntrusted(Manifest.self,
                                                          from: Data(bytes[(firstNewline + 1)..<secondNewline]))
        } catch {
            throw BackupArchiveError.malformedManifest(String(describing: error))
        }
        guard manifest.format == formatName else { throw BackupArchiveError.notABackup }
        guard manifest.formatVersion <= formatVersion else {
            throw BackupArchiveError.unsupportedFormatVersion(manifest.formatVersion)
        }
        let database = Data(bytes[(secondNewline + 1)...])
        guard database.count == manifest.databaseByteCount else {
            throw BackupArchiveError.byteCountMismatch(expected: manifest.databaseByteCount, actual: database.count)
        }
        let checksum = TabulaSHA256.hexDigest(database)
        guard checksum == manifest.sha256.lowercased() else {
            throw BackupArchiveError.checksumMismatch(expected: manifest.sha256, actual: checksum)
        }
        return BackupArchive(manifest: manifest, databaseData: database)
    }

    /// Decodes the contained database, migrating an older one. A newer one throws
    /// `BackupArchiveError.newerSchema` (update the app first).
    public func database(migrations: MigrationChain = .standard) throws -> TabulaDatabase {
        switch DatabaseFileDecoder.decode(databaseData, migrations: migrations) {
        case .current(let database), .migrated(let database, _):
            return database
        case .newer(let version, _, _):
            throw BackupArchiveError.newerSchema(version)
        case .corrupt(let reason):
            throw BackupArchiveError.unreadableDatabase(reason)
        }
    }

    static func liveCounts(_ database: TabulaDatabase) -> [String: Int] {
        func live<E: SyncEntity>(_ entities: [E]) -> Int { entities.filter { !$0.isDeleted }.count }
        return [
            EntityType.settings.rawValue: 1,
            EntityType.timetable.rawValue: live(database.timetables),
            EntityType.subject.rawValue: live(database.subjects),
            EntityType.bellSchedule.rawValue: live(database.bellSchedules),
            EntityType.lesson.rawValue: live(database.lessons),
            EntityType.term.rawValue: live(database.terms),
            EntityType.calendarBreak.rawValue: live(database.breaks),
            EntityType.scheduleOverride.rawValue: live(database.overrides),
            EntityType.task.rawValue: live(database.tasks),
            EntityType.exam.rawValue: live(database.exams),
            EntityType.reminderRule.rawValue: live(database.reminderRules),
        ]
    }
}

/// Errors of `BackupArchive`.
public enum BackupArchiveError: Error, Hashable, Sendable {
    /// Not a Tabula backup file.
    case notABackup
    /// A container format from a newer app version.
    case unsupportedFormatVersion(Int)
    /// The manifest line is not valid.
    case malformedManifest(String)
    /// The database part is truncated or padded.
    case byteCountMismatch(expected: Int, actual: Int)
    /// The database bytes do not match the manifest checksum.
    case checksumMismatch(expected: String, actual: String)
    /// The database was written by a newer app version.
    case newerSchema(Int)
    /// The database part cannot be decoded.
    case unreadableDatabase(CorruptionReason)
}

/// Applies a backup's database to the current one in a way that survives sync.
public enum BackupRestore {
    /// How a backup is applied.
    public enum Mode: Hashable, Sendable {
        /// Field-level merge (`SyncMerge`): nothing newer is lost; deleted items stay deleted unless the
        /// backup holds a later write.
        case merge
        /// The result shows exactly the backup's content. Implemented as **new local mutations** stamped
        /// now (changed fields re-stamped, entities missing from the backup tombstoned, deleted ones
        /// restored), so the restore also wins on other devices after sync instead of losing to newer
        /// clocks. Unknown keys are taken from the backup.
        case replace
    }

    /// The database after applying `backup` to `current`.
    public static func apply<C: TimestampClock>(_ backup: TabulaDatabase, to current: TabulaDatabase, mode: Mode,
                                                clock: inout C, now: Date) throws -> TabulaDatabase {
        switch mode {
        case .merge:
            return try SyncMerge.merge(local: current, remote: backup)
        case .replace:
            var result = current
            var settings = backup.settings
            settings.id = current.settings.id
            result.settings = try MutationStamper.stamp(old: current.settings, new: settings, clock: &clock, now: now)
            result.timetables = try replace(current.timetables, with: backup.timetables, clock: &clock, now: now)
            result.subjects = try replace(current.subjects, with: backup.subjects, clock: &clock, now: now)
            result.bellSchedules = try replace(current.bellSchedules, with: backup.bellSchedules, clock: &clock, now: now)
            result.lessons = try replace(current.lessons, with: backup.lessons, clock: &clock, now: now)
            result.terms = try replace(current.terms, with: backup.terms, clock: &clock, now: now)
            result.breaks = try replace(current.breaks, with: backup.breaks, clock: &clock, now: now)
            result.overrides = try replace(current.overrides, with: backup.overrides, clock: &clock, now: now)
            result.tasks = try replace(current.tasks, with: backup.tasks, clock: &clock, now: now)
            result.exams = try replace(current.exams, with: backup.exams, clock: &clock, now: now)
            result.reminderRules = try replace(current.reminderRules, with: backup.reminderRules, clock: &clock, now: now)
            result.unknownFields = backup.unknownFields
            return result.canonicalized()
        }
    }

    private static func replace<E: SyncEntity, C: TimestampClock>(_ current: [E], with backup: [E],
                                                                   clock: inout C, now: Date) throws -> [E] {
        let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let backupIDs = Set(backup.map(\.id))
        var result: [E] = []
        for entity in backup.sorted(by: { $0.id < $1.id }) {
            result.append(try MutationStamper.stamp(old: currentByID[entity.id], new: entity, clock: &clock, now: now))
        }
        for entity in current.sorted(by: { $0.id < $1.id }) where !backupIDs.contains(entity.id) {
            result.append(entity.isDeleted ? entity : try MutationStamper.delete(entity, clock: &clock, now: now))
        }
        return result
    }
}

extension TabulaRepository {
    /// A backup archive of the stored database.
    public func exportBackup(createdAt: Date) async throws -> BackupArchive {
        try BackupArchive.make(from: try await load(), createdAt: createdAt)
    }
}
