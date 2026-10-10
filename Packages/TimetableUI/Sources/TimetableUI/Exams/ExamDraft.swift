// Edit state of the exam editor: subject, title, kind, date, optional start / end, room, building, topics (add, remove,
// reorder), notes and the reminder override. Pure, Linux-tested.
//
// Rules: title is required; an end needs a start and must be after it (same rule as `Validation`); blank room /
// building / notes are stored as absent; blank topics are dropped. Fields the timetable hides (`FieldVisibility`:
// room, building, notes) keep their stored value when the exam is saved. Everything the editor does not show
// (completion, unknown fields, sync metadata) is preserved from the exam being edited.
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

    /// The exam to store (`AppModel.apply(.upsert(_:))` stamps the metadata).
    public func makeExam(visibility: FieldVisibility) -> Exam? {
        guard canSave, let cleanTitle = EditorText.trimmedOrNil(title) else { return nil }
        var exam = base ?? Exam(id: examID, meta: EditorEntities.placeholderMeta, title: cleanTitle, date: date)
        exam.timetableID = timetableID
        exam.subjectID = subjectID
        exam.title = cleanTitle
        exam.kind = ExamKind(rawValue: kindRaw)
        exam.date = date
        exam.start = hasStart ? start : nil
        exam.end = hasStart && hasEnd ? end : nil
        if visibility.isVisible(.room) { exam.room = EditorText.trimmedOrNil(room) }
        if visibility.isVisible(.building) { exam.building = EditorText.trimmedOrNil(building) }
        if visibility.isVisible(.notes) { exam.notes = EditorText.trimmedOrNil(notes) }
        exam.topics = EditorText.cleanedList(topics.map(\.text))
        exam.reminderOverride = reminderOverride
        return exam
    }
}
