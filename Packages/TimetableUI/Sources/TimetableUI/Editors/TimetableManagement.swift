// Pure planning of the multi-entity changes behind the timetables manager and the subjects list: add, duplicate,
// reorder, set active, reset, delete (with the data-loss guard), subject order (P3-2: reorder, move, add at the end)
// and subject deletion. Every function returns a
// `DatabaseMutation` (or nil when the guard refuses) that the app applies in ONE `model.apply` call, so the
// database never contains half of a change. Linux-tested.
//
// Data-loss guard (Stage A QA finding): the shell shows onboarding when no live timetable exists, so the LAST live
// timetable can never be deleted; the manager offers "Reset timetable" (clear its lessons) instead.
import Foundation
import TimetableCore

/// What deleting a timetable removes (shown in the confirmation).
public struct DeletionImpact: Equatable, Sendable {
    public var lessons = 0
    public var subjects = 0
    public var bellSchedules = 0
    public var terms = 0
    public var breaks = 0
    public var overrides = 0
    /// Tasks and exams that keep existing but lose their link.
    public var linkedTasks = 0
    public var linkedExams = 0

    public init() {}
}

/// Whether a timetable may be deleted.
public enum TimetableDeletionGuard: Equatable, Sendable {
    case allowed
    /// It is the only live timetable (the app would fall back to onboarding): refused.
    case lastRemaining
    case notFound
}

/// How a new timetable gets its time structure.
public enum NewTimetableStructure: Sendable {
    /// Free-form lessons of `minutes` (no bell schedule).
    case freeForm(minutes: Int)
    /// A new bell schedule from a preset template.
    case template(BellScheduleTemplate, scheduleName: String)
    /// A copy of the default bell schedule of another timetable.
    case copyBellSchedule(of: Timetable.ID, scheduleName: String)
}

/// Plans for timetable-level changes.
public enum TimetableManagement {
    // MARK: Queries

    /// Live timetables in display order.
    public static func live(_ database: TabulaDatabase) -> [Timetable] { ActiveTimetable.ordered(database) }

    /// May `id` be deleted?
    public static func deletionGuard(_ id: Timetable.ID, in database: TabulaDatabase) -> TimetableDeletionGuard {
        let timetables = live(database)
        guard timetables.contains(where: { $0.id == id }) else { return .notFound }
        return timetables.count <= 1 ? .lastRemaining : .allowed
    }

    /// May another timetable be added with the entitlement `limit` (`nil` = unlimited)?
    public static func canAdd(to database: TabulaDatabase, limit: Int?) -> Bool {
        guard let limit else { return true }
        return live(database).count < limit
    }

    /// What deleting `id` removes.
    public static func impact(of id: Timetable.ID, in database: TabulaDatabase) -> DeletionImpact {
        let scope = Scope(timetableID: id, database: database)
        var impact = DeletionImpact()
        impact.lessons = scope.lessons.count
        impact.subjects = scope.subjects.count
        impact.bellSchedules = scope.bellSchedules.count
        impact.terms = scope.terms.count
        impact.breaks = scope.breaks.count
        impact.overrides = scope.overrides.count
        impact.linkedTasks = database.tasks.filter { !$0.isDeleted && scope.touches(task: $0) }.count
        impact.linkedExams = database.exams.filter { !$0.isDeleted && scope.touches(exam: $0) }.count
        return impact
    }

    /// How many lessons and lesson-level changes "Reset timetable" removes.
    public static func resetImpact(of id: Timetable.ID, in database: TabulaDatabase) -> (lessons: Int, changes: Int) {
        let lessonIDs = Set(database.lessons.filter { !$0.isDeleted && $0.timetableID == id }.map(\.id))
        let changes = database.overrides.filter { !$0.isDeleted && $0.timetableID == id && refersToLesson($0.change, in: lessonIDs) }
        return (lessonIDs.count, changes.count)
    }

    // MARK: Mutations

