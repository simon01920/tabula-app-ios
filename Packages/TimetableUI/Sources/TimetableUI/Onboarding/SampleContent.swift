// "Just look around" (UX_OVERHAUL_PLAN D8, Astra F10): the sample timetable onboarding creates is remembered
// DEVICE-LOCALLY (UserDefaults in the App Group, never in the synced database: no schema change), so the banner
// "This is sample data · Remove" can remove exactly that content later.
//
// What "Remove" deletes (`SampleContent.removalMutation`):
//   - the sample timetable and its children: subjects, bell schedules, lessons, terms, timetable-scoped holidays and
//     changes (everything whose `timetableID` is the sample timetable);
//   - the sample task and exam onboarding created (by recorded ID).
// What it never deletes: other timetables and their children, global holidays (no timetable), reminder rules, the
// settings, and every task / exam the user created. A user task or exam that points at the sample timetable, one of
// its subjects or lessons keeps existing and only loses that link (the same rule as deleting a timetable in the
// timetables manager). Content the user added INSIDE the sample timetable is one of its children; the confirmation
// names how much of it there is (`RemovalImpact.addedByUser`) before anything is removed.
// When the sample timetable was the last one, the app shows onboarding again (ShellPhase), whose finish ADDS the new
// timetable (OnboardingFinish): nothing else is lost.
import Foundation
import TimetableCore

/// The device-local record of the sample content onboarding created.
public struct SampleContentRecord: Codable, Equatable, Sendable {
    /// The sample timetable.
    public var timetableID: UUID
    /// Its children at creation (subjects, bell schedules, lessons, terms), to tell user additions apart.
    public var childIDs: Set<UUID>
    /// The sample tasks (removed by ID).
    public var taskIDs: Set<UUID>
    /// The sample exams (removed by ID).
    public var examIDs: Set<UUID>

    public init(timetableID: UUID, childIDs: Set<UUID>, taskIDs: Set<UUID>, examIDs: Set<UUID>) {
        self.timetableID = timetableID
        self.childIDs = childIDs
        self.taskIDs = taskIDs
        self.examIDs = examIDs
    }
}

/// Device-local onboarding state (not synced, not part of the database schema).
public protocol OnboardingLocalStore: Sendable {
    /// The sample content to offer for removal, if any.
    func loadSample() -> SampleContentRecord?
    func saveSample(_ record: SampleContentRecord?)
    /// The school type chosen before the user opened iOS Settings to change the app language (iOS relaunches the
    /// app after a per-app language change; F13: progress is kept).
    func loadPendingProfile() -> UserProfile?
    func savePendingProfile(_ profile: UserProfile?)
}

/// JSON / string values under fixed UserDefaults keys (the App Group suite on device, like the HLC).
public final class UserDefaultsOnboardingLocalStore: OnboardingLocalStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; the class holds no other state.
    private let defaults: UserDefaults
    public static let sampleKey = "tabula.onboarding.sample.v1"
    public static let pendingProfileKey = "tabula.onboarding.pendingProfile.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadSample() -> SampleContentRecord? {
        guard let data = defaults.data(forKey: Self.sampleKey) else { return nil }
        return try? JSONDecoder().decode(SampleContentRecord.self, from: data)
    }

    public func saveSample(_ record: SampleContentRecord?) {
        guard let record, let data = try? JSONEncoder().encode(record) else {
            defaults.removeObject(forKey: Self.sampleKey)
            return
        }
        defaults.set(data, forKey: Self.sampleKey)
    }

    public func loadPendingProfile() -> UserProfile? {
        defaults.string(forKey: Self.pendingProfileKey).map(UserProfile.init(rawValue:))
    }

    public func savePendingProfile(_ profile: UserProfile?) {
        if let profile { defaults.set(profile.rawValue, forKey: Self.pendingProfileKey) }
        else { defaults.removeObject(forKey: Self.pendingProfileKey) }
    }
}

/// In memory (seed runs, screenshots, tests).
public final class InMemoryOnboardingLocalStore: OnboardingLocalStore, @unchecked Sendable {
    private let lock = NSLock()
    private var sample: SampleContentRecord?
    private var pendingProfile: UserProfile?

    public init(sample: SampleContentRecord? = nil) {
        self.sample = sample
    }

