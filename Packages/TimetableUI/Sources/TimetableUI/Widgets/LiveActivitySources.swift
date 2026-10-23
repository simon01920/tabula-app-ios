// What the Live Activity planner needs from the app's data (Stage B2): the lesson days from today on and the exams
// with a start time in the scheduling horizon. Built on the main actor from the model's current state; pure,
// Linux-tested.
//
// Lessons come from `WidgetSnapshotBuilder` (the same days, kinds, cancellations, overrides and room field rule as
// the Today tab and the widgets — the three can never disagree). Exams follow the Exams tab (`ExamListModel`): live,
// not completed, by date then start; only exams with a start time can count down, so exams without one get no Live
// Activity (documented in the device checklist).
import Foundation
import TimetableCore

/// One school day with lessons, as instants.
public struct LiveActivityLessonDay: Equatable, Sendable {
    public var day: LocalDate
    /// Lessons that take place, by (start, end), at most `LiveActivityLimits.maxLessons` (the first ones).
    public var lessons: [LiveActivityLesson]

    public init(day: LocalDate, lessons: [LiveActivityLesson]) {
        self.day = day
        self.lessons = lessons
    }

    /// Start of the first lesson.
    public var firstStart: Date { lessons.first?.start ?? .distantFuture }
    /// End of the last lesson.
    public var lastEnd: Date { lessons.map(\.end).max() ?? .distantPast }
}

/// An exam that can get an exam-day Live Activity.
public struct LiveActivityExam: Equatable, Sendable {
    public var id: UUID
    public var day: LocalDate
    public var title: String
    public var subject: LiveActivitySubject?
    public var room: String?
    public var start: Date
    public var end: Date?

    public init(id: UUID, day: LocalDate, title: String, subject: LiveActivitySubject?, room: String?, start: Date,
                end: Date?) {
        self.id = id
        self.day = day
        self.title = title
        self.subject = subject
        self.room = room
        self.start = start
        self.end = end
    }

    /// End of the "in progress" phase (end time, else `LiveActivityPolicy.examAssumedDuration` after the start).
    public var close: Date { end.map { max(start, $0) } ?? start.addingTimeInterval(LiveActivityPolicy.examAssumedDuration) }
}

/// Everything the planner reads from the app's data.
public struct LiveActivitySources: Equatable, Sendable {
    /// The zone the instants were computed in, plus locale / language / 12–24 h.
    public var style: LiveActivityStyle
    /// The calendar context of `style` (day boundaries).
    public var context: CalendarContext
    /// School days with at least one lesson that takes place, ascending, from today on (covered by the snapshot).
    public var lessonDays: [LiveActivityLessonDay]
    /// Exams with a start time from today on, within `LiveActivityPolicy.scheduleHorizon` days, by start.
    public var exams: [LiveActivityExam]

    public init(style: LiveActivityStyle, context: CalendarContext, lessonDays: [LiveActivityLessonDay],
                exams: [LiveActivityExam]) {
        self.style = style
        self.context = context
        self.lessonDays = lessonDays
        self.exams = exams
    }

    /// The lesson day `day`, if it has lessons.
    public func lessonDay(_ day: LocalDate) -> LiveActivityLessonDay? { lessonDays.first { $0.day == day } }
}

public enum LiveActivitySourceBuilder {
    /// The sources at `now`. `database == nil` (onboarding) → no lessons, no exams.
    public static func make(database: TabulaDatabase?, now: Date, context: CalendarContext, locale: Locale,
                            languageCode: String?) -> LiveActivitySources {
        let settings = database?.settings ?? .untouchedDefaults
        let style = LiveActivityStyle(localeID: locale.identifier, languageCode: languageCode, hourCycle: settings.hourCycle,
                                      timeZoneID: context.timeZone.identifier)
        let snapshot = WidgetSnapshotBuilder.make(database: database, now: now, context: context, tier: .pro, locale: locale,
                                                  languageCode: languageCode)
        return make(snapshot: snapshot, database: database, now: now, context: context, style: style)
    }

    /// The sources from an already built widget snapshot (the snapshot's days are planned in `context`).
    public static func make(snapshot: WidgetSnapshot, database: TabulaDatabase?, now: Date, context: CalendarContext,
                            style: LiveActivityStyle) -> LiveActivitySources {
        var lessonDays: [LiveActivityLessonDay] = []
        if snapshot.hasTimetable {
            for day in snapshot.days {
                let lessons = WidgetTimelinePlanner.active(day, context)
                    .prefix(LiveActivityLimits.maxLessons)
                    .map { lesson in
                        LiveActivityLesson(subject: LiveActivitySubject(lesson.subject),
                                           room: LiveActivityLimits.cut(lesson.room, LiveActivityLimits.maxRoomLength),
                                           start: lesson.start(in: context), end: lesson.end(in: context))
                    }
                if !lessons.isEmpty { lessonDays.append(LiveActivityLessonDay(day: day.date, lessons: Array(lessons))) }
            }
        }
        return LiveActivitySources(style: style, context: context, lessonDays: lessonDays,
                                   exams: exams(database: database, now: now, context: context))
    }

    /// Exams with a start time from today through today + `LiveActivityPolicy.scheduleHorizonDays`, by start.
    static func exams(database: TabulaDatabase?, now: Date, context: CalendarContext) -> [LiveActivityExam] {
        guard let database else { return [] }
        let today = context.localDate(of: now)
        let last = today.adding(days: LiveActivityPolicy.scheduleHorizonDays)
        let subjects = Dictionary(database.subjects.filter { !$0.isDeleted }.map { ($0.id, SubjectSummary($0)) },
                                  uniquingKeysWith: { first, _ in first })
        return database.exams
            .filter { !$0.isDeleted && !$0.isCompleted && $0.start != nil && $0.date >= today && $0.date <= last }
            .compactMap { exam -> LiveActivityExam? in
                guard let startTime = exam.start else { return nil }
                let start = context.date(exam.date, startTime)
                let end = exam.end.map { context.date(exam.date, $0) }.flatMap { $0 > start ? $0 : nil }
                let facts = ExamFacts(exam: exam, visibility: ExamFacts.visibility(for: exam, in: database))
                let subject = exam.subjectID.flatMap { subjects[$0] }.map(LiveActivitySubject.init)
                let title = LiveActivityLimits.cut(exam.title, LiveActivityLimits.maxTitleLength,
                                                 maxBytes: LiveActivityLimits.maxTitleBytes) ?? subject?.name ?? ""
                return LiveActivityExam(id: exam.id.uuid, day: exam.date, title: title, subject: subject,
                                        room: LiveActivityLimits.cut(facts.room, LiveActivityLimits.maxRoomLength),
                                        start: start, end: end)
            }
            .sorted { ($0.start, $0.title, $0.id.uuidString) < ($1.start, $1.title, $1.id.uuidString) }
    }
}
