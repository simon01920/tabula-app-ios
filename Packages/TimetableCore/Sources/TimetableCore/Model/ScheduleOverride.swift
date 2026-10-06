import Foundation

/// A one-off change to one date of a timetable (substitution, cancellation, room change, short day, …).
///
/// Several overrides may target the same date; Stage 2B applies them in the order
/// `followDay`, then `useBellSchedule`, then `cancelDay`/`cancelLesson`/`modifyLesson`/`addLesson`.
public struct ScheduleOverride: SyncEntity {
    public typealias ID = EntityID<ScheduleOverride>
    public static let entityType: EntityType = .scheduleOverride

    /// Stable identifier (also the occurrence ID source for `addLesson`).
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Timetable affected.
    public var timetableID: Timetable.ID
    /// Date affected.
    public var date: LocalDate
    /// What changes.
    public var change: OverrideChange

    /// Creates an override.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID, date: LocalDate, change: OverrideChange) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.date = date
        self.change = change
    }
}

/// The change an override makes. **Open union:** an unknown `kind` decodes as `.unknown` and round-trips.
///
/// JSON (`"kind"` discriminator):
/// - `{"kind":"cancelLesson","lessonID":"…"}`
/// - `{"kind":"modifyLesson","lessonID":"…","patch":{…LessonPatch…}}`
/// - `{"kind":"addLesson","lesson":{…OneOffLesson…}}`
/// - `{"kind":"cancelDay","note":"…"}` (`note` optional)
/// - `{"kind":"useBellSchedule","bellScheduleID":"…"}`
/// - `{"kind":"followDay","day":{…DayKey…},"cycleWeek":2}` (`cycleWeek` optional)
public enum OverrideChange: Hashable, Sendable {
    /// The lesson's occurrence on this date does not take place.
    case cancelLesson(Lesson.ID)
    /// The lesson's occurrence on this date is changed (room, teacher, time, subject, …).
    case modifyLesson(Lesson.ID, LessonPatch)
    /// An extra lesson on this date only.
    case addLesson(OneOffLesson)
    /// No lessons on this date (e.g. sports day); optional user note.
    case cancelDay(note: String?)
    /// This date uses another bell schedule of the timetable (e.g. shortened lessons).
    case useBellSchedule(BellSchedule.ID)
    /// This date follows another day's lessons ("Wednesday runs Friday's timetable"). `cycleWeek`
    /// (1-based) picks the week of a week cycle; `nil` = the date's own cycle week.
    case followDay(DayKey, cycleWeek: Int?)
    /// A change written by a newer app version. Ignored by the resolver, preserved byte-for-byte in meaning.
    case unknown(JSONValue)

    /// `true` for `.unknown`.
    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

extension OverrideChange: Codable {
    private enum CodingKeys: String, CodingKey { case kind, lessonID, patch, lesson, note, bellScheduleID, day, cycleWeek }

