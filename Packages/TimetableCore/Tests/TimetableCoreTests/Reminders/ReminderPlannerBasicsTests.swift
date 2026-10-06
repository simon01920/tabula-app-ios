import Foundation
import Testing
@testable import TimetableCore

/// Items, rules, overrides and content. Now = 2026-10-06 10:00Z = 12:00 CEST (Tuesday), Bratislava.
@Suite("ReminderPlanner – basics")
struct ReminderPlannerBasicsTests {
    typealias F = PlannerFixture

    @Test func emptyInputPlansNothing() {
        let plan = ReminderPlanner.plan(F.input(rules: []))
        #expect(plan.notifications.isEmpty)
        #expect(plan.alarms.isEmpty)
        #expect(plan.dropped.isEmpty)
        #expect(!plan.isSaturated)
        #expect(!plan.isAlarmSaturated)
        #expect(plan.saturationNotice == nil)
        #expect(plan.alarmOverflowNotice == nil)
        #expect(plan.generatedAt == Fixture.now)
        #expect(plan.horizonEnd == Fixture.utc("2026-10-20", "10:00"))
        #expect(plan.nextReplanDate == Fixture.utc("2026-10-19", "10:00"))
    }

    @Test func rulesWithoutItemsAndItemsWithoutRulesPlanNothing() {
        let rules = [F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))])]
        #expect(ReminderPlanner.plan(F.input(rules: rules)).notifications.isEmpty)
        let task = F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))
        #expect(ReminderPlanner.plan(F.input(rules: [], tasks: [task])).notifications.isEmpty)
    }

    @Test func homeworkDayBeforeReminder() throws {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))])
        let task = F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")), title: "Úloha 3")
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [task]))
        let note = try #require(plan.notifications.first)
        #expect(plan.notifications.count == 1)
        #expect(note.fireDate == Fixture.utc("2026-10-07", "15:00"))
        #expect(note.localFireTime == LocalDateTime(date: F.d("2026-10-07"), time: F.t("17:00")))
        #expect(note.requestedTier == .standard)
        #expect(note.effectiveTier == .standard)
        #expect(note.tierChanges.isEmpty)
        #expect(note.content.title == LocalizedText(key: "reminder.task.title", args: [.string("Úloha 3")]))
        #expect(note.content.subtitle == nil)
        #expect(note.content.body == LocalizedText(key: "reminder.task.dueTomorrowAt", args: [.time(F.t("08:00"))]))
        #expect(note.threadID == "task/\(task.id.uuidString)")
        #expect(note.categoryID == .task)
        #expect(note.source == .task(task.id))
        #expect(note.ruleID == rule.id)
        #expect(!note.isFollowUp)
        #expect(!note.movedByQuietHours)
        #expect(ReminderID.isPlannerID(note.id.rawValue))
        #expect(plan.nextReplanDate == note.fireDate)
    }

    @Test func taskKindSelectsTheRuleTarget() {
        let rules = [F.rule(1, .homework, [.minutesBefore(60)]), F.rule(2, .assignment, [.minutesBefore(120)]),
                     F.rule(3, .todo, [.minutesBefore(30)])]
        let due = TaskDue.dateTime(F.d("2026-10-08"), F.t("10:00"))
        let tasks = [F.task(1, due: due, kind: .homework), F.task(2, due: due, kind: .assignment),
                     F.task(3, due: due, kind: .todo), F.task(4, due: due, kind: TaskKind(rawValue: "essay"))]
        let plan = ReminderPlanner.plan(F.input(rules: rules, tasks: tasks))
        #expect(plan.plannerNotifications(for: .task(F.taskID(1))).map(\.localFireTime.time) == [F.t("09:00")])
        #expect(plan.plannerNotifications(for: .task(F.taskID(2))).map(\.localFireTime.time) == [F.t("08:00")])
        #expect(plan.plannerNotifications(for: .task(F.taskID(3))).map(\.localFireTime.time) == [F.t("09:30")])
        #expect(plan.plannerNotifications(for: .task(F.taskID(4))).isEmpty, "unknown kind matches no known target")
    }

    @Test func relativeDayWordingFollowsTheFireDate() {
        let rule = F.rule(1, .homework, [.daysBefore(3, at: F.t("18:00")), .daysBefore(1, at: F.t("18:00")),
                                         .daysBefore(0, at: F.t("07:00"))])
        let timed = F.task(1, due: .dateTime(F.d("2026-10-12"), F.t("08:00")))
        let dated = F.task(2, due: .date(F.d("2026-10-12")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [timed, dated]))
        #expect(plan.plannerNotifications(for: .task(timed.id)).map(\.content.body) == [
            LocalizedText(key: "reminder.task.dueInDaysAt", args: [.integer(3), .date(F.d("2026-10-12")), .time(F.t("08:00"))]),
            LocalizedText(key: "reminder.task.dueTomorrowAt", args: [.time(F.t("08:00"))]),
            LocalizedText(key: "reminder.task.dueTodayAt", args: [.time(F.t("08:00"))]),
        ])
        #expect(plan.plannerNotifications(for: .task(dated.id)).map(\.content.body) == [
            LocalizedText(key: "reminder.task.dueInDays", args: [.integer(3), .date(F.d("2026-10-12"))]),
            LocalizedText(key: "reminder.task.dueTomorrow"),
            LocalizedText(key: "reminder.task.dueToday"),
        ])
    }

    @Test func dateOnlyTaskAnchorsAtEightAndAllowsTheWholeDueDay() {
        let rule = F.rule(1, .homework, [.minutesBefore(60), .daysBefore(0, at: F.t("19:00"))])
        let task = F.task(1, due: .date(F.d("2026-10-08")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [task]))
        #expect(plan.notifications.map(\.localFireTime) == [
            LocalDateTime(date: F.d("2026-10-08"), time: F.t("07:00")),
            LocalDateTime(date: F.d("2026-10-08"), time: F.t("19:00")),
        ])
        #expect(plan.dropped.isEmpty)
    }

    @Test func dateOnlyAnchorTimeIsConfigurable() {
        let rule = F.rule(1, .homework, [.minutesBefore(60)])
        var input = F.input(rules: [rule], tasks: [F.task(1, due: .date(F.d("2026-10-08")))])
        input.dateOnlyAnchorTime = F.t("12:30")
        #expect(ReminderPlanner.plan(input).notifications.map(\.localFireTime.time) == [F.t("11:30")])
    }

    @Test func dateOnlyTaskLinkedToALessonAnchorsAtTheLessonStart() {
        let maths = F.subject(1, "Matematika")
        let lesson = F.lesson(7, date: "2026-10-08", start: "10:00", end: "10:45", subject: maths)
        let lessonID: Lesson.ID = F.id(7, ns: F.lessonNS)
        let rule = F.rule(1, .homework, [.minutesBefore(60), .daysBefore(0, at: F.t("11:00"))])
        let linked = F.task(1, due: .date(F.d("2026-10-08")), linked: LessonLink(lessonID: lessonID, date: F.d("2026-10-08")))
        let otherDay = F.task(2, due: .date(F.d("2026-10-08")), linked: LessonLink(lessonID: lessonID, date: F.d("2026-10-09")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [linked, otherDay], lessons: [lesson]))
        // Linked: anchored at 10:00 and due then, so 11:00 is after the deadline.
        #expect(plan.plannerNotifications(for: .task(linked.id)).map(\.localFireTime.time) == [F.t("09:00")])
        #expect(plan.dropped.map(\.reason) == [.afterDue])
        #expect(plan.dropped.first?.source == .task(linked.id))
        // A link to another date is ignored: date-only semantics (08:00 anchor, whole day allowed).
        #expect(plan.plannerNotifications(for: .task(otherDay.id)).map(\.localFireTime.time) == [F.t("07:00"), F.t("11:00")])
        // The text stays date-only (the user never set a time).
        #expect(plan.plannerNotifications(for: .task(linked.id)).first?.content.body == LocalizedText(key: "reminder.task.dueToday"))
    }

    @Test func examContentWithAndWithoutStart() throws {
        let rule = F.rule(1, .exam, [.daysBefore(1, at: F.t("18:00"))])
        let timed = F.exam(1, date: "2026-10-09", start: "09:00", room: " 204 ", title: "Písomka")
        let dated = F.exam(2, date: "2026-10-09", room: "  ", title: "Oral")
        let plan = ReminderPlanner.plan(F.input(rules: [rule], exams: [timed, dated]))
        let first = try #require(plan.plannerNotifications(for: .exam(timed.id)).first)
        #expect(first.content == ReminderContent(
            title: LocalizedText(key: "reminder.exam.title", args: [.string("Písomka")]),
            subtitle: LocalizedText(key: "reminder.room", args: [.string("204")]),
            body: LocalizedText(key: "reminder.exam.tomorrowAt", args: [.time(F.t("09:00"))])))
        #expect(first.categoryID == .exam)
        #expect(first.threadID == "exam/\(timed.id.uuidString)")
        let second = try #require(plan.plannerNotifications(for: .exam(dated.id)).first)
        #expect(second.content.subtitle == nil, "blank room → no subtitle")
        #expect(second.content.body == LocalizedText(key: "reminder.exam.tomorrow"))
    }

    @Test func lessonReminders() throws {
        let physics = F.subject(1, "Fyzika")
        let lessons = [
            F.lesson(1, date: "2026-10-07", start: "08:00", end: "08:45", subject: physics, room: "Lab 2"),
            F.lesson(2, date: "2026-10-07", start: "08:55", end: "09:40", subject: physics, status: .cancelled),
            F.lesson(3, date: "2026-10-07", start: "10:00", end: "10:45", subject: physics, status: .modified),
            F.lesson(4, date: "2026-10-08", start: "08:00", end: "08:45", subject: physics, status: .added),
        ]
        let rules = [F.rule(1, .lesson, [.minutesBefore(5)], tier: .timeSensitive, followUp: .afterMinutes(10))]
        let plan = ReminderPlanner.plan(F.input(rules: rules, lessons: lessons))
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("07:55"), F.t("09:55"), F.t("07:55")])
        #expect(plan.notifications.allSatisfy { $0.effectiveTier == .timeSensitive && !$0.isFollowUp })
        let first = try #require(plan.notifications.first)
        #expect(first.content == ReminderContent(
            title: LocalizedText(key: "reminder.lesson.title", args: [.string("Fyzika")]),
            subtitle: LocalizedText(key: "reminder.room", args: [.string("Lab 2")]),
            body: LocalizedText(key: "reminder.lesson.todayAt", args: [.time(F.t("08:00"))])))
        #expect(first.categoryID == .lesson)
        #expect(first.threadID == "lessons")
        #expect(first.source == .lesson(lessons[0].id))
        // Lesson-derived reminders make the plan re-plan at the next local midnight (2026-10-07 00:00 CEST).
        #expect(plan.nextReplanDate == Fixture.utc("2026-10-06", "22:00"))
    }

    @Test func lessonDayBeforeWording() {
        let lesson = F.lesson(1, date: "2026-10-12", start: "08:00", end: "08:45", subject: F.subject(1, "Bio"))
        let rule = F.rule(1, .lesson, [.daysBefore(1, at: F.t("20:00")), .daysBefore(4, at: F.t("20:00"))])
        let plan = ReminderPlanner.plan(F.input(rules: [rule], lessons: [lesson]))
        #expect(plan.notifications.map(\.content.body) == [
            LocalizedText(key: "reminder.lesson.inDaysAt", args: [.integer(4), .date(F.d("2026-10-12")), .time(F.t("08:00"))]),
            LocalizedText(key: "reminder.lesson.tomorrowAt", args: [.time(F.t("08:00"))]),
        ])
    }

    @Test func deletedDisabledCompletedAndUndatedPlanNothing() {
        let due = TaskDue.dateTime(F.d("2026-10-08"), F.t("08:00"))
        let offsets: [ReminderOffset] = [.daysBefore(1, at: F.t("17:00"))]
        let rules = [F.rule(1, .homework, offsets, enabled: false), F.rule(2, .homework, offsets, deleted: true),
                     F.rule(3, .exam, offsets), F.rule(4, .assignment, offsets)]
        let plan = ReminderPlanner.plan(F.input(
            rules: rules,
            tasks: [F.task(1, due: due), F.task(2, due: due, kind: .assignment, completed: true),
                    F.task(3, due: due, kind: .assignment, deleted: true), F.task(4, due: nil, kind: .assignment)],
            exams: [F.exam(1, date: "2026-10-08", start: "08:00", completed: true)]))
        #expect(plan.notifications.isEmpty)
        #expect(plan.dropped.isEmpty)
    }

    @Test func pastItemsPlanNothingAndReportNothing() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00")), .minutesBefore(-5)], followUp: .nextMorning(at: F.t("07:00")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: .dateTime(F.d("2026-10-01"), F.t("08:00")))]))
        #expect(plan.notifications.isEmpty)
        #expect(plan.dropped.isEmpty)
    }

    @Test func remindersBeyondTheHorizonAreDeferredNotDropped() {
        let rule = F.rule(1, .exam, [.daysBefore(7, at: F.t("18:00")), .daysBefore(1, at: F.t("18:00"))])
        // Exam on 2026-10-25: 7 days before = 10-18 (inside), 1 day before = 10-24 (after horizon end 10-20).
        let plan = ReminderPlanner.plan(F.input(rules: [rule], exams: [F.exam(1, date: "2026-10-25", start: "09:00")]))
        #expect(plan.notifications.map(\.localFireTime) == [LocalDateTime(date: F.d("2026-10-18"), time: F.t("18:00"))])
        #expect(plan.dropped.isEmpty)
    }

    @Test func overrideDisablesReplacesAndStandsAlone() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))])
        let due = TaskDue.dateTime(F.d("2026-10-08"), F.t("10:00"))
        let silenced = F.task(1, due: due, override: ReminderOverride(isEnabled: false))
        let replaced = F.task(2, due: due, override: ReminderOverride(offsets: [.minutesBefore(15)], tier: .timeSensitive))
        let inherits = F.task(3, due: due, override: ReminderOverride())
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [silenced, replaced, inherits]))
        #expect(plan.plannerNotifications(for: .task(silenced.id)).isEmpty)
        let replacedNotes = plan.plannerNotifications(for: .task(replaced.id))
        #expect(replacedNotes.map(\.localFireTime.time) == [F.t("09:45")])
        #expect(replacedNotes.map(\.effectiveTier) == [.timeSensitive])
        #expect(replacedNotes.map(\.ruleID) == [rule.id])
        #expect(plan.plannerNotifications(for: .task(inherits.id)).map(\.localFireTime.time) == [F.t("17:00")])

        // No matching rule: override offsets still plan (a virtual user rule without rule ID).
        let todo = F.task(4, due: due, kind: .todo,
                          override: ReminderOverride(offsets: [.minutesBefore(30)], followUp: .custom(.afterMinutes(10))))
        let lonely = F.task(5, due: due, kind: .todo, override: ReminderOverride(tier: .timeSensitive))
        let standalone = ReminderPlanner.plan(F.input(rules: [rule], tasks: [todo, lonely]))
        #expect(standalone.notifications.map(\.localFireTime.time) == [F.t("09:30"), F.t("09:40")])
        #expect(standalone.notifications.allSatisfy { $0.ruleID == nil && $0.source == .task(todo.id) })
        #expect(standalone.notifications.map(\.isFollowUp) == [false, true])
        #expect(standalone.notifications.map(\.effectiveTier) == [.standard, .standard])
    }

    @Test func unknownAndNegativeOffsetsAreReportedNotPlanned() {
        let unknown = ReminderOffset.unknown(.object(["kind": .string("weeksBefore"), "weeks": .integer(1)]))
        let rule = F.rule(1, .exam, [unknown, .minutesBefore(-5), .daysBefore(-1, at: F.t("08:00")), .minutesBefore(30)])
        let exam = F.exam(1, date: "2026-10-09", start: "09:00")
        let plan = ReminderPlanner.plan(F.input(rules: [rule], exams: [exam]))
        #expect(plan.notifications.count == 1)
        #expect(plan.dropped.map(\.reason).sorted { $0.rawValue < $1.rawValue } == [.invalidOffset, .invalidOffset, .unsupportedOffset])
        #expect(plan.dropped.allSatisfy { $0.fireDate == nil && $0.source == .exam(exam.id) && $0.ruleID == rule.id })
        #expect(Set(plan.dropped.map(\.id)).count == 3)
    }

    @Test func sameItemSameInstantIsDeduplicated() throws {
        let offsets: [ReminderOffset] = [.daysBefore(1, at: F.t("17:00"))]
        let rules = [F.rule(1, .homework, offsets), F.rule(2, .homework, offsets)]
        let task = F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))
        let plan = ReminderPlanner.plan(F.input(rules: rules, tasks: [task]))
        let kept = try #require(plan.notifications.first)
        let dup = try #require(plan.dropped.first)
        #expect(plan.notifications.count == 1)
        #expect(plan.dropped.count == 1)
        #expect(dup.reason == .duplicate)
        #expect(dup.fireDate == kept.fireDate)
        #expect(kept.id < dup.id, "the smaller ID wins a tie")
    }

    @Test func deduplicationKeepsTheHigherTier() throws {
        let rules = [F.rule(1, .exam, [.minutesBefore(30)]), F.rule(2, .exam, [.minutesBefore(30)], tier: .timeSensitive)]
        let plan = ReminderPlanner.plan(F.input(rules: rules, exams: [F.exam(1, date: "2026-10-08", start: "09:00")]))
        let kept = try #require(plan.notifications.first)
        #expect(plan.notifications.count == 1)
        #expect(kept.effectiveTier == .timeSensitive)
        #expect(kept.ruleID == F.ruleID(2))
        #expect(plan.dropped.map(\.reason) == [.duplicate])
        #expect(plan.dropped.first?.ruleID == F.ruleID(1))
    }

    @Test func rulesForUnknownTargetsAreIgnored() {
        let rule = F.rule(1, ReminderTarget(rawValue: "club"), [.minutesBefore(5)])
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: .dateTime(F.d("2026-10-08"), F.t("08:00")))]))
        #expect(plan.notifications.isEmpty)
    }
}
