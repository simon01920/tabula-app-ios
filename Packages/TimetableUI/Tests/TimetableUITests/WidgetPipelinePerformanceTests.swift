import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 10 WP2 — widget / Live Activity / Watch pipeline performance. Every change here must leave the output identical:
// the snapshot (and its bytes) of the exact byte accounting equals the Phase 4 algorithm's, the timeline plans equal
// the Phase 4 planner's (copied below as `LegacyPlanner`), and the shared build cache only reuses a build whose content
// a fresh build would repeat.

private let context = Fixture.context          // Europe/Bratislava, Monday
private let now = Fixture.now                  // Tue 2026-10-13 10:20
private let locale = Locale(identifier: "en_GB")
private let newYork = TimeZone(identifier: "America/New_York")!
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func instant(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> Date { context.date(day, time(h, m)) }

private final class EncodeCounter {
    var count = 0
}

/// A build through the injectable encoder, counting the whole-snapshot encodes.
private func counted(_ database: TabulaDatabase?, at instant: Date = now, tier: Tier = .pro,
                     resolvers: [Timetable.ID: ScheduleResolver]? = nil,
                     sizing: WidgetSnapshotBuild.Sizing = .exact) -> (build: WidgetSnapshotBuild, encodes: Int) {
    let counter = EncodeCounter()
    let build = WidgetSnapshotBuilder.build(database: database, now: instant, context: context, tier: tier, locale: locale,
                                            languageCode: "en", resolvers: resolvers, sizing: sizing,
                                            encode: { snapshot in
                                                counter.count += 1
                                                return try WidgetSnapshotStore.encode(snapshot)
                                            })
    return (build, counter.count)
}

private func hlc(_ database: TabulaDatabase) -> HybridLogicalClock {
    var clock = HybridLogicalClock(node: 0xB2)
    clock.receive(database.latestTimestamp, now: now)
    return clock
}

/// The secondary scenario with `copies` duplicated timetables.
private func withCopies(_ copies: Int) throws -> TabulaDatabase {
    let scenario = SampleScenarios.secondary()
    var database = scenario.database
    var ids = SequentialIDGenerator(namespace: 0xB2B2)
    for index in 0..<copies {
        let (mutation, _) = try #require(TimetableManagement.duplicateMutation(
            scenario.timetable.id, name: "Copy \(index + 1)", in: database, ids: &ids))
        var clock = hlc(database)
        database = try mutation.apply(to: database, clock: &clock, now: now)
    }
    return database
}

/// `SnapshotHardBudgetTests.trueWorstCaseFits`' data: 12 extra lessons a day with maximal CJK text, 50 tasks, 6 exams,
/// 3 timetables.
private func worstCase() throws -> TabulaDatabase {
    var database = SampleScenarios.secondary().database
    let wide = String(repeating: "語", count: 80)
    for index in database.subjects.indices {
        database.subjects[index].name = wide
        database.subjects[index].shortName = wide
    }
    let timetable = try #require(ActiveTimetable.resolve(database))
    let subjectIDs = database.subjects.filter { !$0.isDeleted && $0.timetableID == timetable.id }.map(\.id)
    var serial = 1
    for dayOffset in 0..<8 {
        for slot in 0..<12 {
            let lesson = OneOffLesson(subjectID: subjectIDs[slot % subjectIDs.count],
                                      slot: .time(start: time(7 + slot, 5), end: time(7 + slot, 50)),
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
             date: Fixture.today.adding(days: index + 1), start: time(8), room: String(repeating: "講堂", count: 50))
    }
    var ids = SequentialIDGenerator(namespace: 0xB2B3)
    for copyIndex in 0..<2 {
        let (mutation, _) = try #require(TimetableManagement.duplicateMutation(
            timetable.id, name: String(repeating: "時間割", count: 30) + "\(copyIndex)", in: database, ids: &ids))
        var clock = hlc(database)
        database = try mutation.apply(to: database, clock: &clock, now: now)
    }
    return database
}

/// Every seeded database (the empty seed has none).
private var seededDatabases: [TabulaDatabase?] { SeedKind.allCases.map { SampleScenarios.make($0).database } }

/// Instants that cover school time, after school, a weekend, the DST end and the autumn holidays.
private let probeInstants: [Date] = [
    instant(date(2026, 10, 13), 7, 20), now, instant(date(2026, 10, 13), 16),
    instant(date(2026, 10, 17), 12), instant(date(2026, 10, 23), 15), instant(date(2026, 10, 29), 9),
]

