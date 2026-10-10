// Edit state of the timetable settings editor: name, emoji, days, rotation (none / day cycle / week cycle with strict or
// continuous parity or a reference week), time structure, field visibility, default view, density and palette.
// Pure, Linux-tested.
//
// Guards derived from the data model's validation (errors reject the whole change, so the editor prevents them):
// - day cycle <-> weekdays: lessons use `.weekday` keys without a day cycle and `.cycleDay` keys with one, so the
//   kind of rotation cannot switch between "day cycle" and "none/week cycle" while the timetable has lessons.
// - a cycle cannot become shorter than the highest cycle day / week its lessons use.
import Foundation
import TimetableCore

/// The timetable editor's state.
public struct TimetableDraft: Equatable, Sendable {
    /// The kind of rotation.
    public enum RotationKind: String, Equatable, Sendable, CaseIterable { case none, dayCycle, weekCycle }

    /// How a week cycle is anchored.
    public enum AnchorKind: String, Equatable, Sendable, CaseIterable { case strictParity, continuousParity, referenceWeek }

    /// Fixed or bell-schedule based lesson times.
    public enum TimeKind: String, Equatable, Sendable, CaseIterable { case bellSchedule, freeForm }

    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable, CaseIterable {
        case noName
        case noDays
        case noSchoolDays

        /// Catalog key of the explanation.
        public var l10nKey: String { "editor.timetable.issue.\(rawValue)" }
    }

    public let timetableID: Timetable.ID
    public var name: String
    public var emoji: String
    public var enabledDays: Set<Weekday>
    public var rotationKind: RotationKind
    public var rotationWeekStart: Weekday
    // Week cycle
    public var weekLength: Int
    public var anchorKind: AnchorKind
    public var parityOffset: Int
    public var referenceDate: LocalDate
    public var referenceWeek: Int
    public var weekLabels: [String]
    // Day cycle
    public var dayLength: Int
    public var dayAnchorDate: LocalDate
    public var dayAnchorIndex: Int
    public var daySchoolDays: Set<Weekday>
    public var daySkipsBreaks: Bool
    public var dayLabels: [String]
    // Time structure
    public var timeKind: TimeKind
    public var freeMinutes: Int
    // Presentation
    public var visibleFields: Set<LessonField>
    public var defaultView: TimetableViewKind
    public var density: Density
    /// `nil` = the app-wide palette pack.
    public var palettePackID: PalettePackID?
    private let base: Timetable

    /// Edits `timetable`. `today` seeds anchor dates of rotations that have none yet.
    public init(timetable: Timetable, today: LocalDate) {
        base = timetable
        timetableID = timetable.id
        name = timetable.name
        emoji = timetable.emoji ?? ""
        enabledDays = timetable.enabledDays
        rotationWeekStart = timetable.rotationWeekStart
        var kind = RotationKind.none
        var weekLength = 2, anchorKind = AnchorKind.strictParity, parityOffset = 0, referenceDate = today, referenceWeek = 1
        var weekLabels: [String] = []
        var dayLength = 2, dayAnchorDate = today, dayAnchorIndex = 1, daySchoolDays = Weekday.workweek,
            daySkipsBreaks = true
        var dayLabels: [String] = []
        switch timetable.rotation {
        case .none:
            break
        case .weekCycle(let cycle):
            kind = .weekCycle
            weekLength = cycle.length
            weekLabels = cycle.labels ?? []
            switch cycle.anchor {
            case let .isoWeekParity(policy, offset):
                anchorKind = policy.effective == .continuous ? .continuousParity : .strictParity
                parityOffset = offset
            case let .referenceWeek(date, week):
                anchorKind = .referenceWeek
                referenceDate = date
                referenceWeek = week
            }
        case .dayCycle(let cycle):
            kind = .dayCycle
            dayLength = cycle.length
            dayAnchorDate = cycle.anchorDate
            dayAnchorIndex = cycle.anchorIndex
            daySchoolDays = cycle.schoolDays
            daySkipsBreaks = cycle.skipsBreaks
            dayLabels = cycle.labels ?? []
        }
        rotationKind = kind
        self.weekLength = weekLength
        self.anchorKind = anchorKind
        self.parityOffset = parityOffset
        self.referenceDate = referenceDate
        self.referenceWeek = referenceWeek
        self.weekLabels = weekLabels
        self.dayLength = dayLength
        self.dayAnchorDate = dayAnchorDate
        self.dayAnchorIndex = dayAnchorIndex
        self.daySchoolDays = daySchoolDays
        self.daySkipsBreaks = daySkipsBreaks
        self.dayLabels = dayLabels
        switch timetable.timeStructure {
        case .bellSchedule:
            timeKind = .bellSchedule
            freeMinutes = 45
        case .freeForm(let minutes):
            timeKind = .freeForm
            freeMinutes = minutes
        }
        visibleFields = timetable.fieldVisibility.visibleFields
        defaultView = timetable.defaultView
        density = timetable.density
        palettePackID = timetable.palettePackID
    }

    // MARK: Rules

    /// Can the rotation switch between a day cycle and weekdays? (Not while lessons exist.)
    public static func canChangeRotationFamily(lessonCount: Int) -> Bool { lessonCount == 0 }

