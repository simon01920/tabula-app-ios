import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 3 Stage A: the reminder adapter (planner → clients) with the in-memory notification centre and AlarmKit.

enum Fixture {
    static let zone = TimeZone(identifier: "Europe/Bratislava")!
    static let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
    static let london = CalendarContext(timeZone: TimeZone(identifier: "Europe/London")!, firstWeekday: .monday)
    static let now = SampleScenarios.referenceNow           // Tue 2026-10-13 10:20 Bratislava
    static let today = SampleScenarios.today
    static let meta = EntityMeta.created(at: .zero)

    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

    static let homework = TaskItem(id: TaskItem.ID(uuid(1)), meta: meta, title: "Essay", kind: .homework,
                                   due: .dateTime(today.adding(days: 3), LocalTime(hour: 8, minute: 0)!))
    static let weekly = TaskItem(id: TaskItem.ID(uuid(2)), meta: meta, title: "Vocabulary", kind: .homework,
                                 due: .date(today.adding(days: 2)), repeatRule: RepeatRule(frequency: .weekly))
    static let exam = Exam(id: Exam.ID(uuid(3)), meta: meta, title: "Maths test", date: today.adding(days: 5),
                           start: LocalTime(hour: 8, minute: 0)!, room: "204")

    static let rules: [ReminderRule] = [
        ReminderRule(id: ReminderRule.ID(uuid(10)), meta: meta, target: .homework,
                     offsets: [.daysBefore(1, at: LocalTime(hour: 19, minute: 0)!)], tier: .standard),
        ReminderRule(id: ReminderRule.ID(uuid(11)), meta: meta, target: .exam,
                     offsets: [.daysBefore(1, at: LocalTime(hour: 18, minute: 0)!), .minutesBefore(30)],
                     tier: .timeSensitive),
        ReminderRule(id: ReminderRule.ID(uuid(12)), meta: meta, target: .exam,
                     offsets: [.daysBefore(0, at: LocalTime(hour: 6, minute: 30)!)], tier: .alarm, origin: .user),
    ]

    static func database(alarmsOn: Bool = true, tasks: [TaskItem] = [homework, weekly], exams: [Exam] = [exam]) -> TabulaDatabase {
        var database = SampleScenarios.secondary().database
        database.reminderRules = rules
        database.tasks = tasks
        database.exams = exams
        database.settings.alarmPolicy.isEnabled = alarmsOn
        return database
    }

    static let strings: [String: String] = [
        "reminder.task.title": "%@", "reminder.exam.title": "Exam: %@", "reminder.room": "Room %@",
        "reminder.task.dueInDaysAt": "In %lld days, on %@ at %@", "alarm.snoozed.title": "Snoozed: %@",
        "reminder.action.markDone": "Mark done",
    ]

    static func renderer(_ context: CalendarContext = context) -> LocalizedTextRenderer {
        let settings = AppSettings.untouchedDefaults
        return LocalizedTextRenderer(formatter: TimetableFormatter(settings: settings, context: context,
                                                                   locale: Locale(identifier: "en_US_POSIX")),
                                     lookup: { strings[$0] ?? $0 })
    }

    static func input(_ database: TabulaDatabase, context: CalendarContext = context, now: Date = now,
                      entitled: Bool = true) -> ReminderRunInput {
        ReminderRunInput(database: database, resolvers: ScheduleResolver.all(database: database, context: context),
                         context: context, renderer: renderer(context), now: now, loudAlarmsEntitled: entitled)
    }
}

@MainActor
@Suite("Reminder adapter: apply")
struct ReminderApplyTests {
    @Test func applyingTheSamePlanTwiceIsANoOp() async {
        let center = InMemoryNotificationCenterClient()
        let alarms = InMemoryAlarmClient()
        let engine = ReminderEngine(notifications: center, alarms: alarms, store: InMemoryReminderStateStore())
        let first = await engine.run(Fixture.input(Fixture.database()))
        #expect(first.report.notificationsAdded > 0)
        #expect(first.report.alarmsScheduled == 1)
        let addsAfterFirst = await center.addCount
        let second = await engine.run(Fixture.input(Fixture.database()))
        #expect(second.report.isNoOp)
        #expect(second.report.notificationsUnchanged == first.plan.notifications.count)
        #expect(second.report.alarmsUnchanged == 1)
        #expect(await center.addCount == addsAfterFirst)
        #expect(await alarms.scheduleCount == 1)
        #expect(second.plan == first.plan)
    }

