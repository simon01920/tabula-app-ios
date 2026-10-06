import Foundation

// Stage 2B result types that complement `Model/ScheduleTypes.swift` (which Stage 1 froze for Stage 2C).
// Derived, never persisted; `Codable` only for snapshots and debugging.

/// Which layers of the schedule a resolution applies.
public struct ResolutionOptions: Hashable, Sendable, Codable {
    /// Calendar breaks remove regular lessons (and pause day cycles with `skipsBreaks`, which happens
    /// regardless of this flag because the rotation is calendar data).
    public var appliesBreaks: Bool
    /// One-off overrides (`ScheduleOverride`) are applied.
    public var appliesOverrides: Bool
    /// `Lesson.validity` (terms, date ranges) is applied.
    public var appliesValidity: Bool

    /// Creates options.
    public init(appliesBreaks: Bool, appliesOverrides: Bool, appliesValidity: Bool) {
        self.appliesBreaks = appliesBreaks
        self.appliesOverrides = appliesOverrides
        self.appliesValidity = appliesValidity
    }

    /// What actually happens on a date (default for every consumer: Today, widgets, reminders).
    public static let actual = ResolutionOptions(appliesBreaks: true, appliesOverrides: true, appliesValidity: true)
    /// The regular timetable of the date: rotation, enabled days, bell schedules and validity, but no
    /// holidays and no one-off changes (timetable editor, "Week A/B" templates during holidays).
    public static let regular = ResolutionOptions(appliesBreaks: false, appliesOverrides: false, appliesValidity: true)
    /// Every recurring lesson of the day key, ignoring breaks, overrides and validity.
    public static let allLessons = ResolutionOptions(appliesBreaks: false, appliesOverrides: false, appliesValidity: false)
}

/// Why an occurrence differs from the regular timetable (drives "Room changed"/"Substitute" badges).
///
/// Computed by comparing the occurrence with how the same lesson would look on that date without overrides
/// (natural bell schedule, no patch). A `followDay` alone never produces a reason.
public enum ModificationReason: String, Hashable, Comparable, Sendable, Codable, CaseIterable {
    /// Start or end time differs (`useBellSchedule`, or a patched slot).
    case timeChanged
    /// Substitute subject.
    case subjectChanged
    /// Effective room differs.
    case roomChanged
    /// Effective building differs.
    case buildingChanged
    /// Effective teacher differs (substitute teacher).
    case teacherChanged
    /// Effective lesson type differs.
    case lessonTypeChanged
    /// Effective notes differ.
    case notesChanged
    /// Effective bring-list differs.
    case bringListChanged

    /// Catalog key (`schedule.change.<reason>`).
    public var l10nKey: String { "schedule.change.\(rawValue)" }

    public static func < (lhs: ModificationReason, rhs: ModificationReason) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// The modification reasons of one occurrence.
public struct OccurrenceChanges: Hashable, Sendable, Codable {
    /// The occurrence.
    public var occurrenceID: OccurrenceID
    /// Reasons, in `ModificationReason.allCases` order; never empty.
    public var reasons: [ModificationReason]

    /// Creates a change record (`reasons` are sorted and de-duplicated).
    public init(occurrenceID: OccurrenceID, reasons: [ModificationReason]) {
        self.occurrenceID = occurrenceID
        self.reasons = Array(Set(reasons)).sorted()
    }
}

/// A non-fatal problem met while resolving a date. Warnings never block; the user-visible subset is also
/// reported as `Conflict`s on `DaySchedule` (period not in schedule, span, missing subject, time range).
public struct ResolutionWarning: Hashable, Sendable, Codable {
    /// What happened.
    public enum Kind: String, Hashable, Sendable, Codable, CaseIterable {
        /// A period slot could not be placed (ID absent from the applicable schedule and no ordinal fallback,
        /// or no bell schedule at all); the occurrence is omitted.
        case periodNotInSchedule
        /// Informational: the period ID was absent from the applicable schedule, so the occurrence was placed
        /// at the same ordinal among periods of the same kind (PHASE1_PLAN decision 1).
        case periodMappedByOrdinal
        /// The span ran past the last lesson period; the occurrence was shortened to the periods that exist.
        case spanExceedsSchedule
        /// A bell schedule referenced by the timetable or a `useBellSchedule` override does not exist
        /// (deleted, dangling or from another timetable); the natural schedule is used where possible.
        case missingBellSchedule
        /// A subject is missing: a lesson or one-off is omitted; a patch's substitute subject is ignored.
        case missingSubject
        /// The slot's end is not after its start; the occurrence is omitted.
        case invalidTimeRange
        /// A `followDay` or `useBellSchedule` override lost to a later one on the same date.
        case supersededOverride
        /// `cancelLesson`/`modifyLesson` targets a lesson that does not occur on that date; ignored.
        case overrideTargetNotScheduled
        /// A `followDay` key does not match the rotation (weekday key with a day cycle or the reverse); the
        /// date then has no regular lessons.
        case followDayKindMismatch
        /// An override kind from a newer app version; ignored (and preserved by the store).
        case unknownOverride

