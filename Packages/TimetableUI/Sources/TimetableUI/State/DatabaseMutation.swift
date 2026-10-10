// The only way UI code changes the database (PHASE2_PLAN §0.4): views build a `DatabaseMutation` and hand it to
// `AppModel.apply(_:)`. Applying stamps sync metadata through `MutationStamper` with the app's
// `HybridLogicalClock`, so no screen can forget it. Pure value logic, Linux-tested.
//
// Typical use (feature code):
//   model.apply(.upsert(editedLesson))                   // create or edit any entity
//   model.apply(.delete(lesson.id))                       // tombstone
//   model.apply(.settings { $0.appearance = .dark })      // edit the settings singleton
//   model.apply(.batch([.upsert(subject), .upsert(lesson)], label: "quick add"))
//   model.apply(.replaceDatabase(label: "onboarding") { ids, clock, now in
//       OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: now) })
import Foundation
import TimetableCore

/// An entity type stored as one array of `TabulaDatabase`.
public protocol DatabaseStoredEntity: SyncEntity {
    /// The array holding this type.
    static var collection: WritableKeyPath<TabulaDatabase, [Self]> { get }
}

extension Timetable: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [Timetable]> { \.timetables } }
extension Subject: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [Subject]> { \.subjects } }
extension BellSchedule: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [BellSchedule]> { \.bellSchedules } }
extension Lesson: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [Lesson]> { \.lessons } }
extension Term: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [Term]> { \.terms } }
extension CalendarBreak: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [CalendarBreak]> { \.breaks } }
extension ScheduleOverride: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [ScheduleOverride]> { \.overrides } }
extension TaskItem: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [TaskItem]> { \.tasks } }
extension Exam: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [Exam]> { \.exams } }
extension ReminderRule: DatabaseStoredEntity { public static var collection: WritableKeyPath<TabulaDatabase, [ReminderRule]> { \.reminderRules } }

/// Errors of `DatabaseMutation.apply`.
public enum MutationError: Error, Equatable, Sendable {
    /// `delete` named an ID that is not in the database.
    case notFound(EntityType, UUID)
    /// The stamper rejected the change (e.g. an ID mismatch).
    case stampingFailed(String)
    /// `replaceDatabase` produced a database of another schema version.
    case unsupportedSchemaVersion(Int)
}

/// A change to the database, applied atomically by `AppModel.apply(_:)`.
public struct DatabaseMutation: Sendable {
    /// What the change does, for logs and the debug screen ("upsert lesson", "onboarding").
    public let label: String
    /// `true` when the mutation replaces the whole database (onboarding, debug sample loading).
    public let replacesDatabase: Bool
    private let step: @Sendable (inout TabulaDatabase, inout HybridLogicalClock, Date) throws -> Void

    init(label: String, replacesDatabase: Bool = false,
                 step: @escaping @Sendable (inout TabulaDatabase, inout HybridLogicalClock, Date) throws -> Void) {
        self.label = label
        self.replacesDatabase = replacesDatabase
        self.step = step
    }

    /// Creates `entity` (unknown ID) or replaces the stored entity with the same ID (stamped field by field).
    public static func upsert<E: DatabaseStoredEntity>(_ entity: E) -> DatabaseMutation {
        DatabaseMutation(label: "upsert \(E.entityType.rawValue)") { database, clock, now in
            let path = E.collection
            let index = database[keyPath: path].firstIndex { $0.id == entity.id }
            let old = index.map { database[keyPath: path][$0] }
            let stamped: E
            do {
                stamped = try MutationStamper.stamp(old: old, new: entity, clock: &clock, now: now)
            } catch {
                throw MutationError.stampingFailed(String(describing: error))
            }
            if let index {
                database[keyPath: path][index] = stamped
            } else {
                database[keyPath: path].append(stamped)
            }
        }
    }

    /// Tombstones the entity with `id` (kept in the database with `meta.isDeleted`, as sync requires).
    public static func delete<E: DatabaseStoredEntity>(_ id: EntityID<E>) -> DatabaseMutation {
        DatabaseMutation(label: "delete \(E.entityType.rawValue)") { database, clock, now in
            let path = E.collection
            guard let index = database[keyPath: path].firstIndex(where: { $0.id == id }) else {
                throw MutationError.notFound(E.entityType, id.uuid)
            }
            do {
                database[keyPath: path][index] = try MutationStamper.delete(database[keyPath: path][index],
                                                                            clock: &clock, now: now)
            } catch {
                throw MutationError.stampingFailed(String(describing: error))
            }
        }
    }

    /// Edits the settings singleton.
    public static func settings(_ edit: @escaping @Sendable (inout AppSettings) -> Void) -> DatabaseMutation {
        DatabaseMutation(label: "settings") { database, clock, now in
            var edited = database.settings
            edit(&edited)
            do {
                database.settings = try MutationStamper.stamp(old: database.settings, new: edited, clock: &clock, now: now)
            } catch {
                throw MutationError.stampingFailed(String(describing: error))
            }
        }
    }

    /// Several mutations as one (all or nothing).
    public static func batch(_ mutations: [DatabaseMutation], label: String = "batch") -> DatabaseMutation {
        DatabaseMutation(label: label, replacesDatabase: mutations.contains(where: \.replacesDatabase)) {
            database, clock, now in
            for mutation in mutations { try mutation.step(&database, &clock, now) }
        }
    }

    /// Replaces the whole database with one built (and stamped) by `build` — onboarding
    /// (`OnboardingBuilder.makeInitialDatabase`) or loading sample data. `build` must stamp with the given clock.
    public static func replaceDatabase(
        label: String,
        _ build: @escaping @Sendable (inout SystemIDGenerator, inout HybridLogicalClock, Date) -> TabulaDatabase
    ) -> DatabaseMutation {
        DatabaseMutation(label: label, replacesDatabase: true) { database, clock, now in
            var ids = SystemIDGenerator()
            let built = build(&ids, &clock, now)
            guard built.schemaVersion == TabulaDatabase.currentSchemaVersion else {
                throw MutationError.unsupportedSchemaVersion(built.schemaVersion)
            }
            // The clock must stay ahead of everything in the new data (it may carry foreign timestamps).
            clock.receive(built.latestTimestamp, now: now)
            database = built
        }
    }

    /// Applies the mutation to a copy of `database`. On error `database` and `clock` keep their input values.
    public func apply(to database: TabulaDatabase, clock: inout HybridLogicalClock, now: Date) throws(MutationError) -> TabulaDatabase {
        var copy = database
        var clockCopy = clock
        do {
            try step(&copy, &clockCopy, now)
        } catch let error as MutationError {
            throw error
        } catch {
            throw .stampingFailed(String(describing: error))
        }
        clock = clockCopy
        return copy
    }

    /// The database a replacing mutation starts from when nothing is stored yet (first launch).
    public static var emptyBase: TabulaDatabase { TabulaDatabase(settings: .untouchedDefaults) }
}
