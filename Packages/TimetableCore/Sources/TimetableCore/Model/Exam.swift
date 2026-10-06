import Foundation

/// An exam, test or quiz.
public struct Exam: SyncEntity {
    public typealias ID = EntityID<Exam>
    public static let entityType: EntityType = .exam

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Linked timetable; `nil` = not tied to one.
    public var timetableID: Timetable.ID?
    /// Linked subject.
    public var subjectID: Subject.ID?
    /// Title (user text).
    public var title: String
    /// Written, oral, test, … (open).
    public var kind: ExamKind
    /// Exam date.
    public var date: LocalDate
    /// Start time, if known.
    public var start: LocalTime?
    /// End time, if known; must be after `start` when both are set.
    public var end: LocalTime?
    /// Room.
    public var room: String?
    /// Building/faculty.
    public var building: String?
    /// Topics to study (user text, in the user's order).
    public var topics: [String]
    /// Notes (user text).
    public var notes: String?
    /// Per-exam reminder override; `nil` = follow the matching `ReminderRule`s.
    public var reminderOverride: ReminderOverride?
    /// When the user marked it done; `nil` = upcoming/open.
    public var completedAt: Date?

    /// Creates an exam.
    public init(id: ID, meta: EntityMeta, timetableID: Timetable.ID? = nil, subjectID: Subject.ID? = nil,
                title: String, kind: ExamKind = .written, date: LocalDate, start: LocalTime? = nil,
                end: LocalTime? = nil, room: String? = nil, building: String? = nil, topics: [String] = [],
                notes: String? = nil, reminderOverride: ReminderOverride? = nil, completedAt: Date? = nil) {
        self.id = id
        self.meta = meta
        self.timetableID = timetableID
        self.subjectID = subjectID
        self.title = title
        self.kind = kind
        self.date = date
        self.start = start
        self.end = end
        self.room = room
        self.building = building
        self.topics = topics
        self.notes = notes
        self.reminderOverride = reminderOverride
        self.completedAt = completedAt
    }

    /// `true` when `completedAt` is set.
    public var isCompleted: Bool { completedAt != nil }
}
