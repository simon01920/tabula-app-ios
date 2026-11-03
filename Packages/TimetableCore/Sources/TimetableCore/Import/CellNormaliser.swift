import Foundation

// The LLM seam (AI_IMPORT pipeline steps 4–5). Only low-confidence cells go out, as text JSON (never the image).
// Tier A (Foundation Models, App target, I2) and Tier D (`DeterministicNormaliser`, no-op) implement it.
// Reconciliation never adds lessons and never applies text that is not in the cell (see `ImportReconciliation`).

/// One low-confidence cell sent to the normaliser.
public struct NormalisationCell: Hashable, Sendable, Codable {
    /// `ImportLesson.id`; the suggestion must echo it.
    public var id: Int
    /// The cell's OCR text, verbatim.
    public var text: String
    /// The parser's current split.
    public var subject: String
    public var room: String?
    public var teacher: String?
    public var lessonType: String?
    public var reasons: [ImportConfidenceReason]

    public init(id: Int, text: String, subject: String, room: String? = nil, teacher: String? = nil,
                lessonType: String? = nil, reasons: [ImportConfidenceReason] = []) {
        self.id = id
        self.text = text
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.lessonType = lessonType
        self.reasons = reasons
    }
}

/// The normaliser's input.
public struct NormalisationRequest: Hashable, Sendable, Codable {
    public var cells: [NormalisationCell]
    /// BCP-47 languages of the table.
    public var languages: [String]
    /// Subject names the user already has (expansion targets for abbreviations).
    public var knownSubjects: [String]
    /// Allowed `lessonType` values (`LessonType.knownValues` raw values).
    public var lessonTypes: [String]

    public init(cells: [NormalisationCell], languages: [String] = [], knownSubjects: [String] = [],
                lessonTypes: [String] = LessonType.knownValues.map(\.rawValue)) {
        self.cells = cells
        self.languages = languages
        self.knownSubjects = knownSubjects
        self.lessonTypes = lessonTypes
    }
}

/// A constrained answer for one field: a value, or "unknown" with alternatives (never a guess).
/// JSON: `{"kind":"value","value":"204"}` or `{"kind":"unknown","alternatives":["204","2O4"]}`.
public enum NormalisedValue: Hashable, Sendable, Codable {
    case value(String)
    case unknown(alternatives: [String])

    private enum CodingKeys: String, CodingKey { case kind, value, alternatives }
    private enum Kind: String, Codable { case value, unknown }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .value: self = .value(try c.decode(String.self, forKey: .value))
        case .unknown: self = .unknown(alternatives: try c.decodeIfPresent([String].self, forKey: .alternatives) ?? [])
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let value):
            try c.encode(Kind.value, forKey: .kind)
            try c.encode(value, forKey: .value)
        case .unknown(let alternatives):
            try c.encode(Kind.unknown, forKey: .kind)
            try c.encode(alternatives, forKey: .alternatives)
        }
    }
}

/// The normaliser's answer for one cell. `nil` fields = no opinion.
public struct NormalisationSuggestion: Hashable, Sendable, Codable {
    public var id: Int
    public var subject: NormalisedValue?
    public var room: NormalisedValue?
    public var teacher: NormalisedValue?
    public var lessonType: NormalisedValue?

    public init(id: Int, subject: NormalisedValue? = nil, room: NormalisedValue? = nil,
                teacher: NormalisedValue? = nil, lessonType: NormalisedValue? = nil) {
        self.id = id
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.lessonType = lessonType
    }
}

/// Normalises low-confidence cells. Implementations must not invent cells; the reconciler drops unknown IDs anyway.
public protocol CellNormaliser: Sendable {
    func normalise(_ request: NormalisationRequest) async throws -> [NormalisationSuggestion]
}

/// Tier D: no model; the deterministic result stands and the review screen asks the questions.
public struct DeterministicNormaliser: CellNormaliser {
    public init() {}

    public func normalise(_ request: NormalisationRequest) async throws -> [NormalisationSuggestion] { [] }
}
