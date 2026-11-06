// Phase 10 WP1 (app state & change fan-out): the pure decisions behind the performance fixes, and equivalence of every
// optimised computation with the code it replaces (old algorithm re-implemented here as the reference).
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private enum WP1 {
    static let scenario = SampleScenarios.secondary()
    static let zone = TimeZone(identifier: "Europe/Bratislava")!
    static let london = TimeZone(identifier: "Europe/London")!
    static let enGB = Locale(identifier: "en_GB")
    static let now = SampleScenarios.referenceNow   // Tue 2026-10-13 10:20 Bratislava

    static var database: TabulaDatabase {
        var database = scenario.database
        database.settings.timeZoneMode = .followDevice
        return database
    }

    static func inputs(_ database: TabulaDatabase?, zone: TimeZone = zone, locale: Locale = enGB,
                       settings: AppSettings? = nil) -> DerivedStateInputs {
        DerivedStateInputs(settings: settings ?? database?.settings ?? .untouchedDefaults, database: database,
                           deviceTimeZone: zone, locale: locale)
    }

    static func resolver(_ database: TabulaDatabase = database) throws -> ScheduleResolver {
        try #require(ScheduleResolver(database: database, timetableID: scenario.timetable.id, context: scenario.context))
    }

    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }
}

// MARK: - P2: derived state

@Suite("Phase 10 P2: derived state rebuild decision")
struct DerivedStateRebuildTests {
    @Test func firstBuildRebuildsEverything() {
        #expect(DerivedStateRebuild.needed(from: nil, to: WP1.inputs(WP1.database)) == .everything)
    }

    @Test func sameInputsRebuildNothing() {
        let database = WP1.database
        #expect(DerivedStateRebuild.needed(from: WP1.inputs(database), to: WP1.inputs(database)) == .nothing)
    }

    @Test func taskAndExamChangesKeepContextFormatterAndResolvers() {
        let before = WP1.database
        var after = before
        after.tasks.append(TaskItem(id: TaskItem.ID(WP1.uuid(900)), meta: .created(at: .zero), title: "New"))
        after.exams.removeAll()
        after.settings.globalQuietHours = QuietHours(start: LocalTime(hour: 21, minute: 0)!,
                                                     end: LocalTime(hour: 7, minute: 0)!)
        #expect(DerivedStateRebuild.needed(from: WP1.inputs(before), to: WP1.inputs(after)) == .nothing)
    }

    @Test func lessonChangeRebuildsOnlyResolvers() throws {
        let before = WP1.database
        var after = before
        try #require(!after.lessons.isEmpty)
        after.lessons.removeLast()
        #expect(DerivedStateRebuild.needed(from: WP1.inputs(before), to: WP1.inputs(after))
                == DerivedStateRebuild(context: false, formatter: false, resolvers: true))
        var timetable = before
        timetable.timetables[0].name += " (copy)"
        #expect(DerivedStateRebuild.needed(from: WP1.inputs(before), to: WP1.inputs(timetable)).resolvers)
    }

    @Test func hourCycleSettingRebuildsOnlyTheFormatter() {
        let before = WP1.database
        var after = before
        after.settings.hourCycle = before.settings.hourCycle == .h24 ? .h12 : .h24
        #expect(DerivedStateRebuild.needed(from: WP1.inputs(before), to: WP1.inputs(after))
                == DerivedStateRebuild(context: false, formatter: true, resolvers: false))
    }

    @Test func zoneChangeRebuildsEverything() throws {
        let database = WP1.database
        let before = WP1.inputs(database, zone: WP1.zone)
        let after = WP1.inputs(database, zone: WP1.london)
        try #require(before.context != after.context)
        #expect(DerivedStateRebuild.needed(from: before, to: after) == .everything)
    }

    @Test func localeChangeRebuildsTheFormatter() {
        let database = WP1.database
        let rebuild = DerivedStateRebuild.needed(from: WP1.inputs(database, locale: WP1.enGB),
                                                 to: WP1.inputs(database, locale: Locale(identifier: "de_DE")))
        #expect(rebuild.formatter)
        #expect(!rebuild.context || rebuild.resolvers)   // a context change always takes the resolvers with it
    }

    @Test func databaseAppearingOrVanishingRebuildsResolvers() {
        let database = WP1.database
        let empty = WP1.inputs(nil, settings: database.settings)
        let loaded = WP1.inputs(database)
        #expect(DerivedStateRebuild.needed(from: empty, to: loaded).resolvers)
        #expect(DerivedStateRebuild.needed(from: loaded, to: empty).resolvers)
    }

    /// Equivalence: when the decision keeps the resolvers, resolvers built from the new data give the same days.
    @Test func keptResolversResolveTheNewDataIdentically() {
        let before = WP1.database
        var after = before
        after.tasks.append(TaskItem(id: TaskItem.ID(WP1.uuid(901)), meta: .created(at: .zero), title: "Essay"))
        #expect(!DerivedStateRebuild.needed(from: WP1.inputs(before), to: WP1.inputs(after)).resolvers)
        let context = WP1.inputs(after).context
        let old = ScheduleResolver.all(database: before, context: context)
        let new = ScheduleResolver.all(database: after, context: context)
        #expect(old.map(\.timetable.id) == new.map(\.timetable.id))
        let dates = (-7..<21).map { SampleScenarios.today.adding(days: $0) }
        for (a, b) in zip(old, new) {
            #expect(dates.map { a.resolution(for: $0) } == dates.map { b.resolution(for: $0) })
        }
    }
}

