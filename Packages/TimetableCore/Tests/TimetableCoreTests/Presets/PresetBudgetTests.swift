import Foundation
import Testing
@testable import TimetableCore

/// Pre-freeze QA: each profile's **default** reminder rules, applied to a typical school week, stay well under
/// the 60 planned notifications iOS leaves us (64 pending − 4 reserved).
@Suite("Preset reminder budget")
struct PresetBudgetTests {
    static let context = CalendarContext(timeZone: Fixture.zone("Europe/Bratislava"), firstWeekday: .monday)
    /// "Well under": at most half of the budget, leaving room for user rules and other timetables.
    static let ceiling = NotificationBudget.iOSDefault.available / 2

    /// Onboarding with the preset defaults + sample data + a typical week of homework: one task per school day
    /// (the profile's main kind) and a second exam.
    static func typicalWeek(_ profile: UserProfile) -> (TabulaDatabase, [ResolvedLesson]) {
        var ids = SequentialIDGenerator(namespace: 0xB0D6)
        var clock = TestClock()
        let answers = OnboardingAnswers(profile: profile, timetableName: "School", bellScheduleName: "Normal")
        var db = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: Fixture.now)
        let today = Fixture.date("2026-10-06") // Tuesday
        db = SampleData.make(profile: profile, timetable: db.timetables[0], bellSchedule: db.bellSchedules.first,
                             today: today, localize: { $0.key }, ids: &ids, clock: &clock, now: Fixture.now).merged(into: db)
        let kind: TaskKind = profile == .university ? .assignment : .homework
        for offset in 1...7 where Weekday.workweek.contains(today.adding(days: offset).weekday) {
            db.tasks.append(TaskItem(id: ids.next(), meta: .created(at: clock.tick(now: Fixture.now)), title: "T\(offset)",
                                     kind: kind, timetableID: db.timetables[0].id, due: .date(today.adding(days: offset))))
        }
        db.exams.append(Exam(id: ids.next(), meta: .created(at: clock.tick(now: Fixture.now)), timetableID: db.timetables[0].id,
                             title: "Quiz", kind: .quiz, date: today.adding(days: 3), start: Fixture.time("10:00")))
        let week = DateInterval(start: Fixture.now, duration: 7 * 86_400)
        let lessons = ScheduleResolver.all(database: db, context: context).flatMap { $0.occurrences(in: week) }
        return (db, lessons)
    }

    static func plan(_ db: TabulaDatabase, _ lessons: [ResolvedLesson], rules: [ReminderRule]? = nil) -> ReminderPlan {
        ReminderPlanner.plan(PlannerInput(now: Fixture.now, context: context, settings: db.settings,
                                          rules: rules ?? db.reminderRules, tasks: db.tasks, exams: db.exams,
                                          lessons: lessons, packTonight: PackTonightDay.days(from: lessons), horizonDays: 7))
    }

    @Test(arguments: UserProfile.knownValues)
    func defaultPlanForATypicalWeekStaysWellUnderTheBudget(profile: UserProfile) {
        let (db, lessons) = Self.typicalWeek(profile)
        #expect(!lessons.isEmpty && db.tasks.count >= 6)
        let plan = Self.plan(db, lessons)
        let count = plan.notifications.count + plan.alarms.count
        print("preset budget \(profile.rawValue): \(count) planned for a typical week (\(lessons.count) lessons)")
        #expect(count > 0, "the preset plans something")
        #expect(count <= Self.ceiling, "\(profile): \(count) > \(Self.ceiling)")
        #expect(!plan.isSaturated && plan.alarms.isEmpty)
    }

    @Test func universityLessonRemindersAreOffByDefault() {
        let rules = ProfilePreset.university.reminderRules
        #expect(rules.first { $0.target == .lesson }?.isEnabled == false)
        for target in [ReminderTarget.assignment, .homework, .exam] {
            #expect(rules.first { $0.target == target }?.isEnabled == true, "\(target)")
        }
        // Why: switched on, the 15-minute lesson rule alone adds one reminder per class.
        let (db, lessons) = Self.typicalWeek(.university)
        let enabled = db.reminderRules.map { rule -> ReminderRule in
            var copy = rule
            if copy.target == .lesson { copy.isEnabled = true }
            return copy
        }
        let off = Self.plan(db, lessons).notifications.count
        let on = Self.plan(db, lessons, rules: enabled).notifications.count
        #expect(on - off == lessons.filter { $0.start.addingTimeInterval(-15 * 60) > Fixture.now }.count)
    }
}
