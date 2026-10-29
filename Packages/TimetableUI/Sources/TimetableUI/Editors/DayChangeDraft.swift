// Edit state of "Change for this day": builds one `ScheduleOverride` of a chosen kind for one date. Pure, Linux-tested.
// "Change a lesson" covers substitute (subject, teacher), room and building changes, a note and a move to another time
// on the same date (`LessonPatch.slot`), which is what the lesson detail's "Cancel, Move or Substitute…" promises.
// D10: every optional field is offered whatever the timetable's display setting.
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
        public var symbolName: String { symbol.rawValue }

        /// The app symbol of the kind (the same symbols as the lesson badges, M8).
        public var symbol: AppSymbol {
            switch self {
            case .cancelLesson: return .cancelled
            case .changeLesson: return .changed
            case .cancelDay: return .cancelledDay
            case .shortDay: return .timeChanged
            case .followDay: return .followsAnotherDay
            case .extraLesson: return .extraLesson
            }
        }
    }

    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable, CaseIterable {
        case noLesson
        case nothingChanged
        case noBellSchedule
        case noFollowDay
        case noSubject

        /// Catalog key of the explanation.
        public var l10nKey: String { "editor.dayChange.issue.\(rawValue)" }

        /// How the editor shows it (M5): a missing choice is a hint, visible from the start next to the disabled Save;
        /// a timetable without a bell schedule for a short day is an error.
        public var severity: ValidationSeverity {
            switch self {
            case .nothingChanged, .noLesson, .noFollowDay, .noSubject: return .hint
            case .noBellSchedule: return .error
            }
        }
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
    /// Note for this occurrence ("change a lesson").
    public var lessonNote: String
    /// `true` when "change a lesson" also moves the lesson to `movedSlot` on the same date.
    public var moves: Bool
    public var movedSlot: SlotDraft
    /// Note of "no school".
    public var note: String
    public var bellScheduleID: BellSchedule.ID?
    public var followDay: DayKey?
    public var followCycleWeek: Int?
    public var extraSubjectID: Subject.ID?
    public var extraSlot: SlotDraft
    public var extraRoom: String
    public var extraBuilding: String
    public var extraTeacher: String
    public var extraNotes: String

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
        lessonNote = ""
        moves = false
        movedSlot = SlotDraft(defaultFor: timetable, schedule: schedule)
        note = ""
        bellScheduleID = nil
        followDay = nil
        followCycleWeek = nil
        extraSubjectID = nil
        extraSlot = SlotDraft(defaultFor: timetable, schedule: schedule)
        extraRoom = ""
        extraBuilding = ""
        extraTeacher = ""
        extraNotes = ""
    }

    /// Turns the move on or off; turning it on starts from the lesson's regular slot (`lessonSlot`).
    public mutating func setMoves(_ on: Bool, lessonSlot: LessonSlot?) {
        if on && !moves, let lessonSlot { movedSlot = SlotDraft(slot: lessonSlot) }
        moves = on
    }

    /// Another lesson was chosen: a move started for the previous lesson no longer applies.
    public mutating func selectLesson(_ id: Lesson.ID?) {
        guard id != lessonID else { return }
        lessonID = id
        moves = false
    }

    /// Kinds that need the day to have at least one lesson to pick from.
    public static func kindsNeedingLesson() -> Set<Kind> { [.cancelLesson, .changeLesson] }

    /// Problems that block saving.
    public var issues: [Issue] {
        switch kind {
        case .cancelLesson:
            return lessonID == nil ? [.noLesson] : []
        case .changeLesson:
            if lessonID == nil { return [.noLesson] }
            return patch.isEmpty ? [.nothingChanged] : []
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

    /// The lesson patch of "change lesson": only non-blank values (an empty field keeps the regular value).
    public var patch: LessonPatch {
        var patch = LessonPatch()
        patch.subjectID = substituteSubjectID
        if moves { patch.slot = movedSlot.slot }
        patch.room = EditorText.trimmedOrNil(room)
        patch.building = EditorText.trimmedOrNil(building)
        patch.teacher = EditorText.trimmedOrNil(teacher)
        patch.notes = EditorText.trimmedOrNil(lessonNote)
        return patch
    }

    /// Problems of the time slot that block saving (the extra lesson's slot, or the moved slot).
    public var slotIssues: [SlotDraft.Issue] {
        switch kind {
        case .extraLesson: return extraSlot.issues
        case .changeLesson where moves: return movedSlot.issues
        default: return []
        }
    }

    /// `true` when nothing blocks saving.
    public var canSave: Bool { issues.isEmpty && slotIssues.isEmpty }

    /// The override to store, or `nil` while input is missing.
    public func makeOverride() -> ScheduleOverride? {
        guard canSave else { return nil }
        let change: OverrideChange
        switch kind {
        case .cancelLesson:
            guard let lessonID else { return nil }
            change = .cancelLesson(lessonID)
        case .changeLesson:
            guard let lessonID else { return nil }
            change = .modifyLesson(lessonID, patch)
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
                room: EditorText.trimmedOrNil(extraRoom), building: EditorText.trimmedOrNil(extraBuilding),
                teacher: EditorText.trimmedOrNil(extraTeacher), notes: EditorText.trimmedOrNil(extraNotes)))
        }
        return ScheduleOverride(id: overrideID, meta: EditorEntities.placeholderMeta, timetableID: timetableID,
                                date: date, change: change)
    }
}
