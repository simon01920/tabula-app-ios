import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4 B3: the pure parts of the App Intents (intent → mutation, idempotency, successor identical to the
// notification action, host registry, alarm button policy, "What's next?", timetable sections + entity query).

private let context = Fixture.context
private let now = Fixture.now   // Tue 2026-10-13 10:20 Bratislava

private func hlc(_ database: TabulaDatabase) -> HybridLogicalClock {
    var clock = HybridLogicalClock(node: 0xB3)
    clock.receive(database.latestTimestamp, now: now)
    return clock
}

private func applying(_ decision: IntentActionDecision, to database: TabulaDatabase) throws -> TabulaDatabase {
    guard case .apply(let mutation) = decision else {
        Issue.record("expected .apply, got \(decision)")
        return database
    }
    var clock = hlc(database)
    return try mutation.apply(to: database, clock: &clock, now: now)
}

private func snapshot(_ database: TabulaDatabase?, at instant: Date = now) -> WidgetSnapshot {
    WidgetSnapshotBuilder.make(database: database, now: instant, context: context, tier: .pro,
                               locale: Locale(identifier: "en_US_POSIX"), languageCode: "en")
}

/// The secondary scenario with `copies` duplicated timetables (full copies: subjects, bells, lessons, day changes).
private func withCopies(_ copies: Int) throws -> (database: TabulaDatabase, active: Timetable, copies: [Timetable]) {
    let scenario = SampleScenarios.secondary()
    var database = scenario.database
    var ids = SequentialIDGenerator(namespace: 0xB3B3)
    var made: [Timetable] = []
    for index in 0..<copies {
        let (mutation, id) = try #require(TimetableManagement.duplicateMutation(
            scenario.timetable.id, name: "Copy \(index + 1)", in: database, ids: &ids))
        var clock = hlc(database)
        database = try mutation.apply(to: database, clock: &clock, now: now)
        made.append(try #require(database.timetables.first { $0.id == id }))
    }
    return (database, scenario.timetable, made)
}

@Suite("Phase 4 B3 — intent actions")
struct IntentActionTests {
    @Test func parametersParseOnlyUUIDs() {
        #expect(IntentAction(taskID: Fixture.homework.id.uuidString) == .completeTask(Fixture.homework.id))
        #expect(IntentAction(examID: Fixture.exam.id.uuidString) == .completeExam(Fixture.exam.id))
        #expect(IntentAction(taskID: "not-a-uuid") == nil)
        #expect(IntentAction(examID: "") == nil)
        #expect(IntentAction.completeTask(Fixture.homework.id).source == .task(Fixture.homework.id))
        #expect(IntentAction.completeExam(Fixture.exam.id).source == .exam(Fixture.exam.id))
    }

    /// The widget checkbox / alarm "Done" applies exactly what the notification "Mark done" action applies.
    @Test func markDoneIsTheNotificationActionsMutation() throws {
        let database = Fixture.database()
        for source in [ReminderSource.task(Fixture.homework.id), .task(Fixture.weekly.id), .exam(Fixture.exam.id)] {
            let action: IntentAction
            switch source {
            case .task(let id): action = .completeTask(id)
            case .exam(let id): action = .completeExam(id)
            default: Issue.record("unexpected source"); continue
            }
            let viaIntent = try applying(IntentActionPlanner.decide(action, database: database, now: now), to: database)
            let notificationMutation = try #require(ReminderResponseInterpreter.mutation(for: source, now: now))
            var clock = hlc(database)
            let viaNotification = try notificationMutation.apply(to: database, clock: &clock, now: now)
            #expect(viaIntent == viaNotification, "\(source.rawValue)")
        }
    }

