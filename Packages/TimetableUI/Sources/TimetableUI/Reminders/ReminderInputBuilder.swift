// Builds the planner's `PlannerInput` from the app's database snapshot (Phase 3 Stage A). Pure, Linux-tested.
//
// - Lessons: every live timetable's occurrences from the start of today to the horizon end (the planner ignores
//   elapsed ones; today's earlier lessons still anchor date-only tasks linked to them).
// - Pack tonight: `PackTonightDay.days(from:)` over those lessons, plus each timetable's `nextSchoolDay` after the
//   horizon's last date, so the evening before the first school day past the horizon is covered too.
// - Alarms: `canScheduleAlarms` is decided by the caller (AlarmKit authorised AND the `loudAlarms` entitlement);
//   the planner itself enforces settings policy and decision D7 (alarms only from user rules).
import Foundation
import TimetableCore

/// Knobs of one planning run (defaults = the planner's defaults).
public struct ReminderPlanningOptions: Hashable, Sendable {
    public var horizonDays: Int
    public var budget: NotificationBudget
    public var alarmSoftLimit: Int
    public var canScheduleAlarms: Bool

    public init(horizonDays: Int = 14, budget: NotificationBudget = .iOSDefault, alarmSoftLimit: Int = 10,
                canScheduleAlarms: Bool) {
        self.horizonDays = horizonDays
        self.budget = budget
        self.alarmSoftLimit = alarmSoftLimit
        self.canScheduleAlarms = canScheduleAlarms
    }
}

public enum ReminderInputBuilder {
    /// Planner input for `database` at `now`. `resolvers` = `ScheduleResolver.all(database:context:)` (the app keeps
    /// them in `AppModel.resolvers`).
    public static func input(database: TabulaDatabase, resolvers: [ScheduleResolver], context: CalendarContext,
                             now: Date, options: ReminderPlanningOptions) -> PlannerInput {
        let days = max(1, options.horizonDays)
        let nowLocal = context.local(from: now)
        let horizonEnd = context.date(nowLocal.date.adding(days: days), nowLocal.time)
        let start = context.startOfDay(nowLocal.date)
        var lessons: [ResolvedLesson] = []
        var seen = Set<OccurrenceID>()
        func append(_ items: [ResolvedLesson]) {
            for lesson in items where lesson.status != .cancelled && seen.insert(lesson.id).inserted {
                lessons.append(lesson)
            }
        }
        if start < horizonEnd {
            for resolver in resolvers {
                append(resolver.occurrences(in: DateInterval(start: start, end: horizonEnd)))
            }
        }
        let lastDate = context.localDate(of: horizonEnd)
        for resolver in resolvers {
            if let next = resolver.nextSchoolDay(after: lastDate, horizonDays: 7) { append(next.entries) }
        }
        return PlannerInput(now: now, context: context, settings: database.settings, rules: database.reminderRules,
                            tasks: database.tasks, exams: database.exams, lessons: lessons,
                            packTonight: PackTonightDay.days(from: lessons), budget: options.budget,
                            alarmSoftLimit: options.alarmSoftLimit, horizonDays: days,
                            canScheduleAlarms: options.canScheduleAlarms)
    }

    /// Convenience: resolves the schedule itself.
    public static func input(database: TabulaDatabase, context: CalendarContext, now: Date,
                             options: ReminderPlanningOptions) -> PlannerInput {
        input(database: database, resolvers: ScheduleResolver.all(database: database, context: context), context: context,
              now: now, options: options)
    }
}
