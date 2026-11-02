// The import review model (Phase 9 I1, PHASE9_PLAN decision 5): pure state behind the review screen (I2 renders
// it). Editable lessons, targeted questions, "apply to identical cells", the counts the UI shows, and `approve()`,
// which returns a `SharePayloadV1` for `DatabaseMutation.importShared` (Add as new / Replace with backup).
// Foundation only, Linux-tested (ImportReviewTests). Nothing is saved here.
import Foundation
import TimetableCore

/// A targeted question about one or more lessons ("Room: “204” or “2O4”?"). Answering picks one of `options`.
public struct ImportQuestion: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case ocrReading, abbreviation, split, suggestion
    }

    /// Stable while the question is open (kind, field and options).
    public var id: String
    public var kind: Kind
    public var field: ImportField
    /// The choices, user data shown verbatim; `options[0]` is the value currently applied.
    public var options: [String]
    /// Every lesson the answer applies to (identical questions are merged).
    public var lessonIDs: [Int]
    /// The question text (String Catalog key + arguments, `ImportL10n`).
    public var prompt: LocalizedText
}

/// The numbers the review screen shows.
public struct ImportReviewCounts: Hashable, Sendable {
    public var lessons: Int
    /// Lessons below `ImportCandidate.reviewThreshold`.
    public var needsReview: Int
    public var questions: Int
    /// Distinct subject names.
    public var subjects: Int
    public var days: Int
    public var periods: Int
}

/// The review state. Value type: the screen keeps it in `@State` and calls the mutating methods.
public struct ImportReview: Hashable, Sendable {
    public private(set) var candidate: ImportCandidate
    /// The new timetable's name (the user can edit it before approving).
    public var timetableName: String
    public var emoji: String?

    public init(candidate: ImportCandidate, timetableName: String, emoji: String? = nil) {
        self.candidate = candidate
        self.timetableName = timetableName
        self.emoji = emoji
    }

    public var lessons: [ImportLesson] { candidate.lessons }
    public var periods: [ImportPeriod] { candidate.periods }
    public var notices: [ImportNotice] { candidate.notices }

    public func lesson(_ id: Int) -> ImportLesson? { candidate.lessons.first { $0.id == id } }

    /// Lessons read from cells with the same text as lesson `id` (including `id` itself), in candidate order.
    public func identicalLessonIDs(to id: Int) -> [Int] {
        guard let text = lesson(id).map({ Self.key($0.sourceText) }) else { return [] }
        return candidate.lessons.filter { Self.key($0.sourceText) == text }.map(\.id)
    }

    public var counts: ImportReviewCounts {
        ImportReviewCounts(lessons: candidate.lessons.count, needsReview: candidate.lessons.filter(\.needsReview).count,
                           questions: questions.count, subjects: Set(candidate.lessons.map(\.subject)).count,
                           days: Set(candidate.lessons.map(\.day)).count, periods: candidate.periods.count)
    }

    /// Open questions, one per distinct (kind, field, options), in the order of their first lesson.
    public var questions: [ImportQuestion] {
        var result: [ImportQuestion] = []
        var index: [String: Int] = [:]
        for lesson in candidate.lessons {
            for alternative in lesson.alternatives where alternative.values.count > 1 {
                let kind = Self.kind(alternative.kind)
                let id = ([kind.rawValue, alternative.field.rawValue] + alternative.values).joined(separator: "\u{1F}")
                if let existing = index[id] {
                    result[existing].lessonIDs.append(lesson.id)
                    continue
                }
                index[id] = result.count
                result.append(ImportQuestion(id: id, kind: kind, field: alternative.field, options: alternative.values,
                                             lessonIDs: [lesson.id], prompt: Self.prompt(kind, alternative, lesson)))
            }
        }
        return result
    }

    // MARK: Editing

    /// Sets `field` of lesson `id` (and of every identical cell when `applyToIdentical`). The edited lessons count
    /// as reviewed: open questions about that field go away and confidence is recomputed.
    public mutating func setValue(_ value: String?, field: ImportField, lesson id: Int, applyToIdentical: Bool = false) {
        let ids = applyToIdentical ? identicalLessonIDs(to: id) : [id]
        for index in candidate.lessons.indices where ids.contains(candidate.lessons[index].id) {
            candidate.lessons[index][field] = value
            Self.markReviewed(&candidate.lessons[index], field: field)
        }
    }

    /// Answers a question: applies `option` to every lesson it lists.
    public mutating func answer(_ questionID: String, with option: String) {
        guard let question = questions.first(where: { $0.id == questionID }), question.options.contains(option) else { return }
        for index in candidate.lessons.indices where question.lessonIDs.contains(candidate.lessons[index].id) {
            candidate.lessons[index][question.field] = option
            Self.markReviewed(&candidate.lessons[index], field: question.field)
        }
    }

