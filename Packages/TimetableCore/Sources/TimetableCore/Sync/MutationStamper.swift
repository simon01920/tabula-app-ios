import Foundation

/// Stamps sync metadata onto a locally changed entity. **Every local mutation must go through it** (or
/// `delete`/`restore`); the merge relies on the metadata it writes.
///
/// `stamp(old:new:clock:now:)` compares `old` and `new` field by field through their JSON form (keys =
/// JSON keys, matching `EntityMeta.fieldClocks`) and issues **one** timestamp `t` for the whole mutation:
/// - every changed top-level key gets field clock `t`; unchanged keys keep their previous effective clock;
/// - `updatedAt = t`, `createdAt` is kept, `isDeleted` is taken from `new.meta.isDeleted`;
/// - because a missing field clock means "at `updatedAt`", raising `updatedAt` would silently move every
///   implicit clock forward. The stamper therefore first **materialises** the previous clock of every field
///   of the type (`EntityFieldCatalog`, including absent/nil fields and preserved unknown keys), then writes
///   the clocks canonically (entries equal to the new `updatedAt` are omitted);
/// - child records (`TaskItem.subtasks`/`.attachments`) are stamped the same way per child: new children are
///   created at `t`, changed ones get child field clocks, and children missing from `new` become
///   **tombstones** (kept in the array with `meta.isDeleted = true`) so that a merge cannot resurrect them.
///   UIs may pass arrays without tombstoned children; existing tombstones are carried over;
/// - all of `new.meta` except `isDeleted` is ignored (the stamper owns the metadata);
/// - no change at all returns `old` unchanged and does not tick the clock.
///
/// Causality: the issued timestamp is always greater than every clock in `old`. With a
/// `HybridLogicalClock` this is done by `receive` (the clock learns `old`'s clocks); with another
/// `TimestampClock` a timestamp that is not greater is bumped past `old` (same node).
public enum MutationStamper {
    /// Errors thrown by the stamper.
    public enum StamperError: Error, Hashable, Sendable {
        /// `old` and `new` have different IDs.
        case idMismatch
    }

    /// Stamps `new` (the edited version) against `old` (the stored version, `nil` when creating).
    ///
    /// - Parameter unknownFields: unknown keys preserved for this entity (`TabulaDatabase.unknownFields`),
    ///   so their clocks are materialised too.
    public static func stamp<E: SyncEntity, C: TimestampClock>(old: E?, new: E, clock: inout C, now: Date,
                                                                unknownFields: EntityUnknownFields? = nil) throws -> E {
        let type = E.entityType
        let collections = EntityFieldCatalog.childCollections(for: type)
        var newObject = try SyncJSON.object(new)

        guard let old else {
            let t = issue(&clock, now: now, after: nil)
            newObject["meta"] = SyncJSON.json(EntityMeta(createdAt: t, updatedAt: t, isDeleted: new.meta.isDeleted))
            for collection in collections.keys {
                guard case .array(let items)? = newObject[collection] else { continue }
                newObject[collection] = .array(try items.map { item in
                    var child = try record(item)
                    let deleted = try SyncJSON.meta(of: child).isDeleted
                    child["meta"] = SyncJSON.json(EntityMeta(createdAt: t, updatedAt: t, isDeleted: deleted))
                    return .object(child)
                })
            }
            return try SyncJSON.decode(newObject, as: E.self)
        }
        guard old.id == new.id else { throw StamperError.idMismatch }

        let oldObject = try SyncJSON.object(old)
        let oldMeta = old.meta
        var floor = SyncJSON.latest(in: oldMeta)

        // 1. Detect changes (no clock tick yet).
        var changedKeys = Set<String>()
        for key in Set(oldObject.keys).union(newObject.keys)
            where !EntityFieldCatalog.identityKeys.contains(key) && collections[key] == nil
            && oldObject[key] != newObject[key] {
            changedKeys.insert(key)
        }
        var plans: [String: [ChildPlan]] = [:]
        for collection in collections.keys {
            let plan = try planChildren(old: oldObject[collection], new: newObject[collection])
            plans[collection] = plan
            if plan.contains(where: \.isChange) { changedKeys.insert(collection) }
            for step in plan { floor = max(floor, step.floor) }
        }
        let deletionChanged = oldMeta.isDeleted != new.meta.isDeleted
        if changedKeys.isEmpty && !deletionChanged { return old }

        // 2. One timestamp for the whole mutation.
        let t = issue(&clock, now: now, after: floor)

        // 3. Children.
        for (collection, plan) in plans {
            let childFields = collections[collection] ?? []
            let childUnknown = unknownFields?.children[collection] ?? [:]
            newObject[collection] = .array(try plan.map { step in
                try .object(step.stamped(at: t, catalog: childFields, unknown: childUnknown))
            })
        }

        // 4. The entity itself.
        var keys = EntityFieldCatalog.fieldKeys(for: type)
        if let unknownFields { keys.formUnion(unknownFields.fields.keys) }
        keys.formUnion(oldObject.keys)
        keys.formUnion(newObject.keys)
        keys.formUnion(oldMeta.fieldClocks.keys)
        keys.subtract(EntityFieldCatalog.identityKeys)
        newObject["meta"] = SyncJSON.json(stampedMeta(oldMeta, keys: keys, changed: changedKeys,
                                                      isDeleted: new.meta.isDeleted, at: t))
        return try SyncJSON.decode(newObject, as: E.self)
    }

