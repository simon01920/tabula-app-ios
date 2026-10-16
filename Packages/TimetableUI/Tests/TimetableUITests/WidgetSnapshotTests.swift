import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let zone = SampleScenarios.timeZone
private let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func instant(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> Date { context.date(day, time(h, m)) }
private let today = SampleScenarios.today   // Tue 2026-10-13

private func build(_ database: TabulaDatabase?, at now: Date = SampleScenarios.referenceNow,
                   tier: Tier = .pro) -> WidgetSnapshot {
    WidgetSnapshotBuilder.make(database: database, now: now, context: context, tier: tier,
                               locale: Locale(identifier: "sk_SK"), languageCode: "sk")
}

@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
    @Test func secondaryOnATuesdayCoversTodayTomorrowAndTheNextSchoolDay() throws {
        let scenario = SampleScenarios.secondary()
        let snapshot = build(scenario.database)
        #expect(snapshot.version == WidgetSnapshot.currentVersion)
        #expect(snapshot.hasTimetable && snapshot.tier == .pro)
        #expect(snapshot.localeID == "sk_SK" && snapshot.languageCode == "sk")
        #expect(snapshot.timeZoneID == "Europe/Bratislava" && snapshot.followsDeviceTimeZone)
        #expect(snapshot.days.map(\.date) == [today, date(2026, 10, 14), date(2026, 10, 15)])
        #expect(snapshot.days.allSatisfy { $0.kind == .school && !$0.lessons.isEmpty })

        // Same lessons, times and statuses as the engine.
        let resolver = try #require(ScheduleResolver(database: scenario.database,
                                                     timetableID: ActiveTimetable.resolve(scenario.database)!.id,
                                                     context: context))
        for day in snapshot.days {
            let entries = resolver.day(day.date).entries
            #expect(day.lessons.map(\.id) == entries.map(\.id.rawValue))
            #expect(day.lessons.map(\.status) == entries.map(\.status))
            #expect(day.lessons.map(\.startTime) == entries.map(\.startTime))
            for (lesson, entry) in zip(day.lessons, entries) {
                #expect(lesson.start(in: context) == entry.start && lesson.end(in: context) == entry.end)
                #expect(lesson.subject == entry.subject)
            }
        }
        // The first lesson after the covered range: Friday's first lesson.
        let following = try #require(snapshot.followingLesson)
        #expect(following.date == date(2026, 10, 16))
        #expect(following.id == resolver.day(date(2026, 10, 16)).entries.first { $0.status != .cancelled }?.id.rawValue)
    }

    @Test func roomsFollowTheFieldRuleAndChangesAreFlagged() throws {
        let scenario = SampleScenarios.secondary()
        let snapshot = build(scenario.database)
        let timetable = try #require(ActiveTimetable.resolve(scenario.database))
        let resolver = try #require(ScheduleResolver(database: scenario.database, timetableID: timetable.id, context: context))
        for day in snapshot.days {
            let resolution = resolver.resolution(for: day.date)
            for (lesson, entry) in zip(day.lessons, resolution.schedule.entries) {
                #expect(lesson.room == VisibleLessonFields(lesson: entry, visibility: timetable.fieldVisibility).room)
                let reasons = resolution.reasons(for: entry.id)
                #expect(lesson.reasons == (reasons.isEmpty ? nil : reasons))
            }
        }
        // With rooms hidden, no room reaches the widget.
        var hidden = scenario.database
        let index = try #require(hidden.timetables.firstIndex { $0.id == timetable.id })
        hidden.timetables[index].fieldVisibility = FieldVisibility([])
        #expect(build(hidden).days.flatMap(\.lessons).allSatisfy { $0.room == nil })
        #expect(snapshot.days.flatMap(\.lessons).contains { $0.room != nil })
    }

    @Test func fridayCoversTheWeekendUntilMonday() {
        let snapshot = build(SampleScenarios.secondary().database, at: instant(date(2026, 10, 16), 12))
        #expect(snapshot.days.map(\.date) == [date(2026, 10, 16), date(2026, 10, 17), date(2026, 10, 18), date(2026, 10, 19)])
        #expect(snapshot.days.map(\.kind) == [.school, .free, .free, .school])
        #expect(snapshot.days[1].lessons.isEmpty && snapshot.days[2].lessons.isEmpty)
    }

    @Test func holidaysAreNamedAndTheNextLessonFollowsTheBreak() throws {
        let snapshot = build(SampleScenarios.secondary().database, at: instant(date(2026, 10, 29), 9))
        let first = try #require(snapshot.days.first)
        #expect(first.kind == .holiday && first.note == "Jesenné prázdniny" && first.lessons.isEmpty)
        #expect(snapshot.lastDay == date(2026, 11, 2))
        #expect(snapshot.days.last?.kind == .school)
    }

    @Test func cancelledDayCarriesItsNote() {
        var database = SampleScenarios.elementary()
        database.overrides.append(ScheduleOverride(id: ScheduleOverride.ID(UUID()), meta: .created(at: .zero),
                                                   timetableID: database.timetables[0].id, date: date(2026, 10, 14),
                                                   change: .cancelDay(note: "  Výlet  ")))
        let snapshot = build(database)
        let wednesday = snapshot.day(date(2026, 10, 14))
        #expect(wednesday?.kind == .cancelled && wednesday?.note == "Výlet")
        #expect(wednesday?.lessons.allSatisfy { $0.status == .cancelled } == true)
    }

    @Test func tasksAndExamMatchTheTasksAndExamsTabs() throws {
        let database = SampleScenarios.secondary().database
        let snapshot = build(database)
        let nowLocal = context.local(from: SampleScenarios.referenceNow)
        let live = database.tasks.filter { !$0.isDeleted }
        #expect(snapshot.overdueTaskCount == TaskListModel.counts(of: live, now: nowLocal).overdue)
        let horizon = today.adding(days: WidgetSnapshotBuilder.taskHorizonDays)
        let expected = (TaskListModel.tasks(in: .today, from: live, now: nowLocal)
            + TaskListModel.tasks(in: .upcoming, from: live, now: nowLocal))
            .filter { ($0.due?.date).map { $0 <= horizon } == true }
        #expect(snapshot.tasks.map(\.id) == Array(expected.prefix(WidgetSnapshotBuilder.maxTasks)).map(\.id.uuid))
        #expect(!snapshot.tasks.isEmpty)
        #expect(snapshot.tasks.allSatisfy { $0.dueDate >= today && $0.dueDate <= horizon })
        let next = ExamListModel.make(database: database, today: today, context: context).next
        #expect(snapshot.nextExam?.id == next?.exam.id.uuid)
        #expect(snapshot.nextExam?.date == next?.exam.date)
    }

    @Test func noDatabaseMeansNoTimetable() {
        let snapshot = build(nil)
        #expect(!snapshot.hasTimetable && snapshot.days.isEmpty && snapshot.tasks.isEmpty && snapshot.nextExam == nil)
        let blank = build(SampleScenarios.blank())
        #expect(blank.hasTimetable)   // onboarding finished, nothing entered: a timetable without lessons
        #expect(blank.days.flatMap(\.lessons).isEmpty && blank.followingLesson == nil)
        #expect(blank.days.map(\.date) == [today, date(2026, 10, 14), date(2026, 10, 15)])   // school days, no lessons
    }

    @Test func fixedZoneTimetablesAreMarked() {
        var database = SampleScenarios.secondary().database
        database.settings.timeZoneMode = .fixed(identifier: "Europe/Bratislava")
        let snapshot = build(database)
        #expect(!snapshot.followsDeviceTimeZone)
        #expect(snapshot.effectiveTimeZone(device: TimeZone(identifier: "America/New_York")!).identifier == "Europe/Bratislava")
        #expect(build(SampleScenarios.secondary().database)
            .effectiveTimeZone(device: TimeZone(identifier: "America/New_York")!).identifier == "America/New_York")
    }

    @Test func longUserTextIsShortened() {
        var database = SampleScenarios.secondary().database
        database.subjects[0].name = String(repeating: "Ř", count: 300)
        let snapshot = build(database)
        let names = snapshot.days.flatMap(\.lessons).map(\.subject.name)
        #expect(names.allSatisfy { $0.count <= WidgetSnapshotBuilder.maxTextLength })
        #expect(names.contains(String(repeating: "Ř", count: WidgetSnapshotBuilder.maxTextLength)))
    }
}