// MARK: - P12: one build, exact byte accounting

@Suite("Phase 10 WP2 — snapshot builder: same bytes, fewer encodes")
struct WidgetPipelineBuilderTests {
    @Test func exactAccountingGivesThePhase4BytesOnTheSeeds() throws {
        for database in seededDatabases {
            for probe in probeInstants {
                let fast = counted(database, at: probe)
                let legacy = counted(database, at: probe, sizing: .legacy)
                let reencoded = try WidgetSnapshotStore.encode(fast.build.snapshot)
                #expect(fast.build.snapshot == legacy.build.snapshot)
                #expect(fast.build.data == legacy.build.data)
                #expect(fast.build.data == reencoded)
                #expect(fast.build.sizing == .exact)
                // Everything fits: the size check's encode IS the file (Phase 4: check + the writer's encode).
                #expect(fast.encodes <= 2 && fast.encodes <= legacy.encodes, "\(fast.encodes) vs \(legacy.encodes)")
            }
        }
    }

    @Test(arguments: [1, 2, 4])
    func sectionsAreAddedWithAtMostTwoEncodes(_ copies: Int) throws {
        let database = try withCopies(copies)
        let timetables = ActiveTimetable.ordered(database).count
        let fast = counted(database)
        let legacy = counted(database, sizing: .legacy)
        #expect(fast.build.snapshot == legacy.build.snapshot)
        #expect(fast.build.data == legacy.build.data)
        #expect(fast.build.sizing == .exact)
        #expect(fast.encodes <= 2 && fast.encodes <= timetables + 2, "\(fast.encodes) encodes")
        let size = try #require(fast.build.data).count
        #expect(size <= WidgetSnapshotBuilder.maxEncodedBytes)
        print("WP2 evidence: \(timetables) timetables → \(size) B; encodes exact \(fast.encodes), Phase 4 \(legacy.encodes)")
    }