    /// Marks `entity` deleted (a tombstone stamped now).
    public static func delete<E: SyncEntity, C: TimestampClock>(_ entity: E, clock: inout C, now: Date,
                                                                 unknownFields: EntityUnknownFields? = nil) throws -> E {
        var deleted = entity
        deleted.meta.isDeleted = true
        return try stamp(old: entity, new: deleted, clock: &clock, now: now, unknownFields: unknownFields)
    }

    /// Restores a tombstoned `entity` (a liveness assertion stamped now, which wins over the delete).
    public static func restore<E: SyncEntity, C: TimestampClock>(_ entity: E, clock: inout C, now: Date,
                                                                  unknownFields: EntityUnknownFields? = nil) throws -> E {
        var restored = entity
        restored.meta.isDeleted = false
        return try stamp(old: entity, new: restored, clock: &clock, now: now, unknownFields: unknownFields)
    }

    // MARK: - Internals

    /// Issues the mutation timestamp, strictly after `floor` when given.
    static func issue<C: TimestampClock>(_ clock: inout C, now: Date, after floor: HLCTimestamp?) -> HLCTimestamp {
        guard let floor else { return clock.tick(now: now) }
        if var hlc = clock as? HybridLogicalClock {
            let t = hlc.receive(floor, now: now)
            if let back = hlc as? C { clock = back }
            return t
        }
        let t = clock.tick(now: now)
        guard t <= floor else { return t }
        if floor.logical < UInt32.max {
            return HLCTimestamp(physicalMillis: floor.physicalMillis, logical: floor.logical + 1, node: t.node)
        }
        return HLCTimestamp(physicalMillis: min(floor.physicalMillis + 1, HLCTimestamp.maxPhysicalMillis),
                            logical: 0, node: t.node)
    }

    /// The metadata after a mutation at `t`: changed keys at `t`, the others at their previous effective
    /// clock, written canonically.
    static func stampedMeta(_ old: EntityMeta, keys: Set<String>, changed: Set<String>, isDeleted: Bool,
                            at t: HLCTimestamp) -> EntityMeta {
        var clocks: [String: HLCTimestamp] = [:]
        for key in keys {
            let clock = changed.contains(key) ? t : old.clock(for: key)
            if clock != t { clocks[key] = clock }
        }
        return EntityMeta(createdAt: old.createdAt, updatedAt: t, isDeleted: isDeleted, fieldClocks: clocks)
    }

