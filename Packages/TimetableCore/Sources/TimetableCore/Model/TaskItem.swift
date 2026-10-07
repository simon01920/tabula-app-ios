import Foundation

/// A homework, assignment or to-do. (Deliberately not named `Task`, which would shadow Swift concurrency.)
///
/// `subtasks` and `attachments` are child records with their own `id` + `meta`, set-merged by ID during
/// sync. They are encoded in canonical order (`sortIndex`, then `id`); display order is `sortIndex`.
public struct TaskItem: SyncEntity {
    public typealias ID = EntityID<TaskItem>
    public static let entityType: EntityType = .task

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Title (user text).
    public var title: String
    /// Homework, assignment, to-do, … (open).
    public var kind: TaskKind
    /// Linked subject.
    public var subjectID: Subject.ID?
    /// Linked timetable (filtering); `nil` = not tied to a timetable.
    public var timetableID: Timetable.ID?
    /// Due date or date-time; `nil` = no due date.
    public var due: TaskDue?
    /// The lesson occurrence the task belongs to ("for next Maths lesson").
    public var linkedLesson: LessonLink?
    /// Priority.
    public var priority: TaskPriority
    /// Notes (user text).
    public var notes: String?
    /// Repetition; `nil` = one-off. (`repeat` is a Swift keyword, hence the name.)
    public var repeatRule: RepeatRule?
    /// When it was completed; `nil` = open.
    public var completedAt: Date?
    /// Checklist items.
    public var subtasks: [Subtask]
    /// Attachments (files live outside the database; see `AttachmentRef`).
    public var attachments: [AttachmentRef]
    /// Per-task reminder override; `nil` = follow the matching `ReminderRule`s.
    public var reminderOverride: ReminderOverride?

    /// Creates a task.
    public init(id: ID, meta: EntityMeta, title: String, kind: TaskKind = .homework, subjectID: Subject.ID? = nil,
                timetableID: Timetable.ID? = nil, due: TaskDue? = nil, linkedLesson: LessonLink? = nil,
                priority: TaskPriority = .normal, notes: String? = nil, repeatRule: RepeatRule? = nil,
                completedAt: Date? = nil, subtasks: [Subtask] = [], attachments: [AttachmentRef] = [],
                reminderOverride: ReminderOverride? = nil) {
        self.id = id
        self.meta = meta
        self.title = title
        self.kind = kind
        self.subjectID = subjectID
        self.timetableID = timetableID
        self.due = due
        self.linkedLesson = linkedLesson
        self.priority = priority
        self.notes = notes
        self.repeatRule = repeatRule
        self.completedAt = completedAt
        self.subtasks = subtasks
        self.attachments = attachments
        self.reminderOverride = reminderOverride
    }

    /// `true` when `completedAt` is set.
    public var isCompleted: Bool { completedAt != nil }

    private enum CodingKeys: String, CodingKey {
        case id, meta, title, kind, subjectID, timetableID, due, linkedLesson, priority, notes, repeatRule,
             completedAt, subtasks, attachments, reminderOverride
    }

    /// Encodes with children in canonical order (`sortIndex`, then `id`).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(meta, forKey: .meta)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(subjectID, forKey: .subjectID)
        try container.encodeIfPresent(timetableID, forKey: .timetableID)
        try container.encodeIfPresent(due, forKey: .due)
        try container.encodeIfPresent(linkedLesson, forKey: .linkedLesson)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(repeatRule, forKey: .repeatRule)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(subtasks.sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }, forKey: .subtasks)
        try container.encode(attachments.sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) },
                             forKey: .attachments)
        try container.encodeIfPresent(reminderOverride, forKey: .reminderOverride)
    }
}

/// When a task is due. JSON: `{"kind":"date","date":"…"}` or `{"kind":"dateTime","date":"…","time":"…"}`.
///
/// **Open union** (since the pre-freeze QA): an unknown kind, a missing kind or a non-object decodes as
/// `.unknown` and re-encodes unchanged. Consumers treat such a task as **undated**: no reminders, no due
/// date in lists, no next repetition; share export leaves the due date out. A known kind with a malformed
/// payload is a decoding error.
public enum TaskDue: Hashable, Sendable {
    /// Due some time on `date` (reminders use rule times).
    case date(LocalDate)
    /// Due at a wall-clock time.
    case dateTime(LocalDate, LocalTime)
    /// A due kind from a newer app version; preserved, treated as "no due date".
    case unknown(JSONValue)

    /// The due date; `nil` for `.unknown` (treat the task as undated).
    public var date: LocalDate? {
        switch self {
        case .date(let date), .dateTime(let date, _): return date
        case .unknown: return nil
        }
    }

