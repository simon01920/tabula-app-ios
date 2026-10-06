import Foundation

/// Sync metadata carried by every persisted entity and child.
///
/// - `createdAt`: HLC timestamp of creation, and the **default field clock**: a field without an entry in
///   `fieldClocks` was last written at `createdAt` (orchestrator decision, Phase 1 Stage 3; DOMAIN_MODEL §2.2).
///   The `AppSettings` singleton starts at `createdAt == .zero` (`EntityMeta.untouchedSingleton`), so any real
///   edit on any device beats the untouched defaults another device created independently.
/// - `updatedAt`: the latest mutation of the entity (a field write, a delete or a restore); ≥ every field clock.
///   It is the delete clock of a tombstone and the liveness clock of a live entity (merge rule 3).
/// - `isDeleted`: tombstone flag. Deleted entities stay in the database (and in sync) until garbage
///   collection; every consumer must skip them.
/// - `fieldClocks`: per-field HLC for field-level last-writer-wins, keyed by the field's JSON key. It holds
///   only fields written after creation. **A missing key means the field is at `createdAt`.** The canonical
///   form (written by `MutationStamper` and `SyncMerge`) omits entries equal to `createdAt`.
public struct EntityMeta: Hashable, Sendable, Codable {
    /// When the entity was created; also the clock of every field without a `fieldClocks` entry.
    public var createdAt: HLCTimestamp
    /// When the entity last changed (field write, delete or restore); ≥ every value in `fieldClocks`.
    public var updatedAt: HLCTimestamp
    /// Tombstone flag.
    public var isDeleted: Bool
    /// Per-field clocks keyed by JSON field name; absent keys default to `createdAt`.
    public var fieldClocks: [String: HLCTimestamp]

    /// Creates metadata.
    public init(createdAt: HLCTimestamp, updatedAt: HLCTimestamp, isDeleted: Bool = false,
                fieldClocks: [String: HLCTimestamp] = [:]) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.fieldClocks = fieldClocks
    }

    /// Metadata for a newly created, live entity stamped at `timestamp`.
    public static func created(at timestamp: HLCTimestamp) -> EntityMeta {
        EntityMeta(createdAt: timestamp, updatedAt: timestamp)
    }

    /// Metadata of a fixed-ID singleton (`AppSettings`) that still holds only defaults: every clock is
    /// `.zero`, so the first real edit on any device wins over defaults created independently elsewhere.
    public static let untouchedSingleton = EntityMeta(createdAt: .zero, updatedAt: .zero)

    /// The effective clock of `field` (its entry in `fieldClocks`, else `createdAt`).
    public func clock(for field: String) -> HLCTimestamp { fieldClocks[field] ?? createdAt }

    /// The same metadata in canonical form (`fieldClocks` entries equal to `createdAt` omitted).
    public func canonicalized() -> EntityMeta {
        var copy = self
        copy.fieldClocks = fieldClocks.filter { $0.value != createdAt }
        return copy
    }
}

/// The persisted top-level entity kinds. Raw values are stable record-type names for sync and backups.
public enum EntityType: String, CaseIterable, Codable, Sendable {
    case timetable, subject, bellSchedule, lesson, term, calendarBreak, scheduleOverride, task, exam,
         reminderRule, settings

    /// Catalog key of the human-readable type name (used as a nested argument in validation messages).
    public var l10nKey: String { "entityType.\(rawValue)" }
}

/// A top-level persisted entity with a stable typed ID and sync metadata.
public protocol SyncEntity: Identifiable, Codable, Hashable, Sendable where ID == EntityID<Self> {
    /// Sync metadata (timestamps, tombstone, field clocks).
    var meta: EntityMeta { get set }
    /// The entity kind (record type).
    static var entityType: EntityType { get }
}

extension SyncEntity {
    /// `true` when the entity is a tombstone.
    public var isDeleted: Bool { meta.isDeleted }
}

/// A child record embedded in an entity (`Subtask`, `AttachmentRef`) that is set-merged by `id`.
public protocol ChildEntity: Identifiable, Codable, Hashable, Sendable where ID == EntityID<Self> {
    /// Sync metadata of the child.
    var meta: EntityMeta { get set }
}

/// Source of monotonically increasing HLC timestamps, injected wherever entities are created or changed.
///
/// The sync layer's `HybridLogicalClock` conforms; tests use simple deterministic clocks.
/// Follows the `RandomNumberGenerator` pattern: APIs take `inout some TimestampClock`.
public protocol TimestampClock {
    /// Returns a timestamp strictly greater than every timestamp this clock returned before.
    mutating func tick(now: Date) -> HLCTimestamp
}
