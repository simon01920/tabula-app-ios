import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let now = Date(timeIntervalSince1970: 1_791_879_600)

private func freshClock(_ database: TabulaDatabase) -> HybridLogicalClock {
    var clock = HybridLogicalClock(node: 0xA11)
    clock.receive(database.latestTimestamp, now: now)
    return clock
}

@Suite("DatabaseMutation")
struct DatabaseMutationTests {
    @Test func upsertEditsAreStampedFieldByField() throws {
        let database = SampleScenarios.secondary().database
        var clock = freshClock(database)
        var subject = database.subjects[0]
        subject.defaultRoom = "301"
        let edited = try DatabaseMutation.upsert(subject).apply(to: database, clock: &clock, now: now)
        let stored = try #require(edited.subjects.first { $0.id == subject.id })
        #expect(stored.defaultRoom == "301")
        #expect(stored.meta.updatedAt == clock.last)
        #expect(stored.meta.fieldClocks.keys.sorted() == ["defaultRoom"])
        #expect(stored.meta.updatedAt > database.latestTimestamp)
        #expect(edited.subjects.count == database.subjects.count)
    }

    @Test func upsertCreatesNewEntities() throws {
        let database = SampleScenarios.blank()
        var clock = freshClock(database)
        let timetable = database.timetables[0]
        let subject = Subject(id: Subject.ID(UUID()), meta: .untouchedSingleton, timetableID: timetable.id,
                              name: "Fyzika", color: PalettePack.classic.colors[0].value)
        let edited = try DatabaseMutation.upsert(subject).apply(to: database, clock: &clock, now: now)
        let created = try #require(edited.subjects.first)
        #expect(created.meta.createdAt == created.meta.updatedAt)
        #expect(created.meta.createdAt == clock.last)
    }

    @Test func deleteTombstonesAndUnknownIDFailsWithoutSideEffects() throws {
        let database = SampleScenarios.secondary().database
        var clock = freshClock(database)
        let lesson = database.lessons[0]
        let edited = try DatabaseMutation.delete(lesson.id).apply(to: database, clock: &clock, now: now)
        #expect(edited.lessons.first { $0.id == lesson.id }?.isDeleted == true)
        #expect(edited.lessons.count == database.lessons.count)   // tombstone kept for sync

        let before = clock
        let missing = Lesson.ID(UUID())
        #expect(throws: MutationError.notFound(.lesson, missing.uuid)) {
            _ = try DatabaseMutation.delete(missing).apply(to: database, clock: &clock, now: now)
        }
        #expect(clock == before)
    }

    @Test func settingsAndBatch() throws {
        let database = SampleScenarios.secondary().database
        var clock = freshClock(database)
        var subject = database.subjects[1]
        subject.name = "Matematika (rozšírená)"
        let mutation = DatabaseMutation.batch([.settings { $0.appearance = .dark }, .upsert(subject)], label: "test")
        let edited = try mutation.apply(to: database, clock: &clock, now: now)
        #expect(edited.settings.appearance == .dark)
        #expect(edited.settings.meta.fieldClocks["appearance"] != nil)
        #expect(edited.subjects.first { $0.id == subject.id }?.name == "Matematika (rozšírená)")
        #expect(mutation.label == "test" && !mutation.replacesDatabase)
    }

    @Test func failingBatchIsAllOrNothing() {
        let database = SampleScenarios.secondary().database
        var clock = freshClock(database)
        let before = clock
        let mutation = DatabaseMutation.batch([.settings { $0.appearance = .dark }, .delete(Lesson.ID(UUID()))])
        #expect(throws: MutationError.self) { _ = try mutation.apply(to: database, clock: &clock, now: now) }
        #expect(clock == before)
    }

    @Test func replaceDatabaseKeepsTheClockAheadOfTheNewData() throws {
        var clock = HybridLogicalClock(node: 7)
        let sample = SampleScenarios.secondary().database
        let mutation = DatabaseMutation.replaceDatabase(label: "sample") { _, _, _ in sample }
        let replaced = try mutation.apply(to: DatabaseMutation.emptyBase, clock: &clock, now: Date(timeIntervalSince1970: 0))
        #expect(replaced == sample)
        #expect(clock.last > sample.latestTimestamp)
        #expect(mutation.replacesDatabase)
    }
}

