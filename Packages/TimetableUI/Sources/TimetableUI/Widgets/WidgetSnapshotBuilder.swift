// Builds the `WidgetSnapshot` from the app's database (PHASE4_PLAN §0.1). Pure, Linux-tested; the app calls it on
// the main actor after every change (App/Sources/Widgets/WidgetSnapshotWriter.swift).
//
// Rules (same sources of truth as the Today tab, so widget and app never disagree):
//   - Timetable: the active one (`ActiveTimetable.resolve`), resolved with the app's `CalendarContext`.
//   - Days: today through the next school day after tomorrow (`ScheduleResolver.nextSchoolDay`), every day in between
//     included; without a school day in the next 31 days: today + 7 days. Day kinds follow `TodayState`: a break wins
//     over a cancelled day, which wins over a free day.
//   - Lessons: `DaySchedule.entries` (cancelled ones kept and flagged), room only when the timetable shows rooms.
//   - Following lesson: the first non-cancelled lesson after the last covered day (31-day horizon).
//   - Tasks: the Tasks tab's Today + Upcoming segments (`TaskListModel`) due within 7 days, by due date, at most 20;
//     overdue = the Tasks tab's overdue count.
//   - Next exam: the Exams tab's featured exam (`ExamListModel.next`).
//   - User text is shortened to `maxTextLength` characters (bounded size; a widget cannot show more anyway).
import Foundation
import TimetableCore

public enum WidgetSnapshotBuilder {
    /// Tasks due within this many days (today included as day 0).
    public static let taskHorizonDays = 7
    /// At most this many tasks.
    public static let maxTasks = 20
    /// User text longer than this is cut (characters).
    public static let maxTextLength = 80
    /// Days covered after today when no school day follows tomorrow within the horizon.
    public static let fallbackCoveredDays = 7
    /// Horizon of the next-school-day and following-lesson searches.
    public static let searchHorizonDays = 31

    /// The snapshot at `now`. `database` `nil` (first launch, onboarding) → a snapshot without timetable.
    /// `languageCode` is the app's UI language (`Bundle.main.preferredLocalizations.first`).
    public static func make(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier,
                            locale: Locale, languageCode: String?) -> WidgetSnapshot {
        let settings = database?.settings ?? .untouchedDefaults
        let follows: Bool
        if case .followDevice = settings.timeZoneMode { follows = true } else { follows = false }
        var snapshot = WidgetSnapshot(
            generatedAt: now, timeZoneID: context.timeZone.identifier, followsDeviceTimeZone: follows,
            localeID: locale.identifier, languageCode: languageCode, hourCycle: settings.hourCycle, tier: tier,
            hasTimetable: false, days: [], followingLesson: nil, tasks: [], overdueTaskCount: 0, nextExam: nil)
        guard let database else { return snapshot }

        let today = context.localDate(of: now)
        if let timetable = ActiveTimetable.resolve(database),
           let resolver = ScheduleResolver(database: database, timetableID: timetable.id, context: context) {
            snapshot.hasTimetable = true
            let tomorrow = today.adding(days: 1)
            let last = resolver.nextSchoolDay(after: tomorrow, horizonDays: searchHorizonDays)?.date
                ?? today.adding(days: fallbackCoveredDays)
            var days: [WidgetSnapshot.Day] = []
            var date = today
            while date <= last {
                days.append(day(date, resolver: resolver, database: database, visibility: timetable.fieldVisibility))
                date = date.adding(days: 1)
            }
            snapshot.days = days
            // One second before the day after `last` starts: `nowAndNext` then looks at `last` (nothing starts later
            // that day) and the following days.
            let probe = context.startOfDay(last.adding(days: 1)).addingTimeInterval(-1)
            snapshot.followingLesson = resolver.nowAndNext(at: probe, horizonDays: searchHorizonDays).next
                .map { lesson($0, reasons: [], visibility: timetable.fieldVisibility) }
        }

        let nowLocal = context.local(from: now)
        let liveTasks = database.tasks.filter { !$0.isDeleted }
        snapshot.overdueTaskCount = TaskListModel.counts(of: liveTasks, now: nowLocal).overdue
        let subjects = Dictionary(database.subjects.filter { !$0.isDeleted }.map { ($0.id, SubjectSummary($0)) },
                                  uniquingKeysWith: { first, _ in first })
        let horizon = today.adding(days: taskHorizonDays)
        let due = TaskListModel.tasks(in: .today, from: liveTasks, now: nowLocal, sort: .due)
            + TaskListModel.tasks(in: .upcoming, from: liveTasks, now: nowLocal, sort: .due)
        snapshot.tasks = due.compactMap { task -> WidgetSnapshot.DueTask? in
            guard let dueDate = task.due?.date, dueDate <= horizon else { return nil }
            return WidgetSnapshot.DueTask(id: task.id.uuid, title: shortened(task.title),
                                          subject: task.subjectID.flatMap { subjects[$0] }.map(shortened),
                                          dueDate: dueDate, dueTime: task.due?.time, priority: task.priority)
        }
        .prefix(maxTasks).map { $0 }

        if let row = ExamListModel.make(database: database, today: today, context: context).next {
            let facts = ExamFacts(exam: row.exam, visibility: ExamFacts.visibility(for: row.exam, in: database))
            snapshot.nextExam = WidgetSnapshot.UpcomingExam(
                id: row.exam.id.uuid, title: shortened(row.exam.title), subject: row.subject.map(shortened),
                date: row.exam.date, start: row.exam.start, end: row.exam.end, room: facts.room.map(shortened))
        }
        return snapshot
    }

    // MARK: Internals

    static func day(_ date: LocalDate, resolver: ScheduleResolver, database: TabulaDatabase,
                    visibility: FieldVisibility) -> WidgetSnapshot.Day {
        let resolution = resolver.resolution(for: date)
        let schedule = resolution.schedule
        let kind: WidgetSnapshot.Day.Kind
        var note: String?
        if let breakID = schedule.activeBreakID {
            kind = .holiday
            note = TodayState.nonBlank(database.breaks.first { $0.id == breakID }?.name)
        } else if let overrideID = schedule.cancellingOverrideID {
            kind = .cancelled
            if case .cancelDay(let text)? = database.overrides.first(where: { $0.id == overrideID })?.change {
                note = TodayState.nonBlank(text)
            }
        } else {
            kind = schedule.isSchoolDay ? .school : .free
        }
        let lessons = schedule.entries.map { lesson($0, reasons: resolution.reasons(for: $0.id), visibility: visibility) }
        return WidgetSnapshot.Day(date: date, kind: kind, note: note.map(shortened), lessons: lessons)
    }

    static func lesson(_ lesson: ResolvedLesson, reasons: [ModificationReason],
                       visibility: FieldVisibility) -> WidgetSnapshot.Lesson {
        WidgetSnapshot.Lesson(id: lesson.id.rawValue, subject: shortened(lesson.subject), date: lesson.date,
                              startTime: lesson.startTime, endTime: lesson.endTime,
                              room: VisibleLessonFields(lesson: lesson, visibility: visibility).room.map(shortened),
                              status: lesson.status, reasons: reasons.isEmpty ? nil : reasons)
    }

    /// `text` cut to `maxTextLength` characters (whole grapheme clusters).
    static func shortened(_ text: String) -> String {
        text.count > maxTextLength ? String(text.prefix(maxTextLength)) : text
    }

    static func shortened(_ subject: SubjectSummary) -> SubjectSummary {
        var copy = subject
        copy.name = shortened(subject.name)
        copy.shortName = subject.shortName.map(shortened)
        return copy
    }
}
