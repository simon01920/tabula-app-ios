// Edit state of the lesson editor (and of the "extra lesson" part of the day-change editor): pure value logic that
// turns what the form holds into a `Lesson` / `OneOffLesson`, lists blocking problems and finds live timetable
// conflicts. Linux-tested.
import Foundation
import TimetableCore

/// A lesson's time slot as the form edits it: period(s) of the bell schedule or explicit start/end times.
public struct SlotDraft: Equatable, Sendable {
    /// How the slot is entered.
    public enum Mode: String, Equatable, Sendable, CaseIterable { case period, time }

    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable, CaseIterable {
        case noPeriod
        case endBeforeStart

        /// Catalog key of the explanation.
        public var l10nKey: String { "editor.slot.issue.\(rawValue)" }
    }

    public var mode: Mode
    public var periodID: Period.ID?
    public var span: Int
    public var start: LocalTime
    public var end: LocalTime

    /// Default times when nothing else is known.
    public static let defaultStart = LocalTime(hour: 8, minute: 0) ?? .midnight
    public static let defaultEnd = LocalTime(hour: 8, minute: 45) ?? .midnight

    /// Edits an existing slot.
    public init(slot: LessonSlot) {
        switch slot {
        case let .period(id, span):
            mode = .period
            periodID = id
            self.span = max(1, span)
            start = Self.defaultStart
            end = Self.defaultEnd
        case let .time(start, end):
            mode = .time
            periodID = nil
            span = 1
            self.start = start
            self.end = end
        }
    }

    /// A fresh slot: the first lesson period of `schedule`, or default times in a free-form timetable.
    public init(defaultFor timetable: Timetable, schedule: BellSchedule?) {
        span = 1
        start = Self.defaultStart
        end = Self.defaultEnd
        if case .bellSchedule = timetable.timeStructure, let first = Self.lessonPeriods(of: schedule).first {
            mode = .period
            periodID = first.id
        } else {
            mode = .time
            periodID = nil
        }
    }

    /// Lesson periods of `schedule` in time order.
    public static func lessonPeriods(of schedule: BellSchedule?) -> [Period] {
        (schedule?.lessonPeriods ?? []).sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// The largest span that still fits behind `periodID` in `schedule` (at least 1).
    public func maxSpan(in schedule: BellSchedule?) -> Int {
        let periods = Self.lessonPeriods(of: schedule)
        guard let periodID, let index = periods.firstIndex(where: { $0.id == periodID }) else { return 1 }
        return max(1, periods.count - index)
    }

    /// The stored slot, or `nil` while a period is still missing.
    public var slot: LessonSlot? {
        switch mode {
        case .period: return periodID.map { .period($0, span: max(1, span)) }
        case .time: return .time(start: start, end: end)
        }
    }

    /// Problems that block saving.
    public var issues: [Issue] {
        switch mode {
        case .period: return periodID == nil ? [.noPeriod] : []
        case .time: return end > start ? [] : [.endBeforeStart]
        }
    }

    /// Switches the entry mode, carrying the current times over.
    public mutating func setMode(_ newMode: Mode, schedule: BellSchedule?) {
        guard newMode != mode else { return }
        let periods = Self.lessonPeriods(of: schedule)
        switch newMode {
        case .time:
            if let periodID, let index = periods.firstIndex(where: { $0.id == periodID }) {
                let last = periods[min(periods.count - 1, index + max(1, span) - 1)]
                start = periods[index].start
                end = last.end
            }
        case .period:
            let match = periods.first { $0.start == start } ?? periods.first
            periodID = match?.id
            span = 1
        }
        mode = newMode
    }
}

/// Where a "new lesson" starts (the timetable grid tells the editor which empty cell was tapped).
public struct NewLessonContext: Equatable, Sendable {
    public var day: DayKey?
    public var slot: LessonSlot?
    public var subjectID: Subject.ID?
    public var cycleWeek: Int?