// MARK: - P5: foreground refresh

@Suite("Phase 10 P5: foreground refresh policy")
struct ForegroundRefreshPolicyTests {
    private func fingerprint(zone: TimeZone = WP1.zone, locale: Locale = WP1.enGB,
                             now: Date = WP1.now) -> EnvironmentFingerprint {
        EnvironmentFingerprint(settings: WP1.database.settings, deviceTimeZone: zone, locale: locale, now: now)
    }

    private func decide(background: Bool = false, last: EnvironmentFingerprint?, at: Date? = WP1.now,
                        current: EnvironmentFingerprint, now: Date) -> Bool {
        ForegroundRefreshPolicy.shouldRefresh(returningFromBackground: background, last: last, lastRefreshAt: at,
                                              current: current, now: now)
    }

    @Test func returningFromTheBackgroundAlwaysRefreshes() {
        let same = fingerprint()
        #expect(decide(background: true, last: same, current: same, now: WP1.now.addingTimeInterval(5)))
    }

    @Test func aShortBlipWithNothingChangedDoesNotRefresh() {
        let same = fingerprint()
        #expect(!decide(last: same, current: same, now: WP1.now.addingTimeInterval(20)))
        #expect(!decide(last: same, current: fingerprint(now: WP1.now.addingTimeInterval(299)),
                        now: WP1.now.addingTimeInterval(299)))
    }

    @Test func aBlipAfterFiveMinutesRefreshes() {
        let later = WP1.now.addingTimeInterval(ForegroundRefreshPolicy.blipRefreshAge)
        #expect(decide(last: fingerprint(), current: fingerprint(now: later), now: later))
    }

    @Test func zoneLocaleOrDayChangesRefreshAtOnce() {
        let last = fingerprint()
        let soon = WP1.now.addingTimeInterval(10)
        #expect(decide(last: last, current: fingerprint(zone: WP1.london, now: soon), now: soon))
        #expect(decide(last: last, current: fingerprint(locale: Locale(identifier: "de_DE"), now: soon), now: soon))
        // 23:59:50 → 00:00:10 local: a new day, 20 s later.
        let context = CalendarContext(timeZone: WP1.zone, firstWeekday: .monday)
        let beforeMidnight = context.date(SampleScenarios.today, LocalTime(hour: 23, minute: 59)!).addingTimeInterval(50)
        let afterMidnight = beforeMidnight.addingTimeInterval(20)
        #expect(decide(last: fingerprint(now: beforeMidnight), at: beforeMidnight,
                       current: fingerprint(now: afterMidnight), now: afterMidnight))
    }

    @Test func nothingRefreshedYetOrClockWentBackRefreshes() {
        let same = fingerprint()
        #expect(decide(last: nil, at: nil, current: same, now: WP1.now))
        #expect(decide(last: same, at: nil, current: same, now: WP1.now))
        #expect(decide(last: same, at: WP1.now, current: same, now: WP1.now.addingTimeInterval(-60)))
    }
}

// MARK: - P6: launch hold

@Suite("Phase 10 P6: launch hold")
struct LaunchHoldTests {
    @Test func alreadyLoadedNeverShowsTheMark() {
        #expect(!LaunchHold.showsLaunch(isLoading: false, markAppeared: false, holdFinished: false))
    }