@Suite("Widget snapshot coding and store")
struct WidgetSnapshotStoreTests {
    /// The Watch reuses the snapshot over WatchConnectivity (ARCHITECTURE.md: < 20 KB).
    @Test(arguments: [SeedKind.secondary, .university, .elementary])
    func encodedSnapshotStaysSmall(_ seed: SeedKind) throws {
        let database = try #require(SampleScenarios.make(seed).database)
        for day in [today, date(2026, 10, 16), date(2026, 10, 29)] {
            let data = try WidgetSnapshotStore.encode(build(database, at: instant(day, 10, 20)))
            #expect(data.count < 20_000, "\(seed) snapshot on \(day.isoString): \(data.count) bytes")
        }
        let reference = try WidgetSnapshotStore.encode(build(database))
        print("widget snapshot size \(seed): \(reference.count) bytes")
    }

    @Test func roundTripsAndIsDeterministic() throws {
        let snapshot = build(SampleScenarios.university())
        let data = try WidgetSnapshotStore.encode(snapshot)
        #expect(WidgetSnapshotStore.decode(data) == snapshot)
        #expect(try WidgetSnapshotStore.encode(snapshot) == data)
        #expect(snapshot.contentOnly == build(SampleScenarios.university(), at: SampleScenarios.referenceNow.addingTimeInterval(1)).contentOnly)
    }

