import Foundation

/// Sync metadata carried by every persisted entity and child.
///
/// - `createdAt` / `updatedAt`: HLC timestamps of creation and of the latest change to any field.
/// - `isDeleted`: tombstone flag. Deleted entities stay in the database (and in sync) until garbage
///   collection; every consumer must skip them.
/// - `fieldClocks`: per-field HLC for field-level last-writer-wins, keyed by the field's JSON key.
///   **An empty map (or a missing key) means the field is at `updatedAt`.**
public struct EntityMeta: Hashable, Sendable, Codable {
    /// When the entity was created.
    public var createdAt: HLCTimestamp
    /// When any field last changed (≥ every value in `fieldClocks`).
    public var updatedAt: HLCTimestamp
    /// Tombstone flag.
    public var isDeleted: Bool
    /// Per-field clocks keyed by JSON field name; absent keys default to `updatedAt`.
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

    /// The effective clock of `field` (its entry in `fieldClocks`, else `updatedAt`).
    public func clock(for field: String) -> HLCTimestamp { fieldClocks[field] ?? updatedAt }
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