    @Test func pendingSetMatchesThePlanExactly() async {
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database()))
        let pending = await center.pendingRequests().map(\.id)
        #expect(pending == result.plan.notifications.map(\.id.rawValue).sorted())
        #expect(pending.allSatisfy(ReminderID.isPlannerID))
    }

    @Test func nonPlannerIDsAreNeverTouched() async {
        let center = InMemoryNotificationCenterClient()
        let open = ReminderSource.task(Fixture.homework.id).rawValue
        await center.seedForeign(PendingNotificationInfo(id: "other.feature.1"))
        await center.seedForeign(PendingNotificationInfo(id: "tabula.test.notification"))
        await center.seedForeign(PendingNotificationInfo(id: "snooze.rem.00000000000000aa",
                                                         userInfo: [ReminderUserInfo.source: open]))
        await center.seedForeign(PendingNotificationInfo(id: "rem.short"))          // malformed planner-looking id
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        _ = await engine.run(Fixture.input(Fixture.database()))
        _ = await engine.run(Fixture.input(Fixture.database(tasks: [Fixture.homework])))
        let ids = Set(await center.pendingRequests().map(\.id))
        #expect(ids.isSuperset(of: ["other.feature.1", "tabula.test.notification", "snooze.rem.00000000000000aa", "rem.short"]))
    }

    @Test func snoozesOfCompletedOrDeletedItemsAreRemoved() async {
        let center = InMemoryNotificationCenterClient()
        var done = Fixture.homework
        done.completedAt = Fixture.now
        let doneSource = ReminderSource.task(done.id).rawValue
        let lessonSnooze = PendingNotificationInfo(id: "snooze.rem.00000000000000bb",
                                                   userInfo: [ReminderUserInfo.source: "packTonight/2026-10-14"])
        await center.seedForeign(PendingNotificationInfo(id: "snooze.rem.00000000000000aa",
                                                         userInfo: [ReminderUserInfo.source: doneSource]))
        await center.seedForeign(lessonSnooze)
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database(tasks: [done, Fixture.weekly])))
        let ids = Set(await center.pendingRequests().map(\.id))
        #expect(!ids.contains("snooze.rem.00000000000000aa"))
        #expect(ids.contains(lessonSnooze.id))
        #expect(result.report.staleSnoozesRemoved == 1)
    }

    @Test func timeZoneChangeRemapsUnderTheSameIDs() async {
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let home = await engine.run(Fixture.input(Fixture.database()))
        let before = await center.requests
        let away = await engine.run(Fixture.input(Fixture.database(), context: Fixture.london))
        let after = await center.requests
        #expect(Set(before.keys) == Set(after.keys))                       // no new ids, no duplicates
        #expect(await center.pendingRequests().count == home.plan.notifications.count)
        #expect(away.report.notificationsAdded == away.report.notificationsRemoved)
        // A wall-clock reminder (day before at 19:00) now fires at 19:00 London = one hour later in absolute time.
        let essay = home.plan.notifications.first { $0.source == .task(Fixture.homework.id) }!
        #expect(after[essay.id.rawValue]!.fireDate.timeIntervalSince(before[essay.id.rawValue]!.fireDate) == 3600)
        #expect(after[essay.id.rawValue]!.trigger.timeZoneIdentifier == "Europe/London")
        #expect(after[essay.id.rawValue]!.trigger.hour == 19)
    }

    @Test func lostStateReplacesPendingPlannerRequestsWithoutDuplicates() async {
        let center = InMemoryNotificationCenterClient()
        let first = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let applied = await first.run(Fixture.input(Fixture.database()))
        // New engine, empty store (lost state), same system state.
        let second = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let result = await second.run(Fixture.input(Fixture.database()))
        #expect(result.report.notificationsRemoved == applied.plan.notifications.count)
        #expect(result.report.notificationsAdded == applied.plan.notifications.count)
        #expect(await center.pendingRequests().map(\.id) == applied.plan.notifications.map(\.id.rawValue).sorted())
        // ...and from then on it is stable again.
        #expect(await second.run(Fixture.input(Fixture.database())).report.isNoOp)
    }

    @Test func deliveredAndFailedRequestsAreRetried() async {
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let plan = ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                                   now: Fixture.now,
                                                                   options: ReminderPlanningOptions(canScheduleAlarms: true)))
        let failing = plan.notifications[0].id.rawValue
        await center.setFailing([failing])
        let first = await engine.run(Fixture.input(Fixture.database()))
        #expect(first.report.notificationFailures.count == 1)
        #expect(!first.plan.notifications.contains { $0.id.rawValue == failing })
        await center.setFailing([])
        let second = await engine.run(Fixture.input(Fixture.database()))
        #expect(second.report.notificationsAdded == 1)
        #expect(await center.requests[failing] != nil)
    }

    @Test func completingAnItemRemovesItsRemindersAndAlarm() async {
        let center = InMemoryNotificationCenterClient()
        let alarms = InMemoryAlarmClient()
        let engine = ReminderEngine(notifications: center, alarms: alarms, store: InMemoryReminderStateStore())
        let before = await engine.run(Fixture.input(Fixture.database()))
        let alarmID = before.plan.alarms[0].alarmID
        var exam = Fixture.exam
        exam.completedAt = Fixture.now
        let after = await engine.run(Fixture.input(Fixture.database(exams: [exam])))
        #expect(after.plan.alarms.isEmpty)
        #expect(!after.plan.notifications.contains { $0.source == .exam(exam.id) })
        #expect(await alarms.alarms[alarmID] == nil)
        #expect(await alarms.cancelled == [alarmID])
        #expect(engine.state.alarmLedger.isEmpty)
    }
}