    @Test func aMarkOnScreenStaysForItsSwipe() {
        #expect(LaunchHold.showsLaunch(isLoading: true, markAppeared: false, holdFinished: false))
        #expect(LaunchHold.showsLaunch(isLoading: false, markAppeared: true, holdFinished: false))
        #expect(!LaunchHold.showsLaunch(isLoading: false, markAppeared: true, holdFinished: true))
        #expect(LaunchHold.showsLaunch(isLoading: true, markAppeared: true, holdFinished: true))
    }

    @Test func reduceMotionHasNoHoldAndNoFade() {
        #expect(LaunchHold.holdDuration(reduceMotion: true) == .zero)
        #expect(LaunchHold.fadeDuration(reduceMotion: true) == nil)
        #expect(LaunchHold.holdDuration(reduceMotion: false) == .milliseconds(300))
        #expect(LaunchHold.fadeDuration(reduceMotion: false) == 0.2)
    }
}

// MARK: - P14: quiet-hours draft

@Suite("Phase 10 P14: quiet-hours draft")
struct QuietHoursDraftTests {
    private let stored = QuietHours(start: LocalTime(hour: 22, minute: 0)!, end: LocalTime(hour: 7, minute: 0)!)

    @Test func editsAreShownAndWrittenOnce() {
        var draft = QuietHoursDraft()
        #expect(draft.shown(stored: stored) == stored)
        #expect(!draft.isPending)
        let first = QuietHours(start: LocalTime(hour: 21, minute: 0)!, end: stored.end)
        let second = QuietHours(start: LocalTime(hour: 21, minute: 30)!, end: stored.end)
        draft.edit(first)
        draft.edit(second)
        #expect(draft.isPending)
        #expect(draft.shown(stored: stored) == second)
        #expect(draft.take(stored: stored) == .write(second))
        #expect(!draft.isPending)
        #expect(draft.take(stored: second) == .none)   // idempotent: a second commit writes nothing
    }

    @Test func anEditBackToTheStoredValueWritesNothing() {
        var draft = QuietHoursDraft()
        draft.edit(QuietHours(start: LocalTime(hour: 20, minute: 0)!, end: stored.end))
        draft.edit(stored)
        #expect(draft.take(stored: stored) == .none)
    }
}

// MARK: - P11: one resolution per pass

@Suite("Phase 10 P11: ResolvedWeek equals the per-call factories")
struct ResolvedWeekEquivalenceTests {
    /// The view's former change-reason loop.
    private func referenceReasons(_ dates: [LocalDate], _ resolver: ScheduleResolver) -> [OccurrenceID: [ModificationReason]] {
        var result: [OccurrenceID: [ModificationReason]] = [:]
        for date in dates {
            for change in resolver.resolution(for: date).changes { result[change.occurrenceID] = change.reasons }
        }
        return result
    }

    /// `LessonWorkSupport.index` (App target) as it was.
    private func referenceWork(_ selection: TimetableSelection, _ resolver: ScheduleResolver,
                               _ database: TabulaDatabase) -> LessonWorkIndex {
        guard !(database.tasks.isEmpty && database.exams.isEmpty) else { return .empty }
        var seen = Set<LocalDate>()
        let dates = (0..<7).map { selection.weekStart.adding(days: $0) } + [selection.selectedDate]
        let lessons = dates.filter { seen.insert($0).inserted }.flatMap { resolver.day($0).entries }
        return LessonWorkIndex.make(lessons: lessons, tasks: database.tasks, exams: database.exams)
    }

    private func selections(_ resolver: ScheduleResolver) -> [TimetableSelection] {
        let today = SampleScenarios.today
        let initial = TimetableSelection.initial(today: today, resolver: resolver)
        let override = TimetableSelection.initial(today: WP1.scenario.overrideDate, resolver: resolver)
        return [initial, initial.shifted(byWeeks: 1, resolver: resolver), initial.shifted(byWeeks: -3, resolver: resolver),
                override,
                // A selected day outside the shown week and a week start that is not the display week start.
                TimetableSelection(weekStart: initial.weekStart, selectedDate: initial.weekStart.adding(days: 12)),
                TimetableSelection(weekStart: initial.weekStart.adding(days: 2), selectedDate: initial.weekStart.adding(days: 3))]
    }