    @Test func aRepeatingTaskGetsItsSuccessorExactlyOnce() throws {
        let database = Fixture.database()
        let action = IntentAction.completeTask(Fixture.weekly.id)
        let once = try applying(IntentActionPlanner.decide(action, database: database, now: now), to: database)
        let nextID = TaskItem.nextOccurrenceID(after: Fixture.weekly.id)
        let successor = try #require(once.tasks.first { $0.id == nextID })
        #expect(successor.due == .date(Fixture.today.adding(days: 9)) && !successor.isCompleted)
        #expect(once.tasks.first { $0.id == Fixture.weekly.id }?.completedAt == now)
        #expect(once.tasks.count == database.tasks.count + 1)
        // A second tap (stale widget, or alarm + widget): nothing to apply, no second successor.
        let again = IntentActionPlanner.decide(action, database: once, now: now.addingTimeInterval(60))
        #expect(again.skippedOutcome == .alreadyDone)
        #expect(once.tasks.filter { $0.id == nextID }.count == 1)
    }

    @Test func completedDeletedUnknownAndMissingStoreAreNoOps() {
        var database = Fixture.database()
        database.tasks[0].completedAt = now
        #expect(IntentActionPlanner.decide(.completeTask(Fixture.homework.id), database: database, now: now)
            .skippedOutcome == .alreadyDone)
        database.tasks[1].meta.isDeleted = true
        #expect(IntentActionPlanner.decide(.completeTask(Fixture.weekly.id), database: database, now: now)
            .skippedOutcome == .notFound)
        #expect(IntentActionPlanner.decide(.completeTask(TaskItem.ID(Fixture.uuid(99))), database: database, now: now)
            .skippedOutcome == .notFound)
        #expect(IntentActionPlanner.decide(.completeExam(Exam.ID(Fixture.uuid(98))), database: database, now: now)
            .skippedOutcome == .notFound)
        database.exams[0].completedAt = now
        #expect(IntentActionPlanner.decide(.completeExam(Fixture.exam.id), database: database, now: now)
            .skippedOutcome == .alreadyDone)
        #expect(IntentActionPlanner.decide(.completeTask(Fixture.homework.id), database: nil, now: now)
            .skippedOutcome == .unavailable)
    }

    @Test func anExamIsCompleted() throws {
        let database = Fixture.database()
        let result = try applying(IntentActionPlanner.decide(.completeExam(Fixture.exam.id), database: database, now: now),
                                  to: database)
        #expect(result.exams.first { $0.id == Fixture.exam.id }?.completedAt == now)
        #expect(result.tasks == database.tasks)
    }
}

/// A fake app (the real one is App/Sources/Intents/AppIntentHost.swift).
@MainActor
private final class FakeHost: IntentHostServices {
    var performed: [IntentAction] = []
    var opened = 0
    func perform(_ action: IntentAction) async -> IntentActionOutcome {
        performed.append(action)
        return .completed
    }
    func whatsNextAnswer() async -> String { "answer" }
    func openNewTask() async { opened += 1 }
}

@Suite("Phase 4 B3 — intent host", .serialized)
@MainActor
struct IntentHostTests {
    @Test func withoutServicesNothingIsWritten() async {
        IntentHost.unregister()
        // The widget extension never registers services: Mark done there is a no-op.
        #expect(await IntentHost.perform(.completeTask(Fixture.homework.id), waitingUpTo: .zero) == .unavailable)
        #expect(await IntentHost.services(waitingUpTo: .milliseconds(100)) == nil)
        #expect(await IntentHost.perform(nil, waitingUpTo: .zero) == .notFound)
    }

    @Test func registeredServicesPerformTheAction() async {
        let host = FakeHost()
        IntentHost.register(host)
        defer { IntentHost.unregister() }
        #expect(await IntentHost.perform(IntentAction(taskID: Fixture.weekly.id.uuidString)) == .completed)
        #expect(host.performed == [.completeTask(Fixture.weekly.id)])
        // A malformed id never reaches the app.
        #expect(await IntentHost.perform(IntentAction(taskID: "x")) == .notFound)
        #expect(host.performed.count == 1)
    }

    @Test func aLateRegistrationIsAwaited() async {
        IntentHost.unregister()
        let host = FakeHost()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            IntentHost.register(host)
        }
        let found = await IntentHost.services(waitingUpTo: .seconds(2))
        #expect(found === host)
        IntentHost.unregister()
    }
}