    @Test func worstCaseIsIdenticalAndWithinTheHardLimit() throws {
        let database = try worstCase()
        let fast = counted(database)
        let legacy = counted(database, sizing: .legacy)
        #expect(fast.build.snapshot == legacy.build.snapshot)
        #expect(fast.build.data == legacy.build.data)
        let size = try #require(fast.build.data).count
        #expect(size <= WidgetSnapshotBuilder.maxEncodedBytes, "\(size) B")
        let timetables = ActiveTimetable.ordered(database).count
        if fast.build.sizing == .exact { #expect(fast.encodes <= timetables + 2) }
        print("WP2 worst case: \(size) B, sizing \(fast.build.sizing), encodes exact \(fast.encodes), Phase 4 \(legacy.encodes)")
    }

    /// The accounting on its own: for every limit, the predicted size is the real encoded size and the trimmed snapshot
    /// is the Phase 4 one; limits that need the pathological steps hand over (and `enforceBudget` still matches).
    @Test func trimMatchesThePhase4BudgetAtEveryLimit() throws {
        let encode: (WidgetSnapshot) throws -> Data = WidgetSnapshotStore.encode
        var inputs: [WidgetSnapshot] = []
        let copies = try withCopies(2)
        let worst = try worstCase()
        for database in [SampleScenarios.secondary().database, copies, worst] {
            inputs.append(WidgetSnapshotBuilder.untrimmed(database: database, now: now, context: context, tier: .pro,
                                                          locale: locale, languageCode: "en", resolvers: nil).snapshot)
        }
        var exactRuns = 0
        for input in inputs {
            let full = try WidgetSnapshotStore.encode(input).count
            // About 120 limits per input (odd step: no alignment with element sizes).
            for limit in stride(from: 300, through: full + 500, by: max(97, (full / 120) | 1)) {
                var reference = input
                WidgetSnapshotBuilder.legacyEnforceBudget(&reference, limit: limit, encode: encode)
                var budgeted = input
                WidgetSnapshotBuilder.enforceBudget(&budgeted, limit: limit)
                #expect(budgeted == reference, "limit \(limit)")
                var trimmed = input
                if let size = try? WidgetSnapshotBuilder.trim(&trimmed, limit: limit, sizer: SnapshotSizer(),
                                                               encode: encode) {
                    exactRuns += 1
                    let real = try WidgetSnapshotStore.encode(trimmed).count
                    #expect(size.bytes == real, "limit \(limit)")
                    #expect(size.bytes <= limit)
                    #expect(trimmed == reference, "limit \(limit)")
                }
            }
        }
        #expect(exactRuns > 10, "\(exactRuns) limits used the exact accounting")
    }

    @Test func sizerAgreesWithTheEncoderOnParts() throws {
        let database = try worstCase()
        let snapshot = WidgetSnapshotBuilder.untrimmed(database: database, now: now, context: context, tier: .pro,
                                                       locale: locale, languageCode: "en", resolvers: nil).snapshot
        let sizer = SnapshotSizer()
        // An array is its parts joined by fixed punctuation.
        let encodedDays = try WidgetSnapshotStore.makeEncoder().encode(snapshot.days).count
        let daySizes = try sizer.sizes(snapshot.days)
        #expect(SnapshotSizer.arrayBytes(daySizes) == encodedDays)
        let encodedTasks = try WidgetSnapshotStore.makeEncoder().encode(snapshot.tasks).count
        let taskSizes = try sizer.sizes(snapshot.tasks)
        #expect(SnapshotSizer.arrayBytes(taskSizes) == encodedTasks)
        #expect(SnapshotSizer.arrayBytes([]) == 2)
        // Removing a member: the whole file shrinks by exactly `memberBytes`.
        var withoutFollowing = snapshot
        withoutFollowing.followingLesson = nil
        let following = try #require(snapshot.followingLesson)
        let delta = try WidgetSnapshotStore.encode(snapshot).count - WidgetSnapshotStore.encode(withoutFollowing).count
        let followingSize = try sizer.size(of: following)
        #expect(delta == SnapshotSizer.memberBytes(WidgetSnapshot.CodingKeys.followingLesson.stringValue, followingSize))
        // Dropping tasks: the file shrinks by exactly the array's change.
        var fewer = snapshot
        fewer.tasks = Array(fewer.tasks.prefix(4))
        var sizes = taskSizes
        let change = SnapshotSizer.keepingPrefix(&sizes, 4)
        let full = try WidgetSnapshotStore.encode(snapshot).count
        let trimmed = try WidgetSnapshotStore.encode(fewer).count
        #expect(trimmed - full == change)
    }

    @Test func prebuiltResolversGiveTheSameSnapshot() throws {
        for database in [SampleScenarios.secondary().database, try withCopies(2)] {
            let all = ScheduleResolver.all(database: database, context: context)
            let resolvers = Dictionary(all.map { ($0.timetable.id, $0) }, uniquingKeysWith: { first, _ in first })
            let plain = counted(database)
            #expect(counted(database, resolvers: resolvers).build == plain.build)
            // Resolvers built in another zone are not used (the snapshot stays the Bratislava one).
            let london = ScheduleResolver.all(database: database, context: Fixture.london)
            let wrong = Dictionary(london.map { ($0.timetable.id, $0) }, uniquingKeysWith: { first, _ in first })
            #expect(counted(database, resolvers: wrong).build == plain.build)
        }
    }
}

// MARK: - P3 / C2: one build per change

@Suite("Phase 10 WP2 — shared build cache")
struct WidgetSnapshotBuildCacheTests {
    @Test func reusesTheBuildWithinTheMinuteAndRebuildsOnEveryInputChange() throws {
        var database = SampleScenarios.secondary().database
        var cache = WidgetSnapshotBuildCache()
        func build(_ at: Date, tier: Tier = .pro, language: String? = "en") -> WidgetSnapshotBuild {
            cache.build(database: database, now: at, context: context, tier: tier, locale: locale, languageCode: language,
                        resolvers: nil)
        }
        let first = build(now)
        #expect(cache.buildCount == 1)
        #expect(build(now.addingTimeInterval(59.9)) == first)    // the Live Activity run, then the writer
        #expect(cache.buildCount == 1)
        _ = build(now.addingTimeInterval(60))
        #expect(cache.buildCount == 2)
        _ = build(now.addingTimeInterval(60), tier: .free)
        #expect(cache.buildCount == 3)
        _ = build(now.addingTimeInterval(60), tier: .free, language: "sk")
        #expect(cache.buildCount == 4)
        database.tasks[0].title = "Changed"
        let changed = build(now.addingTimeInterval(60), tier: .free, language: "sk")
        #expect(cache.buildCount == 5)
        #expect(changed.snapshot.contentOnly == WidgetSnapshotBuilder.make(
            database: database, now: now.addingTimeInterval(60), context: context, tier: .free, locale: locale,
            languageCode: "sk").contentOnly)
        // Another zone (context) is a new key.
        _ = cache.build(database: database, now: now.addingTimeInterval(60), context: Fixture.london, tier: .free,
                        locale: locale, languageCode: "sk", resolvers: nil)
        #expect(cache.buildCount == 6)
    }

    /// The claim behind the minute key: within one minute every instant gives the same content (seeds, every probe).
    @Test func contentIsConstantWithinAMinute() throws {
        for database in seededDatabases {
            for probe in probeInstants {
                let early = WidgetSnapshotBuilder.make(database: database, now: probe, context: context, tier: .pro,
                                                       locale: locale, languageCode: "en")
                let late = WidgetSnapshotBuilder.make(database: database, now: probe.addingTimeInterval(59.999),
                                                      context: context, tier: .pro, locale: locale, languageCode: "en")
                #expect(early.contentOnly == late.contentOnly)
            }
        }
    }

    /// The only sub-day instant comparison of the builder: an exam ending at 10:45 is listed for the whole 10:44 minute
    /// and gone for the whole 10:45 minute; a task due 10:44 flips to overdue at a minute boundary too.
    @Test func examEndAndTaskDueFlipOnlyAtMinuteBoundaries() throws {
        var database = SampleScenarios.secondary().database
        var exam = try #require(database.exams.first)
        exam.id = Exam.ID(Fixture.uuid(9100))
        exam.date = Fixture.today
        exam.start = time(10)
        exam.end = time(10, 45)
        exam.completedAt = nil
        exam.title = "Minute boundary"
        database.exams.append(exam)
        var task = try #require(database.tasks.first)
        task.id = TaskItem.ID(Fixture.uuid(9101))
        task.due = .dateTime(Fixture.today, time(10, 44))
        task.completedAt = nil
        database.tasks.append(task)
        func snap(_ seconds: TimeInterval) -> WidgetSnapshot {
            WidgetSnapshotBuilder.make(database: database, now: instant(Fixture.today, 10, 44).addingTimeInterval(seconds),
                                       context: context, tier: .pro, locale: locale, languageCode: "en")
        }
        let listed = { (s: WidgetSnapshot) in s.upcomingExams.contains { $0.id == exam.id.uuid } }
        #expect(listed(snap(0)) && listed(snap(59.999)))
        #expect(!listed(snap(60)) && !listed(snap(119.999)))
        #expect(snap(0).contentOnly == snap(59.999).contentOnly)
        #expect(snap(60).contentOnly == snap(119.999).contentOnly)
    }

    @Test func keyKeepsRepeatedLocalMinutesApart() throws {
        // Sun 2026-10-25 02:30 Bratislava happens twice (CEST, then CET): same local date-time, other UTC minute.
        // 00:30 UTC = 02:30 CEST; 01:30 UTC = 02:30 CET.
        let midnightUTC = TimeInterval(date(2026, 10, 25).daysSinceEpoch) * 86_400
        let firstPass = Date(timeIntervalSince1970: midnightUTC + 30 * 60)
        let secondPass = firstPass.addingTimeInterval(3600)
        #expect(context.local(from: firstPass) == context.local(from: secondPass))
        let database = SampleScenarios.secondary().database
        let a = WidgetSnapshotBuildCache.Key(database: database, now: firstPass, context: context, tier: .pro,
                                             locale: locale, languageCode: "en")
        let b = WidgetSnapshotBuildCache.Key(database: database, now: secondPass, context: context, tier: .pro,
                                             locale: locale, languageCode: "en")
        #expect(a != b)
    }
}