    /// Makes `id` the active timetable.
    public static func setActiveMutation(_ id: Timetable.ID) -> DatabaseMutation {
        .settings { $0.activeTimetableID = id }
    }

    /// Deletes `id` with everything that belongs to it. `nil` when the guard refuses. If it was the active
    /// timetable, another one becomes active in the same batch.
    public static func deleteMutation(_ id: Timetable.ID, in database: TabulaDatabase) -> DatabaseMutation? {
        guard deletionGuard(id, in: database) == .allowed else { return nil }
        let scope = Scope(timetableID: id, database: database)
        var steps: [DatabaseMutation] = []
        for lesson in scope.lessons { steps.append(.delete(lesson.id)) }
        for subject in scope.subjects { steps.append(.delete(subject.id)) }
        for schedule in scope.bellSchedules { steps.append(.delete(schedule.id)) }
        for term in scope.terms { steps.append(.delete(term.id)) }
        for item in scope.breaks { steps.append(.delete(item.id)) }
        for item in scope.overrides { steps.append(.delete(item.id)) }
        for task in database.tasks where !task.isDeleted && scope.touches(task: task) {
            var edited = task
            if edited.timetableID == id { edited.timetableID = nil }
            if let subjectID = edited.subjectID, scope.subjectIDs.contains(subjectID) { edited.subjectID = nil }
            if let link = edited.linkedLesson, scope.lessonIDs.contains(link.lessonID) { edited.linkedLesson = nil }
            steps.append(.upsert(edited))
        }
        for exam in database.exams where !exam.isDeleted && scope.touches(exam: exam) {
            var edited = exam
            if edited.timetableID == id { edited.timetableID = nil }
            if let subjectID = edited.subjectID, scope.subjectIDs.contains(subjectID) { edited.subjectID = nil }
            steps.append(.upsert(edited))
        }
        steps.append(.delete(id))
        if database.settings.activeTimetableID == id,
           let next = live(database).first(where: { $0.id != id }) {
            steps.append(setActiveMutation(next.id))
        }
        return .batch(steps, label: "delete timetable")
    }

    /// Removes every lesson of `id` and the changes that refer to them; subjects, bell schedules, terms and
    /// day-level changes stay.
    public static func resetMutation(_ id: Timetable.ID, in database: TabulaDatabase) -> DatabaseMutation {
        let lessonIDs = Set(database.lessons.filter { !$0.isDeleted && $0.timetableID == id }.map(\.id))
        return .batch(lessonRemovalSteps(lessonIDs, in: database), label: "reset timetable")
    }

    /// Re-orders the live timetables to `order` (IDs not named keep their relative position behind).
    public static func reorderMutation(_ order: [Timetable.ID], in database: TabulaDatabase) -> DatabaseMutation {
        .batch(reorderSteps(order, in: database), label: "reorder timetables")
    }

    /// `true` when `reorderMutation(order, in:)` would change nothing (the UI then skips the apply: no save, no
    /// change notification for a row dropped where it was).
    public static func reorderIsNoOp(_ order: [Timetable.ID], in database: TabulaDatabase) -> Bool {
        reorderSteps(order, in: database).isEmpty
    }

    private static func reorderSteps(_ order: [Timetable.ID], in database: TabulaDatabase) -> [DatabaseMutation] {
        let current = live(database)
        let named = order.compactMap { id in current.first { $0.id == id } }
        let rest = current.filter { timetable in !order.contains(timetable.id) }
        var steps: [DatabaseMutation] = []
        for (index, timetable) in (named + rest).enumerated() where timetable.sortIndex != index {
            var edited = timetable
            edited.sortIndex = index
            steps.append(.upsert(edited))
        }
        return steps
    }

    /// The `sortIndex` for a timetable appended at the end (`max + 1`) and the steps to run first. When `max + 1`
    /// would overflow (a stored `Int.max` from a crafted backup or a synced record) the live timetables are renumbered
    /// densely in display order and the new one gets the count, so adding never traps.
    public static func appendIndex(in database: TabulaDatabase) -> (sortIndex: Int, steps: [DatabaseMutation]) {
        let current = live(database)
        if let next = SubjectOrder.appendedIndex(after: current.map(\.sortIndex)) { return (next, []) }
        return (current.count, reorderSteps(current.map(\.id), in: database))
    }