@Suite("Phase 4 B3 — loud alarm secondary button")
struct AlarmSecondaryActionTests {
    @Test func doneForTasksAndExamsOnlyWithIntents() {
        let task = ReminderSource.task(Fixture.homework.id).rawValue
        let exam = ReminderSource.exam(Fixture.exam.id).rawValue
        let lesson = ReminderSource.lesson(OccurrenceID(rawValue: "lesson:\(Fixture.uuid(5).uuidString):2026-10-13")).rawValue
        let pack = ReminderSource.packTonight(Fixture.today).rawValue
        #expect(AlarmSecondaryAction.make(sourceRawValue: task, snoozeAvailable: true, intentsAvailable: true)
            == .markDone(.completeTask(Fixture.homework.id)))
        #expect(AlarmSecondaryAction.make(sourceRawValue: exam, snoozeAvailable: true, intentsAvailable: true)
            == .markDone(.completeExam(Fixture.exam.id)))
        // No metadata (xtool): Phase 3 behaviour (Snooze) everywhere.
        for source in [task, exam, lesson, pack, ""] {
            #expect(AlarmSecondaryAction.make(sourceRawValue: source, snoozeAvailable: true, intentsAvailable: false) == .snooze)
        }
        // Lessons, pack-tonight and the health check's test alarm keep Snooze with intents too.
        for source in [lesson, pack, "", "garbage"] {
            #expect(AlarmSecondaryAction.make(sourceRawValue: source, snoozeAvailable: true, intentsAvailable: true) == .snooze)
            #expect(AlarmSecondaryAction.make(sourceRawValue: source, snoozeAvailable: false, intentsAvailable: true) == .none)
        }
        #expect(AlarmSecondaryAction.make(sourceRawValue: task, snoozeAvailable: false, intentsAvailable: true)
            == .markDone(.completeTask(Fixture.homework.id)))
    }
}

@Suite("Phase 4 B3 — What's next?")
struct WhatsNextAnswerTests {
    /// The answer follows the Today header (TodayState) at several moments of the secondary scenario's Tuesday.
    @Test func followsTheTodayHeader() throws {
        let database = SampleScenarios.secondary().database
        let timetable = try #require(ActiveTimetable.resolve(database))
        let resolver = try #require(ScheduleResolver(database: database, timetableID: timetable.id, context: context))
        let day = Fixture.today
        for (hour, minute) in [(6, 0), (8, 10), (10, 20), (12, 0), (15, 30), (21, 0)] {
            let instant = context.date(day, LocalTime(hour: hour, minute: minute)!)
            let display = WhatsNextAnswer.display(snapshot: snapshot(database, at: instant), now: instant,
                                                  deviceTimeZone: context.timeZone, lookup: { $0 })
            let header = TodayState.make(now: instant, resolver: resolver, database: database).header
            switch (header, display.kind) {
            case let (.current(lesson, _), .current(line)):
                #expect(line.id == lesson.id.rawValue)
            case let (.upcoming(lesson, _), .upcoming(line)):
                #expect(line.id == lesson.id.rawValue)
            case (.dayOver, .status), (.free, .status), (.holiday, .status), (.dayCancelled, .status):
                #expect(display.next?.id == header.next?.id.rawValue)
            default:
                Issue.record("\(hour):\(minute): Today \(header) vs answer \(display.kind)")
            }
            let sentence = WhatsNextAnswer.sentence(snapshot: snapshot(database, at: instant), now: instant,
                                                    deviceTimeZone: context.timeZone, lookup: { $0 })
            #expect(!sentence.isEmpty && sentence == display.accessibilityLabel)
        }
    }

    @Test func withoutATimetableItSaysOpenTabula() {
        let display = WhatsNextAnswer.display(snapshot: snapshot(nil), now: now, deviceTimeZone: context.timeZone,
                                              lookup: { $0 })
        guard case .unavailable = display.kind else {
            Issue.record("expected the Open Tabula state, got \(display.kind)")
            return
        }
        #expect(display.accessibilityLabel.contains("widget.open.title"))
    }
}

