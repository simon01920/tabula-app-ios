// Backup & restore glue (Phase 6 S2, PHASE6_PLAN decisions 5–6). Foundation only, Linux-tested.
//
//   DatabaseMutation.restore(_:mode:)  applies a decoded backup through `BackupRestore` (merge or replace)
//   BackupImport.read(contentsOf:)     untrusted file → database; failures as plain-word problems (nothing is changed)
//   BackupFolder                       `<store directory>/Backups`: automatic pre-restore / pre-migration archives
//   StrandedStoreMigration             RISKS #47/#56: the Application Support fallback store → the App Group store, once
//
// Attachment files are not part of a `.tabulabackup` (BackupArchive format 1); the stranded-data migration copies them.
import Foundation
import TimetableCore

// MARK: - Restore mutation

extension DatabaseMutation {
    /// Applies `backup` to the current database (`BackupRestore.apply`). The clock first receives the backup's newest
    /// timestamp, so later edits always stamp above the restored data.
    public static func restore(_ backup: TabulaDatabase, mode: BackupRestore.Mode) -> DatabaseMutation {
        DatabaseMutation(label: mode == .merge ? "restore backup (merge)" : "restore backup (replace)") {
            database, clock, now in
            clock.receive(backup.latestTimestamp, now: now)
            database = try BackupRestore.apply(backup, to: database, mode: mode, clock: &clock, now: now)
        }
    }
}

// MARK: - Import

/// Why a file cannot be restored, in the words the user sees (`messageKey`).
public enum BackupImportProblem: Error, Equatable, Sendable {
    /// The file could not be read (not downloaded, no access, too large).
    case unreadableFile
    /// Not a Tabula backup.
    case notABackup
    /// Truncated, checksum mismatch or an undecodable database.
    case damaged
    /// Written by a newer app version (container format or schema).
    case newerVersion

    /// Catalog key of the alert message.
    public var messageKey: String {
        switch self {
        case .unreadableFile: return "settings.backup.error.unreadable"
        case .notABackup: return "settings.backup.error.notBackup"
        case .damaged: return "settings.backup.error.damaged"
        case .newerVersion: return "settings.backup.error.newer"
        }
    }
}

/// Reading a `.tabulabackup` chosen by the user.
public enum BackupImport {
    /// Files above this size are refused before reading (real backups are well under 1 MB).
    public static let maxFileSize = 64 * 1024 * 1024

    /// The verified manifest and the (migrated) database of the file at `url`. Never modifies anything.
    public static func read(contentsOf url: URL) throws(BackupImportProblem) -> (BackupArchive.Manifest, TabulaDatabase) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        guard let size, size <= maxFileSize, let data = try? Data(contentsOf: url) else { throw .unreadableFile }
        return try read(data)
    }

    /// The verified manifest and the (migrated) database of archive bytes.
    public static func read(_ data: Data) throws(BackupImportProblem) -> (BackupArchive.Manifest, TabulaDatabase) {
        do {
            let archive = try BackupArchive.decode(from: data)
            return (archive.manifest, try archive.database())
        } catch let error as BackupArchiveError {
            switch error {
            case .notABackup: throw .notABackup
            case .unsupportedFormatVersion, .newerSchema: throw .newerVersion
            case .malformedManifest, .byteCountMismatch, .checksumMismatch, .unreadableDatabase: throw .damaged
            }
        } catch {
            throw .damaged
        }
    }
}

// MARK: - Automatic backups folder

/// `<store directory>/Backups`: archives Tabula writes before it replaces or moves data. Never pruned.
/// shortcut: no pruning, each copy is small and only written on a Replace restore or the one-time migration.
public enum BackupFolder {
    /// One archive in the folder.
    public struct Entry: Hashable, Sendable, Identifiable {
        public var url: URL
        public var createdAt: Date
        public var id: URL { url }
    }

    /// File extension of every archive (no UTType is declared: shared and imported as plain data).
    public static let fileExtension = "tabulabackup"

    /// The folder for a store directory.
    public static func url(forStoreDirectory directory: URL) -> URL {
        directory.appendingPathComponent("Backups", isDirectory: true)
    }