    /// A new, empty timetable. Presentation settings are taken from `like` when given.
    public static func addMutation<G: IDGenerator>(name: String, emoji: String?, structure: NewTimetableStructure,
                                                   like: Timetable?, in database: TabulaDatabase,
                                                   ids: inout G) -> (mutation: DatabaseMutation, timetableID: Timetable.ID) {
        let newID: Timetable.ID = ids.next()
        var steps: [DatabaseMutation] = []
        let timeStructure: TimeStructure
        switch structure {
        case .freeForm(let minutes):
            timeStructure = .freeForm(defaultDurationMinutes: minutes)
        case let .template(template, scheduleName):
            let periods = template.lessonTimes().map { slot -> Period in
                Period(id: ids.next(), label: nil, start: slot.start, end: slot.end, kind: .lesson)
            }
            let scheduleID: BellSchedule.ID = ids.next()
            steps.append(.upsert(BellSchedule(id: scheduleID, meta: EditorEntities.placeholderMeta, timetableID: newID,
                                              name: scheduleName, periods: periods)))
            timeStructure = .bellSchedule(defaultID: scheduleID, perWeekday: [:])
        case let .copyBellSchedule(sourceID, scheduleName):
            let source = database.timetables.first { $0.id == sourceID }
            let sourceSchedule = source.flatMap { timetable -> BellSchedule? in
                if case .bellSchedule(let defaultID, _) = timetable.timeStructure {
                    return database.bellSchedules.first { $0.id == defaultID && !$0.isDeleted }
                }
                return nil
            }
            if let sourceSchedule {
                let scheduleID: BellSchedule.ID = ids.next()
                let periods = sourceSchedule.periods.map { period -> Period in
                    var copy = period
                    copy.id = ids.next()
                    return copy
                }
                steps.append(.upsert(BellSchedule(id: scheduleID, meta: EditorEntities.placeholderMeta, timetableID: newID,
                                                  name: scheduleName, periods: periods)))
                timeStructure = .bellSchedule(defaultID: scheduleID, perWeekday: [:])
            } else {
                timeStructure = .freeForm(defaultDurationMinutes: 45)
            }
        }
        let append = appendIndex(in: database)
        steps.insert(contentsOf: append.steps, at: 0)
        let timetable = Timetable(
            id: newID, meta: EditorEntities.placeholderMeta, name: name, emoji: emoji,
            enabledDays: Weekday.workweek, rotation: .none, rotationWeekStart: like?.rotationWeekStart ?? .monday,
            timeStructure: timeStructure, fieldVisibility: like?.fieldVisibility ?? FieldVisibility(),
            defaultView: like?.defaultView ?? .grid, density: like?.density ?? .comfortable,
            palettePackID: like?.palettePackID, sortIndex: append.sortIndex)
        steps.append(.upsert(timetable))
        return (.batch(steps, label: "add timetable"), newID)
    }

