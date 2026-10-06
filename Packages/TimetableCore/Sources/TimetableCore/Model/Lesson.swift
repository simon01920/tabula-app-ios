import Foundation

/// A recurring lesson: subject + when (rotation day, slot) + validity + optional fields.
///
/// Optional fields: `nil` or empty means "inherit the subject default, else absent". The field-visibility
/// rule is applied by the UI; placeholders are never stored.
public struct Lesson: SyncEntity {
    public typealias ID = EntityID<Lesson>
    public static let entityType: EntityType = .lesson

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Owning timetable.
    public var timetableID: Timetable.ID
    /// Subject taught (same timetable).
    public var subjectID: Subject.ID
    /// Day key and optional cycle weeks.
    public var occurrence: LessonOccurrenceRule
    /// Period(s) of the bell schedule, or explicit times.
    public var slot: LessonSlot
    /// Date restriction (always, some terms, a date range).
    public var validity: LessonValidity
    /// Room; empty → subject default.
    public var room: String?
    /// Building/faculty; empty → subject default.
    public var building: String?
    /// Teacher; empty → subject default.
    public var teacher: String?
    /// Lecture/seminar/lab/…
    public var lessonType: LessonType?
    /// Free-form notes.
    public var notes: String?
    /// Items to bring (feeds the "pack tonight" reminder). Order is the user's.
    public var bringList: [String]

    /// Creates a lesson.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID, subjectID: Subject.ID,
                occurrence: LessonOccurrenceRule, slot: LessonSlot, validity: LessonValidity = .always,
                room: String? = nil, building: String? = nil, teacher: String? = nil,
                lessonType: LessonType? = nil, notes: String? = nil, bringList: [String] = []) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.subjectID = subjectID
        self.occurrence = occurrence
        self.slot = slot
        self.validity = validity
        self.room = room
        self.building = building
        self.teacher = teacher
        self.lessonType = lessonType
        self.notes = notes
        self.bringList = bringList
    }
}

/// Where a lesson sits in the day.
///
/// JSON: `{"kind":"period","periodID":"…","span":2}` or `{"kind":"time","start":"08:00","end":"09:30"}`.
public enum LessonSlot: Hashable, Sendable {
    /// Starts at period `periodID` and covers `span` (≥ 1) consecutive **lesson** periods of the applicable
    /// bell schedule; the occurrence runs from the first period's start to the last one's end, including any
    /// break periods in between.
    case period(Period.ID, span: Int)
    /// Explicit wall-clock times; `end > start` (no lesson spans midnight).
    case time(start: LocalTime, end: LocalTime)
}

extension LessonSlot: Codable {
    private enum CodingKeys: String, CodingKey { case kind, periodID, span, start, end }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "period":
            self = .period(try container.decode(Period.ID.self, forKey: .periodID),
                           span: try container.decode(Int.self, forKey: .span))
        case "time":
            self = .time(start: try container.decode(LocalTime.self, forKey: .start),
                         end: try container.decode(LocalTime.self, forKey: .end))
        default:
            throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "LessonSlot")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .period(periodID, span):
            try container.encode("period", forKey: .kind)
            try container.encode(periodID, forKey: .periodID)
            try container.encode(span, forKey: .span)
        case let .time(start, end):
            try container.encode("time", forKey: .kind)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        }
    }
}

/// On which dates a recurring lesson exists (before rotation and overrides).
///
/// JSON: `{"kind":"always"}`, `{"kind":"terms","termIDs":[…ascending…]}` or
/// `{"kind":"range","range":{"end":"…","start":"…"}}`.
public enum LessonValidity: Hashable, Sendable {
    /// Every date.
    case always
    /// Only on dates inside one of these terms (e.g. winter semester only).
    case terms(Set<Term.ID>)
    /// Only on dates inside this inclusive range.
    case range(LocalDateRange)
}

extension LessonValidity: Codable {
    private enum CodingKeys: String, CodingKey { case kind, termIDs, range }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "always": self = .always
        case "terms": self = .terms(Set(try container.decode([Term.ID].self, forKey: .termIDs)))
        case "range": self = .range(try container.decode(LocalDateRange.self, forKey: .range))
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "LessonValidity")
        }
    }

    /// Encodes the tagged union (`termIDs` ascending).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .always:
            try container.encode("always", forKey: .kind)
        case .terms(let ids):
            try container.encode("terms", forKey: .kind)
            try container.encodeSorted(ids, forKey: .termIDs)
        case .range(let range):
            try container.encode("range", forKey: .kind)
            try container.encode(range, forKey: .range)
        }
    }
}

/// A term or semester of a timetable (lesson validity, rotation context, exam periods).
public struct Term: SyncEntity {
    public typealias ID = EntityID<Term>
    public static let entityType: EntityType = .term

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Owning timetable.
    public var timetableID: Timetable.ID
    /// Name (user text, e.g. "Winter semester").
    public var name: String
    /// Inclusive date range.
    public var range: LocalDateRange

    /// Creates a term.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID, name: String, range: LocalDateRange) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.name = name
        self.range = range
    }
}

/// A holiday/vacation/exam-period range during which regular lessons do not take place.
public struct CalendarBreak: SyncEntity {
    public typealias ID = EntityID<CalendarBreak>
    public static let entityType: EntityType = .calendarBreak

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Timetable it applies to; `nil` = every timetable.
    public var timetableID: Timetable.ID?
    /// Name (user text, e.g. "Christmas holidays").
    public var name: String
    /// Inclusive date range.
    public var range: LocalDateRange
    /// Holiday, vacation, exam period, no school, … (open).
    public var kind: BreakKind

    /// Creates a calendar break.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID? = nil, name: String, range: LocalDateRange,
                kind: BreakKind = .holiday) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.name = name
        self.range = range
        self.kind = kind
    }
}