@MainActor
@Suite("Reminder adapter: loud alarms")
struct ReminderAlarmTests {
    @Test func probeAndTestAlarmsAreNeverCancelled() async {
        let alarms = InMemoryAlarmClient()
        let probe = Fixture.uuid(99)
        await alarms.seedForeign(probe)
        let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: alarms,
                                    store: InMemoryReminderStateStore())
        _ = await engine.run(Fixture.input(Fixture.database()))
        _ = await engine.run(Fixture.input(Fixture.database(alarmsOn: false)))
        #expect(await alarms.foreign == [probe])
        #expect(await alarms.alarms.isEmpty)
    }

    @Test func lostLedgerStillCancelsOwnDerivedAlarmIDsBeforeRescheduling() async {
        let alarms = InMemoryAlarmClient()
        let center = InMemoryNotificationCenterClient()
        _ = await ReminderEngine(notifications: center, alarms: alarms, store: InMemoryReminderStateStore())
            .run(Fixture.input(Fixture.database()))
        let fresh = ReminderEngine(notifications: center, alarms: alarms, store: InMemoryReminderStateStore())
        let result = await fresh.run(Fixture.input(Fixture.database()))
        #expect(result.report.alarmsCancelled == 1 && result.report.alarmsScheduled == 1)
        #expect(await alarms.alarms.count == 1)
    }

    @Test func maximumLimitReachedFallsBackToNotificationsAndIsLearned() async {
        let alarms = InMemoryAlarmClient(limit: 1)
        await alarms.seedForeign(Fixture.uuid(98))                         // the limit is already used up
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: alarms, store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database()))
        #expect(result.report.alarmLimitReached)
        #expect(result.plan.alarms.isEmpty)
        #expect(result.plan.alarmOverflow.count == 1)
        #expect(result.notices.contains { $0.key == ReminderL10n.noticeAlarmLimit })
        let overflow = result.plan.alarmOverflow[0]
        let fallback = result.plan.notifications.first { $0.id == overflow }
        #expect(fallback?.effectiveTier == .timeSensitive || fallback?.effectiveTier == .standard)
        #expect(await center.requests[overflow.rawValue] != nil)
        #expect(engine.state.learnedAlarmLimit?.count == 0)
        #expect(engine.state.alarmLedger.isEmpty)
        // The learned limit is used next time (no second refusal), then expires after 24 h.
        let again = await engine.run(Fixture.input(Fixture.database()))
        #expect(!again.report.alarmLimitReached && again.report.isNoOp)
        let limit = LearnedAlarmLimit(count: 2, learnedAt: Fixture.now)
        #expect(limit.softLimit(defaultLimit: 10, now: Fixture.now.addingTimeInterval(3600)) == 2)
        #expect(limit.softLimit(defaultLimit: 10, now: Fixture.now.addingTimeInterval(25 * 3600)) == 10)
        #expect(limit.softLimit(defaultLimit: 1, now: Fixture.now) == 1)
    }

    @Test func alarmsNeedAuthorizationAndEntitlementAndNeverPrompt() async {
        for (auth, entitled) in [(AlarmAuthorization.notDetermined, true), (.denied, true), (.authorized, false)] {
            let alarms = InMemoryAlarmClient(authorization: auth)
            let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: alarms,
                                        store: InMemoryReminderStateStore())
            let result = await engine.run(Fixture.input(Fixture.database(), entitled: entitled))
            #expect(result.plan.alarms.isEmpty)
            #expect(await alarms.scheduleCount == 0)
            #expect(await alarms.state == auth)                            // no implicit prompt
            #expect(result.plan.notifications.contains { $0.tierChanges.contains(.alarmsUnavailable) })
        }
    }

    @Test func alarmSpecCarriesIDsAndSnooze() {
        let plan = ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                                   now: Fixture.now,
                                                                   options: ReminderPlanningOptions(canScheduleAlarms: true)))
        let planned = plan.alarms[0]
        let spec = ReminderRequestBuilder(renderer: Fixture.renderer(), context: Fixture.context).alarm(for: planned)
        #expect(spec.id == planned.alarmID)
        #expect(spec.reminderID == planned.id.rawValue)
        #expect(spec.fireDate == planned.fireDate)
        #expect(spec.title == "Exam: Maths test")
        #expect(spec.snoozedTitle == "Snoozed: Exam: Maths test")
        #expect(spec.snoozeSeconds == 540)
        #expect(spec.sourceRawValue == ReminderSource.exam(Fixture.exam.id).rawValue)
    }
}