    /// A full copy of `id` (subjects, bell schedules, terms, lessons, day changes, breaks) under `name`, put at the
    /// end of the list. Tasks and exams are not copied. `nil` when `id` is not a live timetable.
    public static func duplicateMutation<G: IDGenerator>(_ id: Timetable.ID, name: String, in database: TabulaDatabase,
                                                         ids: inout G) -> (mutation: DatabaseMutation, timetableID: Timetable.ID)? {
        guard let source = live(database).first(where: { $0.id == id }) else { return nil }
        let scope = Scope(timetableID: id, database: database)
        let newID: Timetable.ID = ids.next()
        var steps: [DatabaseMutation] = []

        var bellMap: [BellSchedule.ID: BellSchedule.ID] = [:]
        var periodMap: [Period.ID: Period.ID] = [:]
        for schedule in scope.bellSchedules {
            var copy = schedule
            copy.id = ids.next()
            copy.meta = EditorEntities.placeholderMeta
            copy.timetableID = newID
            copy.periods = schedule.periods.map { period -> Period in
                var next = period
                let mapped: Period.ID = periodMap[period.id] ?? ids.next()
                periodMap[period.id] = mapped
                next.id = mapped
                return next
            }
            bellMap[schedule.id] = copy.id
            steps.append(.upsert(copy))
        }
        var subjectMap: [Subject.ID: Subject.ID] = [:]
        for subject in scope.subjects {
            var copy = subject
            copy.id = ids.next()
            copy.meta = EditorEntities.placeholderMeta
            copy.timetableID = newID
            subjectMap[subject.id] = copy.id
            steps.append(.upsert(copy))
        }
        var termMap: [Term.ID: Term.ID] = [:]
        for term in scope.terms {
            var copy = term
            copy.id = ids.next()
            copy.meta = EditorEntities.placeholderMeta
            copy.timetableID = newID
            termMap[term.id] = copy.id
            steps.append(.upsert(copy))
        }
        func slot(_ slot: LessonSlot) -> LessonSlot {
            if case let .period(periodID, span) = slot { return .period(periodMap[periodID] ?? periodID, span: span) }
            return slot
        }
        var lessonMap: [Lesson.ID: Lesson.ID] = [:]
        for lesson in scope.lessons {
            var copy = lesson
            copy.id = ids.next()
            copy.meta = EditorEntities.placeholderMeta
            copy.timetableID = newID
            copy.subjectID = subjectMap[lesson.subjectID] ?? lesson.subjectID
            copy.slot = slot(lesson.slot)
            if case .terms(let termIDs) = lesson.validity {
                copy.validity = .terms(Set(termIDs.map { termMap[$0] ?? $0 }))
            }
            lessonMap[lesson.id] = copy.id
            steps.append(.upsert(copy))
        }
        for item in scope.overrides {
            var copy = item
            copy.id = ids.next()
            copy.meta = EditorEntities.placeholderMeta
            copy.timetableID = newID
            switch item.change {
            case .cancelLesson(let lessonID):
                copy.change = .cancelLesson(lessonMap[lessonID] ?? lessonID)
            case let .modifyLesson(lessonID, patch):
                var edited = patch
                edited.subjectID = patch.subjectID.map { subjectMap[$0] ?? $0 }
                edited.slot = patch.slot.map(slot)
                copy.change = .modifyLesson(lessonMap[lessonID] ?? lessonID, edited)
            case .addLesson(var oneOff):
                oneOff.subjectID = subjectMap[oneOff.subjectID] ?? oneOff.subjectID
                oneOff.slot = slot(oneOff.slot)
                copy.change = .addLesson(oneOff)
            case .useBellSchedule(let scheduleID):
                copy.change = .useBellSchedule(bellMap[scheduleID] ?? scheduleID)
            case .cancelDay, .followDay, .unknown:
                break
            }
            steps.append(.upsert(copy))
        }
        for item in scope.breaks {
            var copy = item
            copy.id = ids.next()
            copy.meta = EditorEntities.placeholderMeta
            copy.timetableID = newID
            steps.append(.upsert(copy))
        }
        var timetable = source
        timetable.id = newID
        timetable.meta = EditorEntities.placeholderMeta
        timetable.name = name
        let append = appendIndex(in: database)
        steps.insert(contentsOf: append.steps, at: 0)
        timetable.sortIndex = append.sortIndex
        if case let .bellSchedule(defaultID, perWeekday) = source.timeStructure {
            timetable.timeStructure = .bellSchedule(defaultID: bellMap[defaultID] ?? defaultID,
                                                    perWeekday: perWeekday.mapValues { bellMap[$0] ?? $0 })
        }
        steps.append(.upsert(timetable))
        return (.batch(steps, label: "duplicate timetable"), newID)
    }

    // MARK: Lessons

