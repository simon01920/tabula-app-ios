import Foundation
import Testing
@testable import TimetableCore

// Helpers for the Stage 2C reminder-planner tests. Every name starts with `Planner` so nothing collides with
// other stages' helpers in the shared `TimetableCoreTests` module.

/// Builders for planner inputs.
enum PlannerFixture {
    static let bratislava = CalendarContext(timeZone: Fixture.zone("Europe/Bratislava"), firstWeekday: .monday)
    static let newYork = CalendarContext(timeZone: Fixture.zone("America/New_York"), firstWeekday: .sunday)
    static let utc = CalendarContext(timeZone: Fixture.zone("UTC"), firstWeekday: .monday)

    // Namespaces keep IDs of different entity kinds apart and readable in failures.
    static let ruleNS: UInt32 = 0x2C01
    static let taskNS: UInt32 = 0x2C02
    static let examNS: UInt32 = 0x2C03
    static let subjectNS: UInt32 = 0x2C04
    static let lessonNS: UInt32 = 0x2C05
    static let timetableNS: UInt32 = 0x2C06

    /// The `n`-th deterministic ID in namespace `ns`.
    static func id<Entity>(_ n: UInt64, ns: UInt32) -> EntityID<Entity> {
        var generator = SequentialIDGenerator(namespace: ns, start: n)
        return generator.next()
    }

    static func ruleID(_ n: UInt64) -> ReminderRule.ID { id(n, ns: ruleNS) }
    static func taskID(_ n: UInt64) -> TaskItem.ID { id(n, ns: taskNS) }
    static func examID(_ n: UInt64) -> Exam.ID { id(n, ns: examNS) }
    static let timetableID: Timetable.ID = id(1, ns: timetableNS)

    static func t(_ string: String) -> LocalTime { Fixture.time(string) }
    static func d(_ string: String) -> LocalDate { Fixture.date(string) }

    static func settings(quiet: QuietHours? = nil, timeSensitive: TimeSensitivePolicy = TimeSensitivePolicy(),
                         alarms: AlarmPolicy = AlarmPolicy()) -> AppSettings {
        AppSettings(meta: Fixture.meta(), globalQuietHours: quiet, timeSensitivePolicy: timeSensitive, alarmPolicy: alarms)
    }

    /// Alarm policy with loud alarms switched on (user opt-in), preset alarms still off.
    static let alarmsOn = AlarmPolicy(isEnabled: true, allowsPresetRules: false)

    static func rule(_ n: UInt64, _ target: ReminderTarget, _ offsets: [ReminderOffset], tier: DeliveryTier = .standard,
                     followUp: FollowUp? = nil, quiet: QuietHours? = nil, origin: RuleOrigin = .user,
                     enabled: Bool = true, deleted: Bool = false) -> ReminderRule {
        var meta = Fixture.meta()
        meta.isDeleted = deleted
        return ReminderRule(id: ruleID(n), meta: meta, target: target, offsets: offsets, followUp: followUp, tier: tier,
                            quietHours: quiet, isEnabled: enabled, origin: origin)
    }

    static func task(_ n: UInt64, due: TaskDue?, kind: TaskKind = .homework, title: String? = nil,
                     completed: Bool = false, deleted: Bool = false, linked: LessonLink? = nil,
                     override: ReminderOverride? = nil) -> TaskItem {
        var meta = Fixture.meta()
        meta.isDeleted = deleted
        return TaskItem(id: taskID(n), meta: meta, title: title ?? "Task \(n)", kind: kind, due: due, linkedLesson: linked,
                        completedAt: completed ? Fixture.now : nil, reminderOverride: override)
    }

    static func exam(_ n: UInt64, date: String, start: String? = nil, room: String? = nil, title: String? = nil,
                     completed: Bool = false, override: ReminderOverride? = nil) -> Exam {
        Exam(id: examID(n), meta: Fixture.meta(), title: title ?? "Exam \(n)", date: d(date), start: start.map(t),
             room: room, reminderOverride: override, completedAt: completed ? Fixture.now : nil)
    }

    static func subject(_ n: UInt64, _ name: String) -> SubjectSummary {
        SubjectSummary(id: id(n, ns: subjectNS), name: name, color: .black)
    }

    /// A resolved occurrence of recurring lesson `n` on `date` (instants computed in `context`).
    static func lesson(_ n: UInt64, date: String, start: String, end: String, subject: SubjectSummary,
                       room: String? = nil, bring: [String] = [], status: ResolvedLesson.Status = .scheduled,
                       context: CalendarContext = bratislava) -> ResolvedLesson {
        let lessonID: Lesson.ID = id(n, ns: lessonNS)
        return ResolvedLesson(id: .lesson(lessonID, on: d(date)), source: .lesson(lessonID), timetableID: timetableID,
                              date: d(date), subject: subject, startTime: t(start), endTime: t(end),
                              start: context.date(d(date), t(start)), end: context.date(d(date), t(end)),
                              room: room, bringList: bring, status: status)
    }

    static func input(now: Date = Fixture.now, context: CalendarContext = bratislava,
                      settings: AppSettings = settings(), rules: [ReminderRule], tasks: [TaskItem] = [],
                      exams: [Exam] = [], lessons: [ResolvedLesson] = [], packTonight: [PackTonightDay] = [],
                      budget: NotificationBudget = .iOSDefault, alarmSoftLimit: Int = 10, horizonDays: Int = 14,
                      canScheduleAlarms: Bool = true) -> PlannerInput {
        PlannerInput(now: now, context: context, settings: settings, rules: rules, tasks: tasks, exams: exams,
                     lessons: lessons, packTonight: packTonight, budget: budget, alarmSoftLimit: alarmSoftLimit,
                     horizonDays: horizonDays, canScheduleAlarms: canScheduleAlarms)
    }

    /// Wall-clock `date` `time` in `context` as an instant.
    static func at(_ date: String, _ time: String, _ context: CalendarContext = bratislava) -> Date {
        context.date(d(date), t(time))
    }
}

extension ReminderPlan {
    /// Notifications for one source.
    func plannerNotifications(for source: ReminderSource) -> [PlannedNotification] {
        notifications.filter { $0.source == source }
    }

    /// Every ID the plan schedules (notifications and alarms).
    var plannerScheduledIDs: [ReminderID] { notifications.map(\.id) + alarms.map(\.id) }

    /// Every catalog key in the scheduled content (including nested texts).
    var plannerContentKeys: Set<String> {
        var keys = Set<String>()
        func visit(_ text: LocalizedText) {
            keys.insert(text.key)
            for case .text(let nested) in text.args { visit(nested) }
        }
        for content in notifications.map(\.content) + alarms.map(\.content) {
            visit(content.title)
            visit(content.body)
            if let subtitle = content.subtitle { visit(subtitle) }
        }
        return keys
    }
}