@Suite("Phase 4 B3 — timetable choice")
struct TimetableChoiceTests {
    @Test func oneTimetableAddsNoSections() {
        let single = snapshot(SampleScenarios.secondary().database)
        #expect(single.timetables == nil && single.timetableChoices.isEmpty)
        #expect(single.selecting(timetableID: UUID().uuidString) == single)
    }

    @Test func sectionsListEveryTimetableAndSelectTheChosenDays() throws {
        let (database, active, copies) = try withCopies(1)
        let copy = copies[0]
        let built = snapshot(database)
        let sections = try #require(built.timetables)
        #expect(sections.map(\.id) == ActiveTimetable.ordered(database).map(\.id.uuid))
        #expect(sections.filter(\.isActive).map(\.id) == [active.id.uuid])
        #expect(sections.first { $0.isActive }?.days == nil)
        #expect(sections.allSatisfy { $0.hasData })
        // Nothing chosen / the active one / a deleted one → unchanged (the active timetable).
        #expect(built.selecting(timetableID: nil) == built)
        #expect(built.selecting(timetableID: active.id.uuidString) == built)
        #expect(built.selecting(timetableID: UUID().uuidString) == built)
        #expect(built.selecting(timetableID: "garbage") == built)
        // The copy: its own occurrences (other lesson IDs), same dates.
        let chosen = try #require(built.selecting(timetableID: copy.id.uuidString.lowercased()))
        #expect(chosen.days.map(\.date) == built.days.map(\.date))
        let resolver = try #require(ScheduleResolver(database: database, timetableID: copy.id, context: context))
        for day in chosen.days {
            #expect(day.lessons.map(\.id) == resolver.resolution(for: day.date).schedule.entries.map(\.id.rawValue))
        }
        #expect(Set(chosen.days.flatMap { $0.lessons.map(\.id) }).isDisjoint(with: built.days.flatMap { $0.lessons.map(\.id) }))
        #expect(chosen.followingLesson != nil)
        // The rest of the snapshot (tasks, exams, settings) is shared.
        #expect(chosen.tasks == built.tasks && chosen.exams == built.exams && chosen.tier == built.tier)
    }

    @Test func sectionsNeverBreakTheSizeBudgetOrTheActiveData() throws {
        let (database, _, copies) = try withCopies(4)
        let built = snapshot(database)
        let size = try WidgetSnapshotStore.encode(built).count
        #expect(size <= WidgetSnapshotBuilder.maxEncodedBytes, "\(size) B")
        // The active timetable's data is what a one-timetable user gets (sections are added after the B1 trim).
        var withoutSections = built
        withoutSections.timetables = nil
        var single = database
        for copy in copies { single.timetables.removeAll { $0.id == copy.id } }
        let reference = snapshot(single)
        #expect(withoutSections.days == reference.days && withoutSections.tasks == reference.tasks)
        let sections = try #require(built.timetables)
        #expect(sections.count == 5)
        // Whatever did not fit has no days and selects to "Open Tabula" (nil), never another timetable's lessons.
        for section in sections where !section.hasData {
            #expect(built.selecting(timetableID: section.id.uuidString) == nil)
        }
        let withData = sections.filter { !$0.isActive && $0.days != nil }.count
        print("B3 budget evidence: 4 copies of the secondary timetable → \(size) B, \(withData)/4 copies with days")
    }

    @Test func olderSnapshotsWithoutSectionsStillDecode() throws {
        let (database, _, copies) = try withCopies(1)
        var built = snapshot(database)
        built.timetables = nil
        let decoded = try #require(WidgetSnapshotStore.decode(try WidgetSnapshotStore.encode(built)))
        #expect(decoded.timetables == nil)
        #expect(decoded.selecting(timetableID: copies[0].id.uuidString) == decoded)   // falls back to the active one
    }