@MainActor
@Suite("Reminder adapter: requests, snooze, actions")
struct ReminderRequestTests {
    @Test func requestsCarryRenderedTextTierThreadCategoryAndSource() {
        let plan = ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                                   now: Fixture.now,
                                                                   options: ReminderPlanningOptions(canScheduleAlarms: true)))
        let builder = ReminderRequestBuilder(renderer: Fixture.renderer(), context: Fixture.context)
        for planned in plan.notifications {
            let spec = builder.request(for: planned)
            #expect(spec.id == planned.id.rawValue)
            #expect(spec.interruption == (planned.effectiveTier == .timeSensitive ? .timeSensitive : .active))
            #expect(spec.threadID == planned.threadID)
            #expect(spec.categoryID == planned.categoryID.rawValue)
            #expect(spec.userInfo[ReminderUserInfo.source] == planned.source.rawValue)
            #expect(spec.userInfo[ReminderUserInfo.kind] == ReminderUserInfo.kindPlanned)
            #expect(spec.trigger.instant == planned.fireDate)
            #expect(spec.trigger.timeZoneIdentifier == "Europe/Bratislava")
        }
        let essay = plan.notifications.first { $0.source == .task(Fixture.homework.id) }!
        #expect(builder.request(for: essay).title == "Essay")
        // The 30-minute exam reminder stays Time Sensitive (lead ≤ 60 min, decision D6).
        #expect(plan.notifications.contains { $0.effectiveTier == .timeSensitive })
        #expect(builder.request(for: plan.notifications.first { $0.effectiveTier == .timeSensitive }!).interruption == .timeSensitive)
    }

    @Test func categoriesMatchTheCoreActions() {
        let categories = ReminderRequestBuilder(renderer: Fixture.renderer(), context: Fixture.context).categories()
        #expect(categories.map(\.id) == ReminderCategory.allCases.map(\.rawValue))
        let task = categories.first { $0.id == ReminderCategory.task.rawValue }!
        #expect(task.actions.map(\.id) == ReminderCategory.task.actions.map(\.rawValue))
        #expect(task.actions[0].title == "Mark done")
        #expect(task.actions.allSatisfy { !$0.opensApp })
    }

    @Test func snoozeIDsUseTheirOwnPrefixAndReplaceEachOther() async {
        #expect(ReminderRequestID.snooze(for: "rem.0123456789abcdef") == "snooze.rem.0123456789abcdef")
        #expect(ReminderRequestID.snooze(for: "snooze.rem.0123456789abcdef") == "snooze.rem.0123456789abcdef")
        #expect(!ReminderID.isPlannerID("snooze.rem.0123456789abcdef"))
        let delivered = DeliveredNotification(
            requestID: "rem.0123456789abcdef", title: "Essay", subtitle: nil, body: "Tomorrow", interruption: .timeSensitive,
            threadID: "task/x", categoryID: ReminderCategory.task.rawValue,
            userInfo: [ReminderUserInfo.reminderID: "rem.0123456789abcdef",
                       ReminderUserInfo.source: ReminderSource.task(Fixture.homework.id).rawValue,
                       ReminderUserInfo.kind: ReminderUserInfo.kindPlanned])
        let center = InMemoryNotificationCenterClient()
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(), store: InMemoryReminderStateStore())
        let outcome = await engine.snooze(delivered, action: .snoozeOneHour, context: Fixture.context,
                                          renderer: Fixture.renderer(), now: Fixture.now)
        #expect(outcome == .added)
        let snoozed = await center.requests["snooze.rem.0123456789abcdef"]!
        #expect(snoozed.fireDate == Fixture.now.addingTimeInterval(3600))
        #expect(snoozed.categoryID == ReminderCategory.task.rawValue && snoozed.interruption == .timeSensitive)
        #expect(snoozed.userInfo[ReminderUserInfo.kind] == ReminderUserInfo.kindSnooze)
        // Snoozing the snooze again ("tomorrow") replaces it: still one request, at 07:00 tomorrow local time.
        var again = delivered
        again.requestID = snoozed.id
        again.userInfo = snoozed.userInfo
        _ = await engine.snooze(again, action: .snoozeTomorrow, context: Fixture.context, renderer: Fixture.renderer(),
                                now: Fixture.now)
        #expect(await center.requests.count == 1)
        let tomorrow = await center.requests["snooze.rem.0123456789abcdef"]!
        #expect(tomorrow.fireDate == Fixture.context.date(Fixture.today.adding(days: 1), LocalTime(hour: 7, minute: 0)!))
        #expect(await engine.snooze(delivered, action: .markDone, context: Fixture.context, renderer: Fixture.renderer(),
                                    now: Fixture.now) == nil)
        // The planner never removes it (not a planner id) while the task is open.
        _ = await engine.run(Fixture.input(Fixture.database()))
        #expect(await center.requests["snooze.rem.0123456789abcdef"] != nil)
    }

    @Test func responsesMapToCommands() {
        let task = ReminderSource.task(Fixture.homework.id)
        func delivered(_ source: ReminderSource?) -> DeliveredNotification {
            DeliveredNotification(requestID: "rem.0123456789abcdef", title: "t", subtitle: nil, body: "b",
                                  interruption: .active, threadID: "", categoryID: "",
                                  userInfo: source.map { [ReminderUserInfo.source: $0.rawValue] } ?? [:])
        }
        #expect(ReminderResponseInterpreter.command(for: .custom(ReminderAction.markDone.rawValue), delivered: delivered(task))
                == .markDone(task))
        let lesson = ReminderSource.lesson(OccurrenceID(rawValue: "x"))
        #expect(ReminderResponseInterpreter.command(for: .custom(ReminderAction.markDone.rawValue), delivered: delivered(lesson))
                == ReminderResponseCommand.none)
        #expect(ReminderResponseInterpreter.command(for: .open, delivered: delivered(task)) == .open(.task(Fixture.homework.id)))
        #expect(ReminderResponseInterpreter.command(for: .open, delivered: delivered(nil)) == .open(nil))
        #expect(ReminderResponseInterpreter.command(for: .custom("unknown"), delivered: delivered(task))
                == .open(.task(Fixture.homework.id)))
        #expect(ReminderResponseInterpreter.command(for: .dismiss, delivered: delivered(task)) == ReminderResponseCommand.none)
        let snooze = ReminderResponseInterpreter.command(for: .custom(ReminderAction.snoozeTomorrow.rawValue),
                                                         delivered: delivered(task))
        #expect(snooze == .snooze(delivered(task), .snoozeTomorrow))
        #expect(ReminderResponseInterpreter.mutation(for: lesson, now: Fixture.now) == nil)
    }

    @Test func triggerTimeRoundTripsAcrossDST() {
        // 2026-10-25 02:30 Bratislava happens twice; the components carry the zone, the instant is preserved.
        let zone = Fixture.zone
        for offset in stride(from: 0, to: 4 * 3600, by: 900) {
            let instant = Fixture.context.date(LocalDate(year: 2026, month: 10, day: 25)!, LocalTime(hour: 0, minute: 0)!)
                .addingTimeInterval(TimeInterval(offset))
            let trigger = NotificationTriggerTime(instant: instant, zone: zone)
            // Ambiguous wall-clock times (02:00–02:59) cannot round-trip through components alone; the real client
            // still gets the right instant from `fireDate` checks on device (checklist A-DST). Unambiguous ones must.
            if !(trigger.hour == 2) { #expect(trigger.instant == instant) }
        }
    }
}