    @Test func rejectsNewerVersionsGarbageAndOversizedFiles() throws {
        var snapshot = build(SampleScenarios.secondary().database)
        snapshot.version = WidgetSnapshot.currentVersion + 1
        #expect(WidgetSnapshotStore.decode(try WidgetSnapshotStore.encode(snapshot)) == nil)
        snapshot.version = 0
        #expect(WidgetSnapshotStore.decode(try WidgetSnapshotStore.encode(snapshot)) == nil)
        #expect(WidgetSnapshotStore.decode(Data("{\"v\":1}".utf8)) == nil)
        #expect(WidgetSnapshotStore.decode(Data("not json".utf8)) == nil)
        #expect(WidgetSnapshotStore.decode(Data(count: WidgetSnapshotStore.maxFileBytes + 1)) == nil)
    }

    @Test func writesAtomicallyIntoTheContainerAndReadsBack() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("widget-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container) }
        #expect(WidgetSnapshotStore.read(container: container) == nil)   // nothing written yet
        let snapshot = build(SampleScenarios.secondary().database)
        try WidgetSnapshotStore.write(try WidgetSnapshotStore.encode(snapshot), container: container)
        #expect(WidgetSnapshotStore.fileURL(container: container).path.hasSuffix("Widgets/widget-snapshot.json"))
        #expect(WidgetSnapshotStore.read(container: container) == snapshot)
        try Data("garbage".utf8).write(to: WidgetSnapshotStore.fileURL(container: container))
        #expect(WidgetSnapshotStore.read(container: container) == nil)
    }
}

@Suite("Widget Pro gate")
struct WidgetProGateTests {
    @Test func smallAndMediumAreFreeLargeAndLockScreenArePro() {
        for family in [WidgetFamilyKind.systemSmall, .systemMedium] {
            #expect(WidgetProGate.decision(for: family, tier: .free) == .allowed)
            #expect(WidgetProGate.decision(for: family, tier: .pro) == .allowed)
        }
        for family in [WidgetFamilyKind.systemLarge, .systemExtraLarge] {
            #expect(WidgetProGate.decision(for: family, tier: .free) == .requiresPro(.largeWidgets))
            #expect(WidgetProGate.decision(for: family, tier: .pro) == .allowed)
        }
        for family in [WidgetFamilyKind.accessoryCircular, .accessoryRectangular, .accessoryInline] {
            #expect(WidgetProGate.decision(for: family, tier: .free) == .requiresPro(.lockScreenWidgets))
            #expect(WidgetProGate.decision(for: family, tier: .pro) == .allowed)
        }
    }

    @Test func followsThePolicyTableAndTheSnapshotTier() {
        let everythingFree = FeaturePolicy(proFeatures: [], limits: [:])
        #expect(WidgetFamilyKind.allCases.allSatisfy { WidgetProGate.decision(for: $0, tier: .free, policy: everythingFree) == .allowed })
        let free = build(SampleScenarios.secondary().database, tier: .free)
        #expect(WidgetProGate.decision(for: .accessoryInline, snapshot: free) == .requiresPro(.lockScreenWidgets))
        #expect(WidgetProGate.decision(for: .accessoryInline, snapshot: build(SampleScenarios.secondary().database)) == .allowed)
        // No snapshot: the "Open Tabula" view, never gated.
        #expect(WidgetProGate.decision(for: .accessoryInline, snapshot: nil) == .allowed)
        // The tier the app ships today is all-access.
        #expect(AllAccessEntitlements().tier == .pro)
    }
}

@Suite("Deep-link URLs")
struct ItemLinkURLTests {
    @Test func roundTripsEveryLinkKind() {
        let links: [ItemLink] = [
            .today, .lesson(OccurrenceID.lesson(Lesson.ID(UUID()), on: today)),
            .lesson(OccurrenceID.oneOff(ScheduleOverride.ID(UUID()))), .task(TaskItem.ID(UUID())),
            .exam(Exam.ID(UUID())), .packTonight(today),
        ]
        for link in links {
            let url = ItemLinkURL.url(for: link)
            #expect(url.scheme == "tabula" && url.host == "open")
            #expect(ItemLinkURL.link(from: url) == link, "\(url)")
        }
        #expect(ItemLinkURL.url(for: .today).absoluteString == "tabula://open/today")
    }

    @Test func rejectsMalformedOrForeignURLs() {
        let bad = [
            "https://open/today", "tabula://other/today", "tabula://open/", "tabula://open/today/x",
            "tabula://open/today?x=1", "tabula://open/today#f", "tabula://open/task/not-a-uuid",
            "tabula://open/lesson/lesson:\(UUID().uuidString):2026-13-01", "tabula://open/lesson/lesson:x:2026-10-13",
            "tabula://open/lesson/override", "tabula://open/pack/2026-10-1", "tabula://open/unknown/1",
            "tabula://open/lesson/" + String(repeating: "a", count: 300), "tabula://c/7KX2M9QH",
        ]
        for text in bad {
            guard let url = URL(string: text) else { continue }
            #expect(ItemLinkURL.link(from: url) == nil, "\(text)")
        }
    }
}
