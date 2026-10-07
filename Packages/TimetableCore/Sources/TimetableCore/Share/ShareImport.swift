import Foundation

/// What the receiving screen shows before the user confirms an import (docs/specs/SHARING.md "Receiving").
public struct SharePreview: Hashable, Sendable {
    /// Timetable name (user text from the sender: display as data).
    public var timetableName: String
    /// Timetable emoji.
    public var emoji: String?
    /// The rotation (none, week cycle, day cycle).
    public var rotation: RotationScheme
    /// Number of subjects.
    public var subjectCount: Int
    /// Number of recurring lessons.
    public var lessonCount: Int
    /// Number of bell schedules.
    public var bellScheduleCount: Int
    /// Number of terms.
    public var termCount: Int
    /// Number of holidays/breaks.
    public var breakCount: Int
    /// `true` when the sender included tasks and exams.
    public var includesTasks: Bool
    /// Number of tasks (0 unless `includesTasks`).
    public var taskCount: Int
    /// Number of exams (0 unless `includesTasks`).
    public var examCount: Int
    /// Non-fatal findings.
    public var warnings: [ShareWarning]
}

/// Entities created from a payload: all new, with fresh IDs and metadata, owned by a new timetable.
public struct ShareImportedTimetable: Hashable, Sendable {
    /// The new timetable.
    public var timetable: Timetable
    /// Its subjects (payload order).
    public var subjects: [Subject]
    /// Its bell schedules (payload order).
    public var bellSchedules: [BellSchedule]
    /// Its lessons (payload order).
    public var lessons: [Lesson]
    /// Its terms (payload order).
    public var terms: [Term]
    /// Its breaks (payload order; always scoped to the new timetable, never global).
    public var breaks: [CalendarBreak]
    /// Its tasks (payload order).
    public var tasks: [TaskItem]
    /// Its exams (payload order).
    public var exams: [Exam]
    /// Validation warnings of the payload.
    public var warnings: [ShareWarning]

    /// Every top-level ID created by the import.
    public var allIDs: [UUID] {
        [timetable.id.uuid] + subjects.map(\.id.uuid) + bellSchedules.map(\.id.uuid) + lessons.map(\.id.uuid)
            + terms.map(\.id.uuid) + breaks.map(\.id.uuid) + tasks.map(\.id.uuid) + exams.map(\.id.uuid)
    }

    /// `db` with the imported entities appended. Never replaces or edits anything: if any new ID already exists
    /// in `db`, nothing is inserted and `.idCollision` is thrown.
    public func inserted(into db: TabulaDatabase) throws(ShareError) -> TabulaDatabase {
        var existing: Set<UUID> = [db.settings.id.uuid]
        existing.formUnion(db.timetables.map(\.id.uuid))
        existing.formUnion(db.subjects.map(\.id.uuid))
        existing.formUnion(db.bellSchedules.map(\.id.uuid))
        existing.formUnion(db.lessons.map(\.id.uuid))
        existing.formUnion(db.terms.map(\.id.uuid))
        existing.formUnion(db.breaks.map(\.id.uuid))
        existing.formUnion(db.overrides.map(\.id.uuid))
        existing.formUnion(db.tasks.map(\.id.uuid))
        existing.formUnion(db.exams.map(\.id.uuid))
        existing.formUnion(db.reminderRules.map(\.id.uuid))
        let new = allIDs
        guard Set(new).count == new.count, !new.contains(where: existing.contains) else { throw .idCollision }
        var copy = db
        copy.timetables.append(timetable)
        copy.subjects += subjects
        copy.bellSchedules += bellSchedules
        copy.lessons += lessons
        copy.terms += terms
        copy.breaks += breaks
        copy.tasks += tasks
        copy.exams += exams
        return copy
    }
}

/// Receiving side of sharing: decode → preview → materialize → insert.
public enum ShareImport {
    /// Decodes and validates an envelope (same as `ShareCodec.decode(_:)`).
    public static func decode(_ envelope: String) throws(ShareError) -> SharePayloadV1 {
        try ShareCodec.decode(envelope)
    }

    /// The preview of a decoded payload (re-validates it, so payloads built in code are checked too).
    public static func preview(_ payload: SharePayloadV1) throws(ShareError) -> SharePreview {
        let warnings = try payload.validate()
        return SharePreview(
            timetableName: payload.timetable.name, emoji: payload.timetable.emoji, rotation: payload.timetable.rotation,
            subjectCount: payload.subjects.count, lessonCount: payload.lessons.count,
            bellScheduleCount: payload.bellSchedules.count, termCount: payload.terms.count,
            breakCount: payload.breaks.count, includesTasks: payload.includesTasks, taskCount: payload.tasks.count,
            examCount: payload.exams.count, warnings: warnings)
    }

    /// Decodes an envelope and returns its preview.
    public static func preview(_ envelope: String) throws(ShareError) -> SharePreview {
        try preview(try ShareCodec.decode(envelope))
    }