    /// `true` when the rotation kinds are in different families (day-cycle keys vs weekday keys).
    public static func isFamilyChange(from old: RotationKind, to new: RotationKind) -> Bool {
        (old == .dayCycle) != (new == .dayCycle)
    }

    /// The shortest length of a day cycle that still holds every cycle day used by `lessons`.
    public static func minimumDayCycleLength(lessons: [Lesson], timetableID: Timetable.ID) -> Int {
        var highest = DayCycle.validLengths.lowerBound
        for lesson in lessons where !lesson.isDeleted && lesson.timetableID == timetableID {
            if case .cycleDay(let index) = lesson.occurrence.day { highest = max(highest, index) }
        }
        return min(highest, DayCycle.validLengths.upperBound)
    }

    /// The shortest length of a week cycle that still holds every week used by `lessons`.
    public static func minimumWeekCycleLength(lessons: [Lesson], timetableID: Timetable.ID) -> Int {
        var highest = WeekCycle.validLengths.lowerBound
        for lesson in lessons where !lesson.isDeleted && lesson.timetableID == timetableID {
            highest = max(highest, lesson.occurrence.cycleWeeks?.max() ?? 0)
        }
        return min(highest, WeekCycle.validLengths.upperBound)
    }

    /// Problems that block saving.
    public var issues: [Issue] {
        var found: [Issue] = []
        if EditorText.trimmedOrNil(name) == nil { found.append(.noName) }
        if enabledDays.isEmpty { found.append(.noDays) }
        if rotationKind == .dayCycle && daySchoolDays.isEmpty { found.append(.noSchoolDays) }
        return found
    }

    /// `true` when nothing blocks saving.
    public var canSave: Bool { issues.isEmpty }

    /// The rotation scheme to store (labels are dropped when blank).
    public var rotation: RotationScheme {
        func cleaned(_ labels: [String], length: Int) -> [String]? {
            let padded = (0..<length).map { labels.indices.contains($0) ? labels[$0].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            return padded.allSatisfy(\.isEmpty) ? nil : padded
        }
        switch rotationKind {
        case .none:
            return .none
        case .weekCycle:
            let anchor: WeekCycleAnchor
            switch anchorKind {
            case .strictParity: anchor = .isoWeekParity(policy: .strict, offset: parityOffset)
            case .continuousParity: anchor = .isoWeekParity(policy: .continuous, offset: parityOffset)
            case .referenceWeek: anchor = .referenceWeek(date: referenceDate, cycleWeek: min(max(1, referenceWeek), weekLength))
            }
            return .weekCycle(WeekCycle(length: weekLength, anchor: anchor, labels: cleaned(weekLabels, length: weekLength)))
        case .dayCycle:
            return .dayCycle(DayCycle(length: dayLength, anchorDate: dayAnchorDate,
                                      anchorIndex: min(max(1, dayAnchorIndex), dayLength), schoolDays: daySchoolDays,
                                      skipsBreaks: daySkipsBreaks, labels: cleaned(dayLabels, length: dayLength)))
        }
    }

    /// The timetable to store. `timeStructure` is computed by the caller (it may need new bell schedules).
    public func makeTimetable(timeStructure: TimeStructure) -> Timetable? {
        guard let trimmedName = EditorText.trimmedOrNil(name) else { return nil }
        var timetable = base
        timetable.name = trimmedName
        timetable.emoji = EditorText.firstCharacter(emoji)
        timetable.enabledDays = enabledDays
        timetable.rotation = rotation
        timetable.rotationWeekStart = rotationWeekStart
        timetable.timeStructure = timeStructure
        timetable.fieldVisibility = FieldVisibility(visibleFields)
        timetable.defaultView = defaultView
        timetable.density = density
        timetable.palettePackID = palettePackID
        return timetable
    }

    /// The time structure for the chosen kind: kept as stored when the kind did not change, a new default schedule
    /// (with its mutation) when switching to bell schedules without an existing one.
    public func resolveTimeStructure<G: IDGenerator>(existingSchedules: [BellSchedule], scheduleName: String,
                                                      ids: inout G) -> (structure: TimeStructure, extra: [DatabaseMutation]) {
        switch timeKind {
        case .freeForm:
            return (.freeForm(defaultDurationMinutes: min(max(1, freeMinutes), LocalTime.minutesPerDay - 1)), [])
        case .bellSchedule:
            if case .bellSchedule = base.timeStructure { return (base.timeStructure, []) }
            if let existing = existingSchedules.first(where: { !$0.isDeleted && $0.timetableID == timetableID }) {
                return (.bellSchedule(defaultID: existing.id, perWeekday: [:]), [])
            }
            let periods = BellScheduleTemplate.secondary.lessonTimes().map { slot -> Period in
                Period(id: ids.next(), label: nil, start: slot.start, end: slot.end, kind: .lesson)
            }
            let scheduleID: BellSchedule.ID = ids.next()
            let schedule = BellSchedule(id: scheduleID, meta: EditorEntities.placeholderMeta, timetableID: timetableID,
                                        name: scheduleName, periods: periods)
            return (.bellSchedule(defaultID: scheduleID, perWeekday: [:]), [.upsert(schedule)])
        }
    }
}
