import Foundation

/// The optional lesson fields of one occurrence after inheritance and patches.
///
/// Precedence for `room`, `building`, `teacher` (PRODUCT.md field rule, DOMAIN_MODEL §3.5/§3.8):
/// 1. a **patch** value, when present: non-blank replaces, blank (empty or whitespace-only) clears the field
///    for that occurrence — no fallback;
/// 2. the lesson's own non-blank value;
/// 3. the (effective) subject's non-blank default;
/// 4. absent (`nil`). Placeholders are never produced; visibility is the UI's job.
///
/// `lessonType` and `notes` have no subject default (subject notes describe the subject, not its lessons).
/// `bringList` drops blank items. Values are returned verbatim (not trimmed).
public struct EffectiveFields: Hashable, Sendable {
    /// Effective room.
    public var room: String?
    /// Effective building.
    public var building: String?
    /// Effective teacher.
    public var teacher: String?
    /// Effective lesson type.
    public var lessonType: LessonType?
    /// Effective notes.
    public var notes: String?
    /// Effective bring-list (blank items removed).
    public var bringList: [String]

    /// Resolves the fields of a lesson (or one-off) with `subject`'s defaults and an optional `patch`.
    public init(room: String?, building: String?, teacher: String?, lessonType: LessonType?, notes: String?,
                bringList: [String], subject: Subject?, patch: LessonPatch? = nil) {
        self.room = Self.resolve(own: room, subjectDefault: subject?.defaultRoom, patch: patch?.room)
        self.building = Self.resolve(own: building, subjectDefault: subject?.defaultBuilding, patch: patch?.building)
        self.teacher = Self.resolve(own: teacher, subjectDefault: subject?.defaultTeacher, patch: patch?.teacher)
        if let patched = patch?.lessonType {
            self.lessonType = Self.isBlank(patched.rawValue) ? nil : patched
        } else {
            self.lessonType = lessonType.flatMap { Self.isBlank($0.rawValue) ? nil : $0 }
        }
        self.notes = Self.resolve(own: notes, subjectDefault: nil, patch: patch?.notes)
        self.bringList = (patch?.bringList ?? bringList).filter { !Self.isBlank($0) }
    }

    /// Fields of a recurring lesson.
    public init(lesson: Lesson, subject: Subject?, patch: LessonPatch? = nil) {
        self.init(room: lesson.room, building: lesson.building, teacher: lesson.teacher, lessonType: lesson.lessonType,
                  notes: lesson.notes, bringList: lesson.bringList, subject: subject, patch: patch)
    }

    /// Fields of a one-off lesson.
    public init(oneOff: OneOffLesson, subject: Subject?) {
        self.init(room: oneOff.room, building: oneOff.building, teacher: oneOff.teacher, lessonType: oneOff.lessonType,
                  notes: oneOff.notes, bringList: oneOff.bringList, subject: subject)
    }

    /// The single-field rule (see type documentation).
    public static func resolve(own: String?, subjectDefault: String?, patch: String?) -> String? {
        if let patch { return isBlank(patch) ? nil : patch }
        if let own, !isBlank(own) { return own }
        if let subjectDefault, !isBlank(subjectDefault) { return subjectDefault }
        return nil
    }

    /// `true` for empty or whitespace/newline-only text.
    public static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    /// Reasons (other than time and subject) why `other` differs from `self`.
    func differences(to other: EffectiveFields) -> [ModificationReason] {
        var reasons: [ModificationReason] = []
        if room != other.room { reasons.append(.roomChanged) }
        if building != other.building { reasons.append(.buildingChanged) }
        if teacher != other.teacher { reasons.append(.teacherChanged) }
        if lessonType != other.lessonType { reasons.append(.lessonTypeChanged) }
        if notes != other.notes { reasons.append(.notesChanged) }
        if bringList != other.bringList { reasons.append(.bringListChanged) }
        return reasons
    }
}

extension LessonPatch {
    /// `self` with every non-nil field of `later` applied on top (field-wise last-writer-wins).
    func merging(_ later: LessonPatch) -> LessonPatch {
        LessonPatch(subjectID: later.subjectID ?? subjectID, slot: later.slot ?? slot, room: later.room ?? room,
                    building: later.building ?? building, teacher: later.teacher ?? teacher,
                    lessonType: later.lessonType ?? lessonType, notes: later.notes ?? notes,
                    bringList: later.bringList ?? bringList)
    }
}