    @Test func entityQueryReadsTheSnapshot() throws {
        let (database, active, copies) = try withCopies(2)
        let built = snapshot(database)
        let suggested = TimetableChoiceQuery.suggested(in: built)
        #expect(suggested.map(\.id) == ActiveTimetable.ordered(database).map(\.id.uuidString))
        #expect(suggested.filter(\.isActive).map(\.id) == [active.id.uuidString])
        #expect(suggested.map(\.name).contains("Copy 2"))
        let asked = [copies[1].id.uuidString, UUID().uuidString, copies[0].id.uuidString.lowercased()]
        #expect(TimetableChoiceQuery.entities(for: asked, in: built).map(\.id) == [copies[1].id.uuidString, copies[0].id.uuidString])
        #expect(TimetableChoiceQuery.entities(for: asked, in: nil).isEmpty)
        #expect(TimetableChoiceQuery.suggested(in: nil).isEmpty)
    }
}

@Suite("Phase 4 B3 final QA — snapshot size is a hard limit")
struct SnapshotHardBudgetTests {
    /// 12+ extra lessons every covered day with maximal multibyte text (3 bytes per character in UTF-8), long rooms,
    /// 40 tasks, 10 overdue, 6 exams, and 3 timetables (2 full copies): still ≤ 19 000 B, today complete.
    @Test func trueWorstCaseFits() throws {
        var database = SampleScenarios.secondary().database
        let wide = String(repeating: "語", count: 80)          // cut to 60 characters = 180 bytes by the builder
        for index in database.subjects.indices {
            database.subjects[index].name = wide
            database.subjects[index].shortName = wide
        }
        let timetable = try #require(ActiveTimetable.resolve(database))
        let subjectIDs = database.subjects.filter { !$0.isDeleted && $0.timetableID == timetable.id }.map(\.id)
        #expect(!subjectIDs.isEmpty)
        var serial = 1
        for dayOffset in 0..<8 {
            for slot in 0..<12 {
                let start = LocalTime(hour: 7 + slot, minute: 5)!, end = LocalTime(hour: 7 + slot, minute: 50)!
                let lesson = OneOffLesson(subjectID: subjectIDs[slot % subjectIDs.count], slot: .time(start: start, end: end),
                                          room: String(repeating: "室", count: 80))
                database.overrides.append(ScheduleOverride(id: ScheduleOverride.ID(Fixture.uuid(5000 + serial)),
                                                           meta: .created(at: .zero), timetableID: timetable.id,
                                                           date: Fixture.today.adding(days: dayOffset), change: .addLesson(lesson)))
                serial += 1
            }
        }
        let template = try #require(database.tasks.first)
        for index in 0..<50 {
            var copy = template
            copy.id = TaskItem.ID(Fixture.uuid(7000 + index))
            copy.title = String(repeating: "課題", count: 50) + "\(index)"
            copy.due = .date(index < 40 ? Fixture.today.adding(days: index % 7) : Fixture.today.adding(days: -(index - 39)))
            copy.completedAt = nil
            database.tasks.append(copy)
        }
        database.exams = (0..<6).map { index in
            Exam(id: Exam.ID(Fixture.uuid(8000 + index)), meta: Fixture.meta, title: String(repeating: "試験", count: 50),
                 date: Fixture.today.adding(days: index + 1), start: LocalTime(hour: 8, minute: 0)!,
                 room: String(repeating: "講堂", count: 50))
        }
        var ids = SequentialIDGenerator(namespace: 0xB3B4)
        for copyIndex in 0..<2 {
            let (mutation, _) = try #require(TimetableManagement.duplicateMutation(
                timetable.id, name: String(repeating: "時間割", count: 30) + "\(copyIndex)", in: database, ids: &ids))
            var clock = hlc(database)
            database = try mutation.apply(to: database, clock: &clock, now: now)
        }
        let built = snapshot(database)
        let size = try WidgetSnapshotStore.encode(built).count
        #expect(size <= WidgetSnapshotBuilder.maxEncodedBytes, "\(size) B")
        // Today is never dropped and keeps all its lessons; the active timetable's data comes first.
        #expect(built.days.first?.date == Fixture.today)
        let resolver = try #require(ScheduleResolver(database: database, timetableID: timetable.id, context: context))
        #expect(built.days.first?.lessons.count == resolver.resolution(for: Fixture.today).schedule.entries.count)
        #expect((built.days.first?.lessons.count ?? 0) >= 12)
        // When days were dropped, the following lesson is the first lesson after the last covered day.
        if let last = built.lastDay, let following = built.followingLesson {
            #expect(following.date > last)
        }
        print("B3 QA worst case: \(size) B, \(built.days.count) day(s), sections \(built.timetables?.count ?? 0)")
    }

    @Test func droppingDaysMovesTheFollowingLessonAndKeepsToday() throws {
        let full = snapshot(SampleScenarios.secondary().database)
        #expect(full.days.count == 3)
        var dayOnlyToday = full
        dayOnlyToday.days = [full.days[0]]
        // A limit that fits today plus the lists but not the other days: the far days go, today stays.
        let limit = try WidgetSnapshotStore.encode(dayOnlyToday).count + 200
        var trimmed = full
        WidgetSnapshotBuilder.enforceBudget(&trimmed, limit: limit)
        #expect(try WidgetSnapshotStore.encode(trimmed).count <= limit)
        #expect(trimmed.days.map(\.date) == [full.days[0].date])
        #expect(trimmed.days[0] == full.days[0])
        // "Next lesson" after today is tomorrow's first lesson, not the one after the original range.
        #expect(trimmed.followingLesson == full.days[1].lessons.first { $0.takesPlace })
        // An impossible limit still ends within it (hard guarantee), today's date kept.
        var tiny = full
        WidgetSnapshotBuilder.enforceBudget(&tiny, limit: 1_000)
        #expect(try WidgetSnapshotStore.encode(tiny).count <= 1_000)
        #expect(tiny.days.first?.date == full.days[0].date)
    }
}

