import Foundation
import Testing
@testable import TimetableCore

/// Follow-ups (only for incomplete items) and the pack-tonight reminder. Now = 2026-10-06 12:00 CEST.
@Suite("ReminderPlanner – follow-ups and pack tonight")
struct ReminderFollowUpAndPackTests {
    typealias F = PlannerFixture

    static let due = TaskDue.dateTime(F.d("2026-10-08"), F.t("08:00"))

    // MARK: Follow-ups

    @Test func followUpAfterMinutesForIncompleteTask() throws {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(120))
        let task = F.task(1, due: Self.due, title: "Essay")
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [task]))
        #expect(plan.notifications.map(\.isFollowUp) == [false, true])
        let followUp = try #require(plan.notifications.last)
        #expect(followUp.localFireTime == LocalDateTime(date: F.d("2026-10-07"), time: F.t("19:00")))
        #expect(followUp.content.title == LocalizedText(key: "reminder.followUp.title", args: [.string("Essay")]))
        #expect(followUp.content.body == LocalizedText(key: "reminder.task.dueTomorrowAt", args: [.time(F.t("08:00"))]))
        #expect(followUp.threadID == plan.notifications[0].threadID, "same thread as its primary")
        #expect(followUp.categoryID == .task)
        #expect(followUp.ruleID == rule.id)
        #expect(followUp.id != plan.notifications[0].id)
    }

    @Test func followUpNextMorning() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .nextMorning(at: F.t("07:00")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: Self.due)]))
        #expect(plan.notifications.map(\.localFireTime) == [
            LocalDateTime(date: F.d("2026-10-07"), time: F.t("17:00")),
            LocalDateTime(date: F.d("2026-10-08"), time: F.t("07:00")),
        ])
        #expect(plan.notifications.last?.content.body == LocalizedText(key: "reminder.task.dueTodayAt", args: [.time(F.t("08:00"))]))
    }

    @Test func completedItemsGetNoReminderAndNoFollowUp() {
        let rules = [F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(120)),
                     F.rule(2, .exam, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(60))]
        let open = ReminderPlanner.plan(F.input(rules: rules, tasks: [F.task(1, due: Self.due)],
                                                exams: [F.exam(1, date: "2026-10-09", start: "08:00")]))
        #expect(open.notifications.filter(\.isFollowUp).count == 2)
        let done = ReminderPlanner.plan(F.input(rules: rules, tasks: [F.task(1, due: Self.due, completed: true)],
                                                exams: [F.exam(1, date: "2026-10-09", start: "08:00", completed: true)]))
        #expect(done.notifications.isEmpty)
        #expect(done.dropped.isEmpty)
        // Re-planning after completion removes the follow-ups (and the primaries) through the diff.
        let diff = ReminderPlanDiff.diff(old: open, new: done)
        #expect(diff.notifications.toRemove == open.notifications.map(\.id).sorted())
        #expect(diff.notifications.toAdd.isEmpty)
    }

    @Test func followUpSurvivesItsPrimaryFiring() throws {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(120))
        let task = F.task(1, due: Self.due)
        let before = ReminderPlanner.plan(F.input(rules: [rule], tasks: [task]))
        // 18:00 CEST: the 17:00 primary has fired, the 19:00 follow-up is still pending with the same ID.
        let after = ReminderPlanner.plan(F.input(now: Fixture.utc("2026-10-07", "16:00"), rules: [rule], tasks: [task]))
        let followUp = try #require(after.notifications.first)
        #expect(after.notifications.count == 1)
        #expect(followUp.isFollowUp)
        #expect(followUp == before.notifications.last)
    }

    @Test func overrideControlsTheFollowUp() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(120))
        let none = F.task(1, due: Self.due, override: ReminderOverride(followUp: .none))
        let custom = F.task(2, due: Self.due, override: ReminderOverride(followUp: .custom(.afterMinutes(30))))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [none, custom]))
        #expect(plan.plannerNotifications(for: .task(none.id)).map(\.isFollowUp) == [false])
        #expect(plan.plannerNotifications(for: .task(custom.id)).map(\.localFireTime.time) == [F.t("17:00"), F.t("17:30")])
    }

    @Test func followUpAfterTheDeadlineIsDropped() throws {
        let rule = F.rule(1, .homework, [.daysBefore(0, at: F.t("07:00"))], followUp: .nextMorning(at: F.t("07:00")))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: Self.due)]))
        #expect(plan.notifications.map(\.isFollowUp) == [false])
        let dropped = try #require(plan.dropped.first)
        #expect(dropped.reason == .afterDue)
        #expect(dropped.isFollowUp)
        #expect(dropped.fireDate == F.at("2026-10-09", "07:00"))
    }

    @Test func followUpHonoursQuietHours() {
        let rule = F.rule(1, .exam, [.daysBefore(1, at: F.t("21:00"))], followUp: .afterMinutes(120))
        let plan = ReminderPlanner.plan(F.input(settings: F.settings(quiet: QuietHours(start: F.t("22:00"), end: F.t("07:00"))),
                                                rules: [rule], exams: [F.exam(1, date: "2026-10-09", start: "10:00")]))
        #expect(plan.notifications.map(\.localFireTime) == [
            LocalDateTime(date: F.d("2026-10-08"), time: F.t("21:00")),
            LocalDateTime(date: F.d("2026-10-09"), time: F.t("07:00")),
        ])
        #expect(plan.notifications.map(\.movedByQuietHours) == [false, true])
    }

    @Test func invalidFollowUpIsReported() {
        let rule = F.rule(1, .homework, [.daysBefore(1, at: F.t("17:00"))], followUp: .afterMinutes(0))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], tasks: [F.task(1, due: Self.due)]))
        #expect(plan.notifications.count == 1)
        #expect(plan.dropped.map(\.reason) == [.invalidOffset])
        #expect(plan.dropped.map(\.isFollowUp) == [true])
    }

    // MARK: Pack tonight

    static let chemistry = F.subject(1, "Chémia")
    static let maths = F.subject(2, "Matematika")
    static let pe = F.subject(3, "Telesná")
    static let art = F.subject(4, "Výtvarná")

    static let week: [ResolvedLesson] = [
        F.lesson(1, date: "2026-10-07", start: "07:10", end: "07:55", subject: art, bring: ["Paint"], status: .cancelled),
        F.lesson(2, date: "2026-10-07", start: "08:00", end: "08:45", subject: chemistry, bring: ["Goggles", "Lab coat"]),
        F.lesson(3, date: "2026-10-07", start: "09:00", end: "09:45", subject: maths, bring: ["Calculator"]),
        F.lesson(4, date: "2026-10-07", start: "10:00", end: "10:45", subject: pe, bring: [" ", ""]),
        F.lesson(5, date: "2026-10-07", start: "11:00", end: "11:45", subject: chemistry, bring: [" Goggles "]),
        F.lesson(6, date: "2026-10-08", start: "08:00", end: "08:45", subject: maths),
        F.lesson(7, date: "2026-10-09", start: "08:00", end: "08:45", subject: pe, bring: ["Shoes"]),
        F.lesson(8, date: "2026-10-12", start: "09:30", end: "10:15", subject: maths, bring: ["Ruler"]),
    ]

    @Test func packTonightDaysSummariseBringLists() throws {
        let days = PackTonightDay.days(from: Self.week.reversed())
        #expect(days.map(\.date) == [F.d("2026-10-07"), F.d("2026-10-09"), F.d("2026-10-12")])
        let wednesday = try #require(days.first)
        #expect(wednesday.firstLessonStart == F.t("08:00"), "the cancelled 07:10 lesson does not count")
        #expect(wednesday.subjects == [PackTonightSubject(subject: Self.chemistry, itemCount: 2),
                                       PackTonightSubject(subject: Self.maths, itemCount: 1)])
        #expect(wednesday.itemCount == 3)
        #expect(days[2].firstLessonStart == F.t("09:30"))
        #expect(PackTonightDay.days(from: []).isEmpty)
    }

    @Test func packTonightEveningBeforeEachSchoolDay() throws {
        let rule = F.rule(1, .packTonight, [.daysBefore(1, at: F.t("19:00"))], followUp: .afterMinutes(30))
        let plan = ReminderPlanner.plan(F.input(rules: [rule], lessons: Self.week, packTonight: PackTonightDay.days(from: Self.week)))
        #expect(plan.notifications.map(\.localFireTime) == [
            LocalDateTime(date: F.d("2026-10-06"), time: F.t("19:00")),
            LocalDateTime(date: F.d("2026-10-08"), time: F.t("19:00")),
            LocalDateTime(date: F.d("2026-10-11"), time: F.t("19:00")), // Sunday evening before Monday
        ])
        #expect(plan.notifications.allSatisfy { !$0.isFollowUp && $0.categoryID == .packTonight && $0.threadID == "packTonight" })
        let first = try #require(plan.notifications.first)
        #expect(first.source == .packTonight(F.d("2026-10-07")))
        #expect(first.content == ReminderContent(
            title: LocalizedText(key: "reminder.packTonight.title"),
            body: LocalizedText(key: "reminder.packTonight.tomorrow", args: [.integer(3), .string("Chémia")])))
        // Privacy: the item texts never reach the notification.
        let allArgs = plan.notifications.flatMap { [$0.content.title, $0.content.body] }.flatMap(\.args)
        for item in ["Goggles", "Lab coat", "Calculator", "Shoes", "Ruler", "Paint"] {
            #expect(!allArgs.contains(.string(item)))
        }
        #expect(plan.nextReplanDate == Fixture.utc("2026-10-06", "22:00"), "lesson-derived → next local midnight")
    }

    @Test func packTonightWordingAndDeadline() {
        let days = PackTonightDay.days(from: Self.week)
        let rule = F.rule(1, .packTonight, [.daysBefore(0, at: F.t("06:30")), .daysBefore(3, at: F.t("18:00")),
                                            .daysBefore(0, at: F.t("09:00"))])
        let plan = ReminderPlanner.plan(F.input(rules: [rule], packTonight: [days[2]]))
        #expect(plan.notifications.map(\.content.body) == [
            LocalizedText(key: "reminder.packTonight.inDays",
                          args: [.integer(1), .string("Matematika"), .date(F.d("2026-10-12"))]),
            LocalizedText(key: "reminder.packTonight.today", args: [.integer(1), .string("Matematika")]),
            LocalizedText(key: "reminder.packTonight.today", args: [.integer(1), .string("Matematika")]),
        ])
        #expect(plan.notifications.map(\.localFireTime.time) == [F.t("18:00"), F.t("06:30"), F.t("09:00")])
        // 09:00 is before the 09:30 first lesson → allowed; nothing after the first lesson.
        #expect(plan.dropped.isEmpty)
        let late = ReminderPlanner.plan(F.input(rules: [F.rule(2, .packTonight, [.daysBefore(0, at: F.t("10:00"))])],
                                                packTonight: [days[2]]))
        #expect(late.notifications.isEmpty)
        #expect(late.dropped.map(\.reason) == [.afterDue])
    }

    @Test func packTonightWithoutItemsOrRulePlansNothing() {
        let empty = PackTonightDay(date: F.d("2026-10-08"), firstLessonStart: F.t("08:00"), subjects: [])
        let rule = F.rule(1, .packTonight, [.daysBefore(1, at: F.t("19:00"))])
        #expect(ReminderPlanner.plan(F.input(rules: [rule], packTonight: [empty])).notifications.isEmpty)
        let days = PackTonightDay.days(from: Self.week)
        #expect(ReminderPlanner.plan(F.input(rules: [], packTonight: days)).notifications.isEmpty)
    }
}