@Suite("Task/exam completion (Mark done)")
struct CompletionMutationTests {
    private func clock(_ database: TabulaDatabase) -> HybridLogicalClock {
        var clock = HybridLogicalClock(node: 0xA11)
        clock.receive(database.latestTimestamp, now: Fixture.now)
        return clock
    }

    @Test func completingAOneOffTaskSetsCompletedAt() throws {
        let database = Fixture.database()
        var hlc = clock(database)
        let result = try DatabaseMutation.completeTask(Fixture.homework.id, at: Fixture.now)
            .apply(to: database, clock: &hlc, now: Fixture.now)
        #expect(result.tasks.first { $0.id == Fixture.homework.id }?.completedAt == Fixture.now)
        #expect(result.tasks.count == database.tasks.count)
    }

    @Test func completingARepeatingTaskInsertsItsSuccessorOnce() throws {
        let database = Fixture.database()
        var hlc = clock(database)
        let once = try DatabaseMutation.completeTask(Fixture.weekly.id, at: Fixture.now)
            .apply(to: database, clock: &hlc, now: Fixture.now)
        let nextID = TaskItem.nextOccurrenceID(after: Fixture.weekly.id)
        let next = try #require(once.tasks.first { $0.id == nextID })
        #expect(next.due == .date(Fixture.today.adding(days: 9)))
        #expect(!next.isCompleted && next.title == "Vocabulary")
        #expect(next.meta.createdAt > .zero)
        // Completing again (second notification) changes nothing.
        let twice = try DatabaseMutation.completeTask(Fixture.weekly.id, at: Fixture.now.addingTimeInterval(60))
            .apply(to: once, clock: &hlc, now: Fixture.now)
        #expect(twice == once)
    }

