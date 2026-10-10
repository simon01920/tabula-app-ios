// File-system `AttachmentStore` (stage B3). Foundation only, so the same code runs in the app and in the Linux tests
// (temporary directories). Layout under `root` (= `<store directory>/Attachments`, next to `tabula.json`):
//
//   Attachments/<UUID>/<sanitized name>      one folder per AttachmentRef ID (uppercase UUID), one file inside
//   Attachments/.staging/<random UUID>/...   in-progress copy-ins; renamed into place when complete
//
// Atomicity: the bytes are copied/written into a staging folder on the same volume, stamped, then the whole folder is
// renamed to `<UUID>` (`FileManager.moveItem` = rename(2) on one volume), so a crash leaves either no folder or a
// complete one; abandoned staging folders are removed by the next cleanup.
// File protection: `.completeUntilFirstUserAuthentication` on folders and files (iOS/watchOS; readable by background
// refresh after the first unlock, like the database). Backup: nothing is excluded, so attachments are in device
// backups together with the database (Apple, "Optimizing your app's data for iCloud backup": only purgeable data
// should be excluded; attachments are user data).
// APIs: FileManager.copyItem/moveItem/removeItem/createDirectory/attributesOfItem/setAttributes/contentsOfDirectory,
//       FileAttributeKey.protectionKey + FileProtectionType.completeUntilFirstUserAuthentication (iOS 5),
//       Data.write(to:options: .atomic). Docs checked 2026-10-10 (docs/ENVIRONMENT.md §22).
import Foundation
import TimetableCore