    @Test func everyOutputMatches() throws {
        let database = WP1.scenario.database
        let resolver = try WP1.resolver(database)
        let today = SampleScenarios.today
        for selection in selections(resolver) {
            let week = ResolvedWeek(selection: selection, resolver: resolver)
            #expect(week.strip(today: today) == WeekStripModel.make(selection: selection, today: today, resolver: resolver))
            let grid = TimetableCore.GridLayout.week(containing: selection.weekStart, resolver: resolver)
            #expect(week.gridLayout() == grid)
            #expect(week.timeBlockWeekLayout() == TimeBlockLayout.week(containing: selection.weekStart, resolver: resolver))
            let dates = grid.columns.map(\.date)
            #expect(week.reasons(for: dates) == referenceReasons(dates, resolver))
            #expect(week.reasons(for: [selection.selectedDate]) == referenceReasons([selection.selectedDate], resolver))
            #expect(week.resolution(for: selection.selectedDate) == resolver.resolution(for: selection.selectedDate))
            #expect(week.resolution(for: today.adding(days: 40)) == resolver.resolution(for: today.adding(days: 40)))
            #expect(week.lessonWork(database: database) == referenceWork(selection, resolver, database))
        }
        #expect(ResolvedWeek(selection: selections(resolver)[0], resolver: resolver).lessonWork(database: nil) == .empty)
    }
}

// MARK: - P11: LessonWorkIndex pre-filter

@Suite("Phase 10 P11: LessonWorkIndex matches before sorting")
struct LessonWorkIndexEquivalenceTests {
    /// The former algorithm: sort every live task / exam, then match.
    private func reference(lessons: [ResolvedLesson], tasks: [TaskItem], exams: [Exam]) -> LessonWorkIndex {
        guard !lessons.isEmpty else { return .empty }
        let ordered = lessons.sorted { ($0.date, $0.startTime, $0.endTime, $0.id) < ($1.date, $1.startTime, $1.endTime, $1.id) }
        struct Key: Hashable { let date: LocalDate; let subject: Subject.ID }
        var byLink: [LessonLink: OccurrenceID] = [:]
        var anchors: [Key: OccurrenceID] = [:]
        var cancelled: [Key: OccurrenceID] = [:]
        var bySubjectDay: [Key: [ResolvedLesson]] = [:]
        for lesson in ordered {
            if case .lesson(let id) = lesson.source {
                let link = LessonLink(lessonID: id, date: lesson.date)
                if byLink[link] == nil { byLink[link] = lesson.id }
            }
            let key = Key(date: lesson.date, subject: lesson.subject.id)
            bySubjectDay[key, default: []].append(lesson)
            if lesson.status == .cancelled {
                if cancelled[key] == nil { cancelled[key] = lesson.id }
            } else if anchors[key] == nil {
                anchors[key] = lesson.id
            }
        }
        func anchor(_ date: LocalDate, _ subject: Subject.ID) -> OccurrenceID? {
            anchors[Key(date: date, subject: subject)] ?? cancelled[Key(date: date, subject: subject)]
        }
        var result: [OccurrenceID: LessonWork] = [:]
        for task in tasks.filter({ !$0.isDeleted }).sorted(by: LessonWorkIndex.taskOrder) {
            var target: OccurrenceID?
            if let link = task.linkedLesson, let linked = byLink[link] {
                target = linked
            } else if let subject = task.subjectID, let date = task.due?.date {
                target = anchor(date, subject)
            }
            guard let occurrence = target else { continue }
            if task.isCompleted {
                result[occurrence, default: LessonWork()].completedTaskIDs.append(task.id)
            } else {
                result[occurrence, default: LessonWork()].openTaskIDs.append(task.id)
            }
        }
        for exam in exams.filter({ !$0.isDeleted })
            .sorted(by: { ($0.date, $0.start ?? .midnight, $0.title, $0.id) < ($1.date, $1.start ?? .midnight, $1.title, $1.id) }) {
            guard let subject = exam.subjectID else { continue }
            var target: OccurrenceID?
            if let start = exam.start, let candidates = bySubjectDay[Key(date: exam.date, subject: subject)] {
                let containing = candidates.filter { $0.startTime <= start && start < $0.endTime }
                target = (containing.first { $0.status != .cancelled } ?? containing.first)?.id
            }
            guard let occurrence = target ?? anchor(exam.date, subject) else { continue }
            result[occurrence, default: LessonWork()].examIDs.append(exam.id)
        }
        return LessonWorkIndex(byOccurrence: result)
    }

