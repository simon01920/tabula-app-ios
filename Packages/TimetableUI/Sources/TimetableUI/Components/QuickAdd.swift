// "Tap an empty cell → pick a subject → the lesson exists" (REFERENCE_ANALYSIS §2, the biggest data-entry lever).
// The target captures everything the new recurring lesson needs from the tapped cell: the column's resolved day key
// (weekday, or cycle day for day cycles), the shown cycle week (week cycles: the lesson runs in that week only, the
// way a printed A/B timetable is entered) and the row's period (or its times for free-form rows). Pure, Linux-tested.
import Foundation
import TimetableCore

/// An empty grid slot to fill.
public struct QuickAddTarget: Hashable, Sendable, Identifiable {
    public var timetableID: Timetable.ID
    /// The tapped column's date (for the sheet title).
    public var date: LocalDate
    /// Day key of the new lesson's occurrence rule.
    public var dayKey: DayKey
    /// Cycle week of the column (week cycles only).
    public var cycleWeek: Int?
    /// Period of the row (bell-schedule timetables); `nil` → `start`/`end` are used.
    public var periodID: Period.ID?
    /// 1-based lesson number of the row, if any (sheet title / VoiceOver).
    public var lessonNumber: Int?
    public var start: LocalTime
    public var end: LocalTime

    public var id: String { "\(timetableID.uuidString):\(date.isoString):\(start.isoString)" }

    public init(timetableID: Timetable.ID, date: LocalDate, dayKey: DayKey, cycleWeek: Int?, periodID: Period.ID?,
                lessonNumber: Int?, start: LocalTime, end: LocalTime) {
        self.timetableID = timetableID
        self.date = date
        self.dayKey = dayKey
        self.cycleWeek = cycleWeek
        self.periodID = periodID
        self.lessonNumber = lessonNumber
        self.start = start
        self.end = end
    }

    /// The target of the slot at (`column`, `row`) in `layout`, or `nil` when it is not a lesson row of a column with
    /// a day key.
    public static func make(layout: GridLayout, column columnIndex: Int, row rowIndex: Int,
                            timetable: Timetable) -> QuickAddTarget? {
        guard layout.columns.indices.contains(columnIndex), layout.rows.indices.contains(rowIndex) else { return nil }
        let column = layout.columns[columnIndex]
        let row = layout.rows[rowIndex]
        guard row.isLessonRow, let dayKey = column.dayKey else { return nil }
        let cycleWeek: Int?
        if case .weekCycle = timetable.rotation { cycleWeek = column.cycleWeek } else { cycleWeek = nil }
        return QuickAddTarget(timetableID: timetable.id, date: column.date, dayKey: dayKey, cycleWeek: cycleWeek,
                              periodID: row.periodID, lessonNumber: row.lessonNumber, start: row.start, end: row.end)
    }

    /// The occurrence rule of the new lesson.
    public var occurrence: LessonOccurrenceRule {
        LessonOccurrenceRule(day: dayKey, cycleWeeks: cycleWeek.map { [$0] })
    }

    /// The slot of the new lesson: one period, else explicit times.
    public var slot: LessonSlot {
        if let periodID { return .period(periodID, span: 1) }
        return .time(start: start, end: end)
    }

    /// The new recurring lesson (no optional fields: room/teacher/building come from the subject's defaults).
    /// Metadata is a placeholder; `AppModel.apply(.upsert(_:))` stamps it.
    public func makeLesson(id: Lesson.ID, subjectID: Subject.ID) -> Lesson {
        Lesson(id: id, meta: .created(at: .zero), timetableID: timetableID, subjectID: subjectID,
               occurrence: occurrence, slot: slot, validity: .always)
    }
}

/// Subjects offered by the quick-add sheet.
public enum QuickAddSubjects {
    /// Live subjects of `timetableID` in display order (`SubjectOrder`: manual order, then name, then ID).
    public static func list(_ database: TabulaDatabase, timetableID: Timetable.ID, locale: Locale) -> [Subject] {
        SubjectOrder.live(database, timetableID: timetableID, locale: locale)
    }
}