    public init(day: DayKey? = nil, slot: LessonSlot? = nil, subjectID: Subject.ID? = nil, cycleWeek: Int? = nil) {
        self.day = day
        self.slot = slot
        self.subjectID = subjectID
        self.cycleWeek = cycleWeek
    }
}

/// How long a lesson applies.
public enum ValidityMode: String, Equatable, Sendable, CaseIterable {
    case always, terms, range
    /// Written by a newer app version: shown read-only and preserved.
    case unknown
}

/// The lesson editor's state.
public struct LessonDraft: Equatable, Sendable {
    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable, CaseIterable {
        case noSubject
        case noTerms
        case emptyRange
        case noCycleWeeks

        /// Catalog key of the explanation.
        public var l10nKey: String { "editor.lesson.issue.\(rawValue)" }
    }

    public let lessonID: Lesson.ID
    public let timetableID: Timetable.ID
    public let isNew: Bool
    public var subjectID: Subject.ID?
    public var day: DayKey
    /// Selected cycle weeks; empty (or all weeks) = every week. Only used with a week rotation.
    public var cycleWeeks: Set<Int>
    public var slot: SlotDraft
    public var validityMode: ValidityMode
    public var termIDs: Set<Term.ID>
    public var rangeStart: LocalDate
    public var rangeEnd: LocalDate
    public var room: String
    public var building: String
    public var teacher: String
    public var lessonType: LessonType?
    public var notes: String
    public var bringList: [String]
    /// The stored lesson (or a skeleton): hidden fields and unknown validity are taken from here.
    private let base: Lesson

    /// Edits `lesson`. `today` seeds the validity range of lessons that have none (today until 30 days later).
    public init(lesson: Lesson, timetable: Timetable, today: LocalDate) {
        lessonID = lesson.id
        timetableID = lesson.timetableID
        isNew = false
        base = lesson
        subjectID = lesson.subjectID
        day = lesson.occurrence.day
        cycleWeeks = lesson.occurrence.cycleWeeks ?? []
        slot = SlotDraft(slot: lesson.slot)
        let fallbackStart = today
        var mode = ValidityMode.always
        var terms = Set<Term.ID>()
        var range = LocalDateRange(start: fallbackStart, end: fallbackStart.adding(days: 30))
        switch lesson.validity {
        case .always: break
        case .terms(let ids): mode = .terms; terms = ids
        case .range(let value): mode = .range; range = value
        case .unknown: mode = .unknown
        }
        validityMode = mode
        termIDs = terms
        rangeStart = range.start
        rangeEnd = range.end
        room = lesson.room ?? ""
        building = lesson.building ?? ""
        teacher = lesson.teacher ?? ""
        lessonType = lesson.lessonType
        notes = lesson.notes ?? ""
        bringList = lesson.bringList
    }

    /// A new lesson in `timetable`. Subject defaults (room, building, teacher) are applied for the enabled fields.
    public init(newIn timetable: Timetable, context: NewLessonContext, schedule: BellSchedule?, subject: Subject?,
                firstWeekday: Weekday, id: Lesson.ID, today: LocalDate) {
        lessonID = id
        timetableID = timetable.id
        isNew = true
        let firstDay = DayChoices.keys(for: timetable, firstWeekday: firstWeekday).first ?? .weekday(.monday)
        let startDay = context.day ?? firstDay
        subjectID = context.subjectID ?? subject?.id
        day = startDay
        cycleWeeks = context.cycleWeek.map { [$0] } ?? []
        if let slot = context.slot {
            self.slot = SlotDraft(slot: slot)
        } else {
            self.slot = SlotDraft(defaultFor: timetable, schedule: schedule)
        }
        let fallbackStart = today
        validityMode = .always
        termIDs = []
        rangeStart = fallbackStart
        rangeEnd = fallbackStart.adding(days: 30)
        room = ""
        building = ""
        teacher = ""
        lessonType = nil
        notes = ""
        bringList = []
        base = Lesson(id: id, meta: EditorEntities.placeholderMeta, timetableID: timetable.id,
                      subjectID: subject?.id ?? Subject.ID(UUID()), occurrence: LessonOccurrenceRule(day: startDay),
                      slot: .time(start: SlotDraft.defaultStart, end: SlotDraft.defaultEnd))
        if let subject { applySubjectDefaults(subject, visibility: timetable.fieldVisibility) }
    }