@Suite("Phase 4 B3 — new-task link")
struct NewTaskLinkTests {
    @Test func roundTrips() {
        let url = ItemLinkURL.url(for: .newTask)
        #expect(url.absoluteString == "tabula://open/new-task")
        #expect(ItemLinkURL.link(from: url) == .newTask)
        #expect(ItemLinkURL.link(from: URL(string: "tabula://open/new-task/x")!) == nil)
    }

    /// Final QA m3/m8: 44 pt checkbox rows fit 2 / 7 rows; the alarm button policy id follows intents + the switch.
    @Test func checkboxCapacitiesAndAlarmPolicyID() {
        #expect(HomeworkDisplay.capacity(for: .systemMedium, withCheckbox: true) == 2)
        #expect(HomeworkDisplay.capacity(for: .systemLarge, withCheckbox: true) == 7)
        #expect(HomeworkDisplay.capacity(for: .systemMedium, withCheckbox: false) == 3)
        #expect(HomeworkDisplay.capacity(for: .systemSmall, withCheckbox: true) == 1)
        // 2 rows × 44 + header + "+N more" must fit the medium content height (170 − 2 × 16 = 138 pt); 7 rows the large one (350 pt).
        #expect(2 * HomeworkDisplay.checkboxRowHeight + 16 + 13 <= 138)
        #expect(7 * HomeworkDisplay.checkboxRowHeight + 16 + 13 <= 350)
        #expect(AlarmSecondaryAction.policyID(intentsAvailable: true) != AlarmSecondaryAction.policyID(intentsAvailable: false))
        #expect(AlarmSecondaryAction.policyID(intentsAvailable: true, doneReplacesSnooze: false)
            == AlarmSecondaryAction.policyID(intentsAvailable: false))
        // A state saved before B3 (no button policy) differs from any current signature → alarms re-scheduled once.
        let old = ReminderRenderSignature(language: "en", localeIdentifier: "en_US", hourCycle: "auto", timeZoneIdentifier: "Europe/Bratislava")
        var new = old
        new.alarmButtons = AlarmSecondaryAction.policyID(intentsAvailable: true)
        #expect(old != new)
    }
}