    /// The due time, if any.
    public var time: LocalTime? {
        if case .dateTime(_, let time) = self { return time }
        return nil
    }

    /// `false` for `.unknown`.
    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

extension TaskDue: Codable {
    private enum CodingKeys: String, CodingKey { case kind, date, time }

    /// Decodes a known kind, or preserves the whole value as `.unknown`.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil else {
            self = .unknown(try JSONValue(from: decoder))
            return
        }
        switch kind {
        case "date": self = .date(try container.decode(LocalDate.self, forKey: .date))
        case "dateTime":
            self = .dateTime(try container.decode(LocalDate.self, forKey: .date),
                             try container.decode(LocalTime.self, forKey: .time))
        default: self = .unknown(try JSONValue(from: decoder))
        }
    }

    /// Encodes the tagged union; `.unknown` re-encodes its JSON unchanged.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .date(let date):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("date", forKey: .kind)
            try container.encode(date, forKey: .date)
        case let .dateTime(date, time):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("dateTime", forKey: .kind)
            try container.encode(date, forKey: .date)
            try container.encode(time, forKey: .time)
        case .unknown(let raw):
            try raw.encode(to: encoder)
        }
    }
}

/// A reference to one occurrence of a recurring lesson. JSON: `{"date":"…","lessonID":"…"}`.
public struct LessonLink: Hashable, Sendable, Codable {
    /// The recurring lesson.
    public var lessonID: Lesson.ID
    /// The occurrence date.
    public var date: LocalDate

    /// Creates a link.
    public init(lessonID: Lesson.ID, date: LocalDate) {
        self.lessonID = lessonID
        self.date = date
    }
}

/// How a task repeats after completion.
///
/// JSON: `{"frequency":"weekly","interval":1,"weekdays":[1,3],"until":"…"}` (`until` optional).
public struct RepeatRule: Hashable, Sendable {
    /// Daily, weekly, monthly, … (open).
    public var frequency: RepeatFrequency
    /// Every `interval` units, ≥ 1.
    public var interval: Int
    /// For weekly repeats: the weekdays; empty = the weekday of the due date.
    public var weekdays: Set<Weekday>
    /// Last date a repetition may fall on; `nil` = forever.
    public var until: LocalDate?

    /// Creates a repeat rule.
    public init(frequency: RepeatFrequency, interval: Int = 1, weekdays: Set<Weekday> = [], until: LocalDate? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.until = until
    }
}

extension RepeatRule: Codable {
    private enum CodingKeys: String, CodingKey { case frequency, interval, weekdays, until }

    /// Encodes with `weekdays` ascending.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval, forKey: .interval)
        try container.encodeSorted(weekdays, forKey: .weekdays)
        try container.encodeIfPresent(until, forKey: .until)
    }
}

/// A checklist item of a task (child record).
public struct Subtask: ChildEntity {
    public typealias ID = EntityID<Subtask>

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Title (user text).
    public var title: String
    /// Completion instant; `nil` = open.
    public var completedAt: Date?
    /// Display order (ascending).
    public var sortIndex: Int

    /// Creates a subtask.
    public init(id: ID, meta: EntityMeta, title: String, completedAt: Date? = nil, sortIndex: Int = 0) {
        self.id = id
        self.meta = meta
        self.title = title
        self.completedAt = completedAt
        self.sortIndex = sortIndex
    }
}

/// A reference to an attachment (child record). The bytes live outside the database (App Group file /
/// CloudKit asset); only metadata is persisted here.
public struct AttachmentRef: ChildEntity {
    public typealias ID = EntityID<AttachmentRef>

    /// Stable identifier (also names the stored file).
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// Photo, file, link, voice note, … (open).
    public var kind: AttachmentKind
    /// Optional display title (user text).
    public var title: String?
    /// File name inside the attachments container (for stored files).
    public var fileName: String?
    /// URL string for `.link` attachments (never opened automatically).
    public var url: String?
    /// Uniform type identifier string (e.g. `public.jpeg`).
    public var contentType: String?
    /// Size in bytes, for quota accounting.
    public var byteCount: Int64?
    /// Display order (ascending).
    public var sortIndex: Int

    /// Creates an attachment reference.
    public init(id: ID, meta: EntityMeta, kind: AttachmentKind, title: String? = nil, fileName: String? = nil,
                url: String? = nil, contentType: String? = nil, byteCount: Int64? = nil, sortIndex: Int = 0) {
        self.id = id
        self.meta = meta
        self.kind = kind
        self.title = title
        self.fileName = fileName
        self.url = url
        self.contentType = contentType
        self.byteCount = byteCount
        self.sortIndex = sortIndex
    }
}