    /// Decodes a known kind, or preserves the whole value as `.unknown` (also when it is not an object or
    /// `kind` is missing / not a string). A *known* kind with a malformed payload is a decoding error.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil else {
            self = .unknown(try JSONValue(from: decoder))
            return
        }
        switch kind {
        case "cancelLesson":
            self = .cancelLesson(try container.decode(Lesson.ID.self, forKey: .lessonID))
        case "modifyLesson":
            self = .modifyLesson(try container.decode(Lesson.ID.self, forKey: .lessonID),
                                 try container.decode(LessonPatch.self, forKey: .patch))
        case "addLesson":
            self = .addLesson(try container.decode(OneOffLesson.self, forKey: .lesson))
        case "cancelDay":
            self = .cancelDay(note: try container.decodeIfPresent(String.self, forKey: .note))
        case "useBellSchedule":
            self = .useBellSchedule(try container.decode(BellSchedule.ID.self, forKey: .bellScheduleID))
        case "followDay":
            self = .followDay(try container.decode(DayKey.self, forKey: .day),
                              cycleWeek: try container.decodeIfPresent(Int.self, forKey: .cycleWeek))
        default:
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    /// Encodes the tagged union; `.unknown` re-encodes its JSON unchanged.
    public func encode(to encoder: any Encoder) throws {
        if case .unknown(let raw) = self {
            try raw.encode(to: encoder)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cancelLesson(let lessonID):
            try container.encode("cancelLesson", forKey: .kind)
            try container.encode(lessonID, forKey: .lessonID)
        case let .modifyLesson(lessonID, patch):
            try container.encode("modifyLesson", forKey: .kind)
            try container.encode(lessonID, forKey: .lessonID)
            try container.encode(patch, forKey: .patch)
        case .addLesson(let lesson):
            try container.encode("addLesson", forKey: .kind)
            try container.encode(lesson, forKey: .lesson)
        case .cancelDay(let note):
            try container.encode("cancelDay", forKey: .kind)
            try container.encodeIfPresent(note, forKey: .note)
        case .useBellSchedule(let id):
            try container.encode("useBellSchedule", forKey: .kind)
            try container.encode(id, forKey: .bellScheduleID)
        case let .followDay(day, cycleWeek):
            try container.encode("followDay", forKey: .kind)
            try container.encode(day, forKey: .day)
            try container.encodeIfPresent(cycleWeek, forKey: .cycleWeek)
        case .unknown:
            break // handled above
        }
    }
}

/// Changes to one occurrence of a lesson. `nil` = keep the effective value.
///
/// A non-nil value replaces the effective value (after subject defaults). An **empty** string/array
/// explicitly clears the field for that occurrence (it does *not* fall back to the subject default).
public struct LessonPatch: Hashable, Sendable, Codable {
    /// Substitute subject.
    public var subjectID: Subject.ID?
    /// Moved slot.
    public var slot: LessonSlot?
    /// Changed room.
    public var room: String?
    /// Changed building.
    public var building: String?
    /// Substitute teacher.
    public var teacher: String?
    /// Changed lesson type.
    public var lessonType: LessonType?
    /// Note for this occurrence.
    public var notes: String?
    /// Changed bring-list.
    public var bringList: [String]?

    /// Creates a patch.
    public init(subjectID: Subject.ID? = nil, slot: LessonSlot? = nil, room: String? = nil,
                building: String? = nil, teacher: String? = nil, lessonType: LessonType? = nil,
                notes: String? = nil, bringList: [String]? = nil) {
        self.subjectID = subjectID
        self.slot = slot
        self.room = room
        self.building = building
        self.teacher = teacher
        self.lessonType = lessonType
        self.notes = notes
        self.bringList = bringList
    }

    /// `true` when the patch changes nothing.
    public var isEmpty: Bool { self == LessonPatch() }
}

/// An extra lesson that exists on a single date (`OverrideChange.addLesson`). Same field rules as `Lesson`.
public struct OneOffLesson: Hashable, Sendable, Codable {
    /// Subject taught.
    public var subjectID: Subject.ID
    /// Slot on that date.
    public var slot: LessonSlot
    /// Room; empty → subject default.
    public var room: String?
    /// Building; empty → subject default.
    public var building: String?
    /// Teacher; empty → subject default.
    public var teacher: String?
    /// Lesson type.
    public var lessonType: LessonType?
    /// Notes.
    public var notes: String?
    /// Items to bring.
    public var bringList: [String]

    /// Creates a one-off lesson.
    public init(subjectID: Subject.ID, slot: LessonSlot, room: String? = nil, building: String? = nil,
                teacher: String? = nil, lessonType: LessonType? = nil, notes: String? = nil,
                bringList: [String] = []) {
        self.subjectID = subjectID
        self.slot = slot
        self.room = room
        self.building = building
        self.teacher = teacher
        self.lessonType = lessonType
        self.notes = notes
        self.bringList = bringList
    }
}