    /// Deletes one lesson together with the day changes that refer to it; tasks lose their link to it.
    public static func deleteLessonMutation(_ id: Lesson.ID, in database: TabulaDatabase) -> DatabaseMutation {
        .batch(lessonRemovalSteps([id], in: database), label: "delete lesson")
    }

    /// How many day changes deleting the lesson removes.
    public static func lessonChangeCount(_ id: Lesson.ID, in database: TabulaDatabase) -> Int {
        database.overrides.filter { !$0.isDeleted && refersToLesson($0.change, in: [id]) }.count
    }

    // MARK: Subjects

    /// Live subjects of `timetableID` in display order (`SubjectOrder`).
    public static func subjects(of timetableID: Timetable.ID, in database: TabulaDatabase, locale: Locale) -> [Subject] {
        SubjectOrder.live(database, timetableID: timetableID, locale: locale)
    }

    /// Re-orders the live subjects of `timetableID` to `order` with dense indices (IDs not named keep their relative
    /// position behind). Only subjects whose index changes are written (one stamped upsert each), so untouched
    /// subjects keep their field clocks.
    /// `nil` when the order is unchanged (e.g. a row dropped where it was): the UI then applies nothing, so there is no
    /// save and no change notification.
    public static func reorderSubjectsMutation(_ order: [Subject.ID], timetableID: Timetable.ID,
                                               in database: TabulaDatabase, locale: Locale) -> DatabaseMutation? {
        let changed = SubjectOrder.reordered(order, in: database, timetableID: timetableID, locale: locale)
        guard !changed.isEmpty else { return nil }
        return .batch(changed.map { .upsert($0) }, label: "reorder subjects")
    }

    /// Moves a subject one or more places within its timetable (the accessibility "Move up" / "Move down" actions).
    /// `nil` when the subject is not live or cannot move that far.
    public static func moveSubjectMutation(_ id: Subject.ID, by offset: Int, in database: TabulaDatabase,
                                           locale: Locale) -> DatabaseMutation? {
        guard let subject = database.subjects.first(where: { $0.id == id && !$0.isDeleted }) else { return nil }
        let ids = subjects(of: subject.timetableID, in: database, locale: locale).map(\.id)
        guard let order = SubjectOrder.moving(id, by: offset, in: ids) else { return nil }
        return reorderSubjectsMutation(order, timetableID: subject.timetableID, in: database, locale: locale)
    }

    /// Saves a subject from the subject editor.
    /// - New subject (no stored entity with its ID): it is added at the END of its timetable's list
    ///   (`SubjectOrder.insertion`; subjects without an index are numbered in their visible order first, in the same
    ///   batch).
    /// - Existing subject: the editor never changes the order, so the stored `sortIndex` is kept — a reorder made
    ///   meanwhile (on this device or synced from another) is never overwritten by the editor's stale copy.
    public static func saveSubjectMutation(_ subject: Subject, in database: TabulaDatabase, locale: Locale) -> DatabaseMutation {
        var edited = subject
        if let stored = database.subjects.first(where: { $0.id == subject.id }) {
            edited.sortIndex = stored.sortIndex
            return .upsert(edited)
        }
        let plan = SubjectOrder.insertion(in: database, timetableID: subject.timetableID, locale: locale)
        edited.sortIndex = plan.sortIndex
        return .batch(plan.renumbered.map { .upsert($0) } + [.upsert(edited)], label: "add subject")
    }

    /// What deleting a subject removes: its lessons, the changes that refer to it; tasks/exams lose the link.
    public static func subjectImpact(of id: Subject.ID, in database: TabulaDatabase) -> (lessons: Int, changes: Int, linkedItems: Int) {
        let lessonIDs = Set(database.lessons.filter { !$0.isDeleted && $0.subjectID == id }.map(\.id))
        let changes = database.overrides.filter { !$0.isDeleted && (refersToLesson($0.change, in: lessonIDs) || refersToSubject($0.change, id)) }
        let tasks = database.tasks.filter { !$0.isDeleted && ($0.subjectID == id || ($0.linkedLesson.map { lessonIDs.contains($0.lessonID) } ?? false)) }
        let exams = database.exams.filter { !$0.isDeleted && $0.subjectID == id }
        return (lessonIDs.count, changes.count, tasks.count + exams.count)
    }