    @Test func manyTasksIncludingHistoryGiveTheSameIndex() throws {
        let database = WP1.scenario.database
        let resolver = try WP1.resolver(database)
        let today = SampleScenarios.today
        let week = (0..<7).map { today.adding(days: $0 - 1) }
        let lessons = week.flatMap { resolver.day($0).entries }
        try #require(!lessons.isEmpty)
        let subjects = database.subjects.filter { !$0.isDeleted }.map(\.id)
        try #require(!subjects.isEmpty)
        let linkable = lessons.compactMap { lesson -> LessonLink? in
            if case .lesson(let id) = lesson.source { return LessonLink(lessonID: id, date: lesson.date) }
            return nil
        }
        var tasks = database.tasks
        for index in 0..<240 {
            var meta = EntityMeta.created(at: .zero)
            meta.isDeleted = index % 17 == 0
            let date = today.adding(days: index % 40 - 30)   // mostly history outside the shown week
            let due: TaskDue? = index % 13 == 0 ? nil
                : index % 2 == 0 ? .date(date) : .dateTime(date, LocalTime(hour: 7 + index % 9, minute: 0)!)
            let link = index % 5 == 0 && !linkable.isEmpty ? linkable[index % linkable.count] : nil
            tasks.append(TaskItem(id: TaskItem.ID(WP1.uuid(1_000 + index)), meta: meta, title: "T\(index % 7)",
                                  subjectID: index % 11 == 0 ? nil : subjects[index % subjects.count], due: due,
                                  linkedLesson: link, priority: TaskPriority.allCases[index % 4],
                                  completedAt: index % 3 == 0 ? Date(timeIntervalSince1970: 0) : nil))
        }
        var exams = database.exams
        for index in 0..<40 {
            var meta = EntityMeta.created(at: .zero)
            meta.isDeleted = index % 9 == 0
            exams.append(Exam(id: Exam.ID(WP1.uuid(5_000 + index)), meta: meta,
                              subjectID: index % 7 == 0 ? nil : subjects[index % subjects.count], title: "E\(index % 3)",
                              date: today.adding(days: index % 12 - 4),
                              start: index % 2 == 0 ? LocalTime(hour: 8 + index % 6, minute: 15)! : nil))
        }
        let made = LessonWorkIndex.make(lessons: lessons, tasks: tasks, exams: exams)
        #expect(made == reference(lessons: lessons, tasks: tasks, exams: exams))
        #expect(!made.byOccurrence.isEmpty)
        #expect(LessonWorkIndex.make(lessons: lessons.reversed(), tasks: tasks.reversed(), exams: exams.reversed()) == made)
    }
}

// MARK: - P4: reminder engine

/// Counts saves and records the ledger of each saved state.
private final class CountingReminderStateStore: ReminderStateStore, @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private var state: AppliedReminderState?
    private var savedLedgers: [[UUID]] = []

    var saves: Int { lock.withLock { savedLedgers.count } }
    var ledgers: [[UUID]] { lock.withLock { savedLedgers } }

    func load() -> AppliedReminderState? { lock.withLock { state } }
    func save(_ state: AppliedReminderState) {
        lock.withLock {
            self.state = state
            savedLedgers.append(state.alarmLedger)
        }
    }
}

@MainActor
@Suite("Phase 10 P4: reminder engine saves once and plans off the main actor")
struct ReminderEngineFanOutTests {
    @Test func offMainPlanEqualsThePlanner() async {
        let database = Fixture.database()
        let options = ReminderPlanningOptions(canScheduleAlarms: true)
        let resolvers = ScheduleResolver.all(database: database, context: Fixture.context)
        let direct = ReminderPlanner.plan(ReminderInputBuilder.input(database: database, resolvers: resolvers,
                                                                     context: Fixture.context, now: Fixture.now,
                                                                     options: options))
        let detached = await ReminderEngine.plan(database: database, resolvers: resolvers, context: Fixture.context,
                                                 now: Fixture.now, options: options)
        #expect(detached == direct)
    }

