import Foundation

// Result types of the schedule engine (Stage 2B) — defined here so Stage 2C (reminders), widgets and the
// watch snapshot can depend on them before the resolver exists. These are **derived, not persisted** in
// the database. They are `Codable` (synthesised) for widget/watch snapshots, which are versioned separately.

/// Deterministic identifier of one lesson occurrence.
///
/// - Recurring lesson on a date: `"lesson:<LESSON-UUID>:<yyyy-MM-dd>"` — stable across re-resolution,
///   patches (`modifyLesson` keeps the ID) and app restarts.
/// - One-off lesson from an override: `"override:<OVERRIDE-UUID>"`.
/// Notification identifiers and widget entries derive from it, so the format must never change.
public struct OccurrenceID: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The canonical string.
    public let rawValue: String

    /// Wraps a raw value (use the factories for new IDs).
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The occurrence of recurring `lessonID` on `date`.
    public static func lesson(_ lessonID: Lesson.ID, on date: LocalDate) -> OccurrenceID {
        OccurrenceID(rawValue: "lesson:\(lessonID.uuidString):\(date.isoString)")
    }

    /// The one-off lesson added by override `overrideID`.
    public static func oneOff(_ overrideID: ScheduleOverride.ID) -> OccurrenceID {
        OccurrenceID(rawValue: "override:\(overrideID.uuidString)")
    }

    public static func < (lhs: OccurrenceID, rhs: OccurrenceID) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Same as `rawValue`.
    public var description: String { rawValue }

    /// Single-value string coding.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// Single-value string coding.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The subject fields a resolved lesson needs for display without a database lookup (widgets, watch).
public struct SubjectSummary: Hashable, Sendable, Codable {
    /// Subject ID.
    public var id: Subject.ID
    /// Full name.
    public var name: String
    /// Short name, if any.
    public var shortName: String?
    /// Colour.
    public var color: ColorValue
    /// Symbol, if any.
    public var symbol: SubjectSymbol?

    /// Creates a summary.
    public init(id: Subject.ID, name: String, shortName: String? = nil, color: ColorValue, symbol: SubjectSymbol? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.color = color
        self.symbol = symbol
    }

    /// The summary of `subject`.
    public init(_ subject: Subject) {
        self.init(id: subject.id, name: subject.name, shortName: subject.shortName, color: subject.color,
                  symbol: subject.symbol)
    }
}

/// One concrete lesson on one date, after rotation, validity, breaks, overrides, bell schedules and subject
/// defaults have been applied.
public struct ResolvedLesson: Identifiable, Hashable, Sendable, Codable {
    /// Lifecycle of the occurrence on its date.
    public enum Status: String, Hashable, Sendable, Codable, CaseIterable {
        /// As in the regular timetable.
        case scheduled
        /// Changed by a `modifyLesson` override (or moved by `useBellSchedule`/`followDay` only if 2B decides so).
        case modified
        /// A one-off lesson from an `addLesson` override.
        case added
        /// Cancelled by `cancelLesson` or `cancelDay`; kept so the UI can show it struck through.
        case cancelled
    }

    /// Where the occurrence comes from.
    public enum Source: Hashable, Sendable, Codable {
        /// A recurring `Lesson`.
        case lesson(Lesson.ID)
        /// An `addLesson` override.
        case oneOff(ScheduleOverride.ID)
    }

    /// Deterministic occurrence ID.
    public var id: OccurrenceID
    /// Origin.
    public var source: Source
    /// Timetable.
    public var timetableID: Timetable.ID
    /// Date (wall-clock).
    public var date: LocalDate
    /// Subject after patches.
    public var subject: SubjectSummary
    /// Start (wall-clock).
    public var startTime: LocalTime
    /// End (wall-clock).
    public var endTime: LocalTime
    /// Start instant in the `CalendarContext` used for resolution.
    public var start: Date
    /// End instant in the `CalendarContext` used for resolution.
    public var end: Date
    /// First period, when slotted by period.
    public var periodID: Period.ID?
    /// The period's user label, if any.
    public var periodLabel: String?
    /// 1-based number among the schedule's lesson periods (for "3rd period" display), if slotted by period.
    public var periodNumber: Int?
    /// Number of lesson periods covered, if slotted by period.
    public var periodSpan: Int?
    /// Effective room (lesson → patch → subject default); `nil` = absent.
    public var room: String?
    /// Effective building.
    public var building: String?
    /// Effective teacher.
    public var teacher: String?
    /// Effective lesson type.
    public var lessonType: LessonType?
    /// Effective notes.
    public var notes: String?
    /// Effective bring-list.
    public var bringList: [String]
    /// Status on this date.
    public var status: Status
    /// Overrides that affected this occurrence, ascending by ID.
    public var appliedOverrideIDs: [ScheduleOverride.ID]

    /// Creates a resolved lesson.
    public init(id: OccurrenceID, source: Source, timetableID: Timetable.ID, date: LocalDate,
                subject: SubjectSummary, startTime: LocalTime, endTime: LocalTime, start: Date, end: Date,
                periodID: Period.ID? = nil, periodLabel: String? = nil, periodNumber: Int? = nil,
                periodSpan: Int? = nil, room: String? = nil, building: String? = nil, teacher: String? = nil,
                lessonType: LessonType? = nil, notes: String? = nil, bringList: [String] = [],
                status: Status = .scheduled, appliedOverrideIDs: [ScheduleOverride.ID] = []) {
        self.id = id
        self.source = source
        self.timetableID = timetableID
        self.date = date
        self.subject = subject
        self.startTime = startTime
        self.endTime = endTime
        self.start = start
        self.end = end
        self.periodID = periodID
        self.periodLabel = periodLabel
        self.periodNumber = periodNumber
        self.periodSpan = periodSpan
        self.room = room
        self.building = building
        self.teacher = teacher
        self.lessonType = lessonType
        self.notes = notes
        self.bringList = bringList
        self.status = status
        self.appliedOverrideIDs = appliedOverrideIDs
    }

