// AI_IMPORT Tier A (PHASE9_PLAN decision 1): Apple's on-device language model as TimetableCore's `CellNormaliser`.
// Only low-confidence cells go in, as text JSON (never the image); guided generation (`@Generable`) at temperature 0
// comes out; `ImportReconciliation` then applies only text that is verbatim in the cell and turns anything else into
// a question, so the model cannot invent lessons or values.
// Used only when `AppleIntelligenceStatus.current == .available` AND the model supports one of the table's
// languages (`supportsLocale`). Any error, including `GenerationError.unsupportedLanguageOrLocale` (iOS 26) and its
// iOS 27 successor `LanguageModelError.unsupportedLanguageOrLocale`, propagates; `ImportReconciliation.normalise`
// catches it and keeps the deterministic result (Tier D).
// @Generable / @Guide compile under xtool (ENVIRONMENT §117); macros are allowed here (App/Sources outside Debug/).
// API names checked in iPhoneOS27.0.sdk FoundationModels.swiftinterface (2026-11-02): LanguageModelSession
//   (init(model:tools:instructions: String?)), respond(to: String, generating:includeSchemaInPrompt:options:),
//   Response.content, GenerationOptions(samplingMode:temperature:maximumResponseTokens:), SystemLanguageModel
//   .supportsLocale(_:), Generable(description:), Guide(description:).
import Foundation
import FoundationModels
import TimetableCore

struct FoundationModelsNormaliser: CellNormaliser {
    enum Failure: Error { case unavailable, unsupportedLanguage }

    /// Cells per prompt: keeps each request well inside the on-device context window.
    static let batchSize = 12

    /// Whether Tier A may run for a table in `languages` (an empty list means "the app's language").
    static func canRun(languages: [String]) -> Bool {
        guard AppleIntelligenceStatus.current == .available else { return false }
        guard !languages.isEmpty else { return true }
        return languages.contains { SystemLanguageModel.default.supportsLocale(Locale(identifier: $0)) }
    }

    func normalise(_ request: NormalisationRequest) async throws -> [NormalisationSuggestion] {
        guard Self.canRun(languages: request.languages) else { throw Failure.unsupportedLanguage }
        var suggestions: [NormalisationSuggestion] = []
        var start = 0
        while start < request.cells.count {
            try Task.checkCancellation()
            var batch = request
            batch.cells = Array(request.cells[start..<min(start + Self.batchSize, request.cells.count)])
            suggestions += try await respond(batch)
            start += Self.batchSize
        }
        return suggestions
    }

    private func respond(_ request: NormalisationRequest) async throws -> [NormalisationSuggestion] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(request), as: UTF8.self)
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: json, generating: FMAnswer.self,
                                                 options: GenerationOptions(temperature: 0))
        let ids = Set(request.cells.map(\.id))
        return response.content.cells.filter { ids.contains($0.id) }.map { cell in
            NormalisationSuggestion(id: cell.id, subject: cell.subject.suggestion, room: cell.room.suggestion,
                                    teacher: cell.teacher.suggestion, lessonType: cell.lessonType.suggestion)
        }
    }

    static let instructions = """
        You split the text of school timetable cells into fields. The input is JSON: "cells" (id, the cell's OCR \
        text, the current subject/room/teacher/lessonType split and why it is uncertain), "knownSubjects" and \
        "lessonTypes". For every cell return its id and, for each field, a value copied exactly from the cell text. \
        Never invent text that is not in the cell, never translate, never expand abbreviations. If you are not sure, \
        leave value empty and list up to three readings from the cell text in alternatives. lessonType must be one \
        of lessonTypes or empty.
        """
}

// MARK: - Guided generation schema

@Generable(description: "The fields of each uncertain timetable cell")
struct FMAnswer {
    @Guide(description: "One entry per input cell, same ids")
    var cells: [FMCell]
}

@Generable(description: "One timetable cell split into fields")
struct FMCell {
    @Guide(description: "The id of the input cell")
    var id: Int
    var subject: FMField
    var room: FMField
    var teacher: FMField
    var lessonType: FMField
}

@Generable(description: "One field of a cell")
struct FMField {
    @Guide(description: "Text copied exactly from the cell, or empty when unsure or absent")
    var value: String
    @Guide(description: "Up to three possible readings from the cell text when unsure; otherwise empty")
    var alternatives: [String]
}

extension FMField {
    /// The core's constrained answer: a value, "unknown" with alternatives, or no opinion (`nil`).
    var suggestion: NormalisedValue? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return .value(text) }
        let options = alternatives.prefix(3).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return options.isEmpty ? nil : .unknown(alternatives: Array(options))
    }
}