    public func loadSample() -> SampleContentRecord? { locked { sample } }
    public func saveSample(_ record: SampleContentRecord?) { locked { sample = record } }
    public func loadPendingProfile() -> UserProfile? { locked { pendingProfile } }
    public func savePendingProfile(_ profile: UserProfile?) { locked { pendingProfile = profile } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Planning for the sample content: what to record after onboarding, whether the banner applies, what "Remove" does.
public enum SampleContent {
    /// What "Remove" affects (shown in the confirmation).
    public struct RemovalImpact: Equatable, Sendable {
        /// Children of the sample timetable the user added (lessons, subjects, changes …): removed with it.
        public var addedByUser = 0
        /// The user's own tasks and exams linked to the sample: kept, but they lose the link.
        public var unlinkedItems = 0

        public init(addedByUser: Int = 0, unlinkedItems: Int = 0) {
            self.addedByUser = addedByUser
            self.unlinkedItems = unlinkedItems
        }
    }

    /// The record for the sample timetable `timetableID` right after onboarding created it: every live entity
    /// that belongs to the brand-new timetable is sample content.
    public static func record(for timetableID: Timetable.ID, in database: TabulaDatabase) -> SampleContentRecord {
        let scope = Scope(timetableID: timetableID, database: database)
        return SampleContentRecord(
            timetableID: timetableID.uuid,
            childIDs: scope.childIDs,
            taskIDs: Set(database.tasks.filter { !$0.isDeleted && scope.touches(task: $0) }.map(\.id.uuid)),
            examIDs: Set(database.exams.filter { !$0.isDeleted && scope.touches(exam: $0) }.map(\.id.uuid)))
    }

    /// `true` while the sample timetable is still live (else the record is stale and can be forgotten).
    public static func isActive(_ record: SampleContentRecord, in database: TabulaDatabase) -> Bool {
        database.timetables.contains { $0.id.uuid == record.timetableID && !$0.isDeleted }
    }

    /// What removing the sample affects.
    public static func impact(of record: SampleContentRecord, in database: TabulaDatabase) -> RemovalImpact {
        let scope = Scope(timetableID: Timetable.ID(record.timetableID), database: database)
        var impact = RemovalImpact()
        impact.addedByUser = scope.childIDs.subtracting(record.childIDs).count
        impact.unlinkedItems = database.tasks.filter {
            !$0.isDeleted && !record.taskIDs.contains($0.id.uuid) && scope.touches(task: $0)
        }.count + database.exams.filter {
            !$0.isDeleted && !record.examIDs.contains($0.id.uuid) && scope.touches(exam: $0)
        }.count
        return impact
    }

    /// Removes the sample timetable with its children and the sample tasks / exams in ONE batch; `nil` when the
    /// sample timetable no longer exists. See the file header for the exact scope.
    public static func removalMutation(_ record: SampleContentRecord, in database: TabulaDatabase) -> DatabaseMutation? {
        guard isActive(record, in: database) else { return nil }
        let timetableID = Timetable.ID(record.timetableID)
        let scope = Scope(timetableID: timetableID, database: database)
        var steps: [DatabaseMutation] = []
        for lesson in scope.lessons { steps.append(.delete(lesson.id)) }
        for subject in scope.subjects { steps.append(.delete(subject.id)) }
        for schedule in scope.bellSchedules { steps.append(.delete(schedule.id)) }
        for term in scope.terms { steps.append(.delete(term.id)) }
        for item in scope.breaks { steps.append(.delete(item.id)) }
        for item in scope.overrides { steps.append(.delete(item.id)) }
        for task in database.tasks where !task.isDeleted {
            if record.taskIDs.contains(task.id.uuid) {
                steps.append(.delete(task.id))
            } else if scope.touches(task: task) {
                var edited = task
                if edited.timetableID == timetableID { edited.timetableID = nil }
                if let subjectID = edited.subjectID, scope.subjectIDs.contains(subjectID) { edited.subjectID = nil }
                if let link = edited.linkedLesson, scope.lessonIDs.contains(link.lessonID) { edited.linkedLesson = nil }
                steps.append(.upsert(edited))
            }
        }
        for exam in database.exams where !exam.isDeleted {
            if record.examIDs.contains(exam.id.uuid) {
                steps.append(.delete(exam.id))
            } else if scope.touches(exam: exam) {
                var edited = exam
                if edited.timetableID == timetableID { edited.timetableID = nil }
                if let subjectID = edited.subjectID, scope.subjectIDs.contains(subjectID) { edited.subjectID = nil }
                steps.append(.upsert(edited))
            }
        }
        steps.append(.delete(timetableID))
        if database.settings.activeTimetableID == timetableID,
           let next = ActiveTimetable.ordered(database).first(where: { $0.id != timetableID }) {
            steps.append(.settings { $0.activeTimetableID = next.id })
        }
        return .batch(steps, label: "remove sample data")
    }

    /// The live children of one timetable.
    private struct Scope {
        let lessons: [Lesson]
        let subjects: [Subject]
        let bellSchedules: [BellSchedule]
        let terms: [Term]
        let breaks: [CalendarBreak]
        let overrides: [ScheduleOverride]
        let timetableID: Timetable.ID
        let lessonIDs: Set<Lesson.ID>
        let subjectIDs: Set<Subject.ID>

        init(timetableID: Timetable.ID, database: TabulaDatabase) {
            self.timetableID = timetableID
            lessons = database.lessons.filter { !$0.isDeleted && $0.timetableID == timetableID }
            subjects = database.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }
            bellSchedules = database.bellSchedules.filter { !$0.isDeleted && $0.timetableID == timetableID }
            terms = database.terms.filter { !$0.isDeleted && $0.timetableID == timetableID }
            breaks = database.breaks.filter { !$0.isDeleted && $0.timetableID == timetableID }
            overrides = database.overrides.filter { !$0.isDeleted && $0.timetableID == timetableID }
            lessonIDs = Set(lessons.map(\.id))
            subjectIDs = Set(subjects.map(\.id))
        }

        var childIDs: Set<UUID> {
            Set(lessons.map(\.id.uuid) + subjects.map(\.id.uuid) + bellSchedules.map(\.id.uuid) + terms.map(\.id.uuid)
                + breaks.map(\.id.uuid) + overrides.map(\.id.uuid))
        }

        func touches(task: TaskItem) -> Bool {
            task.timetableID == timetableID
                || (task.subjectID.map(subjectIDs.contains) ?? false)
                || (task.linkedLesson.map { lessonIDs.contains($0.lessonID) } ?? false)
        }

        func touches(exam: Exam) -> Bool {
            exam.timetableID == timetableID || (exam.subjectID.map(subjectIDs.contains) ?? false)
        }
    }
}