/// Attachment files in a directory; serialises every operation (quota checks cannot race two imports).
public actor FileAttachmentStore: AttachmentStore {
    /// `<store directory>/Attachments`.
    public nonisolated let root: URL
    private let policy: AttachmentCleanupPolicy
    private let clock: @Sendable () -> Date
    private var protectedByOwner: [UUID: Set<UUID>] = [:]

    static let stagingName = ".staging"

    /// A store rooted at `root` (created on first write). `clock` stamps imports and drives the grace period —
    /// always the real clock in the app (file dates are real), injectable for tests.
    public init(root: URL, policy: AttachmentCleanupPolicy = .standard, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.policy = policy
        self.clock = clock
    }

    /// The attachments root for a database directory (`<directory>/Attachments`).
    public static func root(forStoreDirectory directory: URL) -> URL {
        directory.appendingPathComponent("Attachments", isDirectory: true)
    }

    private var staging: URL { root.appendingPathComponent(Self.stagingName, isDirectory: true) }

    private func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString.uppercased(), isDirectory: true)
    }

    // MARK: Import

    public func importFile(at source: URL, id: AttachmentRef.ID, suggestedName: String, contentType: String?,
                           quota: AttachmentQuota) async throws -> StoredAttachmentFile {
        let fileManager = FileManager.default
        // Early refusal from the source's size (the definitive check is on the copied bytes).
        if let size = (try? fileManager.attributesOfItem(atPath: source.path))?[.size] as? NSNumber {
            try checkQuota(adding: size.int64Value, quota: quota)
        }
        return try stage(id: id, suggestedName: suggestedName, contentType: contentType, quota: quota) { destination in
            do {
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                throw AttachmentStoreError.sourceUnreadable
            }
        }
    }

    public func importData(_ data: Data, id: AttachmentRef.ID, suggestedName: String, contentType: String?,
                           quota: AttachmentQuota) async throws -> StoredAttachmentFile {
        try checkQuota(adding: Int64(data.count), quota: quota)
        return try stage(id: id, suggestedName: suggestedName, contentType: contentType, quota: quota) { destination in
            do {
                try data.write(to: destination, options: .withoutOverwriting)
            } catch {
                throw AttachmentStoreError.ioFailure("write: \(error.localizedDescription)")
            }
        }
    }

    /// Stages `write` into `.staging/<random>/<name>`, stamps it, checks the quota on the real size and renames the
    /// staging folder to `<id>`. On any failure the staging folder is removed and nothing is visible.
    private func stage(id: AttachmentRef.ID, suggestedName: String, contentType: String?, quota: AttachmentQuota,
                       write: (URL) throws -> Void) throws -> StoredAttachmentFile {
        let fileManager = FileManager.default
        let target = folder(for: id.uuid)
        guard !fileManager.fileExists(atPath: target.path) else { throw AttachmentStoreError.alreadyExists }
        let name = AttachmentFileName.sanitize(suggestedName)
        let stagingFolder = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try createProtectedDirectory(root)
            try createProtectedDirectory(staging)
            try createProtectedDirectory(stagingFolder)
        } catch {
            throw AttachmentStoreError.ioFailure("mkdir: \(error.localizedDescription)")
        }
        let stagedFile = stagingFolder.appendingPathComponent(name, isDirectory: false)
        do {
            try write(stagedFile)
            let size = Self.fileSize(stagedFile)
            try checkQuota(adding: size, quota: quota)
            let now = clock()
            // The copy keeps the source's dates; stamp the import time so the grace period starts now.
            try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: stagedFile.path)
            Self.protect(stagedFile)
            try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: stagingFolder.path)
            guard !fileManager.fileExists(atPath: target.path) else { throw AttachmentStoreError.alreadyExists }
            do {
                try fileManager.moveItem(at: stagingFolder, to: target)
            } catch {
                throw AttachmentStoreError.ioFailure("rename: \(error.localizedDescription)")
            }
            return StoredAttachmentFile(fileName: name, byteCount: size,
                                        contentType: AttachmentContentType.resolve(provided: contentType, fileName: name))
        } catch {
            try? fileManager.removeItem(at: stagingFolder)
            if let storeError = error as? AttachmentStoreError { throw storeError }
            throw AttachmentStoreError.ioFailure(error.localizedDescription)
        }
    }

    private func checkQuota(adding bytes: Int64, quota: AttachmentQuota) throws {
        guard quota.limitBytes != nil else { return }
        let usage = usageNow()
        guard quota.allows(adding: bytes, currentUsage: usage) else {
            throw AttachmentStoreError.quotaExceeded(needed: bytes, available: quota.available(currentUsage: usage) ?? 0)
        }
    }

    // MARK: Read / delete

    public func fileURL(id: AttachmentRef.ID, fileName: String?) async -> URL? {
        guard let fileName, AttachmentFileName.isSafeStoredName(fileName) else { return nil }
        let url = folder(for: id.uuid).appendingPathComponent(fileName, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return url
    }

    public func deleteFiles(id: AttachmentRef.ID) async throws {
        let target = folder(for: id.uuid)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw AttachmentStoreError.ioFailure("delete: \(error.localizedDescription)")
        }
    }

    public func totalUsage() async -> Int64 { usageNow() }

    private func usageNow() -> Int64 {
        entries().reduce(0) { $0 + $1.byteCount }
    }

    // MARK: Protection + cleanup

    public func setProtectedIDs(_ ids: Set<UUID>, owner: UUID) async {
        protectedByOwner[owner] = ids
    }

    public func clearProtection(owner: UUID) async {
        protectedByOwner[owner] = nil
    }

    /// Union of all open editors' protected IDs.
    var protectedIDs: Set<UUID> { protectedByOwner.values.reduce(into: Set<UUID>()) { $0.formUnion($1) } }

    public func cleanUpOrphans(liveIDs: Set<UUID>) async -> AttachmentCleanupReport {
        var report = AttachmentCleanupReport()
        let now = clock()
        let found = entries()
        let doomed = Set(policy.deletable(entries: found, liveIDs: liveIDs, protectedIDs: protectedIDs, now: now))
        for entry in found.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard doomed.contains(entry.id) else {
                report.kept += 1
                continue
            }
            // Re-check right before deleting (an import for this ID cannot be in flight: the actor serialises).
            guard !liveIDs.contains(entry.id), !protectedIDs.contains(entry.id) else {
                report.kept += 1
                continue
            }
            do {
                try FileManager.default.removeItem(at: folder(for: entry.id))
                report.deleted.append(entry.id)
                report.freedBytes += entry.byteCount
            } catch {
                report.failures.append("\(entry.id.uuidString): \(error.localizedDescription)")
            }
        }
        report.removedStaging = removeAbandonedStaging(now: now)
        return report
    }

    private func removeAbandonedStaging(now: Date) -> Int {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(atPath: staging.path) else { return 0 }
        var removed = 0
        for child in children {
            let url = staging.appendingPathComponent(child)
            let modified = Self.newestModification(url) ?? .distantPast
            if policy.isAbandonedStaging(lastModified: modified, now: now), (try? fileManager.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    // MARK: Scanning

    /// Every `<UUID>/` folder under the root (non-UUID names, `.staging` and loose files are ignored).
    func entries() -> [AttachmentDirectoryEntry] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(atPath: root.path) else { return [] }
        var result: [AttachmentDirectoryEntry] = []
        for child in children {
            guard let id = UUID(uuidString: child) else { continue }
            let url = root.appendingPathComponent(child, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let (bytes, newest) = Self.folderStats(url)
            result.append(AttachmentDirectoryEntry(id: id, byteCount: bytes, lastModified: newest))
        }
        return result
    }

    private static func folderStats(_ folder: URL) -> (Int64, Date) {
        let fileManager = FileManager.default
        var bytes: Int64 = 0
        var newest = modificationDate(folder) ?? .distantPast
        if let enumerator = fileManager.enumerator(atPath: folder.path) {
            while let relative = enumerator.nextObject() as? String {
                let path = folder.appendingPathComponent(relative).path
                guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { continue }
                if let date = attributes[.modificationDate] as? Date, date > newest { newest = date }
                if (attributes[.type] as? FileAttributeType) == .typeRegular,
                   let size = attributes[.size] as? NSNumber {
                    bytes += size.int64Value
                }
            }
        }
        return (bytes, newest)
    }

    private static func newestModification(_ url: URL) -> Date? {
        let (_, newest) = folderStats(url)
        return newest == .distantPast ? nil : newest
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func createProtectedDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        Self.protect(url)
    }

    /// Sets `.completeUntilFirstUserAuthentication` where data protection exists (no-op elsewhere / on failure).
    private static func protect(_ url: URL) {
        #if os(iOS) || os(watchOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
        #endif
    }
}