@Suite("MutationValidation")
struct MutationValidationTests {
    private func issue(_ severity: ValidationIssue.Severity, _ code: ValidationIssue.Code, _ id: UUID) -> ValidationIssue {
        ValidationIssue(severity: severity, code: code, entityType: .lesson, entityID: id)
    }

    @Test func newErrorsBlockExistingOnesDoNot() {
        let a = UUID(), b = UUID()
        let old = issue(.error, .danglingReference, a)
        #expect(MutationValidation.verdict(before: [old], after: [old]) == .accepted(newWarnings: []))
        let new = issue(.error, .invalidTimeRange, b)
        #expect(MutationValidation.verdict(before: [old], after: [old, new]) == .rejected(newErrors: [new]))
    }

    @Test func newWarningsAreSurfacedInfosIgnored() {
        let warning = issue(.warning, .overlappingPeriods, UUID())
        let info = issue(.info, .emptyScheduleDay, UUID())
        #expect(MutationValidation.verdict(before: [], after: [info, warning]) == .accepted(newWarnings: [warning]))
    }

    @Test func realInvalidEditIsRejected() throws {
        let database = SampleScenarios.secondary().database
        var clock = freshClock(database)
        var lesson = database.lessons[0]
        lesson.subjectID = Subject.ID(UUID())   // dangling reference
        let edited = try DatabaseMutation.upsert(lesson).apply(to: database, clock: &clock, now: now)
        guard case .rejected(let errors) = MutationValidation.verdict(before: database.validate(), after: edited.validate()) else {
            Issue.record("expected rejection")
            return
        }
        #expect(errors.contains { $0.code == .danglingReference })
    }
}

@Suite("PersistenceController")
struct PersistenceControllerTests {
    @Test func loadEmptyAndLoaded() async {
        #expect(await PersistenceController(repository: InMemoryRepository()).load() == .empty)
        let database = SampleScenarios.blank()
        let outcome = await PersistenceController(repository: InMemoryRepository(database)).load()
        #expect(outcome == .loaded(database.canonicalized(), banners: [], isReadOnly: false))
    }

    @Test func savesInOrderAndSkipsStaleGenerations() async throws {
        let repository = InMemoryRepository()
        let controller = PersistenceController(repository: repository)
        let first = SampleScenarios.blank()
        let second = SampleScenarios.secondary().database
        #expect(await controller.save(second, generation: 2) == .saved(generation: 2))
        #expect(await controller.save(first, generation: 1) == .skippedStale(generation: 1, lastSaved: 2))
        #expect(try await repository.load() == second.canonicalized())
        #expect(await controller.writeCount == 1)
    }

    @Test func concurrentSavesNeverRegress() async throws {
        let repository = InMemoryRepository()
        let controller = PersistenceController(repository: repository)
        let databases = (0..<20).map { index -> TabulaDatabase in
            var database = SampleScenarios.blank()
            database.timetables[0].name = "T\(index)"
            return database
        }
        await withTaskGroup(of: Void.self) { group in
            for (index, database) in databases.enumerated() {
                group.addTask { _ = await controller.save(database, generation: index) }
            }
        }
        // Whatever the arrival order, the stored data is the highest generation that was requested last.
        let stored = try await repository.load()
        let last = await controller.lastSavedGeneration
        #expect(last == 19)
        #expect(stored.timetables[0].name == "T\(last)")
    }

    @Test func newerFileIsReadOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tabula-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileRepository = FileRepository(directory: directory)
        var database = SampleScenarios.blank()
        try await fileRepository.save(database)
        // Rewrite the file as if a newer app version had saved it.
        database.schemaVersion = 99
        try database.encoded().write(to: fileRepository.databaseURL)

        let controller = PersistenceController(repository: FileRepository(directory: directory))
        guard case .loaded(_, let banners, let isReadOnly) = await controller.load() else {
            Issue.record("expected a read-only load")
            return
        }
        #expect(isReadOnly)
        #expect(banners == [.readOnly(fileSchemaVersion: 99)])
        #expect(await controller.save(SampleScenarios.blank(), generation: 1) == .readOnly)
    }
}