// MARK: - C3: timeline planner, each instant resolved once

/// The Phase 4 planner, verbatim (before Phase 10 WP2), as the reference.
private enum LegacyPlanner {
    static func plan(snapshot: WidgetSnapshot, now: Date, deviceTimeZone: TimeZone, includeCancelledBoundaries: Bool,
                     includeTaskDueBoundaries: Bool) -> NowNextTimelinePlan {
        let context = WidgetTimelinePlanner.context(for: snapshot, deviceTimeZone: deviceTimeZone)
        let first = entry(snapshot: snapshot, at: now, context: context)
        if case .unavailable = first.state {
            return NowNextTimelinePlan(entries: [first], reloadDate: now.addingTimeInterval(WidgetTimelinePlanner.unavailableRetry),
                                       context: context)
        }
        var boundaries: Set<Date> = []
        var midnights: Set<Date> = []
        for day in snapshot.days {
            midnights.insert(context.startOfDay(day.date.adding(days: 1)))
            for lesson in day.lessons where lesson.takesPlace || includeCancelledBoundaries {
                boundaries.insert(lesson.start(in: context))
                boundaries.insert(lesson.end(in: context))
            }
        }
        if includeTaskDueBoundaries, let last = snapshot.lastDay {
            for task in snapshot.tasks {
                guard let time = task.dueTime, task.dueDate >= context.localDate(of: now), task.dueDate <= last else { continue }
                boundaries.insert(context.date(task.dueDate, time).addingTimeInterval(60))
            }
        }
        boundaries.formUnion(midnights)
        let future = boundaries.filter { $0 > now }.sorted()
        var kept = Array(future.prefix(WidgetTimelinePlanner.maxEntries - 1))
        let isCut = kept.count < future.count
        if isCut, let lastMidnight = kept.lastIndex(where: { midnights.contains($0) }) {
            kept = Array(kept[...lastMidnight])
        }
        var entries = [first]
        for date in kept {
            entries.append(entry(snapshot: snapshot, at: date, context: context))
        }
        let coverageEnd = snapshot.lastDay.map { context.startOfDay($0.adding(days: 1)) } ?? now
        let natural = isCut ? (kept.last ?? now) : max(coverageEnd, now)
        let reload = min(natural, now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval))
        return NowNextTimelinePlan(entries: entries, reloadDate: reload, context: context)
    }

    static func entry(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> NowNextTimelineEntry {
        let state = state(snapshot: snapshot, at: instant, context: context)
        var later: [WidgetSnapshot.Lesson] = []
        if let next = state.next, let day = snapshot.day(next.date) {
            let nextStart = next.start(in: context)
            later = active(day, context).filter { candidate in
                candidate.id != next.id && candidate.start(in: context) >= nextStart && candidate.start(in: context) > instant
            }
            .prefix(WidgetTimelinePlanner.maxLaterLessons).map { $0 }
        }
        return NowNextTimelineEntry(date: instant, state: state, laterLessons: later)
    }

    static func state(snapshot: WidgetSnapshot, at instant: Date, context: CalendarContext) -> NowNextState {
        guard snapshot.hasTimetable else { return .unavailable(.noTimetable) }
        let today = context.localDate(of: instant)
        guard let day = snapshot.day(today) else { return .unavailable(.outdated) }
        let lessons = active(day, context)
        let running = lessons.filter { $0.start(in: context) <= instant && instant < $0.end(in: context) }
        let current = running.max { lhs, rhs in
            let (ls, rs) = (lhs.start(in: context), rhs.start(in: context))
            if ls != rs { return ls < rs }
            let (le, re) = (lhs.end(in: context), rhs.end(in: context))
            if le != re { return le > re }
            return lhs.id > rhs.id
        }
        let next = nextLesson(after: instant, from: today, snapshot: snapshot, context: context)
        if let current { return .current(current, next: next) }
        if lessons.isEmpty {
            switch day.kind {
            case .holiday: return .holiday(name: day.note, next: next)
            case .cancelled: return .dayCancelled(note: day.note, next: next)
            case .school, .free: return .free(next: next)
            }
        }
        let lastEnd = lessons.map { $0.end(in: context) }.max() ?? instant
        if instant >= lastEnd { return .dayOver(next: next) }
        guard let next, next.date == today else { return .dayOver(next: next) }
        return .upcoming(next, isFirstOfDay: instant < lessons[0].start(in: context))
    }

    static func active(_ day: WidgetSnapshot.Day, _ context: CalendarContext) -> [WidgetSnapshot.Lesson] {
        day.lessons.filter(\.takesPlace).sorted { lhs, rhs in
            let (ls, rs) = (lhs.start(in: context), rhs.start(in: context))
            if ls != rs { return ls < rs }
            let (le, re) = (lhs.end(in: context), rhs.end(in: context))
            if le != re { return le < re }
            return lhs.id < rhs.id
        }
    }

    static func nextLesson(after instant: Date, from today: LocalDate, snapshot: WidgetSnapshot,
                           context: CalendarContext) -> WidgetSnapshot.Lesson? {
        for day in snapshot.days where day.date >= today {
            if let lesson = active(day, context).first(where: { $0.start(in: context) > instant }) { return lesson }
        }
        if let following = snapshot.followingLesson, following.start(in: context) > instant { return following }
        return nil
    }
}