    /// The occurrence's instants as an interval.
    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

/// A schedule problem on one date. Conflicts warn; they never block (PRODUCT.md).
public struct Conflict: Hashable, Sendable, Codable {
    /// What is wrong.
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        /// Two or more occurrences overlap in time.
        case overlap
        /// The lesson's period does not exist in the bell schedule that applies on this date.
        case periodNotInSchedule
        /// The period span runs past the last lesson period of the applicable schedule.
        case spanExceedsSchedule
        /// The (patched) subject does not exist or is deleted.
        case missingSubject
        /// End is not after start (after patches / schedule changes).
        case invalidTimeRange

        /// Catalog key of the message.
        public var l10nKey: String { "conflict.\(rawValue)" }
    }

    /// Kind of problem.
    public var kind: Kind
    /// Date.
    public var date: LocalDate
    /// Affected occurrences, ascending (an occurrence may be absent from `DaySchedule.entries` when it
    /// could not be placed).
    public var occurrenceIDs: [OccurrenceID]

    /// Creates a conflict (`occurrenceIDs` are sorted).
    public init(kind: Kind, date: LocalDate, occurrenceIDs: [OccurrenceID]) {
        self.kind = kind
        self.date = date
        self.occurrenceIDs = occurrenceIDs.sorted()
    }

    /// Localisable message (`conflict.<kind>`, argument: number of occurrences).
    public var message: LocalizedText {
        LocalizedText(key: kind.l10nKey, args: [.integer(occurrenceIDs.count)])
    }
}

/// The resolved schedule of one timetable on one date.
public struct DaySchedule: Hashable, Sendable, Codable {
    /// Date.
    public var date: LocalDate
    /// Timetable.
    public var timetableID: Timetable.ID
    /// The day key the date resolved to (after `followDay`); `nil` when not a school day.
    public var dayKey: DayKey?
    /// 1-based week of a week cycle, if the timetable has one.
    public var cycleWeek: Int?
    /// User label of the cycle week/day, if defined (`nil` → the UI derives "A"/"B"/"Day 3").
    public var cycleLabel: String?
    /// `true` when lessons can take place (enabled weekday, not in a break, not cancelled).
    public var isSchoolDay: Bool
    /// The break covering this date, if any.
    public var activeBreakID: CalendarBreak.ID?
    /// The `cancelDay` override, if the whole day is cancelled.
    public var cancellingOverrideID: ScheduleOverride.ID?
    /// Bell schedule used (after `useBellSchedule`), if any.
    public var bellScheduleID: BellSchedule.ID?
    /// Term containing the date, if any.
    public var termID: Term.ID?
    /// Occurrences sorted by start, then end, then ID (cancelled ones included, flagged by status).
    public var entries: [ResolvedLesson]
    /// Problems found on this date.
    public var conflicts: [Conflict]

    /// Creates a day schedule.
    public init(date: LocalDate, timetableID: Timetable.ID, dayKey: DayKey? = nil, cycleWeek: Int? = nil,
                cycleLabel: String? = nil, isSchoolDay: Bool, activeBreakID: CalendarBreak.ID? = nil,
                cancellingOverrideID: ScheduleOverride.ID? = nil, bellScheduleID: BellSchedule.ID? = nil,
                termID: Term.ID? = nil, entries: [ResolvedLesson] = [], conflicts: [Conflict] = []) {
        self.date = date
        self.timetableID = timetableID
        self.dayKey = dayKey
        self.cycleWeek = cycleWeek
        self.cycleLabel = cycleLabel
        self.isSchoolDay = isSchoolDay
        self.activeBreakID = activeBreakID
        self.cancellingOverrideID = cancellingOverrideID
        self.bellScheduleID = bellScheduleID
        self.termID = termID
        self.entries = entries
        self.conflicts = conflicts
    }
}

/// "Now & Next" at an instant: the current lesson with remaining time, the next lesson and the gap state.
public struct NowNext: Hashable, Sendable, Codable {
    /// Where `at` falls relative to the day's lessons.
    public enum State: Hashable, Sendable, Codable {
        /// Inside `current`.
        case inLesson
        /// Between two lessons of the same day (a break or free period).
        case betweenLessons
        /// Before the first lesson of the day.
        case beforeFirstLesson
        /// After the last lesson of the day.
        case afterLastLesson
        /// No lessons today (weekend, cancelled day, empty day).
        case noLessonsToday
        /// Inside a calendar break (holidays).
        case inBreak(CalendarBreak.ID)
    }

    /// The instant evaluated.
    public var at: Date
    /// Lesson in progress (not cancelled), if any.
    public var current: ResolvedLesson?
    /// Seconds until `current` ends.
    public var remaining: TimeInterval?
    /// Next non-cancelled lesson (may be on a later day), if any within the resolver's horizon.
    public var next: ResolvedLesson?
    /// Seconds until `next` starts.
    public var untilNext: TimeInterval?
    /// Gap/break state.
    public var state: State

    /// Creates a now/next value.
    public init(at: Date, current: ResolvedLesson? = nil, remaining: TimeInterval? = nil,
                next: ResolvedLesson? = nil, untilNext: TimeInterval? = nil, state: State) {
        self.at = at
        self.current = current
        self.remaining = remaining
        self.next = next
        self.untilNext = untilNext
        self.state = state
    }
}