    /// Deletes a subject together with its lessons and the changes that refer to it.
    public static func deleteSubjectMutation(_ id: Subject.ID, in database: TabulaDatabase) -> DatabaseMutation {
        let lessonIDs = Set(database.lessons.filter { !$0.isDeleted && $0.subjectID == id }.map(\.id))
        var steps = lessonRemovalSteps(lessonIDs, in: database, clearingSubject: id)
        for item in database.overrides where !item.isDeleted && refersToSubject(item.change, id)
            && !refersToLesson(item.change, in: lessonIDs) {
            steps.append(.delete(item.id))
        }
        for exam in database.exams where !exam.isDeleted && exam.subjectID == id {
            var edited = exam
            edited.subjectID = nil
            steps.append(.upsert(edited))
        }
        steps.append(.delete(id))
        return .batch(steps, label: "delete subject")
    }

    // MARK: Internals

    private struct Scope {
        let lessons: [Lesson]
        let subjects: [Subject]
        let bellSchedules: [BellSchedule]
        let terms: [Term]
        let breaks: [CalendarBreak]
        let overrides: [ScheduleOverride]
        let timetableID: Timetable.ID
        var lessonIDs: Set<Lesson.ID> { Set(lessons.map(\.id)) }
        var subjectIDs: Set<Subject.ID> { Set(subjects.map(\.id)) }

        init(timetableID: Timetable.ID, database: TabulaDatabase) {
            self.timetableID = timetableID
            lessons = database.lessons.filter { !$0.isDeleted && $0.timetableID == timetableID }
            subjects = database.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }
            bellSchedules = database.bellSchedules.filter { !$0.isDeleted && $0.timetableID == timetableID }
            terms = database.terms.filter { !$0.isDeleted && $0.timetableID == timetableID }
            breaks = database.breaks.filter { !$0.isDeleted && $0.timetableID == timetableID }
            overrides = database.overrides.filter { !$0.isDeleted && $0.timetableID == timetableID }
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

    private static func refersToLesson(_ change: OverrideChange, in lessonIDs: Set<Lesson.ID>) -> Bool {
        switch change {
        case .cancelLesson(let id), .modifyLesson(let id, _): return lessonIDs.contains(id)
        case .addLesson, .cancelDay, .useBellSchedule, .followDay, .unknown: return false
        }
    }

    private static func refersToSubject(_ change: OverrideChange, _ id: Subject.ID) -> Bool {
        switch change {
        case .modifyLesson(_, let patch): return patch.subjectID == id
        case .addLesson(let oneOff): return oneOff.subjectID == id
        case .cancelLesson, .cancelDay, .useBellSchedule, .followDay, .unknown: return false
        }
    }

    /// Deletes lessons, the changes that refer to them and clears task links to them.
    private static func lessonRemovalSteps(_ lessonIDs: Set<Lesson.ID>, in database: TabulaDatabase,
                                            clearingSubject subjectID: Subject.ID? = nil) -> [DatabaseMutation] {
        var steps: [DatabaseMutation] = []
        for lesson in database.lessons where !lesson.isDeleted && lessonIDs.contains(lesson.id) {
            steps.append(.delete(lesson.id))
        }
        for item in database.overrides where !item.isDeleted && refersToLesson(item.change, in: lessonIDs) {
            steps.append(.delete(item.id))
        }
        for task in database.tasks where !task.isDeleted {
            var edited = task
            if let link = task.linkedLesson, lessonIDs.contains(link.lessonID) { edited.linkedLesson = nil }
            if let subjectID, task.subjectID == subjectID { edited.subjectID = nil }
            if edited != task { steps.append(.upsert(edited)) }
        }
        return steps
    }
}
