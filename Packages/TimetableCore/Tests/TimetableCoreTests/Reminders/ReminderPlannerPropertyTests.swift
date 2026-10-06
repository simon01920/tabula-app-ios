import Foundation
import Testing
@testable import TimetableCore

/// Randomised scenarios (seeded, reproducible) checked against the planner's invariants.
@Suite("ReminderPlanner – properties")
struct ReminderPlannerPropertyTests {
    typealias F = PlannerFixture

    static let zones = ["Europe/Bratislava", "America/New_York", "UTC", "Asia/Tokyo", "Australia/Lord_Howe",
                        "America/Sao_Paulo", "Pacific/Chatham", "Asia/Kolkata"]
    static let targets: [ReminderTarget] = ReminderTarget.knownValues + [ReminderTarget(rawValue: "future")]

    /// A random but valid-ish world: rules (including negative/unknown offsets), tasks, exams, lessons.
    static func scenario(seed: UInt64) -> PlannerInput {
        var rng = TestRNG(seed: seed)
        func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
        func chance(_ percent: Int) -> Bool { int(1...100) <= percent }
        func time() -> LocalTime { LocalTime(minuteOfDay: int(0...95) * 15)! }

        let context = CalendarContext(timeZone: Fixture.zone(zones[int(0...zones.count - 1)]),
                                      firstWeekday: Weekday(rawValue: int(1...7))!)
        let now = Fixture.utc("2026-01-01", "00:00").addingTimeInterval(TimeInterval(int(0...(730 * 1440)) * 60 + int(0...59)))
        let today = context.localDate(of: now)
        let settings = F.settings(
            quiet: chance(50) ? QuietHours(start: time(), end: time()) : nil,
            timeSensitive: TimeSensitivePolicy(isEnabled: chance(80), maxLeadMinutes: [0, 30, 60, 120][int(0...3)]),
            alarms: AlarmPolicy(isEnabled: chance(60), allowsPresetRules: chance(30)))

        func offset() -> ReminderOffset {
            switch int(1...20) {
            case 1: return .unknown(.object(["kind": .string("x")]))
            case 2: return .minutesBefore(-int(1...30))
            case 3...10: return .minutesBefore(int(0...1500))
            default: return .daysBefore(chance(5) ? -1 : int(0...10), at: time())
            }
        }
        let rules: [ReminderRule] = (1...int(1...6)).map { n in
            let followUp: FollowUp? = chance(40) ? (chance(50) ? .afterMinutes(int(0...600)) : .nextMorning(at: time())) : nil
            return F.rule(UInt64(n), targets[int(0...targets.count - 1)], (1...int(1...3)).map { _ in offset() },
                          tier: DeliveryTier.allCases[int(0...2)], followUp: followUp,
                          quiet: chance(20) ? QuietHours(start: time(), end: time()) : nil,
                          origin: chance(50) ? .user : .preset, enabled: chance(90), deleted: chance(5))
        }
        func override() -> ReminderOverride? {
            guard chance(15) else { return nil }
            let follows: [FollowUpOverride] = [.inherit, .none, .custom(.afterMinutes(int(1...120)))]
            return ReminderOverride(isEnabled: chance(80), offsets: chance(50) ? [offset()] : nil,
                                    tier: chance(50) ? DeliveryTier.allCases[int(0...2)] : nil, followUp: follows[int(0...2)])
        }
        let kinds: [TaskKind] = [.homework, .assignment, .todo]
        let tasks: [TaskItem] = (0..<int(0...80)).map { n in
            let date = today.adding(days: int(-3...20))
            let due: TaskDue? = chance(10) ? nil : (chance(50) ? .dateTime(date, time()) : .date(date))
            return F.task(UInt64(n + 1), due: due, kind: kinds[int(0...2)], completed: chance(15), override: override())
        }
        let exams: [Exam] = (0..<int(0...20)).map { n in
            let date = today.adding(days: int(-2...25))
            return Exam(id: F.examID(UInt64(n + 1)), meta: Fixture.meta(), title: "E\(n)", date: date,
                        start: chance(60) ? time() : nil, reminderOverride: override(), completedAt: chance(10) ? now : nil)
        }
        let subjects = (1...4).map { F.subject(UInt64($0), "S\($0)") }
        let lessons: [ResolvedLesson] = (0..<int(0...40)).map { n in
            let date = today.adding(days: int(-1...15))
            let start = LocalTime(minuteOfDay: int(28...64) * 15)!
            let lessonID: Lesson.ID = F.id(UInt64(n + 1), ns: F.lessonNS)
            return ResolvedLesson(id: .lesson(lessonID, on: date), source: .lesson(lessonID), timetableID: F.timetableID,
                                  date: date, subject: subjects[int(0...3)], startTime: start,
                                  endTime: start.adding(minutes: 45)!, start: context.date(date, start),
                                  end: context.date(date, start.adding(minutes: 45)!),
                                  bringList: chance(30) ? (0..<int(1...3)).map { "item\($0)" } : [],
                                  status: chance(10) ? .cancelled : .scheduled)
        }
        let budget = chance(70) ? NotificationBudget.iOSDefault : NotificationBudget(maxPending: int(0...20), reserved: int(0...5))
        return PlannerInput(now: now, context: context, settings: settings, rules: rules, tasks: tasks, exams: exams,
                            lessons: lessons, packTonight: PackTonightDay.days(from: lessons), budget: budget,
                            alarmSoftLimit: int(0...12), horizonDays: int(0...21), canScheduleAlarms: chance(80))
    }