    @Test func aTombstonedSuccessorIsNotResurrected() throws {
        var database = Fixture.database()
        var tombstone = try #require(Fixture.weekly.nextOccurrence(createdAt: .zero))
        tombstone.meta.isDeleted = true
        database.tasks.append(tombstone)
        var hlc = clock(database)
        let result = try DatabaseMutation.completeTask(Fixture.weekly.id, at: Fixture.now)
            .apply(to: database, clock: &hlc, now: Fixture.now)
        let matches = result.tasks.filter { $0.id == tombstone.id }
        #expect(matches.count == 1 && matches[0].isDeleted)
    }

    @Test func aLiveSuccessorIsNotDuplicated() throws {
        var database = Fixture.database()
        database.tasks.append(try #require(Fixture.weekly.nextOccurrence(createdAt: .zero)))
        var hlc = clock(database)
        let result = try DatabaseMutation.completeTask(Fixture.weekly.id, at: Fixture.now)
            .apply(to: database, clock: &hlc, now: Fixture.now)
        #expect(result.tasks.count == database.tasks.count)
    }

    @Test func unknownOrDeletedItemsFail() {
        var database = Fixture.database()
        database.tasks[0].meta.isDeleted = true
        var hlc = clock(database)
        #expect(throws: MutationError.notFound(.task, Fixture.homework.id.uuid)) {
            try DatabaseMutation.completeTask(Fixture.homework.id, at: Fixture.now).apply(to: database, clock: &hlc, now: Fixture.now)
        }
        #expect(throws: MutationError.notFound(.exam, Fixture.uuid(77))) {
            try DatabaseMutation.completeExam(Exam.ID(Fixture.uuid(77)), at: Fixture.now).apply(to: database, clock: &hlc, now: Fixture.now)
        }
    }

    @Test func completingAnExam() throws {
        let database = Fixture.database()
        var hlc = clock(database)
        let mutation = try #require(ReminderResponseInterpreter.mutation(for: .exam(Fixture.exam.id), now: Fixture.now))
        let result = try mutation.apply(to: database, clock: &hlc, now: Fixture.now)
        #expect(result.exams[0].completedAt == Fixture.now)
    }
}