    private static func record(_ value: JSONValue) throws -> [String: JSONValue] {
        guard case .object(let object) = value else { throw SyncError.malformedRecord("child is not an object") }
        return object
    }

    /// What happens to one child record in a mutation.
    private enum ChildPlan {
        case unchanged([String: JSONValue])
        case created([String: JSONValue])
        case changed(old: [String: JSONValue], oldMeta: EntityMeta, new: [String: JSONValue],
                     keys: Set<String>, isDeleted: Bool)

        var isChange: Bool {
            if case .unchanged = self { return false }
            return true
        }

        var floor: HLCTimestamp {
            switch self {
            case .unchanged(let record): return (try? SyncJSON.latest(in: SyncJSON.meta(of: record))) ?? .zero
            case .created: return .zero
            case .changed(_, let oldMeta, _, _, _): return SyncJSON.latest(in: oldMeta)
            }
        }

        func stamped(at t: HLCTimestamp, catalog: Set<String>,
                     unknown: [UUID: [String: JSONValue]]) throws -> [String: JSONValue] {
            switch self {
            case .unchanged(let record):
                return record
            case .created(var record):
                let deleted = try SyncJSON.meta(of: record).isDeleted
                record["meta"] = SyncJSON.json(EntityMeta(createdAt: t, updatedAt: t, isDeleted: deleted))
                return record
            case let .changed(old, oldMeta, new, changedKeys, isDeleted):
                var record = new
                var keys = catalog.union(old.keys).union(new.keys).union(oldMeta.fieldClocks.keys)
                if let idString = new["id"]?.stringValue, let id = UUID(uuidString: idString),
                   let extra = unknown[id] {
                    keys.formUnion(extra.keys)
                }
                keys.subtract(EntityFieldCatalog.identityKeys)
                record["meta"] = SyncJSON.json(MutationStamper.stampedMeta(oldMeta, keys: keys, changed: changedKeys,
                                                                           isDeleted: isDeleted, at: t))
                return record
            }
        }
    }

    /// Diffs two child arrays by child `id`. Order of the result: `new`'s order, then tombstones.
    private static func planChildren(old: JSONValue?, new: JSONValue?) throws -> [ChildPlan] {
        var oldByID: [String: [String: JSONValue]] = [:]
        var oldOrder: [String] = []
        if case .array(let items)? = old {
            for item in items {
                let child = try record(item)
                let id = try SyncJSON.id(of: child)
                if oldByID[id] == nil { oldOrder.append(id) }
                oldByID[id] = child
            }
        }
        var plan: [ChildPlan] = []
        var seen = Set<String>()
        if case .array(let items)? = new {
            for item in items {
                let child = try record(item)
                let id = try SyncJSON.id(of: child)
                guard seen.insert(id).inserted else { continue }
                guard let previous = oldByID[id] else {
                    plan.append(.created(child))
                    continue
                }
                let oldMeta = try SyncJSON.meta(of: previous)
                let newDeleted = try SyncJSON.meta(of: child).isDeleted
                var changed = Set<String>()
                for key in Set(previous.keys).union(child.keys)
                    where !EntityFieldCatalog.identityKeys.contains(key) && previous[key] != child[key] {
                    changed.insert(key)
                }
                if changed.isEmpty && newDeleted == oldMeta.isDeleted {
                    plan.append(.unchanged(previous))
                } else {
                    plan.append(.changed(old: previous, oldMeta: oldMeta, new: child, keys: changed,
                                         isDeleted: newDeleted))
                }
            }
        }
        for id in oldOrder where !seen.contains(id) {
            guard let previous = oldByID[id] else { continue }
            let oldMeta = try SyncJSON.meta(of: previous)
            if oldMeta.isDeleted {
                plan.append(.unchanged(previous))      // existing tombstone, carried over
            } else {
                plan.append(.changed(old: previous, oldMeta: oldMeta, new: previous, keys: [], isDeleted: true))
            }
        }
        return plan
    }
}
