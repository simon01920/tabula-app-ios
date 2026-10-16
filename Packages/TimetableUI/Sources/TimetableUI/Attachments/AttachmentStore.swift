// Attachment file storage contract (PHASE3_PLAN §0.7, stage B3): the database holds only `AttachmentRef`s; the bytes
// live in `<store directory>/Attachments/<attachment UUID>/<sanitized file name>` next to the database.
//
// Data-loss rules (normative for every implementation):
// 1. Copy-in is atomic: bytes are staged in `Attachments/.staging/<random>/` on the same volume and the finished
//    folder is renamed to `Attachments/<UUID>` — a folder either holds the complete file or does not exist.
// 2. A file whose UUID is referenced by a live `AttachmentRef` (live task, ref not tombstoned) is never deleted.
// 3. Orphans (no live ref: never saved, ref tombstoned, task tombstoned) are deleted only when they are older than
//    `AttachmentCleanupPolicy.gracePeriod` and not protected by an open editor — so an editor that has added a file
//    but not saved yet is never raced, and a cancelled editor's files are removed later.
// 4. Entries the store does not recognise (non-UUID names, loose files) are never touched.
// 5. Cleanup never runs without a successfully loaded, writable database (the caller checks; see
//    `AttachmentCleanupGate`).
import Foundation
import TimetableCore

/// What a successful copy-in stored.
public struct StoredAttachmentFile: Equatable, Sendable {
    /// The sanitised name inside `Attachments/<UUID>/` (goes into `AttachmentRef.fileName`).
    public let fileName: String
    /// Size on disk in bytes (goes into `AttachmentRef.byteCount`).
    public let byteCount: Int64
    /// Uniform type identifier (goes into `AttachmentRef.contentType`).
    public let contentType: String

    public init(fileName: String, byteCount: Int64, contentType: String) {
        self.fileName = fileName
        self.byteCount = byteCount
        self.contentType = contentType
    }
}

/// Why a store operation failed.
public enum AttachmentStoreError: Error, Equatable, Sendable {
    /// The file would exceed the quota. Bytes: needed for this file, still available.
    case quotaExceeded(needed: Int64, available: Int64)
    /// The source file could not be read.
    case sourceUnreadable
    /// The source is a folder, package, symbolic link or other non-regular file (only single files are attached).
    case notARegularFile
    /// A folder for this attachment ID already exists (IDs are never reused).
    case alreadyExists
    /// A file-system operation failed (message for logs only).
    case ioFailure(String)
}

/// The attachment quota from the entitlements (`Limit.attachmentQuotaMB`, 10⁶ bytes per MB). `nil` = unlimited.
public struct AttachmentQuota: Equatable, Sendable {
    /// Limit in bytes, or `nil` for unlimited.
    public let limitBytes: Int64?

    public init(limitBytes: Int64?) {
        self.limitBytes = limitBytes
    }

    /// The quota of the current tier.
    public init(entitlements: any EntitlementsProvider) {
        limitBytes = entitlements.limit(.attachmentQuotaMB).map { Int64(max(0, $0)) * 1_000_000 }
    }

    /// Unlimited.
    public static let unlimited = AttachmentQuota(limitBytes: nil)

    /// Bytes still available at `usage` (never negative), or `nil` when unlimited.
    public func available(currentUsage usage: Int64) -> Int64? {
        limitBytes.map { max(0, $0 - max(0, usage)) }
    }

    /// `true` when a file of `bytes` fits at `usage`.
    public func allows(adding bytes: Int64, currentUsage usage: Int64) -> Bool {
        guard let available = available(currentUsage: usage) else { return true }
        return max(0, bytes) <= available
    }
}

/// One `Attachments/<UUID>/` folder as found on disk.
public struct AttachmentDirectoryEntry: Equatable, Sendable {
    /// The folder's attachment ID.
    public let id: UUID
    /// Total bytes of the files inside.
    public let byteCount: Int64
    /// Newest modification date of the folder and its files (the import stamps it with the import time).
    public let lastModified: Date

    public init(id: UUID, byteCount: Int64, lastModified: Date) {
        self.id = id
        self.byteCount = byteCount
        self.lastModified = lastModified
    }
}

/// Which folders a cleanup may delete (pure; rules 2–3 above).
public struct AttachmentCleanupPolicy: Equatable, Sendable {
    /// Files younger than this are kept even without a live ref (unsaved editors, app killed mid-edit).
    public var gracePeriod: TimeInterval
    /// Abandoned staging folders (interrupted imports) older than this are removed.
    public var stagingMaxAge: TimeInterval

    public init(gracePeriod: TimeInterval = 24 * 60 * 60, stagingMaxAge: TimeInterval = 60 * 60) {
        self.gracePeriod = gracePeriod
        self.stagingMaxAge = stagingMaxAge
    }

    public static let standard = AttachmentCleanupPolicy()

    /// IDs of `entries` that are orphans and old enough to delete, sorted. An entry dated in the future (clock moved
    /// back) counts as recent, so it is kept.
    public func deletable(entries: [AttachmentDirectoryEntry], liveIDs: Set<UUID>, protectedIDs: Set<UUID>,
                          now: Date) -> [UUID] {
        entries
            .filter { !liveIDs.contains($0.id) && !protectedIDs.contains($0.id) }
            .filter { now.timeIntervalSince($0.lastModified) >= gracePeriod }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// `true` when a staging folder last modified at `date` is abandoned.
    public func isAbandonedStaging(lastModified date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) >= stagingMaxAge
    }
}

