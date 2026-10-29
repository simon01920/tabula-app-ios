import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let today = LocalDate(year: 2026, month: 10, day: 13)!
private let names = OnboardingNames(timetable: "School", bellSchedule: "Bells", term: "Semester")
private let reference = Date(timeIntervalSince1970: 1_791_879_600)

/// "Just look around" → "This is sample data · Remove" (UX_OVERHAUL_PLAN D8): Remove deletes only the sample
/// timetable with its children and the sample task / exam; user-created entities are never deleted.
@Suite("Sample content removal scope")
struct SampleContentTests {
    private struct Fixture {
        var database: TabulaDatabase
        var clock: HybridLogicalClock
        let record: SampleContentRecord
        let sampleID: Timetable.ID

        mutating func apply(_ mutation: DatabaseMutation) throws {
            database = try mutation.apply(to: database, clock: &clock, now: reference)
        }
    }

    /// Onboarding with "Just look around" on top of `existing` (nil = first launch), then the record.
    private func lookAround(on existing: TabulaDatabase?, profile: UserProfile = .secondary) throws -> Fixture {
        var draft = OnboardingDraft(today: today, profile: profile)
        draft.start = .sample
        draft.termEnabled = true
        let mutation = draft.finishMutation(existing: existing, names: names, localeFirstWeekday: .monday,
                                            localize: { $0.key }, now: reference)
        var clock = HybridLogicalClock(node: 0x5A)
        if let existing { clock.receive(existing.latestTimestamp, now: reference) }
        let database = try mutation.apply(to: existing ?? DatabaseMutation.emptyBase, clock: &clock, now: reference)
        let id = try #require(database.settings.activeTimetableID)
        return Fixture(database: database, clock: clock, record: SampleContent.record(for: id, in: database), sampleID: id)
    }

    @Test func recordCoversTheSampleTimetableAndItsContent() throws {
        let fixture = try lookAround(on: nil)
        let database = fixture.database
        #expect(fixture.record.timetableID == fixture.sampleID.uuid)
        #expect(fixture.record.taskIDs == Set(database.tasks.map(\.id.uuid)) && fixture.record.taskIDs.count == 1)
        #expect(fixture.record.examIDs == Set(database.exams.map(\.id.uuid)) && fixture.record.examIDs.count == 1)
        let children = Set(database.lessons.map(\.id.uuid) + database.subjects.map(\.id.uuid)
                           + database.bellSchedules.map(\.id.uuid) + database.terms.map(\.id.uuid))
        #expect(fixture.record.childIDs == children && !children.isEmpty)
        #expect(SampleContent.isActive(fixture.record, in: database))
        #expect(SampleContent.impact(of: fixture.record, in: database) == .init())
    }

    @Test func editsToSampleItemsAreCountedSoTheDialogNeverPromisesTheyStay() throws {
        var fixture = try lookAround(on: nil)
        #expect(SampleContent.impact(of: fixture.record, in: fixture.database).keepsAllUserWork)
        // The user renames a sample subject and edits the sample task.
        var subject = try #require(fixture.database.subjects.first { !$0.isDeleted })
        subject.name = "My Maths"
        var task = try #require(fixture.database.tasks.first { !$0.isDeleted })
        task.title = "Bring the compass"
        try fixture.apply(.batch([.upsert(subject), .upsert(task)], label: "user edits"))
        let impact = SampleContent.impact(of: fixture.record, in: fixture.database)
        #expect(impact.changedByUser == 2 && impact.addedByUser == 0)
        #expect(!impact.keepsAllUserWork)
        // A record from before the stamps existed counts no edits (it cannot tell them apart).
        var old = fixture.record
        old.stamps = nil
        #expect(SampleContent.impact(of: old, in: fixture.database).changedByUser == 0)
        // The stored record round-trips with its stamps.
        let store = InMemoryOnboardingLocalStore()
        let data = try JSONEncoder().encode(fixture.record)
        #expect(try JSONDecoder().decode(SampleContentRecord.self, from: data) == fixture.record)
        store.saveSample(fixture.record)
        #expect(store.loadSample() == fixture.record)
    }