private let math = SubjectSummary(id: Subject.ID(UUID()), name: "Mathematics", shortName: "MAT",
                                  color: ColorValue(red: 30, green: 90, blue: 200))

private func lesson(_ name: String, _ day: LocalDate, _ start: LocalTime, _ end: LocalTime,
                    status: ResolvedLesson.Status = .scheduled) -> WidgetSnapshot.Lesson {
    WidgetSnapshot.Lesson(id: "lesson:\(name):\(day.isoString)", subject: math, date: day, startTime: start, endTime: end,
                          room: "214", status: status)
}

/// `days` school days from `first`, `perDay` lessons each (45 min, 5-min breaks from 07:00), plus awkward cases on the
/// first day: two lessons with the same start, one ending before it starts (end clamps to start), a cancelled one.
private func denseSnapshot(from first: LocalDate, days: Int, perDay: Int) -> WidgetSnapshot {
    var built: [WidgetSnapshot.Day] = []
    for offset in 0..<days {
        let day = first.adding(days: offset)
        var lessons = (0..<perDay).map { slot in
            lesson("L\(slot)", day, LocalTime(minuteOfDay: 420 + slot * 50)!, LocalTime(minuteOfDay: 465 + slot * 50)!)
        }
        if offset == 0 {
            lessons.append(lesson("Same", day, time(7), time(7, 30)))
            lessons.append(lesson("Backwards", day, time(9), time(8, 30)))
            lessons.append(lesson("Gone", day, time(8), time(9), status: .cancelled))
        }
        built.append(WidgetSnapshot.Day(date: day, kind: .school, lessons: lessons.reversed()))
    }
    let following = lesson("After", first.adding(days: days + 2), time(8), time(8, 45))
    return WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 0), timeZoneID: "Europe/Bratislava",
                          followsDeviceTimeZone: true, localeID: "en_GB", languageCode: "en", hourCycle: .h24, tier: .pro,
                          hasTimetable: true, days: built, followingLesson: following, tasks: [], overdueTaskCount: 0,
                          nextExam: nil)
}

