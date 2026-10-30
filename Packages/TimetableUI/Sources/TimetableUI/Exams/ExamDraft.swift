// Edit state of the exam editor: subject, title, kind, date, optional start / end, room, building, topics (add, remove,
// reorder), notes and the reminder override. Pure, Linux-tested.
//
// Rules: title is required; an end needs a start and must be after it (same rule as `Validation`); blank room /
// building / notes are stored as absent; blank topics are dropped. The editor offers room, building and notes whatever
// the timetable's field visibility says (D10: visibility shapes summaries only). Everything the editor does not show
// (completion, unknown fields, sync metadata) is preserved from the exam being edited.
//
// "When" (M25): `timeMode` is a view over the existing start / end fields, with no schema change. During a lesson =
// the times of one lesson of that day (copied into start / end), Custom time = start and optional end, All day = no
// start. Only the times are stored.
import Foundation
import TimetableCore

public struct ExamDraft: Equatable, Sendable {
    /// One topic line; `id` only keeps list rows stable while editing.
    public struct Topic: Equatable, Sendable, Identifiable {
        public var id: Int
        public var text: String
        public init(id: Int, text: String) {
            self.id = id
            self.text = text
        }
    }

    /// A problem that blocks saving.
    public enum Issue: String, Equatable, Sendable, CaseIterable {
        case noTitle, endNotAfterStart
        /// Catalog key of the explanation.
        public var l10nKey: String { "exams.editor.issue.\(rawValue)" }
    }

    public let examID: Exam.ID
    public let isNew: Bool
    public var timetableID: Timetable.ID?
    public var subjectID: Subject.ID?
    public var title: String
    /// `ExamKind.rawValue` (open vocabulary).
    public var kindRaw: String
    public var date: LocalDate
    public var hasStart: Bool
    public var start: LocalTime
    public var hasEnd: Bool
    public var end: LocalTime
    public var room: String
    public var building: String
    public var topics: [Topic]
    public var notes: String
    public var reminderOverride: ReminderOverride?
    /// How the time is chosen (M25). Derived from the fields on opening; never stored.
    public private(set) var timeMode: ExamTimeMode
    /// The lesson chosen while `timeMode == .lesson`.
    public private(set) var chosenLessonID: OccurrenceID?
    private var nextTopicID: Int
    private let base: Exam?

    /// Edits `exam`.
    public init(exam: Exam) {
        examID = exam.id
        isNew = false
        base = exam
        timetableID = exam.timetableID
        subjectID = exam.subjectID
        title = exam.title
        kindRaw = exam.kind.rawValue
        date = exam.date
        hasStart = exam.start != nil
        start = exam.start ?? Self.defaultStart
        hasEnd = exam.start != nil && exam.end != nil
        end = exam.end ?? Self.defaultStart.adding(minutes: Self.defaultLength) ?? Self.defaultStart
        room = exam.room ?? ""
        building = exam.building ?? ""
        topics = exam.topics.enumerated().map { Topic(id: $0.offset, text: $0.element) }
        nextTopicID = exam.topics.count
        notes = exam.notes ?? ""
        reminderOverride = exam.reminderOverride
        timeMode = exam.start == nil ? .allDay : .custom
    }

    /// A new exam on `date` (default: a week from `today`), linked to `timetableID`.
    public init(newOn today: LocalDate, timetableID: Timetable.ID?, subjectID: Subject.ID? = nil,
                id: Exam.ID = Exam.ID(UUID())) {
        examID = id
        isNew = true
        base = nil
        self.timetableID = timetableID
        self.subjectID = subjectID
        title = ""
        kindRaw = ExamKind.written.rawValue
        date = today.adding(days: 7)
        hasStart = false
        start = Self.defaultStart
        hasEnd = false
        end = Self.defaultStart.adding(minutes: Self.defaultLength) ?? Self.defaultStart
        room = ""
        building = ""
        topics = []
        nextTopicID = 0
        notes = ""
        reminderOverride = nil
        timeMode = .allDay
    }

    static let defaultStart = LocalTime(hour: 8, minute: 0) ?? .midnight
    static let defaultLength = 60

    // MARK: Equatable (topic ids and the id counter do not count as edits)

    public static func == (lhs: ExamDraft, rhs: ExamDraft) -> Bool {
        lhs.examID == rhs.examID && lhs.timetableID == rhs.timetableID && lhs.subjectID == rhs.subjectID
            && lhs.title == rhs.title && lhs.kindRaw == rhs.kindRaw && lhs.date == rhs.date
            && lhs.hasStart == rhs.hasStart && (!lhs.hasStart || lhs.start == rhs.start)
            && lhs.hasEnd == rhs.hasEnd && (!lhs.hasEnd || lhs.end == rhs.end)
            && lhs.room == rhs.room && lhs.building == rhs.building && lhs.notes == rhs.notes
            && lhs.topics.map(\.text) == rhs.topics.map(\.text) && lhs.reminderOverride == rhs.reminderOverride
    }

    // MARK: Editing

