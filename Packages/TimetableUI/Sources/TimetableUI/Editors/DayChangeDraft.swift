// Edit state of "Change for this day": builds one `ScheduleOverride` of a chosen kind for one date. Pure, Linux-tested.
// The data model applies several overrides on one date in a fixed order (follow day, bell schedule, then the
// per-lesson ones), so each kind is a separate override and the editor can be used repeatedly for the same day.
import Foundation
import TimetableCore

/// The day-change editor's state.
public struct DayChangeDraft: Equatable, Sendable {
    /// What to change.
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case cancelLesson
        case changeLesson
        case cancelDay
        case shortDay
        case followDay
        case extraLesson

        /// Catalog key of the kind's name.
        public var l10nKey: String { "editor.dayChange.kind.\(rawValue)" }
        /// SF Symbol of the kind.
        public var symbolName: String {
            switch self {
            case .cancelLesson: return "xmark.circle"
            case .changeLesson: return "arrow.triangle.2.circlepath"
            case .cancelDay: return "calendar.badge.minus"
            case .shortDay: return "clock.badge.exclamationmark"
            case .followDay: return "arrow.turn.up.right"
            case .extraLesson: return "plus.circle"
            }
        }
    }

    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable {
        case noLesson
        case nothingChanged
        case noBellSchedule
        case noFollowDay
        case noSubject

        /// Catalog key of the explanation.
        public var l10nKey: String { "editor.dayChange.issue.\(rawValue)" }
    }

    public let overrideID: ScheduleOverride.ID
    public let timetableID: Timetable.ID
    public var date: LocalDate
    public var kind: Kind
    /// The lesson cancelled or changed.
    public var lessonID: Lesson.ID?
    public var substituteSubjectID: Subject.ID?
    public var room: String
    public var building: String
    public var teacher: String
    public var note: String
    public var bellScheduleID: BellSchedule.ID?
    public var followDay: DayKey?
    public var followCycleWeek: Int?
    public var extraSubjectID: Subject.ID?
    public var extraSlot: SlotDraft
    public var extraRoom: String
    public var extraTeacher: String

    /// A fresh draft for `date`; `lessonID` pre-selects a lesson (the user tapped one). `kind` defaults to
    /// "change lesson" when a lesson is selected, else "cancel day".
    public init(timetable: Timetable, date: LocalDate, lessonID: Lesson.ID?, kind: Kind? = nil, schedule: BellSchedule?,
                id: ScheduleOverride.ID) {
        overrideID = id
        timetableID = timetable.id
        self.date = date
        self.kind = kind ?? (lessonID == nil ? .cancelDay : .changeLesson)
        self.lessonID = lessonID
        substituteSubjectID = nil
        room = ""
        building = ""
        teacher = ""
        note = ""
        bellScheduleID = nil
        followDay = nil
        followCycleWeek = nil
        extraSubjectID = nil
        extraSlot = SlotDraft(defaultFor: timetable, schedule: schedule)
        extraRoom = ""
        extraTeacher = ""
    }

    /// Kinds that need the day to have at least one lesson to pick from.
    public static func kindsNeedingLesson() -> Set<Kind> { [.cancelLesson, .changeLesson] }

    /// Problems that block saving.
    public func issues(visibility: FieldVisibility) -> [Issue] {
        switch kind {
        case .cancelLesson:
            return lessonID == nil ? [.noLesson] : []
        case .changeLesson:
            if lessonID == nil { return [.noLesson] }
            return patch(visibility: visibility).isEmpty ? [.nothingChanged] : []
        case .cancelDay:
            return []
        case .shortDay:
            return bellScheduleID == nil ? [.noBellSchedule] : []
        case .followDay:
            return followDay == nil ? [.noFollowDay] : []
        case .extraLesson:
            return extraSubjectID == nil ? [.noSubject] : []
        }
    }

    /// The lesson patch of "change lesson": only fields the timetable shows, only non-blank values.
    public func patch(visibility: FieldVisibility) -> LessonPatch {
        var patch = LessonPatch()
        patch.subjectID = substituteSubjectID
        if visibility.isVisible(.room) { patch.room = EditorText.trimmedOrNil(room) }
        if visibility.isVisible(.building) { patch.building = EditorText.trimmedOrNil(building) }
        if visibility.isVisible(.teacher) { patch.teacher = EditorText.trimmedOrNil(teacher) }
        return patch
    }

    /// `true` when nothing blocks saving.
    public func canSave(visibility: FieldVisibility) -> Bool {
        issues(visibility: visibility).isEmpty && (kind != .extraLesson || extraSlot.issues.isEmpty)
    }

    /// The override to store, or `nil` while input is missing.
    public func makeOverride(visibility: FieldVisibility) -> ScheduleOverride? {
        guard canSave(visibility: visibility) else { return nil }
        let change: OverrideChange
        switch kind {
        case .cancelLesson:
            guard let lessonID else { return nil }
            change = .cancelLesson(lessonID)
        case .changeLesson:
            guard let lessonID else { return nil }
            change = .modifyLesson(lessonID, patch(visibility: visibility))
        case .cancelDay:
            change = .cancelDay(note: EditorText.trimmedOrNil(note))
        case .shortDay:
            guard let bellScheduleID else { return nil }
            change = .useBellSchedule(bellScheduleID)
        case .followDay:
            guard let followDay else { return nil }
            change = .followDay(followDay, cycleWeek: followCycleWeek)
        case .extraLesson:
            guard let extraSubjectID, let slot = extraSlot.slot else { return nil }
            change = .addLesson(OneOffLesson(
                subjectID: extraSubjectID, slot: slot,
                room: visibility.isVisible(.room) ? EditorText.trimmedOrNil(extraRoom) : nil,
                teacher: visibility.isVisible(.teacher) ? EditorText.trimmedOrNil(extraTeacher) : nil))
        }
        return ScheduleOverride(id: overrideID, meta: EditorEntities.placeholderMeta, timetableID: timetableID,
                                date: date, change: change)
    }
}
