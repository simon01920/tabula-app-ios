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
//   - Timetable sections (Phase 4 B3, widget timetable choice): with ≥ 2 live timetables, one section each; the other
//     timetables' days only while the whole snapshot fits `maxEncodedBytes` (`addTimetableSections`).
import Foundation
import TimetableCore

public enum WidgetSnapshotBuilder {
    /// Tasks due within this many days (today included as day 0).
    public static let taskHorizonDays = 7
    /// At most this many tasks.
    public static let maxTasks = 20
    /// At most this many overdue tasks are listed (the count is always complete).
    public static let maxOverdueTasks = 8
    /// User text longer than this is cut (characters).
    public static let maxTextLength = 60
    /// At most this many upcoming exams are listed (B1 QA M1).
    public static let maxExams = 4
    /// The encoded snapshot is trimmed (far-future tasks first) until it is at most this many bytes: the Watch
    /// reuses it and ARCHITECTURE.md budgets < 20 KB (B1 QA M2).
    public static let maxEncodedBytes = 19_000
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
        let active = ActiveTimetable.resolve(database)
        if let timetable = active, let covered = coverage(timetable, database: database, today: today, context: context) {
            snapshot.hasTimetable = true
            snapshot.days = covered.days
            snapshot.followingLesson = covered.following
        }

        let nowLocal = context.local(from: now)
        let liveTasks = database.tasks.filter { !$0.isDeleted }
        snapshot.overdueTaskCount = TaskListModel.counts(of: liveTasks, now: nowLocal).overdue
        let subjects = Dictionary(database.subjects.filter { !$0.isDeleted }.map { ($0.id, SubjectSummary($0)) },
                                  uniquingKeysWith: { first, _ in first })
        let horizon = today.adding(days: taskHorizonDays)
        let due = TaskListModel.tasks(in: .today, from: liveTasks, now: nowLocal, sort: .due)
            + TaskListModel.tasks(in: .upcoming, from: liveTasks, now: nowLocal, sort: .due)
        func dueTask(_ task: TaskItem) -> WidgetSnapshot.DueTask? {
            guard let dueDate = task.due?.date else { return nil }
            return WidgetSnapshot.DueTask(id: task.id.uuid, title: shortened(task.title),
                                          subject: task.subjectID.flatMap { subjects[$0] }.map(shortened),
                                          dueDate: dueDate, dueTime: task.due?.time, priority: task.priority)
        }
        snapshot.tasks = due.compactMap { task in dueTask(task).flatMap { $0.dueDate <= horizon ? $0 : nil } }
            .prefix(maxTasks).map { $0 }
        // Open tasks (the Tasks tab's Today + Upcoming + Overdue; undated ones included) for the Homework count.
        let counts = TaskListModel.counts(of: liveTasks, now: nowLocal)
        snapshot.openTaskCount = counts.today + counts.upcoming + counts.overdue
        // Overdue tasks: those due today (time passed) first, then the oldest; listed oldest first.
        let overdueAll = TaskListModel.tasks(in: .overdue, from: liveTasks, now: nowLocal, sort: .due).compactMap(dueTask)
        let overdueToday = overdueAll.filter { $0.dueDate == today }
        let overdueOlder = overdueAll.filter { $0.dueDate != today }
        let overdue = (overdueToday + overdueOlder).prefix(maxOverdueTasks)
            .sorted { ($0.dueDate, $0.dueTime ?? .midnight) < ($1.dueDate, $1.dueTime ?? .midnight) }
        snapshot.overdueItems = overdue.isEmpty ? nil : overdue