    /// Kinds the picker offers: the known ones, plus the current value when it is a custom word.
    public var kindChoices: [ExamKind] {
        var choices = ExamKind.knownValues
        let current = ExamKind(rawValue: kindRaw)
        if !choices.contains(current) { choices.append(current) }
        return choices
    }

    /// Turns the start time on / off. Switching it off also drops the end.
    public mutating func setHasStart(_ on: Bool) {
        hasStart = on
        if !on { hasEnd = false }
    }

    /// Turns the end time on / off. Switching it on proposes one hour after the start.
    public mutating func setHasEnd(_ on: Bool) {
        guard !on || hasStart else { return }
        hasEnd = on
        if on, end <= start { end = start.adding(minutes: Self.defaultLength) ?? start }
    }

    // MARK: When (M25)

    /// The modes to offer for the lessons of the chosen date: "During a lesson" only when there is a lesson (or it is
    /// the current mode, so it never vanishes under the user).
    public func availableTimeModes(choices: [ExamLessonChoice]) -> [ExamTimeMode] {
        ExamTimeMode.allCases.filter { $0 != .lesson || !choices.isEmpty || timeMode == .lesson }
    }

    /// Switches the mode. Lesson: the lesson already chosen, else the one with the current times, else the first;
    /// Custom: keeps the current times (a start of 8:00 when there was none); All day: no start, no end.
    public mutating func setTimeMode(_ mode: ExamTimeMode, choices: [ExamLessonChoice]) {
        switch mode {
        case .allDay:
            setHasStart(false)
            chosenLessonID = nil
            timeMode = .allDay
        case .custom:
            setHasStart(true)
            chosenLessonID = nil
            timeMode = .custom
        case .lesson:
            let keep = choices.first { $0.id == chosenLessonID }
                ?? choices.first { hasStart && $0.start == start && hasEnd && $0.end == end } ?? choices.first
            if let keep { chooseLesson(keep) }
        }
    }

    /// Chooses a lesson: its times become the exam's start and end; an exam without a subject gets the lesson's.
    public mutating func chooseLesson(_ choice: ExamLessonChoice) {
        timeMode = .lesson
        chosenLessonID = choice.id
        hasStart = true
        start = choice.start
        hasEnd = true
        end = choice.end
        if subjectID == nil { subjectID = choice.subject.id }
    }

    /// Re-reads the mode against the lessons of the (possibly changed) date: a stored exam whose times are exactly one
    /// lesson's opens as "During a lesson"; a chosen lesson that is no longer on the date turns into Custom time.
    public mutating func syncTimeMode(choices: [ExamLessonChoice]) {
        switch timeMode {
        case .lesson:
            if let id = chosenLessonID, !choices.contains(where: { $0.id == id }) {
                chosenLessonID = nil
                timeMode = .custom
            }
        case .custom:
            if hasEnd, let match = choices.first(where: { $0.start == start && $0.end == end }) {
                chosenLessonID = match.id
                timeMode = .lesson
            }
        case .allDay:
            break
        }
    }

    public mutating func addTopic() {
        topics.append(Topic(id: nextTopicID, text: ""))
        nextTopicID += 1
    }

    public mutating func removeTopics(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where topics.indices.contains(index) { topics.remove(at: index) }
    }

    public mutating func moveTopics(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().compactMap { topics.indices.contains($0) ? topics[$0] : nil }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where topics.indices.contains(index) { topics.remove(at: index) }
        topics.insert(contentsOf: moving, at: max(0, min(topics.count, destination - before)))
    }

    // MARK: Saving

    public var issues: [Issue] {
        var found: [Issue] = []
        if EditorText.trimmedOrNil(title) == nil { found.append(.noTitle) }
        if hasStart, hasEnd, end <= start { found.append(.endNotAfterStart) }
        return found
    }

    public var canSave: Bool { issues.isEmpty }

    /// `completedAt` of the exam when the editor opened (the editor never changes it; `EditorStoreMerge`).
    public var openedCompletedAt: Date? { base?.completedAt }

    /// The exam to store (`AppModel.apply(.upsert(_:))` stamps the metadata). Room, building and notes are always
    /// saved: field visibility only shapes summaries, the editor offers every field (D10, U2-15).
    public func makeExam() -> Exam? {
        guard canSave, let cleanTitle = EditorText.trimmedOrNil(title) else { return nil }
        var exam = base ?? Exam(id: examID, meta: EditorEntities.placeholderMeta, title: cleanTitle, date: date)
        exam.timetableID = timetableID
        exam.subjectID = subjectID
        exam.title = cleanTitle
        exam.kind = ExamKind(rawValue: kindRaw)
        exam.date = date
        exam.start = hasStart ? start : nil
        exam.end = hasStart && hasEnd ? end : nil
        exam.room = EditorText.trimmedOrNil(room)
        exam.building = EditorText.trimmedOrNil(building)
        exam.notes = EditorText.trimmedOrNil(notes)
        exam.topics = EditorText.cleanedList(topics.map(\.text))
        exam.reminderOverride = reminderOverride
        return exam
    }
}
