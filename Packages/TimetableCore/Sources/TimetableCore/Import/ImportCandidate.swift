import Foundation

// What the deterministic parser makes of a `RecognizedTable` (PHASE9_PLAN decision 4): a candidate timetable that
// the review screen shows and the user approves. Every lesson comes from one cell of the input; nothing is invented.

/// Where the days are in the table.
public enum ImportOrientation: String, Hashable, Sendable, Codable {
    /// One row per day, periods across (the Slovak aSc layout).
    case daysAsRows
    /// One column per day, periods down.
    case daysAsColumns
}

/// The editable text fields of an imported lesson.
public enum ImportField: String, Hashable, Sendable, Codable, CaseIterable {
    case subject, room, teacher, building, lessonType, notes

    /// String Catalog key of the field name (`import.field.room`).
    public var l10nKey: String { "import.field.\(rawValue)" }
}

/// Why a cell's confidence is below 1. Raw values are stable (JSON, LLM seam); the UI shows `l10nKey`.
public enum ImportConfidenceReason: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    /// The OCR engine was unsure of the text.
    case ocrLow
    /// Look-alike characters were corrected (O → 0, l → 1); see the lesson's alternatives.
    case ocrConfusion
    /// The cell text could not be split cleanly into subject, room, teacher and type.
    case ambiguousSplit
    /// The subject looks like an abbreviation of a known subject; see the alternatives.
    case abbreviation
    /// The day header was missing or unreadable; the day comes from the cell's position.
    case unknownDay
    /// The period header was missing or unreadable; the period comes from the cell's position.
    case unknownPeriod
    /// The lesson overlaps another lesson, or its times do not fit the bell schedule.
    case timeConflict
    /// The lesson's times were inferred or assumed, not printed.
    case timeInferred
    /// An AI suggestion changed or questioned this cell (Tier A); check it.
    case normaliser

    /// String Catalog key (`import.reason.ocrLow`).
    public var l10nKey: String { "import.reason.\(rawValue)" }

    /// Confidence multiplier applied by the parser and by reconciliation.
    public var penalty: Double {
        switch self {
        case .ocrLow: return 1 // already in the OCR confidence
        case .ocrConfusion: return 0.55
        case .ambiguousSplit: return 0.55
        case .abbreviation: return 0.85
        case .unknownDay: return 0.5
        case .unknownPeriod: return 0.7
        case .timeConflict: return 0.5
        case .timeInferred: return 0.95
        case .normaliser: return 0.9
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Where an alternative reading comes from.
public enum ImportAlternativeKind: String, Hashable, Sendable, Codable {
    /// OCR look-alike characters ("204" or "2O4").
    case ocrReading
    /// A known subject this abbreviation may stand for ("Bio" or "Biology").
    case abbreviation
    /// Another way to split the cell text into subject and other fields.
    case split
    /// Suggested by the `CellNormaliser` (Tier A).
    case normaliser
}

/// Other plausible values for one field of a lesson. `values[0]` is the value currently applied.
public struct ImportAlternative: Hashable, Sendable, Codable {
    public var field: ImportField
    public var kind: ImportAlternativeKind
    public var values: [String]

    public init(field: ImportField, kind: ImportAlternativeKind, values: [String]) {
        self.field = field
        self.kind = kind
        self.values = values
    }
}

/// The input cell a lesson was read from (grid indices of `RecognizedTable.gridCells`).
public struct ImportCellRef: Hashable, Sendable, Codable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// How a period's times were obtained.
public enum ImportTimeSource: String, Hashable, Sendable, Codable {
    /// Start and end were printed.
    case printed
    /// The start was printed; the end was inferred from the gaps between starts.
    case inferredEnd
    /// No times were printed; a default schedule was assumed (the user must check it).
    case assumed
}

/// One period of the inferred bell schedule. `number` is the printed period number (or the position, 1-based).
public struct ImportPeriod: Hashable, Sendable, Codable, Identifiable {
    public var number: Int
    public var start: LocalTime
    public var end: LocalTime
    public var timeSource: ImportTimeSource

    public var id: Int { number }

    public init(number: Int, start: LocalTime, end: LocalTime, timeSource: ImportTimeSource) {
        self.number = number
        self.start = start
        self.end = end
        self.timeSource = timeSource
    }
}

/// One lesson read from one cell. A cell with week markers ("MAT (A)" / "FYZ (B)") gives one lesson per week.
public struct ImportLesson: Hashable, Sendable, Codable, Identifiable {
    /// Stable within a candidate (input order); questions and edits refer to it.
    public var id: Int
    public var day: Weekday
    /// First period (`ImportPeriod.number`).
    public var period: Int
    /// Number of consecutive periods covered (≥ 1).
    public var span: Int
    /// Cycle weeks (1 = A, 2 = B); `nil` = every week.
    public var cycleWeeks: Set<Int>?
    public var subject: String
    public var room: String?
    public var teacher: String?
    public var building: String?
    public var lessonType: LessonType?
    public var notes: String?
    /// The cell's OCR text, verbatim. "Apply to identical cells" compares it.
    public var sourceText: String
    public var source: ImportCellRef
    /// The cell's OCR confidence 0…1 (input to `confidence`).
    public var ocrConfidence: Double
    /// 0…1. Below `ImportCandidate.reviewThreshold` the review screen highlights the cell.
    public var confidence: Double
    public var reasons: Set<ImportConfidenceReason>
    public var alternatives: [ImportAlternative]

    public init(id: Int, day: Weekday, period: Int, span: Int = 1, cycleWeeks: Set<Int>? = nil, subject: String,
                room: String? = nil, teacher: String? = nil, building: String? = nil, lessonType: LessonType? = nil,
                notes: String? = nil, sourceText: String, source: ImportCellRef, ocrConfidence: Double = 1, confidence: Double = 1,
                reasons: Set<ImportConfidenceReason> = [], alternatives: [ImportAlternative] = []) {
        self.id = id
        self.day = day
        self.period = period
        self.span = span
        self.cycleWeeks = cycleWeeks
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.building = building
        self.lessonType = lessonType
        self.notes = notes
        self.sourceText = sourceText
        self.source = source
        self.ocrConfidence = ocrConfidence
        self.confidence = confidence
        self.reasons = reasons
        self.alternatives = alternatives
    }

    /// The value of `field` (`lessonType` as its raw value); `nil` when empty.
    public subscript(field: ImportField) -> String? {
        get {
            switch field {
            case .subject: return subject.isEmpty ? nil : subject
            case .room: return room
            case .teacher: return teacher
            case .building: return building
            case .lessonType: return lessonType?.rawValue
            case .notes: return notes
            }
        }
        set {
            let value = newValue.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            switch field {
            case .subject: subject = value ?? ""
            case .room: room = value
            case .teacher: teacher = value
            case .building: building = value
            case .lessonType: lessonType = value.map(LessonType.init(rawValue:))
            case .notes: notes = value
            }
        }
    }

    /// `true` when the review screen should highlight the cell.
    public var needsReview: Bool { confidence < ImportCandidate.reviewThreshold }
}

/// Findings about the whole table (shown as notices above the grid).
public enum ImportNotice: String, Hashable, Sendable, Codable, CaseIterable {
    /// No text was recognised at all.
    case emptyInput
    /// No day names were found; nothing could be imported.
    case noDaysFound
    /// No lesson times were printed; a default schedule (08:00, 45 min, 10 min breaks) was assumed.
    case timesAssumed
    /// Period end times were inferred from the gaps between start times.
    case endTimesInferred
    /// The days repeat (two blocks of days): imported as an A/B week rotation; check which week is A.
    case weekRotationDetected

    /// String Catalog key (`import.notice.timesAssumed`).
    public var l10nKey: String { "import.notice.\(rawValue)" }
}

/// The parser's result. Hand it to the review model; nothing is saved until the user approves.
public struct ImportCandidate: Hashable, Sendable, Codable {
    /// Cells below this confidence are highlighted for review.
    public static let reviewThreshold = 0.6

    public var orientation: ImportOrientation
    /// The detected days, in table order.
    public var days: [Weekday]
    /// The inferred bell schedule, ascending.
    public var periods: [ImportPeriod]
    public var lessons: [ImportLesson]
    /// 2 when A/B weeks were detected (cycle weeks 1…2 in `ImportLesson.cycleWeeks`), else `nil`.
    public var weekCycleLength: Int?
    public var notices: [ImportNotice]
    /// The table's languages (copied from the input).
    public var languages: [String]

    public init(orientation: ImportOrientation = .daysAsRows, days: [Weekday] = [], periods: [ImportPeriod] = [],
                lessons: [ImportLesson] = [], weekCycleLength: Int? = nil, notices: [ImportNotice] = [],
                languages: [String] = []) {
        self.orientation = orientation
        self.days = days
        self.periods = periods
        self.lessons = lessons
        self.weekCycleLength = weekCycleLength
        self.notices = notices
        self.languages = languages
    }
}

/// Options of `TimetableImportParser.parse`.
public struct ImportParserOptions: Hashable, Sendable, Codable {
    /// Fields the user shows. Text that looks like a hidden field (e.g. a teacher when Teacher is off) goes to
    /// `notes` instead of being dropped.
    public var enabledFields: Set<LessonField>
    /// Subject names the user already has; a short subject matching one ("Bio" → "Biology") becomes a question.
    public var knownSubjects: [String]

    public init(enabledFields: Set<LessonField> = [.room, .teacher, .lessonType, .building, .notes],
                knownSubjects: [String] = []) {
        self.enabledFields = enabledFields
        self.knownSubjects = knownSubjects
    }
}
