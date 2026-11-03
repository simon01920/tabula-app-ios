import Foundation

/// Merges `CellNormaliser` suggestions into a deterministic candidate (AI_IMPORT pipeline step 5).
///
/// Rules (so a model can never invent data):
/// - Suggestions for IDs that are not low-confidence cells of the candidate are ignored; no lesson is ever added.
/// - A suggested `.value` of at least 2 characters is **applied** only when it is part of the cell's OCR text (case,
///   diacritics and O/0, l/1 look-alikes ignored), and what is stored is the cell's own spelling of that part — or a
///   known `LessonType` for `lessonType`. Anything else (an expansion such as "Bio" → "Biology", a single character)
///   is only offered as an alternative, which the review screen turns into a question.
/// - `.unknown(alternatives)` adds the alternatives as a question and keeps the deterministic value.
/// - Confidence is recomputed from the remaining reasons (`.normaliser` replaces resolved split/OCR reasons).
public enum ImportReconciliation {
    /// The request for every lesson below `ImportCandidate.reviewThreshold`, in candidate order.
    public static func request(for candidate: ImportCandidate, options: ImportParserOptions = .init()) -> NormalisationRequest {
        let cells = candidate.lessons.filter(\.needsReview).map {
            NormalisationCell(id: $0.id, text: $0.sourceText, subject: $0.subject, room: $0.room, teacher: $0.teacher,
                              lessonType: $0.lessonType?.rawValue, reasons: $0.reasons.sorted())
        }
        return NormalisationRequest(cells: cells, languages: candidate.languages, knownSubjects: options.knownSubjects)
    }

    /// Runs `normaliser` on the low-confidence cells and reconciles. A failing normaliser (unsupported language,
    /// model unavailable) leaves the deterministic candidate unchanged.
    public static func normalise(_ candidate: ImportCandidate, using normaliser: some CellNormaliser,
                                 options: ImportParserOptions = .init()) async -> ImportCandidate {
        let request = request(for: candidate, options: options)
        guard !request.cells.isEmpty, let suggestions = try? await normaliser.normalise(request) else { return candidate }
        return apply(suggestions, to: candidate)
    }

    /// `candidate` with `suggestions` merged (see the type's rules).
    public static func apply(_ suggestions: [NormalisationSuggestion], to candidate: ImportCandidate) -> ImportCandidate {
        var result = candidate
        let eligible = Set(candidate.lessons.filter(\.needsReview).map(\.id))
        for suggestion in suggestions where eligible.contains(suggestion.id) {
            guard let index = result.lessons.firstIndex(where: { $0.id == suggestion.id }) else { continue }
            var lesson = result.lessons[index]
            var touched = false
            let pairs: [(ImportField, NormalisedValue?)] = [(.subject, suggestion.subject), (.room, suggestion.room),
                                                            (.teacher, suggestion.teacher), (.lessonType, suggestion.lessonType)]
            for (field, value) in pairs {
                guard let value else { continue }
                touched = merge(value, field: field, into: &lesson) || touched
            }
            if touched {
                lesson.reasons.insert(.normaliser)
                lesson.confidence = ImportScoring.confidence(ocr: lesson.ocrConfidence, reasons: lesson.reasons)
            }
            result.lessons[index] = lesson
        }
        return result
    }

    /// Returns `true` when something changed.
    private static func merge(_ value: NormalisedValue, field: ImportField, into lesson: inout ImportLesson) -> Bool {
        let current = lesson[field]
        switch value {
        case .value(let raw):
            let suggested = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // The model agrees with the current value (maybe in another spelling): keep it as it is.
            if let current, ImportText.lookAlikeFold(current) == ImportText.lookAlikeFold(suggested) { return false }
            // Applied text is the cell's own spelling of the matched span, never the model's.
            let applied = field == .lessonType
                ? (LessonType.knownValues.map(\.rawValue).contains(suggested) ? suggested : nil)
                : ImportText.verbatimSpan(of: suggested, in: lesson.sourceText)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = applied ?? suggested
            guard !text.isEmpty, text != current else { return false }
            if applied != nil {
                lesson[field] = text
                lesson.alternatives.removeAll { $0.field == field }
                if field == .subject || field == .room || field == .teacher {
                    lesson.reasons.remove(.ambiguousSplit)
                    // Text the parser parked in notes now has its field.
                    if field != .subject, let notes = lesson.notes {
                        let rest = notes.split(separator: "\n").map(String.init).filter { $0 != text }
                        lesson.notes = rest.isEmpty ? nil : rest.joined(separator: "\n")
                        lesson.alternatives.removeAll { $0.kind == .split && $0.values.contains { $0.hasSuffix(" " + text) } }
                    }
                }
                if !lesson.alternatives.contains(where: { $0.kind == .ocrReading }) { lesson.reasons.remove(.ocrConfusion) }
            } else {
                addAlternative([current ?? "", text], field: field, to: &lesson)
            }
            return true
        case .unknown(let alternatives):
            let values = alternatives.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0 != current }
            guard !values.isEmpty else { return false }
            addAlternative([current ?? ""] + values, field: field, to: &lesson)
            return true
        }
    }

    private static func addAlternative(_ values: [String], field: ImportField, to lesson: inout ImportLesson) {
        var unique: [String] = []
        for value in values where !unique.contains(value) { unique.append(value) }
        guard unique.count > 1 else { return }
        lesson.alternatives.removeAll { $0.field == field && $0.kind == .normaliser }
        lesson.alternatives.append(ImportAlternative(field: field, kind: .normaliser, values: unique))
    }
}

/// Confidence arithmetic shared by the parser, reconciliation and the review model.
public enum ImportScoring {
    /// OCR confidence under this adds `.ocrLow`.
    public static let lowOCR = 0.6

    /// `ocr` × the penalty of each reason, clamped to 0…1.
    public static func confidence(ocr: Double, reasons: Set<ImportConfidenceReason>) -> Double {
        min(1, max(0, reasons.sorted().reduce(ocr) { $0 * $1.penalty })) // sorted: Set order would change the last bits
    }
}