        // Upcoming exams: not completed, and not ended yet (no end: the whole exam day), soonest first.
        let subjectsByID = subjects
        let upcoming = database.exams.filter { !$0.isDeleted && !$0.isCompleted && $0.date >= today }
            .filter { exam in
                guard exam.date == today, let end = exam.end, end > (exam.start ?? .midnight) else { return true }
                return context.date(exam.date, end) > now
            }
            .sorted { ($0.date, $0.start ?? LocalTime.midnight, $0.title) < ($1.date, $1.start ?? LocalTime.midnight, $1.title) }
            .prefix(maxExams)
        let exams = upcoming.map { exam -> WidgetSnapshot.UpcomingExam in
            let facts = ExamFacts(exam: exam, visibility: ExamFacts.visibility(for: exam, in: database))
            return WidgetSnapshot.UpcomingExam(
                id: exam.id.uuid, title: shortened(exam.title), subject: exam.subjectID.flatMap { subjectsByID[$0] }.map(shortened),
                date: exam.date, start: exam.start, end: exam.end, room: facts.room.map(shortened))
        }
        snapshot.nextExam = exams.first
        snapshot.exams = exams.isEmpty ? nil : exams
        enforceBudget(&snapshot)
        if let active { addTimetableSections(&snapshot, active: active, database: database, today: today, context: context) }
        return snapshot
    }

    /// The days of `timetable` from `today` through the next school day after tomorrow (every day in between), and the
    /// first lesson after them; `nil` when the timetable cannot be resolved.
    static func coverage(_ timetable: Timetable, database: TabulaDatabase, today: LocalDate,
                         context: CalendarContext) -> (days: [WidgetSnapshot.Day], following: WidgetSnapshot.Lesson?)? {
        guard let resolver = ScheduleResolver(database: database, timetableID: timetable.id, context: context) else { return nil }
        let tomorrow = today.adding(days: 1)
        let last = resolver.nextSchoolDay(after: tomorrow, horizonDays: searchHorizonDays)?.date
            ?? today.adding(days: fallbackCoveredDays)
        var days: [WidgetSnapshot.Day] = []
        var date = today
        while date <= last {
            days.append(day(date, resolver: resolver, database: database, visibility: timetable.fieldVisibility))
            date = date.adding(days: 1)
        }
        // One second before the day after `last` starts: `nowAndNext` then looks at `last` (nothing starts later
        // that day) and the following days.
        let probe = context.startOfDay(last.adding(days: 1)).addingTimeInterval(-1)
        let following = resolver.nowAndNext(at: probe, horizonDays: searchHorizonDays).next
            .map { lesson($0, reasons: [], visibility: timetable.fieldVisibility) }
        return (days, following)
    }

    /// Phase 4 B3 (widget timetable choice): one section per live timetable, display order. Added AFTER the B1 trim, so
    /// the active timetable, tasks and exams keep everything they had; another timetable's days are kept only while
    /// the encoded snapshot stays within `maxEncodedBytes` (else that section has no days and a widget configured for it
    /// shows "Open Tabula"). Nothing is added with a single timetable (no choice to make).
    static func addTimetableSections(_ snapshot: inout WidgetSnapshot, active: Timetable, database: TabulaDatabase,
                                     today: LocalDate, context: CalendarContext) {
        let ordered = ActiveTimetable.ordered(database)
        guard ordered.count > 1 else { return }
        var named = snapshot
        named.timetables = ordered.map {
            TimetableSection(id: $0.id.uuid, name: shortened($0.name), isActive: $0.id == active.id)
        }
        // Not even the names fit (final QA m2): no sections, the widgets follow the active timetable.
        guard let namedSize = try? WidgetSnapshotStore.encode(named).count, namedSize <= maxEncodedBytes else { return }
        snapshot = named
        for (index, timetable) in ordered.enumerated() where timetable.id != active.id {
            guard let covered = coverage(timetable, database: database, today: today, context: context) else { continue }
            var candidate = snapshot
            candidate.timetables?[index].days = covered.days
            candidate.timetables?[index].followingLesson = covered.following
            if let size = try? WidgetSnapshotStore.encode(candidate).count, size <= maxEncodedBytes { snapshot = candidate }
        }
    }

    // MARK: Internals

    /// Trims the lowest-priority lists until the encoded snapshot fits `maxEncodedBytes`: tasks beyond the first 8,
    /// overdue beyond the first 3, exams beyond 2, tasks beyond 4, exams beyond 1, overdue beyond 1; then (B3 final QA)
    /// covered days from the far end, never today. `limit` is a parameter for tests only.
    static func enforceBudget(_ snapshot: inout WidgetSnapshot, limit: Int = maxEncodedBytes) {
        func size() -> Int { (try? WidgetSnapshotStore.encode(snapshot).count) ?? 0 }
        let maxEncodedBytes = limit
        let steps: [(inout WidgetSnapshot) -> Void] = [
            { $0.tasks = Array($0.tasks.prefix(8)) },
            { $0.overdueItems = $0.overdueItems.map { Array($0.prefix(3)) } },
            { $0.exams = $0.exams.map { Array($0.prefix(2)) } },
            { $0.tasks = Array($0.tasks.prefix(4)) },
            { $0.exams = $0.exams.map { Array($0.prefix(1)) } },
            { $0.overdueItems = $0.overdueItems.map { Array($0.prefix(1)) } },
        ]
        for step in steps {
            guard size() > maxEncodedBytes else { return }
            step(&snapshot)
        }
        // Phase 4 B3 final QA m2 (a hard guarantee; the Phase 5 Watch reuses the snapshot): drop covered days from the
        // far end, never today. The first lesson that takes place on a dropped day becomes `followingLesson` (it IS the
        // first lesson after the new last covered day), so "Next lesson" stays right; days past the covered range show
        // "Open Tabula" (outdated), never invented data.
        while size() > maxEncodedBytes, snapshot.days.count > 1 {
            let dropped = snapshot.days.removeLast()
            if let first = dropped.lessons.first(where: { $0.takesPlace }) { snapshot.followingLesson = first }
        }
        // Pathological input only (dozens of lessons today with maximal text): the lists go, then today's last
        // lessons, then the remaining optional items, until the snapshot fits.
        if size() > maxEncodedBytes {
            snapshot.tasks = []
            snapshot.overdueItems = nil
            snapshot.exams = snapshot.nextExam.map { [$0] }
        }
        while size() > maxEncodedBytes, let today = snapshot.days.indices.first, !snapshot.days[today].lessons.isEmpty {
            snapshot.days[today].lessons.removeLast()
        }
        if size() > maxEncodedBytes {
            snapshot.followingLesson = nil
            snapshot.exams = nil
            snapshot.nextExam = nil
        }
    }

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