    @Test func aRunWithANewAlarmSavesTheLedgerAheadThenOnce() async throws {
        let store = CountingReminderStateStore()
        let alarms = InMemoryAlarmClient()
        let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: alarms, store: store)
        let signature = ReminderRenderSignature(language: "en", localeIdentifier: "en_US_POSIX", hourCycle: "auto",
                                                timeZoneIdentifier: Fixture.zone.identifier, alarmButtons: "snooze")
        var input = Fixture.input(Fixture.database())
        input.renderSignature = signature
        let result = await engine.run(input)
        try #require(!result.plan.alarms.isEmpty)
        // Write-ahead (ledger with the new alarm, before scheduling) + the one final save.
        #expect(store.saves == 2)
        let alarmIDs = Set(result.plan.alarms.map(\.alarmID))
        #expect(alarmIDs.isSubset(of: Set(store.ledgers[0])))
        // The final save holds everything the run changed.
        let saved = try #require(store.load())
        #expect(saved == engine.state)
        #expect(saved.renderSignature == signature)
        #expect(saved.lastRunAt == Fixture.now)
        #expect(saved.plan == result.plan)
        // Same input again: nothing new to schedule, so exactly one save.
        _ = await engine.run(input)
        #expect(store.saves == 3)
        #expect(await alarms.cancelled.isEmpty)
    }

    @Test func aRunWithoutAlarmsSavesOnce() async {
        let store = CountingReminderStateStore()
        let engine = ReminderEngine(notifications: InMemoryNotificationCenterClient(), alarms: InMemoryAlarmClient(),
                                    store: store)
        let result = await engine.run(Fixture.input(Fixture.database(alarmsOn: false)))
        #expect(result.plan.alarms.isEmpty)
        #expect(!result.plan.notifications.isEmpty)
        #expect(store.saves == 1)
        #expect(store.load() == engine.state)
    }
}

// MARK: - B12: Mark done failure notice

@Suite("Phase 10 B12: Mark done failure notice")
struct MarkDoneFailedNoticeTests {
    private let renderer = LocalizedTextRenderer(
        formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .auto, timeZone: WP1.zone),
        lookup: EnglishCatalog.lookup)

    @Test func noticeNamesTheItemAndOpensIt() {
        let source = ReminderSource.task(TaskItem.ID(WP1.uuid(7))).rawValue
        let delivered = DeliveredNotification(
            requestID: "rem.0123456789abcdef", title: "Essay", subtitle: nil, body: "Tomorrow", interruption: .active,
            threadID: "task", categoryID: "tabula.task",
            userInfo: [ReminderUserInfo.source: source, ReminderUserInfo.kind: ReminderUserInfo.kindPlanned])
        let builder = ReminderRequestBuilder(renderer: renderer, context: CalendarContext(timeZone: WP1.zone, firstWeekday: .monday))
        let spec = builder.markDoneFailedNotice(for: delivered, now: WP1.now)
        #expect(spec.id == "tabula.notice.markDoneFailed." + source)
        #expect(!ReminderID.isPlannerID(spec.id) && !ReminderRequestID.isSnooze(spec.id))   // never touched by the diff
        #expect(spec.title == "Couldn't Mark as Done")
        #expect(spec.body == "Open Tabula to try again.")
        #expect(spec.subtitle == "Essay")
        #expect(spec.categoryID.isEmpty)   // no actions
        #expect(spec.threadID == "task")
        #expect(spec.userInfo[ReminderUserInfo.source] == source)
        #expect(spec.userInfo[ReminderUserInfo.kind] == ReminderUserInfo.kindNotice)
        #expect(spec.fireDate == WP1.now.addingTimeInterval(1))
        #expect(spec.trigger.instant == spec.fireDate)
        // A tap opens the item, like the original notification.
        let tapped = DeliveredNotification(requestID: spec.id, title: spec.title, subtitle: spec.subtitle, body: spec.body,
                                           interruption: .active, threadID: spec.threadID, categoryID: spec.categoryID,
                                           userInfo: spec.userInfo)
        #expect(ReminderResponseInterpreter.command(for: .open, delivered: tapped)
                == .open(.task(TaskItem.ID(WP1.uuid(7)))))
    }

    @Test func everyAdapterKeyIsInTheCatalog() throws {
        let catalog = try CatalogFile.keys()
        let missing = ReminderRequestBuilder.Keys.all.filter { !catalog.contains($0) }
        #expect(missing.isEmpty, "missing catalog keys: \(missing)")
    }
}