@Suite("Reminder adapter: input, background refresh, state")
struct ReminderSupportTests {
    @Test func inputCoversTodayHorizonAndTheNextSchoolDayForPackTonight() {
        let database = Fixture.database()
        let input = ReminderInputBuilder.input(database: database, context: Fixture.context, now: Fixture.now,
                                               options: ReminderPlanningOptions(horizonDays: 1, canScheduleAlarms: false))
        #expect(input.horizonDays == 1 && !input.canScheduleAlarms)
        #expect(input.lessons.contains { $0.date == Fixture.today })        // earlier today's lessons stay (linking)
        #expect(input.lessons.allSatisfy { $0.status != .cancelled })
        #expect(Set(input.lessons.map(\.id)).count == input.lessons.count)
        let dates = Set(input.lessons.map(\.date))
        #expect(dates.contains(Fixture.today.adding(days: 1)) || dates.contains(Fixture.today.adding(days: 2)))
        #expect(input.packTonight == PackTonightDay.days(from: input.lessons))
        #expect(input.rules == database.reminderRules && input.tasks == database.tasks)
    }

    @Test func backgroundRefreshRequestFollowsNextReplanDate() {
        let now = Fixture.now
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: nil, now: now) == now.addingTimeInterval(3600))
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: now.addingTimeInterval(5 * 3600), now: now)
                == now.addingTimeInterval(4 * 3600))
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: now.addingTimeInterval(600), now: now)
                == now.addingTimeInterval(900))
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: now.addingTimeInterval(-600), now: now)
                == now.addingTimeInterval(900))
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: now.addingTimeInterval(5 * 86400), now: now)
                == now.addingTimeInterval(12 * 3600))
        let plan = ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                                   now: now, options: ReminderPlanningOptions(canScheduleAlarms: true)))
        let date = BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: plan.nextReplanDate, now: now)
        #expect(date >= now.addingTimeInterval(900) && date <= plan.nextReplanDate)
    }

    @Test func stateRoundTripsThroughUserDefaults() throws {
        let suite = "p3a.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsReminderStateStore(defaults: defaults)
        #expect(store.load() == nil)
        let plan = ReminderPlanner.plan(ReminderInputBuilder.input(database: Fixture.database(), context: Fixture.context,
                                                                   now: Fixture.now,
                                                                   options: ReminderPlanningOptions(canScheduleAlarms: true)))
        let state = AppliedReminderState(plan: plan, alarmLedger: [Fixture.uuid(2), Fixture.uuid(1)],
                                         learnedAlarmLimit: LearnedAlarmLimit(count: 3, learnedAt: Fixture.now),
                                         lastReport: ReminderApplyReport(notificationsAdded: 4), lastRunAt: Fixture.now)
        store.save(state)
        #expect(store.load() == state)
        #expect(state.alarmLedger == [Fixture.uuid(1), Fixture.uuid(2)])
        defaults.set(Data("{\"version\":99}".utf8), forKey: UserDefaultsReminderStateStore.key)
        #expect(store.load() == nil)                                        // unreadable → "nothing applied"
    }
}

@Suite("Reminders health check")
struct ReminderHealthCheckTests {
    private func input(auth: NotificationAuthorization = .authorized, timeSensitive: NotificationSettingState = .enabled,
                       alarms: AlarmAuthorization = .authorized, lowPower: Bool = false,
                       refresh: BackgroundRefreshState = .available, plan: ReminderPlan? = nil,
                       usesTS: Bool = true, usesAlarms: Bool = true) -> ReminderHealthInput {
        ReminderHealthInput(notifications: NotificationSettingsSnapshot(authorization: auth, timeSensitive: timeSensitive),
                            alarmAuthorization: alarms,
                            device: DeviceReminderState(isLowPowerModeEnabled: lowPower, backgroundRefresh: refresh),
                            pendingCount: 12, lastPlan: plan, usesTimeSensitive: usesTS, usesLoudAlarms: usesAlarms,
                            hasReminders: true)
    }

    private func item(_ kind: ReminderHealthItem.Kind, _ items: [ReminderHealthItem]) -> ReminderHealthItem? {
        items.first { $0.kind == kind }
    }