@Suite("Phase 10 WP2 — timeline planner: same entries, one resolve per instant")
struct WidgetPipelinePlannerTests {
    @Test func plansEqualThePhase4PlannerOnTheSeeds() throws {
        let bratislava = SampleScenarios.timeZone
        for database in seededDatabases {
            for built in probeInstants {
                let snapshot = WidgetSnapshotBuilder.make(database: database, now: built, context: context, tier: .pro,
                                                          locale: locale, languageCode: "en")
                for offset in stride(from: 0.0, through: 30 * 3600, by: 167 * 60) {
                    let at = built.addingTimeInterval(offset)
                    for zone in [bratislava, newYork] {
                        for (cancelled, due) in [(false, false), (true, true)] {
                            let new = WidgetTimelinePlanner.plan(snapshot: snapshot, now: at, deviceTimeZone: zone,
                                                                 includeCancelledBoundaries: cancelled,
                                                                 includeTaskDueBoundaries: due)
                            let old = LegacyPlanner.plan(snapshot: snapshot, now: at, deviceTimeZone: zone,
                                                         includeCancelledBoundaries: cancelled, includeTaskDueBoundaries: due)
                            #expect(new == old)
                        }
                    }
                }
            }
        }
    }

    @Test func statesEntriesAndActiveEqualThePhase4PlannerOnAwkwardDays() {
        let snapshot = denseSnapshot(from: Fixture.today, days: 8, perDay: 10)
        for day in snapshot.days {
            #expect(WidgetTimelinePlanner.active(day, context) == LegacyPlanner.active(day, context))
        }
        var probe = instant(Fixture.today, 0)
        let end = instant(Fixture.today.adding(days: 11), 0)
        while probe < end {
            #expect(WidgetTimelinePlanner.state(snapshot: snapshot, at: probe, context: context)
                    == LegacyPlanner.state(snapshot: snapshot, at: probe, context: context))
            #expect(WidgetTimelinePlanner.entry(snapshot: snapshot, at: probe, context: context)
                    == LegacyPlanner.entry(snapshot: snapshot, at: probe, context: context))
            probe = probe.addingTimeInterval(13 * 60)
        }
    }

    /// Generous bound (debug build, slow CI runner): 8 days × 10 lessons, 29 entries.
    @Test func eightDaysOfTenLessonsPlanQuickly() {
        let snapshot = denseSnapshot(from: Fixture.today, days: 8, perDay: 10)
        let at = instant(Fixture.today, 6)
        var plan: NowNextTimelinePlan?
        let elapsed = ContinuousClock().measure {
            plan = WidgetTimelinePlanner.plan(snapshot: snapshot, now: at, deviceTimeZone: SampleScenarios.timeZone,
                                              includeCancelledBoundaries: true, includeTaskDueBoundaries: true)
        }
        #expect(elapsed < .seconds(1), "\(elapsed)")
        #expect((plan?.entries.count ?? 0) > 1 && (plan?.entries.count ?? 0) <= WidgetTimelinePlanner.maxEntries)
        #expect(plan == LegacyPlanner.plan(snapshot: snapshot, now: at, deviceTimeZone: SampleScenarios.timeZone,
                                           includeCancelledBoundaries: true, includeTaskDueBoundaries: true))
        print("WP2 evidence: 8 × 10 lessons planned in \(elapsed)")
    }

    /// Lesson details are joined with the snapshot language's inline separator (RISKS #69), not a hard-coded " · ".
    @Test func detailSeparatorFollowsTheSnapshotLanguage() {
        #expect(NowNextPresenter.separator(inFormat: "%1$@ · %2$@") == " · ")
        #expect(NowNextPresenter.separator(inFormat: "%1$@・%2$@") == "・")
        #expect(NowNextPresenter.separator(inFormat: "widget.nowNext.inline.current %@ %@") == " · ")   // missing key
        #expect(NowNextPresenter.separator(inFormat: "%2$@ %1$@") == " · ")
        let snapshot = denseSnapshot(from: Fixture.today, days: 2, perDay: 3)
        let entry = WidgetTimelinePlanner.entry(snapshot: snapshot, at: instant(Fixture.today, 7, 20), context: context)
        func display(_ lookup: @escaping LocalizedTextRenderer.Lookup) -> NowNextDisplay {
            let renderer = NowNextPresenter.renderer(for: snapshot, context: context, lookup: lookup)
            return NowNextPresenter(renderer: renderer, context: context).display(entry)
        }
        let japanese = display { key in key == "widget.nowNext.inline.current %@ %@" ? "%1$@・%2$@" : key }
        #expect(japanese.detailSeparator == "・")
        #expect(display { $0 }.detailSeparator == " · ")
    }

    /// The Live Activity lesson days use the planner's resolved instants: same values as `start(in:)` / `end(in:)`.
    @Test func liveActivityLessonDaysAreUnchanged() {
        for database in seededDatabases {
            let sources = LiveActivitySourceBuilder.make(database: database, now: now, context: context, locale: locale,
                                                         languageCode: "en")
            let snapshot = WidgetSnapshotBuilder.make(database: database, now: now, context: context, tier: .pro,
                                                      locale: locale, languageCode: "en")
            var expected: [LiveActivityLessonDay] = []
            if snapshot.hasTimetable {
                for day in snapshot.days {
                    let lessons = LegacyPlanner.active(day, context).prefix(LiveActivityLimits.maxLessons).map { lesson in
                        LiveActivityLesson(subject: LiveActivitySubject(lesson.subject),
                                           room: LiveActivityLimits.cut(lesson.room, LiveActivityLimits.maxRoomLength),
                                           start: lesson.start(in: context), end: lesson.end(in: context))
                    }
                    if !lessons.isEmpty { expected.append(LiveActivityLessonDay(day: day.date, lessons: Array(lessons))) }
                }
            }
            #expect(sources.lessonDays == expected)
            // The overload the app uses with the shared build gives the same sources.
            #expect(LiveActivitySourceBuilder.make(snapshot: snapshot, database: database, now: now, context: context,
                                                   locale: locale, languageCode: "en") == sources)
        }
    }
}