    /// Writes `archive` as `<UTC yyyyMMddTHHmmssZ>-<label>[-n].tabulabackup` (never overwrites; temp file + rename).
    @discardableResult
    public static func write(_ archive: BackupArchive, label: String, in folder: URL,
                             fileSystem: any RepositoryFileSystem = FoundationFileSystem()) throws -> URL {
        try fileSystem.createDirectory(at: folder)
        let stem = "\(stampFormatter.string(from: archive.manifest.createdAt))-\(label)"
        var url = folder.appendingPathComponent("\(stem).\(fileExtension)")
        var counter = 2
        while fileSystem.fileExists(at: url) {
            url = folder.appendingPathComponent("\(stem)-\(counter).\(fileExtension)")
            counter += 1
        }
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).tmp")
        try fileSystem.write(try archive.encoded(), to: temporary)
        try fileSystem.replaceItem(at: url, withItemAt: temporary)
        return url
    }

    /// The archives in `folder`, newest first (empty when the folder does not exist).
    public static func entries(in folder: URL) -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name -> Entry? in
            guard name.hasSuffix(".\(fileExtension)"), !name.hasPrefix("."),
                  let date = stampFormatter.date(from: String(name.prefix(16))) else { return nil }
            return Entry(url: folder.appendingPathComponent(name), createdAt: date)
        }
        .sorted { ($0.createdAt, $0.url.lastPathComponent) > ($1.createdAt, $1.url.lastPathComponent) }
    }

    private static var stampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }
}

// MARK: - Stranded data (RISKS #47 / #56)

/// Moves the store out of the Application Support fallback into the App Group store, once.
///
/// Runs at launch, before the store loads, when the App Group container exists. Steps: load the fallback (nothing
/// there → `.nothingToDo`); load the group store; write a backup archive of each into `<group>/Backups`; copy the
/// fallback's attachment folders that the group lacks; save the fallback database (group store empty) or
/// `SyncMerge.merge(group, fallback)` (group store non-empty) atomically through `FileRepository`; then write the marker
/// into the fallback folder. The fallback folder itself is kept. Any failure changes nothing that matters and returns
/// `.skipped` (retried on the next launch; every step is idempotent).
public enum StrandedStoreMigration {
    /// What a run did.
    public enum Outcome: Equatable, Sendable {
        /// No fallback database, or it was migrated before (marker).
        case nothingToDo
        /// The group store was empty: it now holds the fallback's data.
        case movedIn
        /// Both held data: the group store now holds the merge.
        case merged
        /// Not migrated (unreadable or newer-version store, write failure); retried next launch.
        case skipped(String)
    }

    /// Marker file written into the fallback folder after a successful run.
    public static let markerName = "MovedToAppGroup.marker"

    /// Runs the migration (see the type). `now` stamps the backup archives.
    public static func run(fallbackDirectory: URL, groupDirectory: URL, now: Date) async -> Outcome {
        let fileManager = FileManager.default
        let marker = fallbackDirectory.appendingPathComponent(markerName)
        if fileManager.fileExists(atPath: marker.path) { return .nothingToDo }

        let fallbackStore = FileRepository(directory: fallbackDirectory)
        let fallback: TabulaDatabase
        do {
            fallback = try await fallbackStore.load()
        } catch RepositoryError.notFound {
            return .nothingToDo
        } catch {
            return .skipped("fallback: \(error)")
        }
        if await fallbackStore.isReadOnly { return .skipped("fallback is from a newer app version") }

        let groupStore = FileRepository(directory: groupDirectory)
        var group: TabulaDatabase?
        do {
            group = try await groupStore.load()
        } catch RepositoryError.notFound {
            group = nil
        } catch {
            return .skipped("group: \(error)")
        }
        if await groupStore.isReadOnly { return .skipped("group store is from a newer app version") }

        do {
            let folder = BackupFolder.url(forStoreDirectory: groupDirectory)
            try BackupFolder.write(.make(from: fallback, createdAt: now), label: "pre-migration-fallback", in: folder)
            if let group {
                try BackupFolder.write(.make(from: group, createdAt: now), label: "pre-migration-group", in: folder)
            }
            try copyAttachments(from: FileAttachmentStore.root(forStoreDirectory: fallbackDirectory),
                                to: FileAttachmentStore.root(forStoreDirectory: groupDirectory))
            try await groupStore.save(group.map { try SyncMerge.merge(local: $0, remote: fallback) } ?? fallback)
            try Data(ISO8601DateFormatter().string(from: now).utf8).write(to: marker, options: .atomic)
        } catch {
            return .skipped("write: \(error)")
        }
        return group == nil ? .movedIn : .merged
    }

    /// Copies every attachment folder of `source` that `destination` lacks: into the destination's staging folder,
    /// then renamed into place, so a crash leaves no half-copied folder under its final name.
    static func copyAttachments(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: source.path) else { return }
        let staging = destination.appendingPathComponent(FileAttachmentStore.stagingName, isDirectory: true)
        for name in names where !name.hasPrefix(".") {
            let target = destination.appendingPathComponent(name, isDirectory: true)
            if fileManager.fileExists(atPath: target.path) { continue }
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let temporary = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.copyItem(at: source.appendingPathComponent(name, isDirectory: true), to: temporary)
            try fileManager.moveItem(at: temporary, to: target)
        }
    }
}