    /// Keeps the current value (`options[0]`) for every lesson the question lists.
    public mutating func dismiss(_ questionID: String) {
        guard let question = questions.first(where: { $0.id == questionID }) else { return }
        answer(questionID, with: question.options[0])
    }

    /// Marks lesson `id` (or all identical cells) as checked by the user without changing it.
    public mutating func confirm(lesson id: Int, applyToIdentical: Bool = false) {
        let ids = applyToIdentical ? identicalLessonIDs(to: id) : [id]
        for index in candidate.lessons.indices where ids.contains(candidate.lessons[index].id) {
            candidate.lessons[index].alternatives = []
            candidate.lessons[index].reasons = []
            candidate.lessons[index].ocrConfidence = 1
            candidate.lessons[index].confidence = 1
        }
    }

    /// Removes lesson `id` (or all identical cells), e.g. a header the parser mistook for a lesson.
    public mutating func removeLesson(_ id: Int, applyToIdentical: Bool = false) {
        let ids = Set(applyToIdentical ? identicalLessonIDs(to: id) : [id])
        candidate.lessons.removeAll { ids.contains($0.id) }
    }

    /// Changes the day, first period or span of lesson `id`. Invalid periods are ignored.
    public mutating func move(lesson id: Int, day: Weekday, period: Int, span: Int) {
        guard let index = candidate.lessons.firstIndex(where: { $0.id == id }),
              let first = candidate.periods.firstIndex(where: { $0.number == period }),
              span >= 1, first + span <= candidate.periods.count else { return }
        candidate.lessons[index].day = day
        candidate.lessons[index].period = period
        candidate.lessons[index].span = span
        candidate.lessons[index].reasons.subtract([.unknownDay, .unknownPeriod, .timeConflict])
        Self.rescore(&candidate.lessons[index])
    }

    /// Sets the times of period `number`; ignored unless `start < end` and the order of periods is kept.
    public mutating func setPeriodTimes(_ number: Int, start: LocalTime, end: LocalTime) {
        guard let index = candidate.periods.firstIndex(where: { $0.number == number }), start < end else { return }
        if index > 0, candidate.periods[index - 1].end > start { return }
        if index + 1 < candidate.periods.count, candidate.periods[index + 1].start < end { return }
        candidate.periods[index].start = start
        candidate.periods[index].end = end
        candidate.periods[index].timeSource = .printed
    }

    // MARK: Approve

    /// The payload for the existing share import path. `bellScheduleName` is the localised default schedule name.
    /// Throws `ShareError` when the result does not validate (shown like a share import error).
    public func approve(bellScheduleName: String) throws(ShareError) -> SharePayloadV1 {
        try ImportPayloadBuilder.payload(from: candidate, name: timetableName, bellScheduleName: bellScheduleName, emoji: emoji)
    }

    // MARK: Private

    private static func key(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func kind(_ kind: ImportAlternativeKind) -> ImportQuestion.Kind {
        switch kind {
        case .ocrReading: return .ocrReading
        case .abbreviation: return .abbreviation
        case .split: return .split
        case .normaliser: return .suggestion
        }
    }

    private static func prompt(_ kind: ImportQuestion.Kind, _ alternative: ImportAlternative, _ lesson: ImportLesson) -> LocalizedText {
        let field = LocalizedArgument.text(LocalizedText(key: alternative.field.l10nKey))
        let values = alternative.values
        switch kind {
        case .ocrReading:
            return LocalizedText(key: ImportL10n.questionOCRReading, args: [field, .string(values[0]), .string(values[1])])
        case .abbreviation:
            return LocalizedText(key: ImportL10n.questionAbbreviation, args: [.string(values[0]), .string(values[1])])
        case .split:
            return LocalizedText(key: ImportL10n.questionSplit, args: [.string(lesson.sourceText)])
        case .suggestion:
            return LocalizedText(key: ImportL10n.questionSuggestion, args: [field, .string(lesson.sourceText)])
        }
    }

    private static func markReviewed(_ lesson: inout ImportLesson, field: ImportField) {
        lesson.alternatives.removeAll { $0.field == field }
        switch field {
        case .subject: lesson.reasons.subtract([.abbreviation, .ambiguousSplit])
        case .room, .teacher, .building: lesson.reasons.subtract([.ambiguousSplit])
        case .lessonType, .notes: break
        }
        if !lesson.alternatives.contains(where: { $0.kind == .ocrReading }) { lesson.reasons.remove(.ocrConfusion) }
        if !lesson.alternatives.contains(where: { $0.kind == .normaliser }) { lesson.reasons.remove(.normaliser) }
        lesson.reasons.remove(.ocrLow)
        lesson.ocrConfidence = 1 // the user has read this cell
        rescore(&lesson)
    }

    private static func rescore(_ lesson: inout ImportLesson) {
        lesson.confidence = ImportScoring.confidence(ocr: lesson.ocrConfidence, reasons: lesson.reasons)
    }
}