        /// Catalog key (`schedule.warning.<kind>`).
        public var l10nKey: String { "schedule.warning.\(rawValue)" }
    }

    /// What happened.
    public var kind: Kind
    /// Date resolved.
    public var date: LocalDate
    /// Affected occurrence, if any.
    public var occurrenceID: OccurrenceID?
    /// Affected recurring lesson, if any.
    public var lessonID: Lesson.ID?
    /// Override involved, if any.
    public var overrideID: ScheduleOverride.ID?
    /// Winning override (for `supersededOverride`).
    public var supersededByID: ScheduleOverride.ID?
    /// Period involved, if any.
    public var periodID: Period.ID?
    /// Bell schedule involved, if any.
    public var bellScheduleID: BellSchedule.ID?
    /// Subject involved, if any.
    public var subjectID: Subject.ID?

    /// Creates a warning.
    public init(kind: Kind, date: LocalDate, occurrenceID: OccurrenceID? = nil, lessonID: Lesson.ID? = nil,
                overrideID: ScheduleOverride.ID? = nil, supersededByID: ScheduleOverride.ID? = nil,
                periodID: Period.ID? = nil, bellScheduleID: BellSchedule.ID? = nil, subjectID: Subject.ID? = nil) {
        self.kind = kind
        self.date = date
        self.occurrenceID = occurrenceID
        self.lessonID = lessonID
        self.overrideID = overrideID
        self.supersededByID = supersededByID
        self.periodID = periodID
        self.bellScheduleID = bellScheduleID
        self.subjectID = subjectID
    }

    /// Localisable message (`schedule.warning.<kind>`, no arguments).
    public var message: LocalizedText { LocalizedText(key: kind.l10nKey) }
}

/// The full result of resolving one date: the `DaySchedule` plus what the frozen result type has no room
/// for (natural rotation position, applied day-level overrides, modification reasons, warnings).
public struct DayResolution: Hashable, Sendable, Codable {
    /// The day's schedule.
    public var schedule: DaySchedule
    /// Day key from rotation and enabled weekdays alone, before breaks and overrides (`nil` when the
    /// weekday is not enabled or a day cycle does not advance on the date).
    public var naturalDayKey: DayKey?
    /// Cycle week before a `followDay` (week cycles only).
    public var naturalCycleWeek: Int?
    /// The `followDay` override in effect, if any.
    public var followDayOverrideID: ScheduleOverride.ID?
    /// The `useBellSchedule` override in effect, if any.
    public var bellScheduleOverrideID: ScheduleOverride.ID?
    /// Modification reasons of `.modified` (and patched `.cancelled`) occurrences, ascending by occurrence ID.
    public var changes: [OccurrenceChanges]
    /// Problems met, in a deterministic order.
    public var warnings: [ResolutionWarning]

    /// Creates a resolution.
    public init(schedule: DaySchedule, naturalDayKey: DayKey? = nil, naturalCycleWeek: Int? = nil,
                followDayOverrideID: ScheduleOverride.ID? = nil, bellScheduleOverrideID: ScheduleOverride.ID? = nil,
                changes: [OccurrenceChanges] = [], warnings: [ResolutionWarning] = []) {
        self.schedule = schedule
        self.naturalDayKey = naturalDayKey
        self.naturalCycleWeek = naturalCycleWeek
        self.followDayOverrideID = followDayOverrideID
        self.bellScheduleOverrideID = bellScheduleOverrideID
        self.changes = changes
        self.warnings = warnings
    }

    /// The modification reasons of `occurrenceID` (empty when unchanged).
    public func reasons(for occurrenceID: OccurrenceID) -> [ModificationReason] {
        changes.first { $0.occurrenceID == occurrenceID }?.reasons ?? []
    }
}

/// String Catalog keys emitted by the schedule engine (Stage 2B): modification badges and resolution warnings.
/// None takes arguments. Listed in DOMAIN_MODEL Appendix A.7 and in `Resources/Localizable.xcstrings`.
public enum ScheduleL10n {
    /// Every key: `schedule.change.<reason>` then `schedule.warning.<kind>`, in declaration order.
    public static var allKeys: [String] {
        ModificationReason.allCases.map(\.l10nKey) + ResolutionWarning.Kind.allCases.map(\.l10nKey)
    }
}
