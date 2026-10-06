import Foundation

/// A named set of periods (e.g. "Normal day", "Short Friday") belonging to one timetable.
///
/// **Period-ID convention:** lessons reference periods by `Period.ID`. A variant schedule of the same
/// timetable (short day, exam day) is created by copying the default schedule *including its period IDs*
/// and changing the times, so a lesson in "period 3" lands in period 3 of whichever schedule applies.
/// Period IDs are therefore unique **within** a schedule, not across schedules.
/// For merge purposes the whole `periods` array is one field.
public struct BellSchedule: SyncEntity {
    public typealias ID = EntityID<BellSchedule>
    public static let entityType: EntityType = .bellSchedule

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Owning timetable.
    public var timetableID: Timetable.ID
    /// Name (user text).
    public var name: String
    /// Periods, ascending by start time; must not overlap.
    public var periods: [Period]

    /// Creates a bell schedule.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID, name: String, periods: [Period]) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.name = name
        self.periods = periods
    }

    /// Periods of kind `.lesson`, ascending by start.
    public var lessonPeriods: [Period] {
        periods.filter { $0.kind == .lesson }.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// The period with `id`, if present.
    public func period(_ id: Period.ID) -> Period? { periods.first { $0.id == id } }
}

/// One period of a bell schedule. Not a sync entity: it is part of `BellSchedule.periods`.
public struct Period: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<Period>

    /// Identifier, unique within its schedule and shared with corresponding periods of variant schedules.
    public var id: ID
    /// Optional label (user text, e.g. "0" or "Zero hour"); `nil` → the UI numbers lesson periods 1, 2, ….
    public var label: String?
    /// Start (wall clock).
    public var start: LocalTime
    /// End (wall clock); must be after `start` (periods never span midnight).
    public var end: LocalTime
    /// Lesson, break or lunch.
    public var kind: PeriodKind

    /// Creates a period.
    public init(id: ID, label: String? = nil, start: LocalTime, end: LocalTime, kind: PeriodKind = .lesson) {
        self.id = id
        self.label = label
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// Length in minutes (≤ 0 for an invalid period).
    public var durationMinutes: Int { start.minutes(to: end) }
}