    @Test func invariantsHoldForRandomScenarios() {
        var failures = FailureBudget(limit: 8)
        var totalScheduled = 0, totalDropped = 0, saturated = 0, withAlarms = 0
        let allKeys = Set(ReminderL10n.allKeys)
        for seed in UInt64(1)...300 {
            let input = Self.scenario(seed: seed)
            let plan = ReminderPlanner.plan(input)
            totalScheduled += plan.notifications.count + plan.alarms.count
            totalDropped += plan.dropped.count
            if plan.isSaturated { saturated += 1 }
            if !plan.alarms.isEmpty { withAlarms += 1 }
            let problems = Self.violations(of: plan, input: input, allKeys: allKeys)
            for problem in problems where !failures.record("seed \(seed): \(problem)") { return }
            if ReminderPlanner.plan(input) != plan, !failures.record("seed \(seed): not deterministic") { return }
        }
        // The generator must actually exercise the interesting paths.
        #expect(totalScheduled > 3000)
        #expect(totalDropped > 300)
        #expect(saturated > 10)
        #expect(withAlarms > 10)
    }

    static func violations(of plan: ReminderPlan, input: PlannerInput, allKeys: Set<String>) -> [String] {
        var problems: [String] = []
        let context = input.context
        let now = input.now
        let all: [(id: ReminderID, fire: Date, local: LocalDateTime, source: ReminderSource)] =
            plan.notifications.map { ($0.id, $0.fireDate, $0.localFireTime, $0.source) }
            + plan.alarms.map { ($0.id, $0.fireDate, $0.localFireTime, $0.source) }

        // Window: nothing in the past, nothing past the horizon.
        if plan.horizonEnd <= now { problems.append("horizon end not after now") }
        for item in all where item.fire <= now || item.fire > plan.horizonEnd {
            problems.append("\(item.id) fires outside (now, horizonEnd]")
        }
        // Budgets.
        if plan.notifications.count > input.budget.available { problems.append("over budget") }
        if input.budget == .iOSDefault && plan.notifications.count > 60 { problems.append("more than 60") }
        if plan.alarms.count > max(0, input.alarmSoftLimit) { problems.append("over alarm soft limit") }
        let budgetDrops = plan.dropped.filter { $0.reason == .budget }
        if plan.isSaturated != !budgetDrops.isEmpty { problems.append("isSaturated mismatch") }
        if plan.isSaturated && plan.notifications.count != input.budget.available { problems.append("saturated but not full") }
        // Unique IDs across scheduled and dropped.
        let ids = all.map(\.id) + plan.dropped.map(\.id)
        if Set(ids).count != ids.count { problems.append("duplicate IDs") }
        // Order.
        let tierOrder = plan.notifications.map { ($0.fireDate, -$0.effectiveTier.planRank, $0.id) }
        for (a, b) in zip(tierOrder, tierOrder.dropFirst()) where !(a < b) { problems.append("notifications out of order") }
        // Tiers.
        for note in plan.notifications {
            if note.effectiveTier == .alarm { problems.append("notification with alarm tier") }
            if note.effectiveTier > note.requestedTier { problems.append("tier upgraded") }
            if note.tierChanges.isEmpty != (note.effectiveTier == note.requestedTier) { problems.append("tierChanges mismatch") }
            if note.isFollowUp && !note.source.isCompletable { problems.append("follow-up for a non-completable source") }
        }
        // Wall clock: consistent and never a nonexistent local time.
        for item in all {
            if context.local(from: item.fire) != item.local { problems.append("\(item.id) localFireTime mismatch") }
            switch context.resolve(item.local.date, item.local.time) {
            case .skipped: problems.append("\(item.id) at a nonexistent local time")
            case .unique(let date): if date != item.fire { problems.append("\(item.id) wall clock does not map back") }
            case .repeated(let earlier, let later):
                if item.fire != earlier && item.fire != later { problems.append("\(item.id) repeated-hour mismatch") }
            }
        }
        // Global quiet hours (rules without own quiet hours; alarms are exempt).
        let rulesByID = Dictionary(input.rules.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let quiet = input.settings.globalQuietHours {
            // Alarm fallbacks keep the alarm's time (alarms are exempt from global quiet hours).
            for note in plan.notifications
            where note.ruleID.flatMap({ rulesByID[$0]?.quietHours }) == nil && !note.tierChanges.contains(.alarmLimitReached) {
                if quiet.contains(note.localFireTime.time) { problems.append("\(note.id) inside global quiet hours") }
            }
        }
        // Completed or deleted items never appear.
        let closedTasks = Set(input.tasks.filter { $0.isCompleted || $0.isDeleted }.map { ReminderSource.task($0.id) })
        let closedExams = Set(input.exams.filter(\.isCompleted).map { ReminderSource.exam($0.id) })
        for source in all.map(\.source) + plan.dropped.map(\.source)
        where closedTasks.contains(source) || closedExams.contains(source) {
            problems.append("completed item \(source.rawValue) planned")
        }
        // Timed exams: never after the start; Time Sensitive only within the lead limit.
        let timedExams = Dictionary(input.exams.compactMap { exam in exam.start.map { (ReminderSource.exam(exam.id), context.date(exam.date, $0)) } },
                                    uniquingKeysWith: { a, _ in a })
        let maxLead = TimeInterval(max(0, input.settings.timeSensitivePolicy.maxLeadMinutes)) * 60
        for note in plan.notifications {
            guard let start = timedExams[note.source] else { continue }
            if note.fireDate > start { problems.append("\(note.id) after the exam start") }
            if note.effectiveTier == .timeSensitive
                && (!input.settings.timeSensitivePolicy.isEnabled || start.timeIntervalSince(note.fireDate) > maxLead) {
                problems.append("\(note.id) Time Sensitive beyond the lead limit")
            }
        }
        // Drops inside the window carry a date; content keys are all catalogued.
        for drop in plan.dropped where drop.reason == .budget || drop.reason == .duplicate {
            guard let fire = drop.fireDate, fire > now, fire <= plan.horizonEnd else {
                problems.append("\(drop.id) \(drop.reason) without an in-window date")
                continue
            }
        }
        let unknownKeys = plan.plannerContentKeys.subtracting(allKeys)
        if !unknownKeys.isEmpty { problems.append("uncatalogued keys \(unknownKeys)") }
        // Re-plan date.
        if plan.nextReplanDate <= now || plan.nextReplanDate > plan.horizonEnd { problems.append("nextReplanDate out of range") }
        // Diff against itself is empty; against nothing adds everything.
        if !ReminderPlanDiff.diff(old: plan, new: plan).isEmpty { problems.append("self-diff not empty") }
        if ReminderPlanDiff.diff(old: nil, new: plan).notifications.toAdd.count != plan.notifications.count {
            problems.append("diff from nil incomplete")
        }
        return problems
    }
}

extension DeliveryTier {
    /// Numeric rank for property-test ordering checks.
    fileprivate var planRank: Int { DeliveryTier.allCases.firstIndex(of: self)! }
}