    /// Fills room/building/teacher from `subject` for fields the timetable shows and that are still empty.
    public mutating func applySubjectDefaults(_ subject: Subject, visibility: FieldVisibility) {
        if visibility.isVisible(.room), EditorText.trimmedOrNil(room) == nil { room = subject.defaultRoom ?? "" }
        if visibility.isVisible(.building), EditorText.trimmedOrNil(building) == nil { building = subject.defaultBuilding ?? "" }
        if visibility.isVisible(.teacher), EditorText.trimmedOrNil(teacher) == nil { teacher = subject.defaultTeacher ?? "" }
    }

    /// Problems that block saving.
    public func issues(in timetable: Timetable) -> [Issue] {
        var found: [Issue] = []
        if subjectID == nil { found.append(.noSubject) }
        switch validityMode {
        case .terms where termIDs.isEmpty: found.append(.noTerms)
        case .range where rangeEnd < rangeStart: found.append(.emptyRange)
        default: break
        }
        return found
    }

    /// Problems of the time slot.
    public var slotIssues: [SlotDraft.Issue] { slot.issues }

    /// `true` when nothing blocks saving.
    public func canSave(in timetable: Timetable) -> Bool {
        issues(in: timetable).isEmpty && slotIssues.isEmpty
    }

    /// The lesson to store, or `nil` while required input is missing. Fields hidden by the timetable keep their
    /// stored value.
    public func makeLesson(in timetable: Timetable) -> Lesson? {
        guard canSave(in: timetable), let subjectID, let slot = slot.slot else { return nil }
        let visibility = timetable.fieldVisibility
        var lesson = base
        lesson.subjectID = subjectID
        var weeks: Set<Int>?
        if case .weekCycle(let cycle) = timetable.rotation {
            let allWeeks = Set(1...max(1, cycle.length))
            let chosen = cycleWeeks.intersection(allWeeks)
            weeks = (chosen.isEmpty || chosen == allWeeks) ? nil : chosen
        }
        lesson.occurrence = LessonOccurrenceRule(day: day, cycleWeeks: weeks)
        lesson.slot = slot
        switch validityMode {
        case .always: lesson.validity = .always
        case .terms: lesson.validity = .terms(termIDs)
        case .range: lesson.validity = .range(LocalDateRange(start: rangeStart, end: rangeEnd))
        case .unknown: break
        }
        if visibility.isVisible(.room) { lesson.room = EditorText.trimmedOrNil(room) }
        if visibility.isVisible(.building) { lesson.building = EditorText.trimmedOrNil(building) }
        if visibility.isVisible(.teacher) { lesson.teacher = EditorText.trimmedOrNil(teacher) }
        if visibility.isVisible(.lessonType) { lesson.lessonType = lessonType }
        if visibility.isVisible(.notes) { lesson.notes = EditorText.trimmedOrNil(notes) }
        if visibility.isVisible(.bringList) { lesson.bringList = EditorText.cleanedList(bringList) }
        return lesson
    }
}

/// An overlap the lesson being edited would cause.
public struct LessonConflictInfo: Equatable, Sendable {
    public var dayKey: DayKey
    public var cycleWeek: Int?
    /// Subject names of the other lessons it overlaps with (sorted, may repeat).
    public var otherSubjectNames: [String]
}

/// Live conflict detection for the lesson editor ("warn, never block").
public enum LessonConflicts {
    /// The overlaps involving `lesson` if it were stored into `database` (replacing the stored lesson with the
    /// same ID, if any).
    public static func conflicts(for lesson: Lesson, in database: TabulaDatabase, context: CalendarContext) -> [LessonConflictInfo] {
        var candidate = database
        if let index = candidate.lessons.firstIndex(where: { $0.id == lesson.id }) {
            candidate.lessons[index] = lesson
        } else {
            candidate.lessons.append(lesson)
        }
        guard let resolver = ScheduleResolver(database: candidate, timetableID: lesson.timetableID, context: context) else {
            return []
        }
        let subjects = Dictionary(candidate.subjects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let lessonsByID = Dictionary(candidate.lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ConflictDetector.templateConflicts(in: resolver)
            .filter { $0.lessonIDs.contains(lesson.id) }
            .map { conflict in
                let names = conflict.lessonIDs.filter { $0 != lesson.id }.compactMap { id in
                    lessonsByID[id].flatMap { subjects[$0.subjectID] }
                }
                return LessonConflictInfo(dayKey: conflict.dayKey, cycleWeek: conflict.cycleWeek, otherSubjectNames: names.sorted())
            }
    }
}