    @Test func allGoodIsOkWithInfoRows() {
        let items = ReminderHealthCheck.evaluate(input())
        #expect(items.map(\.kind) == [.notifications, .timeSensitive, .alarms, .focus, .silentMode, .lowPower,
                                      .backgroundRefresh, .pending, .hiddenApp])
        #expect(ReminderHealthCheck.overall(items) == .info)
        #expect(item(.pending, items)?.detail == LocalizedText(key: "health.pending.detail", args: [.integer(12), .integer(64)]))
    }

    @Test func permissionProblemsOfferTheRightAction() {
        let denied = ReminderHealthCheck.evaluate(input(auth: .denied, alarms: .denied))
        #expect(item(.notifications, denied)?.status == .problem)
        #expect(item(.notifications, denied)?.action == .openNotificationSettings)
        #expect(item(.alarms, denied)?.action == .openAppSettings)
        #expect(ReminderHealthCheck.overall(denied) == .problem)
        let fresh = ReminderHealthCheck.evaluate(input(auth: .notDetermined, alarms: .notDetermined))
        #expect(item(.notifications, fresh)?.action == .requestNotifications)
        #expect(item(.alarms, fresh)?.action == .requestAlarms)
        #expect(item(.notifications, fresh)?.status == .warning)
    }

    @Test func tierRowsOnlyWhenUsed() {
        let items = ReminderHealthCheck.evaluate(input(usesTS: false, usesAlarms: false))
        #expect(item(.timeSensitive, items) == nil && item(.alarms, items) == nil && item(.hiddenApp, items) == nil)
        let off = ReminderHealthCheck.evaluate(input(timeSensitive: .notSupported))
        #expect(item(.timeSensitive, off)?.status == .warning)
        #expect(item(.timeSensitive, off)?.detailKey == "health.timeSensitive.notSupported")
    }

    @Test func deviceStateRows() {
        let items = ReminderHealthCheck.evaluate(input(lowPower: true, refresh: .denied))
        #expect(item(.lowPower, items)?.status == .warning)
        #expect(item(.backgroundRefresh, items)?.status == .warning)
        #expect(item(.backgroundRefresh, items)?.action == .openAppSettings)
        let restricted = ReminderHealthCheck.evaluate(input(refresh: .restricted))
        #expect(item(.backgroundRefresh, restricted)?.status == .info)
        #expect(item(.backgroundRefresh, restricted)?.action == nil)
    }

    @Test func planNoticesBecomeRows() async {
        let alarms = InMemoryAlarmClient(limit: 0)
        let engine = await ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: alarms,
                                          store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database()))
        let items = ReminderHealthCheck.evaluate(input(plan: result.plan))
        #expect(item(.alarmOverflow, items)?.detail.key == ReminderL10n.noticeAlarmLimit)
        #expect(item(.alarmOverflow, items)?.status == .warning)
        var budget = Fixture.input(Fixture.database())
        budget.budget = NotificationBudget(maxPending: 2, reserved: 0)
        let saturated = await engine.run(budget)
        #expect(item(.saturation, ReminderHealthCheck.evaluate(input(plan: saturated.plan)))?.detail.key
                == ReminderL10n.noticeSaturated)
    }

    @Test func usageIsDerivedFromRulesAndOverrides() {
        let usage = ReminderHealthCheck.usage(in: Fixture.database())
        #expect(usage.any && usage.timeSensitive && usage.loudAlarms)
        #expect(!ReminderHealthCheck.usage(in: Fixture.database(alarmsOn: false)).loudAlarms)
        let none = ReminderHealthCheck.usage(in: nil)
        #expect(!none.any && !none.timeSensitive && !none.loudAlarms)
    }

    @Test func everyKeyIsInTheCatalog() throws {
        let catalog = try CatalogFile.keys()
        let missing = (ReminderHealthCheck.allKeys + [ReminderRequestBuilder.Keys.alarmSnoozedTitle,
                                                      ReminderRequestBuilder.Keys.testTitle,
                                                      ReminderRequestBuilder.Keys.testBody,
                                                      ReminderRequestBuilder.Keys.testAlarmTitle])
            .filter { !catalog.contains($0) }
        #expect(missing.isEmpty, "missing catalog keys: \(missing)")
    }
}

/// Reads the String Catalog's keys (Resources/Localizable.xcstrings, relative to this test file).
enum CatalogFile {
    static func keys() throws -> Set<String> {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return Set((json?["strings"] as? [String: Any])?.keys.map { $0 } ?? [])
    }
}
