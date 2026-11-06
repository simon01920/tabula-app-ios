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
    /// timestamp, so later edits always stamp above the restored data. `settings.syncEnabled` keeps this device's value
    /// in both modes (re-stamped now if the merge took the backup's), so a restore never switches iCloud sync.
    public static func restore(_ backup: TabulaDatabase, mode: BackupRestore.Mode) -> DatabaseMutation {
        DatabaseMutation(label: mode == .merge ? "restore backup (merge)" : "restore backup (replace)") {
            database, clock, now in
            clock.receive(backup.latestTimestamp, now: now)
            var restored = try BackupRestore.apply(backup, to: database, mode: mode, clock: &clock, now: now)
            if restored.settings.syncEnabled != database.settings.syncEnabled {
                var settings = restored.settings
                settings.syncEnabled = database.settings.syncEnabled
                restored.settings = try MutationStamper.stamp(old: restored.settings, new: settings, clock: &clock, now: now)
            }
            database = restored
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

/// `<store directory>/Backups`: archives Tabula writes before it replaces, merges or moves data (labels: pre-restore,
/// pre-import, pre-migration-fallback, pre-migration-group, pre-demo). Every `write` prunes older archives of its
/// label (Phase 10 B11: copies are written on every restore, Merge included, and every share-code Replace, so the
/// folder used to grow without bound). An archive is deleted only when it is beyond the newest `keepPerLabel` of its
/// label AND its stamp is more than `minimumAge` (30 days) older than the write (QA fix after Phase 10, decision
/// P10-6: the pre-restore copy that "Replace" promises must survive a burst of further restores). The archive just
/// written is never deleted; other labels and files that are not archives are never touched.
public enum BackupFolder {
    /// Archives always kept per label (the newest ones).
    public static let keepPerLabel = 5
    /// Archives beyond the newest `keepPerLabel` are deleted only once their stamp is at least this much older than
    /// the write (30 days; UTC stamps, so fixed seconds).
    public static let minimumAge: TimeInterval = 30 * 24 * 60 * 60

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

    /// Writes `archive` as `<UTC yyyyMMddTHHmmssZ>-<label>[-n].tabulabackup` (never overwrites; temp file + rename),
    /// then prunes older archives of `label` (`prune`, best effort: a failed delete never fails the write). `now` is
    /// the time of the write the 30-day age is measured from; `nil` uses the archive's own creation time (every
    /// caller stamps the archive with the current time).
    @discardableResult
    public static func write(_ archive: BackupArchive, label: String, in folder: URL, now: Date? = nil,
                             fileSystem: any RepositoryFileSystem = FoundationFileSystem()) throws -> URL {
        let url = try writeArchive(archive, label: label, in: folder, fileSystem: fileSystem)
        prune(label: label, in: folder, protecting: url, now: now ?? archive.manifest.createdAt, fileSystem: fileSystem)
        return url
    }

    /// Deletes the archives of `label` in `folder` that `prunable` returns. `protecting` (the archive just written)
    /// is always kept and counts as one of the newest. Best effort: unreadable folders and failed deletes are ignored.
    public static func prune(label: String, in folder: URL, keep: Int = keepPerLabel, protecting: URL, now: Date,
                             minimumAge: TimeInterval = BackupFolder.minimumAge,
                             fileSystem: any RepositoryFileSystem = FoundationFileSystem()) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in prunable(names: names, label: label, keep: keep, protecting: protecting.lastPathComponent,
                             now: now, minimumAge: minimumAge) {
            try? fileSystem.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// The pruning policy (pure): the names among `names` to delete. Archives labelled `label` are ordered newest
    /// first by (UTC stamp, `-n` counter); the newest `keep` (at least 1) always stay, and one beyond them is returned
    /// only when its stamp is more than `minimumAge` before `now` (a stamp in the future, after the clock moved back,
    /// is never old enough). `protecting` is never returned and always counts as one of the newest when present.
    /// Names of other labels, temporary files (`.…tmp`) and anything that is not an archive name written by `write`
    /// are never returned.
    public static func prunable(names: [String], label: String, keep: Int, protecting: String, now: Date,
                                minimumAge: TimeInterval = BackupFolder.minimumAge) -> [String] {
        let matching = names.compactMap { name -> (name: String, stamp: String, counter: Int)? in
            guard let parsed = archiveName(name, label: label) else { return nil }
            return (name, parsed.stamp, parsed.counter)
        }
        .sorted { ($0.stamp, $0.counter, $0.name) > ($1.stamp, $1.counter, $1.name) }
        let formatter = stampFormatter
        let cutoff = now.addingTimeInterval(-minimumAge)
        var remaining = max(keep, 1) - (matching.contains { $0.name == protecting } ? 1 : 0)
        var deletable: [String] = []
        for entry in matching where entry.name != protecting {
            if remaining > 0 {
                remaining -= 1
            } else if let stamped = formatter.date(from: entry.stamp), stamped < cutoff {
                deletable.append(entry.name)
            }
        }
        return deletable
    }

    /// (stamp, counter) when `name` is `<stamp>-<label>.tabulabackup` (counter 1) or `<stamp>-<label>-<n>.tabulabackup`.
    private static func archiveName(_ name: String, label: String) -> (stamp: String, counter: Int)? {
        let suffix = ".\(fileExtension)"
        guard !name.hasPrefix("."), name.hasSuffix(suffix), name.count > 17 + suffix.count else { return nil }
        let stamp = String(name.prefix(16))
        guard stampFormatter.date(from: stamp) != nil, name.dropFirst(16).first == "-" else { return nil }
        let rest = String(name.dropFirst(17).dropLast(suffix.count))
        if rest == label { return (stamp, 1) }
        guard rest.hasPrefix("\(label)-") else { return nil }
        let digits = rest.dropFirst(label.count + 1)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let counter = Int(digits) else { return nil }
        return (stamp, counter)
    }

    private static func writeArchive(_ archive: BackupArchive, label: String, in folder: URL,
                                     fileSystem: any RepositoryFileSystem) throws -> URL {
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