/// The attachment IDs a database still needs.
public enum AttachmentReferences {
    /// IDs of every non-tombstoned `AttachmentRef` of every non-tombstoned task (all kinds; a link has no folder,
    /// so including it is harmless).
    public static func liveIDs(in database: TabulaDatabase) -> Set<UUID> {
        var ids = Set<UUID>()
        for task in database.tasks where !task.isDeleted {
            for ref in task.attachments where !ref.meta.isDeleted {
                ids.insert(ref.id.uuid)
            }
        }
        return ids
    }

    /// The live refs of an editor's array in display order (`sortIndex`, then `id`).
    public static func visible(_ refs: [AttachmentRef]) -> [AttachmentRef] {
        refs.filter { !$0.meta.isDeleted }.sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
    }

    /// `refs` with the live ones renumbered `0…n-1` in `order` (IDs); tombstones and unknown IDs untouched.
    public static func reordered(_ refs: [AttachmentRef], to order: [AttachmentRef.ID]) -> [AttachmentRef] {
        var position: [AttachmentRef.ID: Int] = [:]
        for (index, id) in order.enumerated() where position[id] == nil { position[id] = index }
        return refs.map { ref in
            guard !ref.meta.isDeleted, let index = position[ref.id] else { return ref }
            var copy = ref
            copy.sortIndex = index
            return copy
        }
    }

    /// The `sortIndex` for a ref appended after the live ones. Overflow-safe: after a stored `Int.max` it stays at
    /// `Int.max` (the tie is ordered by ID, so the new ref is not guaranteed last, but adding never traps).
    public static func nextSortIndex(_ refs: [AttachmentRef]) -> Int {
        SubjectOrder.appendedIndex(after: refs.filter { !$0.meta.isDeleted }.map(\.sortIndex)) ?? Int.max
    }
}

/// The IDs an open attachment editor protects: every ID it has shown or added since it opened (also the ones removed
/// again), so nothing this editor touched can be cleaned up before the editor closes (protection lifetime = editor
/// lifetime). Grows only.
public struct AttachmentEditorProtection: Equatable, Sendable {
    public private(set) var ids: Set<UUID> = []

    public init() {}

    /// Adds the IDs of `refs` (tombstones included); `true` when the set grew.
    @discardableResult
    public mutating func record(_ refs: [AttachmentRef]) -> Bool {
        let before = ids.count
        ids.formUnion(refs.map(\.id.uuid))
        return ids.count != before
    }

    /// Adds one ID (an import that is still copying); `true` when the set grew.
    @discardableResult
    public mutating func record(_ id: AttachmentRef.ID) -> Bool {
        ids.insert(id.uuid).inserted
    }
}

/// Whether a cleanup may run now (rule 5). The app evaluates it from its model state.
public enum AttachmentCleanupGate {
    /// `true` only for a loaded, writable database whose last save did not fail (never clean against an in-memory
    /// state that is not on disk), and that was not recovered from a backup or a discarded write in this session
    /// (after a recovery the files of the lost changes are kept until the next launch).
    public static func mayRun(databaseLoaded: Bool, isReadOnly: Bool, hasProblem: Bool, recoveredThisSession: Bool,
                              lastSaveFailed: Bool) -> Bool {
        databaseLoaded && !isReadOnly && !hasProblem && !recoveredThisSession && !lastSaveFailed
    }
}

/// What a cleanup did.
public struct AttachmentCleanupReport: Equatable, Sendable {
    /// Deleted orphan folders.
    public var deleted: [UUID] = []
    /// Bytes freed by `deleted`.
    public var freedBytes: Int64 = 0
    /// Folders kept because they are live, protected or still in the grace period.
    public var kept: Int = 0
    /// Abandoned staging folders removed.
    public var removedStaging: Int = 0
    /// Deletions that failed (logged; retried by the next cleanup).
    public var failures: [String] = []

    public init() {}
}

/// File storage for attachment bytes. Implementations serialise operations (the file store is an actor).
public protocol AttachmentStore: Sendable {
    /// Copies the file at `source` in atomically as `Attachments/<id>/<sanitized suggestedName>`.
    /// Throws `notARegularFile` for folders/packages/links and `quotaExceeded` (nothing stored) when it does not fit.
    func importFile(at source: URL, id: AttachmentRef.ID, suggestedName: String, contentType: String?,
                    quota: AttachmentQuota) async throws -> StoredAttachmentFile
    /// Writes `data` atomically as `Attachments/<id>/<sanitized suggestedName>`.
    func importData(_ data: Data, id: AttachmentRef.ID, suggestedName: String, contentType: String?,
                    quota: AttachmentQuota) async throws -> StoredAttachmentFile
    /// The URL of a stored file, or `nil` when the name is unsafe or the file is missing (e.g. a ref synced from
    /// another device whose bytes are not here).
    func fileURL(id: AttachmentRef.ID, fileName: String?) async -> URL?
    /// Deletes `Attachments/<id>` (no-op when missing). Only for refs known to be gone; editors never call it.
    func deleteFiles(id: AttachmentRef.ID) async throws
    /// Bytes used by all attachment folders (staging excluded).
    func totalUsage() async -> Int64
    /// Marks `ids` as in use by an open editor (`owner` = that editor), replacing its previous set.
    func setProtectedIDs(_ ids: Set<UUID>, owner: UUID) async
    /// Ends an editor's protection.
    func clearProtection(owner: UUID) async
    /// Deletes orphan folders per `AttachmentCleanupPolicy` and removes abandoned staging folders.
    func cleanUpOrphans(liveIDs: Set<UUID>) async -> AttachmentCleanupReport
}
