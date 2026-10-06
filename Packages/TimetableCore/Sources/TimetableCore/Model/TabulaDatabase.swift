import Foundation

/// The persisted schema root: every entity of the app plus the settings singleton.
///
/// - `schemaVersion` is `TabulaDatabase.currentSchemaVersion` (1) for data written by this version.
///   Decoding does **not** reject other versions; the repository decides (migration / read-only mode).
/// - **Deterministic encoding:** every entity array is written sorted by `id`, every set sorted, every
///   object's keys sorted (via `TabulaJSON`). The same logical database always yields the same bytes,
///   regardless of the order arrays were built in. (Duplicate IDs — reported by `validate()` — are the
///   one case where ordering is not total.)
/// - Missing arrays decode as empty.
/// - Tombstoned entities (`meta.isDeleted`) are part of the database.
public struct TabulaDatabase: Hashable, Sendable {
    /// The schema version written by this app version.
    public static let currentSchemaVersion = TimetableCoreInfo.schemaVersion

    /// Schema version of this data.
    public var schemaVersion: Int
    /// The settings singleton.
    public var settings: AppSettings
    /// Timetables.
    public var timetables: [Timetable]
    /// Subjects.
    public var subjects: [Subject]
    /// Bell schedules.
    public var bellSchedules: [BellSchedule]
    /// Recurring lessons.
    public var lessons: [Lesson]
    /// Terms / semesters.
    public var terms: [Term]
    /// Holidays and other breaks.
    public var breaks: [CalendarBreak]
    /// One-off schedule overrides.
    public var overrides: [ScheduleOverride]
    /// Tasks.
    public var tasks: [TaskItem]
    /// Exams.
    public var exams: [Exam]
    /// Reminder rules.
    public var reminderRules: [ReminderRule]

    /// Creates a database (empty collections by default).
    public init(schemaVersion: Int = TabulaDatabase.currentSchemaVersion, settings: AppSettings,
                timetables: [Timetable] = [], subjects: [Subject] = [], bellSchedules: [BellSchedule] = [],
                lessons: [Lesson] = [], terms: [Term] = [], breaks: [CalendarBreak] = [],
                overrides: [ScheduleOverride] = [], tasks: [TaskItem] = [], exams: [Exam] = [],
                reminderRules: [ReminderRule] = []) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.timetables = timetables
        self.subjects = subjects
        self.bellSchedules = bellSchedules
        self.lessons = lessons
        self.terms = terms
        self.breaks = breaks
        self.overrides = overrides
        self.tasks = tasks
        self.exams = exams
        self.reminderRules = reminderRules
    }

    /// A copy with every entity array sorted by `id` and task children in canonical order — the order
    /// that decoding the canonical encoding produces. `canonicalized() == decode(encode(self))`.
    public func canonicalized() -> TabulaDatabase {
        var copy = self
        copy.timetables.sort { $0.id < $1.id }
        copy.subjects.sort { $0.id < $1.id }
        copy.bellSchedules.sort { $0.id < $1.id }
        copy.lessons.sort { $0.id < $1.id }
        copy.terms.sort { $0.id < $1.id }
        copy.breaks.sort { $0.id < $1.id }
        copy.overrides.sort { $0.id < $1.id }
        copy.tasks.sort { $0.id < $1.id }
        for index in copy.tasks.indices {
            copy.tasks[index].subtasks.sort { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
            copy.tasks[index].attachments.sort { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
        }
        copy.exams.sort { $0.id < $1.id }
        copy.reminderRules.sort { $0.id < $1.id }
        return copy
    }

    /// Canonical JSON bytes (`TabulaJSON.makeEncoder(pretty:)`).
    public func encoded(pretty: Bool = false) throws -> Data {
        try TabulaJSON.makeEncoder(pretty: pretty).encode(self)
    }

    /// Decodes a database from JSON produced by `encoded()` (or any compatible writer).
    public static func decode(from data: Data) throws -> TabulaDatabase {
        try TabulaJSON.makeDecoder().decode(TabulaDatabase.self, from: data)
    }
}

extension TabulaDatabase: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, settings, timetables, subjects, bellSchedules, lessons, terms, breaks, overrides,
             tasks, exams, reminderRules
    }

    /// Decodes a database; absent arrays become empty.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        self.settings = try c.decode(AppSettings.self, forKey: .settings)
        self.timetables = try c.decodeIfPresent([Timetable].self, forKey: .timetables) ?? []
        self.subjects = try c.decodeIfPresent([Subject].self, forKey: .subjects) ?? []
        self.bellSchedules = try c.decodeIfPresent([BellSchedule].self, forKey: .bellSchedules) ?? []
        self.lessons = try c.decodeIfPresent([Lesson].self, forKey: .lessons) ?? []
        self.terms = try c.decodeIfPresent([Term].self, forKey: .terms) ?? []
        self.breaks = try c.decodeIfPresent([CalendarBreak].self, forKey: .breaks) ?? []
        self.overrides = try c.decodeIfPresent([ScheduleOverride].self, forKey: .overrides) ?? []
        self.tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        self.exams = try c.decodeIfPresent([Exam].self, forKey: .exams) ?? []
        self.reminderRules = try c.decodeIfPresent([ReminderRule].self, forKey: .reminderRules) ?? []
    }

    /// Encodes every array sorted by `id` (deterministic output).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(settings, forKey: .settings)
        try c.encode(timetables.sorted { $0.id < $1.id }, forKey: .timetables)
        try c.encode(subjects.sorted { $0.id < $1.id }, forKey: .subjects)
        try c.encode(bellSchedules.sorted { $0.id < $1.id }, forKey: .bellSchedules)
        try c.encode(lessons.sorted { $0.id < $1.id }, forKey: .lessons)
        try c.encode(terms.sorted { $0.id < $1.id }, forKey: .terms)
        try c.encode(breaks.sorted { $0.id < $1.id }, forKey: .breaks)
        try c.encode(overrides.sorted { $0.id < $1.id }, forKey: .overrides)
        try c.encode(tasks.sorted { $0.id < $1.id }, forKey: .tasks)
        try c.encode(exams.sorted { $0.id < $1.id }, forKey: .exams)
        try c.encode(reminderRules.sorted { $0.id < $1.id }, forKey: .reminderRules)
    }
}