    /// Creates new entities from a (validated) payload.
    ///
    /// - Every entity, period and subtask gets a fresh ID from `ids` (the payload carries no IDs, so incoming IDs
    ///   can never be reused) and its own `EntityMeta.created(at: clock.tick(now:))`.
    /// - Generation order (deterministic): timetable, bell schedules, period keys (first appearance), subjects,
    ///   terms, breaks, lessons, tasks (each followed by its subtasks), exams.
    /// - Breaks belong to the new timetable; colour names with an unknown palette key are dropped; periods are
    ///   stored ascending by (start, end, key); tasks and exams are open.
    /// - Nothing existing is touched; insert the result with `ShareImportedTimetable.inserted(into:)`.
    public static func materialize<G: IDGenerator, C: TimestampClock>(
        _ payload: SharePayloadV1, ids: inout G, clock: inout C, now: Date, sortIndex: Int = 0
    ) throws(ShareError) -> ShareImportedTimetable {
        let warnings = try payload.validate()
        func meta() -> EntityMeta { .created(at: clock.tick(now: now)) }

        let timetableID: Timetable.ID = ids.next()
        let timetableMeta = meta()

        let scheduleIDs: [BellSchedule.ID] = payload.bellSchedules.map { _ in ids.next() }
        var periodIDs: [Int: Period.ID] = [:]
        for schedule in payload.bellSchedules {
            for period in schedule.periods where periodIDs[period.key] == nil {
                periodIDs[period.key] = ids.next()
            }
        }
        var bellSchedules: [BellSchedule] = []
        for (index, schedule) in payload.bellSchedules.enumerated() {
            let periods = schedule.periods.sorted { ($0.start, $0.end, $0.key) < ($1.start, $1.end, $1.key) }.map {
                Period(id: periodIDs[$0.key]!, label: $0.label, start: $0.start, end: $0.end, kind: $0.kind)
            }
            bellSchedules.append(BellSchedule(id: scheduleIDs[index], meta: meta(), timetableID: timetableID,
                                              name: schedule.name, periods: periods))
        }

        var subjects: [Subject] = []
        for shared in payload.subjects {
            var colorName = shared.colorName
            if case .key(let key)? = colorName, !SharePalette.colorKeys.contains(key) { colorName = nil }
            subjects.append(Subject(id: ids.next(), meta: meta(), timetableID: timetableID, name: shared.name,
                                    shortName: shared.shortName, color: shared.color, colorName: colorName,
                                    symbol: shared.symbol, defaultRoom: shared.defaultRoom,
                                    defaultBuilding: shared.defaultBuilding, defaultTeacher: shared.defaultTeacher,
                                    notes: shared.notes))
        }

        var terms: [Term] = []
        for shared in payload.terms {
            terms.append(Term(id: ids.next(), meta: meta(), timetableID: timetableID, name: shared.name, range: shared.range))
        }

        var breaks: [CalendarBreak] = []
        for shared in payload.breaks {
            breaks.append(CalendarBreak(id: ids.next(), meta: meta(), timetableID: timetableID, name: shared.name,
                                        range: shared.range, kind: shared.kind))
        }

        var lessons: [Lesson] = []
        for shared in payload.lessons {
            let slot: LessonSlot
            switch shared.slot {
            case let .period(key, span): slot = .period(periodIDs[key]!, span: span)
            case let .time(start, end): slot = .time(start: start, end: end)
            }
            let validity: LessonValidity
            switch shared.validity {
            case .always: validity = .always
            case .terms(let indices): validity = .terms(Set(indices.map { terms[$0].id }))
            case .range(let range): validity = .range(range)
            }
            lessons.append(Lesson(id: ids.next(), meta: meta(), timetableID: timetableID,
                                  subjectID: subjects[shared.subject].id,
                                  occurrence: LessonOccurrenceRule(day: shared.day, cycleWeeks: shared.cycleWeeks),
                                  slot: slot, validity: validity, room: shared.room, building: shared.building,
                                  teacher: shared.teacher, lessonType: shared.lessonType, notes: shared.notes,
                                  bringList: shared.bringList))
        }

        var tasks: [TaskItem] = []
        for shared in payload.tasks {
            let taskID: TaskItem.ID = ids.next()
            let taskMeta = meta()
            var subtasks: [Subtask] = []
            for (index, title) in shared.subtasks.enumerated() {
                subtasks.append(Subtask(id: ids.next(), meta: meta(), title: title, sortIndex: index))
            }
            tasks.append(TaskItem(
                id: taskID, meta: taskMeta, title: shared.title, kind: shared.kind,
                subjectID: shared.subject.map { subjects[$0].id }, timetableID: timetableID, due: shared.due,
                linkedLesson: shared.linkedLesson.map { LessonLink(lessonID: lessons[$0.lesson].id, date: $0.date) },
                priority: shared.priority, notes: shared.notes, repeatRule: shared.repeatRule, subtasks: subtasks))
        }

        var exams: [Exam] = []
        for shared in payload.exams {
            exams.append(Exam(id: ids.next(), meta: meta(), timetableID: timetableID,
                              subjectID: shared.subject.map { subjects[$0].id }, title: shared.title, kind: shared.kind,
                              date: shared.date, start: shared.start, end: shared.end, room: shared.room,
                              building: shared.building, topics: shared.topics, notes: shared.notes))
        }

        let source = payload.timetable
        let timeStructure: TimeStructure
        switch source.timeStructure {
        case let .bellSchedule(defaultIndex, perWeekday):
            timeStructure = .bellSchedule(defaultID: scheduleIDs[defaultIndex], perWeekday: perWeekday.mapValues { scheduleIDs[$0] })
        case .freeForm(let minutes):
            timeStructure = .freeForm(defaultDurationMinutes: minutes)
        }
        let timetable = Timetable(id: timetableID, meta: timetableMeta, name: source.name, emoji: source.emoji,
                                  enabledDays: source.enabledDays, rotation: source.rotation,
                                  rotationWeekStart: source.rotationWeekStart, timeStructure: timeStructure,
                                  fieldVisibility: FieldVisibility(source.fieldVisibility), defaultView: source.defaultView,
                                  density: source.density, palettePackID: source.palettePackID, sortIndex: sortIndex)

        return ShareImportedTimetable(timetable: timetable, subjects: subjects, bellSchedules: bellSchedules,
                                      lessons: lessons, terms: terms, breaks: breaks, tasks: tasks, exams: exams,
                                      warnings: warnings)
    }
}