@Suite("StoreStatus")
struct StoreStatusTests {
    @Test func reportEventsBecomeBanners() {
        let database = SampleScenarios.blank()
        let report = LoadReport(source: .backup, fileSchemaVersion: 1, events: [
            .restoredFromBackup(primaryProblem: .empty), .quarantinedCorruptFile(fileName: "tabula.corrupt.json"),
            .discardedIncompleteWrite(fileName: ".tabula.json.tmp"),
        ])
        #expect(StoreLoadOutcome.loaded(database, report: report) == .loaded(database, banners: [.restoredFromBackup],
                                                                           isReadOnly: false))
        let interrupted = LoadReport(source: .primary, fileSchemaVersion: 1,
                                     events: [.discardedIncompleteWrite(fileName: ".tabula.json.tmp")])
        #expect(StoreLoadOutcome.loaded(database, report: interrupted)
                == .loaded(database, banners: [.discardedIncompleteWrite], isReadOnly: false))
    }

    @Test func errorsMapToProblemsNeverToOnboardingExceptNotFound() {
        #expect(StoreLoadOutcome.failed(RepositoryError.notFound) == .empty)
        #expect(StoreLoadOutcome.failed(RepositoryError.unrecoverable(primary: .empty, backup: .missing)) == .failed(.unrecoverable))
        #expect(StoreLoadOutcome.failed(RepositoryError.newerSchemaUnreadable(fileSchemaVersion: 3, detail: ""))
                == .failed(.newerVersion(fileSchemaVersion: 3)))
        if case .failed(.other) = StoreLoadOutcome.failed(CocoaError(.fileReadNoPermission)) {} else {
            Issue.record("expected .other")
        }
    }

    @Test func bannerKeysAndDismissal() {
        #expect(StoreBanner.readOnly(fileSchemaVersion: 2).isDismissible == false)
        #expect(StoreBanner.saveFailed.isDismissible)
        #expect(StoreBanner.restoredFromBackup.titleKey == "store.banner.restored.title")
    }
}

@Suite("Shell state")
struct ShellStateTests {
    @Test func phases() {
        let blank = SampleScenarios.blank()
        #expect(ShellPhase.derive(isLoading: true, problem: nil, database: nil) == .loading)
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: nil) == .onboarding)
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: blank) == .main)
        var unfinished = blank
        unfinished.settings.onboardingCompletedAt = nil
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: unfinished) == .onboarding)
        #expect(ShellPhase.derive(isLoading: false, problem: .unrecoverable, database: nil) == .blocked(.unrecoverable))
    }

    @Test func activeTimetableFallsBackToFirstLive() {
        var database = SampleScenarios.blank()
        let first = database.timetables[0]
        #expect(ActiveTimetable.resolve(database)?.id == first.id)
        database.settings.activeTimetableID = Timetable.ID(UUID())
        #expect(ActiveTimetable.resolve(database)?.id == first.id)
        database.timetables[0].meta.isDeleted = true
        #expect(ActiveTimetable.resolve(database) == nil)
    }

    @Test func calendarEnvironment() {
        #expect(CalendarEnvironment.firstWeekday(of: Locale(identifier: "en_US")) == .sunday)
        #expect(CalendarEnvironment.firstWeekday(of: Locale(identifier: "sk_SK")) == .monday)
        var settings = AppSettings.untouchedDefaults
        let zone = SampleScenarios.timeZone
        #expect(CalendarEnvironment.context(settings: settings, deviceTimeZone: zone, locale: Locale(identifier: "en_US"))
                == CalendarContext(timeZone: zone, firstWeekday: .sunday))
        settings.weekStartOverride = .saturday
        #expect(CalendarEnvironment.context(settings: settings, deviceTimeZone: zone, locale: Locale(identifier: "en_US"))
                .firstWeekday == .saturday)
    }

    @Test func clockResumesPastStoredAndDatabase() {
        var generator = SystemRandomNumberGenerator()
        let database = SampleScenarios.secondary().database
        let resumed = ClockBootstrap.resume(stored: nil, database: database, now: Date(timeIntervalSince1970: 0),
                                            generator: &generator)
        #expect(resumed.node != 0)
        #expect(resumed.last > database.latestTimestamp)
        let stored = HybridLogicalClock(node: 42, last: HLCTimestamp(physicalMillis: 9_999_999_999_999, logical: 0, node: 42))
        let kept = ClockBootstrap.resume(stored: stored, database: database, now: now, generator: &generator)
        #expect(kept == stored)   // already ahead: unchanged
        let store = InMemoryClockStore()
        store.save(kept)
        #expect(store.load() == kept)
    }
}
