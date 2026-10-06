import Foundation

/// The pending local-notification budget.
///
/// iOS keeps at most 64 pending local notifications per app (docs/spikes/ALARMKIT.md F28). `reserved` slots
/// are left free for notifications the app adds outside the plan (snoozes from notification actions), so the
/// planner schedules at most `available = maxPending − reserved`.
public struct NotificationBudget: Hashable, Sendable, Codable {
    /// The system cap (64 on iOS).
    public var maxPending: Int
    /// Slots kept free for snoozes and other ad-hoc notifications.
    public var reserved: Int

    /// Creates a budget.
    public init(maxPending: Int = 64, reserved: Int = 4) {
        self.maxPending = maxPending
        self.reserved = reserved
    }

    /// The iOS default: 64 pending, 4 reserved → 60 planned.
    public static let iOSDefault = NotificationBudget()

    /// Number of notifications the planner may schedule (never negative).
    public var available: Int { max(0, maxPending - max(0, reserved)) }
}

/// Everything the reminder planner needs. Pure data; the planner reads no clock, zone or locale itself.
public struct PlannerInput: Sendable {
    /// The instant of planning. Nothing at or before it is scheduled.
    public var now: Date
    /// Zone and week start used to turn wall-clock times into instants.
    public var context: CalendarContext
    /// App settings (global quiet hours, Time Sensitive and alarm policies).
    public var settings: AppSettings
    /// All reminder rules (deleted and disabled ones are ignored).
    public var rules: [ReminderRule]
    /// All tasks (deleted, completed and undated ones plan nothing).
    public var tasks: [TaskItem]
    /// All exams (deleted and completed ones plan nothing).
    public var exams: [Exam]
    /// Lesson occurrences resolved by the caller for the horizon (cancelled ones are ignored). Used by
    /// `lesson` rules and to anchor tasks linked to a lesson occurrence.
    public var lessons: [ResolvedLesson]
    /// School days with bring-list items (see `PackTonightDay.days(from:)`), for `packTonight` rules.
    public var packTonight: [PackTonightDay]
    /// Pending-notification budget.
    public var budget: NotificationBudget
    /// Self-imposed cap on loud alarms. AlarmKit's real limit is dynamic and undocumented (ALARMKIT.md F5),
    /// so this is soft: alarms beyond it fall back to Time Sensitive notifications and are reported in
    /// `ReminderPlan.alarmOverflow`.
    public var alarmSoftLimit: Int
    /// How many days ahead to plan (≥ 1; smaller values are treated as 1).
    public var horizonDays: Int
    /// `false` when AlarmKit is not authorised or the Pro entitlement for loud alarms is missing. Alarm-tier
    /// reminders then fall back to Time Sensitive (`TierChangeReason.alarmsUnavailable`).
    public var canScheduleAlarms: Bool
    /// Reference time for items that have a date but no time (date-only tasks, exams without a start):
    /// `minutesBefore` offsets and the Time Sensitive lead time are measured from it. Default 08:00 (a typical
    /// school start). A task linked to a lesson occurrence present in `lessons` uses that lesson's start.
    public var dateOnlyAnchorTime: LocalTime

    /// 08:00, the default `dateOnlyAnchorTime`.
    public static let defaultDateOnlyAnchorTime = LocalTime(hour: 8, minute: 0)!

    /// Creates planner input. Defaults: iOS budget (64/4), alarm soft limit 10, horizon 14 days.
    public init(now: Date, context: CalendarContext, settings: AppSettings, rules: [ReminderRule],
                tasks: [TaskItem] = [], exams: [Exam] = [], lessons: [ResolvedLesson] = [],
                packTonight: [PackTonightDay] = [], budget: NotificationBudget = .iOSDefault,
                alarmSoftLimit: Int = 10, horizonDays: Int = 14, canScheduleAlarms: Bool = true,
                dateOnlyAnchorTime: LocalTime = PlannerInput.defaultDateOnlyAnchorTime) {
        self.now = now
        self.context = context
        self.settings = settings
        self.rules = rules
        self.tasks = tasks
        self.exams = exams
        self.lessons = lessons
        self.packTonight = packTonight
        self.budget = budget
        self.alarmSoftLimit = alarmSoftLimit
        self.horizonDays = horizonDays
        self.canScheduleAlarms = canScheduleAlarms
        self.dateOnlyAnchorTime = dateOnlyAnchorTime
    }
}

/// One school day's bring-list summary, the source of a "pack tonight" reminder.
///
/// **Privacy:** only counts and subject names reach the notification; the item texts never do (a lock
/// screen shows "3 items for Chemistry and 1 other subject", the app shows the list when opened).
public struct PackTonightDay: Hashable, Sendable, Codable {
    /// The school day the items are needed on.
    public var date: LocalDate
    /// Start of the day's first non-cancelled lesson: `minutesBefore` offsets count back from it and no
    /// reminder fires after it.
    public var firstLessonStart: LocalTime
    /// Subjects that need items, in the order of their first lesson that day.
    public var subjects: [PackTonightSubject]

    /// Creates a day summary.
    public init(date: LocalDate, firstLessonStart: LocalTime, subjects: [PackTonightSubject]) {
        self.date = date
        self.firstLessonStart = firstLessonStart
        self.subjects = subjects
    }

    /// Total number of items to bring.
    public var itemCount: Int { subjects.reduce(0) { $0 + $1.itemCount } }

    /// Builds the summaries from resolved lessons: per date, cancelled lessons ignored, items trimmed,
    /// empty items dropped and duplicates within one subject counted once. Only days with at least one item
    /// are returned, ascending by date. Several timetables on the same date are combined.
    public static func days(from lessons: [ResolvedLesson]) -> [PackTonightDay] {
        let live = lessons.filter { $0.status != .cancelled }
        let byDate = Dictionary(grouping: live, by: \.date)
        var result: [PackTonightDay] = []
        for date in byDate.keys.sorted() {
            let dayLessons = byDate[date]!.sorted {
                ($0.startTime, $0.endTime, $0.id) < ($1.startTime, $1.endTime, $1.id)
            }
            var order: [Subject.ID] = []
            var summaries: [Subject.ID: SubjectSummary] = [:]
            var items: [Subject.ID: Set<String>] = [:]
            for lesson in dayLessons {
                let cleaned = lesson.bringList
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !cleaned.isEmpty else { continue }
                let id = lesson.subject.id
                if summaries[id] == nil {
                    order.append(id)
                    summaries[id] = lesson.subject
                }
                items[id, default: []].formUnion(cleaned)
            }
            guard !order.isEmpty, let first = dayLessons.first else { continue }
            let subjects = order.map { PackTonightSubject(subject: summaries[$0]!, itemCount: items[$0]!.count) }
            result.append(PackTonightDay(date: date, firstLessonStart: first.startTime, subjects: subjects))
        }
        return result
    }
}

/// A subject's share of a `PackTonightDay`.
public struct PackTonightSubject: Hashable, Sendable, Codable {
    /// The subject (its `name` may appear in the notification).
    public var subject: SubjectSummary
    /// Number of distinct items for this subject.
    public var itemCount: Int

    /// Creates a subject entry.
    public init(subject: SubjectSummary, itemCount: Int) {
        self.subject = subject
        self.itemCount = itemCount
    }
}
