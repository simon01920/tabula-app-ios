import Foundation

/// Turns an approved candidate into a `SharePayloadV1`, so import reuses the share path
/// (`DatabaseMutation.importShared`: Add as new / Replace with backup, fresh IDs, validation).
public enum ImportPayloadBuilder {
    /// The payload for `candidate`. Subjects are the distinct subject names (first appearance order, classic palette
    /// colours in turn); one bell schedule keyed by period number; lessons in candidate order. Lessons without a
    /// subject are skipped. `name` and `bellScheduleName` are user-visible text the UI localises. Throws when the result does not validate (e.g. a name over the share limits).
    public static func payload(from candidate: ImportCandidate, name: String, bellScheduleName: String, emoji: String? = nil)
        throws(ShareError) -> SharePayloadV1 {
        let lessons = candidate.lessons.filter { !$0.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var subjectIndex: [String: Int] = [:]
        var subjects: [ShareSubject] = []
        let colors = PalettePack.classic.colors
        for lesson in lessons where subjectIndex[lesson.subject] == nil {
            let color = colors[subjects.count % colors.count]
            subjectIndex[lesson.subject] = subjects.count
            subjects.append(ShareSubject(name: lesson.subject, color: color.value, colorName: .key(color.nameKey),
                                         sortIndex: subjects.count))
        }
        let periods = candidate.periods.map { SharePeriod(key: $0.number, label: String($0.number), start: $0.start, end: $0.end) }
        let rotation: RotationScheme = candidate.weekCycleLength.map {
            .weekCycle(WeekCycle(length: $0, anchor: .isoWeekParity(policy: .strict, offset: 0)))
        } ?? .none
        var fields: Set<LessonField> = []
        let shareLessons = lessons.map { lesson -> ShareLesson in
            if lesson.room != nil { fields.insert(.room) }
            if lesson.teacher != nil { fields.insert(.teacher) }
            if lesson.building != nil { fields.insert(.building) }
            if lesson.lessonType != nil { fields.insert(.lessonType) }
            if lesson.notes != nil { fields.insert(.notes) }
            return ShareLesson(subject: subjectIndex[lesson.subject]!, day: .weekday(lesson.day),
                               cycleWeeks: candidate.weekCycleLength == nil ? nil : lesson.cycleWeeks,
                               slot: .period(key: lesson.period, span: max(1, lesson.span)), room: lesson.room,
                               building: lesson.building, teacher: lesson.teacher, lessonType: lesson.lessonType,
                               notes: lesson.notes)
        }
        let days = Set(candidate.days).union(lessons.map(\.day))
        let payload = SharePayloadV1(
            timetable: ShareTimetable(name: name, emoji: emoji, enabledDays: days.isEmpty ? Weekday.workweek : days,
                                      rotation: rotation, timeStructure: .bellSchedule(defaultIndex: 0, perWeekday: [:]),
                                      fieldVisibility: fields),
            subjects: subjects, bellSchedules: [ShareBellSchedule(name: bellScheduleName, periods: periods)], lessons: shareLessons)
        _ = try payload.validate()
        return payload
    }
}