    @Test func removalOnAFreshInstallDeletesEverythingSampleAndKeepsSettingsAndRules() throws {
        var fixture = try lookAround(on: nil)
        let rules = fixture.database.reminderRules
        let mutation = try #require(SampleContent.removalMutation(fixture.record, in: fixture.database))
        try fixture.apply(mutation)
        let database = fixture.database
        #expect(database.timetables.allSatisfy { $0.isDeleted })
        #expect(database.subjects.allSatisfy { $0.isDeleted } && database.lessons.allSatisfy { $0.isDeleted })
        #expect(database.bellSchedules.allSatisfy { $0.isDeleted } && database.terms.allSatisfy { $0.isDeleted })
        #expect(database.tasks.allSatisfy { $0.isDeleted } && database.exams.allSatisfy { $0.isDeleted })
        #expect(database.reminderRules == rules)                     // preferences are not sample content
        #expect(database.validate().filter { $0.severity == .error }.isEmpty)
        // The shell shows onboarding again; its finish then ADDS a timetable (OnboardingFinish).
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: database) == .onboarding)
        #expect(!SampleContent.isActive(fixture.record, in: database))
        let again = SampleContent.removalMutation(fixture.record, in: database)
        #expect(again == nil)
    }

    @Test func removalNeverTouchesUserCreatedEntities() throws {
        // The user's own data: a timetable with subjects, lessons, tasks and exams (the secondary scenario).
        let existing = SampleScenarios.secondary().database
        var fixture = try lookAround(on: existing, profile: .university)
        let sampleSubject = try #require(fixture.database.subjects.first { $0.timetableID == fixture.sampleID })
        let sampleLesson = try #require(fixture.database.lessons.first { $0.timetableID == fixture.sampleID })

        // While looking around the user adds: a task linked to a sample subject + lesson, an exam in the sample
        // timetable, an unrelated task, and a lesson inside the sample timetable.
        let linkedTask = TaskItem(id: TaskItem.ID(UUID()), meta: .created(at: fixture.clock.tick(now: reference)),
                                  title: "Mine, linked", kind: .homework, subjectID: sampleSubject.id,
                                  timetableID: fixture.sampleID, due: .date(today),
                                  linkedLesson: LessonLink(lessonID: sampleLesson.id, date: today))
        let linkedExam = Exam(id: Exam.ID(UUID()), meta: .created(at: fixture.clock.tick(now: reference)),
                              timetableID: fixture.sampleID, subjectID: sampleSubject.id, title: "My exam",
                              kind: .test, date: today.adding(days: 3))
        let freeTask = TaskItem(id: TaskItem.ID(UUID()), meta: .created(at: fixture.clock.tick(now: reference)),
                                title: "Mine, free", kind: .todo)
        var addedLesson = sampleLesson
        addedLesson.id = Lesson.ID(UUID())
        addedLesson.meta = .created(at: fixture.clock.tick(now: reference))
        try fixture.apply(.batch([.upsert(linkedTask), .upsert(linkedExam), .upsert(freeTask), .upsert(addedLesson)]))
        let before = fixture.database

        let impact = SampleContent.impact(of: fixture.record, in: before)
        #expect(impact.addedByUser == 1)       // the lesson added inside the sample timetable (named in the dialog)
        #expect(impact.unlinkedItems == 2)     // linked task + exam keep existing, lose the link

        let mutation = try #require(SampleContent.removalMutation(fixture.record, in: before))
        try fixture.apply(mutation)
        let after = fixture.database

        // Everything that existed before onboarding is byte-for-byte unchanged.
        func unchanged<E: Equatable & Identifiable>(_ old: [E], _ new: [E]) -> Bool {
            old.allSatisfy { item in new.contains(item) }
        }
        #expect(unchanged(existing.timetables, after.timetables))
        #expect(unchanged(existing.subjects, after.subjects))
        #expect(unchanged(existing.lessons, after.lessons))
        #expect(unchanged(existing.tasks, after.tasks))
        #expect(unchanged(existing.exams, after.exams))
        #expect(unchanged(existing.bellSchedules, after.bellSchedules))
        #expect(unchanged(existing.terms, after.terms))
        #expect(unchanged(existing.breaks, after.breaks))
        #expect(unchanged(existing.overrides, after.overrides))
        #expect(after.reminderRules == before.reminderRules)

        // The user's tasks and exam made while looking around survive; only links to the sample are cleared.
        let keptLinked = try #require(after.tasks.first { $0.id == linkedTask.id })
        #expect(!keptLinked.isDeleted && keptLinked.title == "Mine, linked")
        #expect(keptLinked.subjectID == nil && keptLinked.timetableID == nil && keptLinked.linkedLesson == nil)
        let keptExam = try #require(after.exams.first { $0.id == linkedExam.id })
        #expect(!keptExam.isDeleted && keptExam.subjectID == nil && keptExam.timetableID == nil)
        let freeAfter = after.tasks.first { $0.id == freeTask.id }
        let freeBefore = before.tasks.first { $0.id == freeTask.id }
        #expect(freeAfter != nil && freeAfter == freeBefore)

        // The sample itself is gone: timetable, children, sample task and exam.
        #expect(after.timetables.first { $0.id == fixture.sampleID }?.isDeleted == true)
        #expect(after.subjects.filter { $0.timetableID == fixture.sampleID }.allSatisfy { $0.isDeleted })
        #expect(after.lessons.filter { $0.timetableID == fixture.sampleID }.allSatisfy { $0.isDeleted })
        #expect(after.bellSchedules.filter { $0.timetableID == fixture.sampleID }.allSatisfy { $0.isDeleted })
        #expect(after.terms.filter { $0.timetableID == fixture.sampleID }.allSatisfy { $0.isDeleted })
        let sampleTasks = after.tasks.filter { fixture.record.taskIDs.contains($0.id.uuid) }
        let sampleExams = after.exams.filter { fixture.record.examIDs.contains($0.id.uuid) }
        #expect(sampleTasks.count == fixture.record.taskIDs.count && sampleTasks.allSatisfy { $0.isDeleted })
        #expect(sampleExams.count == fixture.record.examIDs.count && sampleExams.allSatisfy { $0.isDeleted })

        // The user's timetable becomes active again; the app stays in the tabs.
        #expect(existing.timetables.contains { $0.id == after.settings.activeTimetableID })
        #expect(ShellPhase.derive(isLoading: false, problem: nil, database: after) == .main)
        #expect(after.validate().filter { $0.severity == .error }.isEmpty)
    }

    @Test func localStoresRoundTrip() throws {
        let fixture = try lookAround(on: nil)
        let suite = "tabula.test.sample.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for store in [UserDefaultsOnboardingLocalStore(defaults: defaults) as any OnboardingLocalStore,
                      InMemoryOnboardingLocalStore()] {
            #expect(store.loadSample() == nil && store.loadPendingProfile() == nil)
            store.saveSample(fixture.record)
            store.savePendingProfile(.university)
            #expect(store.loadSample() == fixture.record)
            #expect(store.loadPendingProfile() == .university)
            store.saveSample(nil)
            store.savePendingProfile(nil)
            #expect(store.loadSample() == nil && store.loadPendingProfile() == nil)
        }
    }
}
