import Foundation

// Share DTOs (wire format v1, docs/specs/SHARE_FORMAT.md §3–4).
//
// These types are separate from the persisted entities: no IDs, no sync metadata. Entities reference each
// other by **index** into the payload's arrays (subjects, bell schedules, terms, lessons) and periods by a
// payload-wide **period key**, so a payload carries no UUIDs at all. Import (`ShareImport.materialize`)
// assigns fresh IDs and metadata. Small value types without IDs (`RotationScheme`, `DayKey`, `TaskDue`,
// `RepeatRule`, `SubjectSymbol`, `TextValue`, calendar values, vocabularies) are reused as Swift types; their
// wire encoding is defined here, independently of the persisted encoding.

/// A shared timetable, format version 1. Arrays are in canonical order (the exporter's order; indices refer
/// to it). Encode with `ShareCodec.encode(_:)`, decode with `ShareCodec.decode(_:)` (which validates).
public struct SharePayloadV1: Hashable, Sendable {
    /// The payload format version this type reads and writes (wire key `v`).
    public static let version = 1

    /// The timetable itself.
    public var timetable: ShareTimetable
    /// Subjects; lessons, tasks and exams refer to them by index.
    public var subjects: [ShareSubject]
    /// Bell schedules; the time structure refers to them by index.
    public var bellSchedules: [ShareBellSchedule]
    /// Recurring lessons; tasks refer to them by index.
    public var lessons: [ShareLesson]
    /// Terms; lesson validity refers to them by index.
    public var terms: [ShareTerm]
    /// Holidays and other breaks (imported as breaks of the new timetable).
    public var breaks: [ShareBreak]
    /// `true` when the sender chose "Include tasks" (then `tasks`/`exams` are meaningful, possibly empty).
    public var includesTasks: Bool
    /// Open tasks (only when `includesTasks`).
    public var tasks: [ShareTask]
    /// Upcoming exams (only when `includesTasks`).
    public var exams: [ShareExam]

    /// Creates a payload.
    public init(timetable: ShareTimetable, subjects: [ShareSubject] = [], bellSchedules: [ShareBellSchedule] = [],
                lessons: [ShareLesson] = [], terms: [ShareTerm] = [], breaks: [ShareBreak] = [],
                includesTasks: Bool = false, tasks: [ShareTask] = [], exams: [ShareExam] = []) {
        self.timetable = timetable
        self.subjects = subjects
        self.bellSchedules = bellSchedules
        self.lessons = lessons
        self.terms = terms
        self.breaks = breaks
        self.includesTasks = includesTasks
        self.tasks = tasks
        self.exams = exams
    }
}

/// The shared timetable's own fields (wire key `t`).
public struct ShareTimetable: Hashable, Sendable {
    /// Name (`n`).
    public var name: String
    /// Emoji (`e`).
    public var emoji: String?
    /// Enabled weekdays (`d`, ascending ISO numbers).
    public var enabledDays: Set<Weekday>
    /// Rotation (`ro`, omitted for `.none`).
    public var rotation: RotationScheme
    /// First day of a rotation week (`ws`, ISO weekday; omitted when Monday; absent = Monday). Optional key added
    /// within `v` = 1 (pre-freeze); see `Timetable.rotationWeekStart`.
    public var rotationWeekStart: Weekday
    /// Bell schedules or free-form times (`ts`).
    public var timeStructure: ShareTimeStructure
    /// Visible optional lesson fields (`fv`, ascending, omitted when empty).
    public var fieldVisibility: Set<LessonField>
    /// Default view (`dv`).
    public var defaultView: TimetableViewKind
    /// Density (`de`).
    public var density: Density
    /// Palette pack (`pp`).
    public var palettePackID: PalettePackID?

    /// Creates the timetable part of a payload.
    public init(name: String, emoji: String? = nil, enabledDays: Set<Weekday> = Weekday.workweek,
                rotation: RotationScheme = .none, rotationWeekStart: Weekday = .monday, timeStructure: ShareTimeStructure,
                fieldVisibility: Set<LessonField> = [], defaultView: TimetableViewKind = .grid,
                density: Density = .comfortable, palettePackID: PalettePackID? = nil) {
        self.name = name
        self.emoji = emoji
        self.enabledDays = enabledDays
        self.rotation = rotation
        self.rotationWeekStart = rotationWeekStart
        self.timeStructure = timeStructure
        self.fieldVisibility = fieldVisibility
        self.defaultView = defaultView
        self.density = density
        self.palettePackID = palettePackID
    }
}

/// How lesson times are defined (wire key `ts`): `{"k":"b","d":0,"w":{"5":1}}` or `{"k":"f","m":90}`.
public enum ShareTimeStructure: Hashable, Sendable {
    /// Bell schedules by index into `SharePayloadV1.bellSchedules`, with per-weekday replacements.
    case bellSchedule(defaultIndex: Int, perWeekday: [Weekday: Int])
    /// Free-form times with a default lesson length (1…1439 minutes).
    case freeForm(defaultDurationMinutes: Int)
}

/// A shared subject.
public struct ShareSubject: Hashable, Sendable {
    /// Name (`n`).
    public var name: String
    /// Short name (`sn`).
    public var shortName: String?
    /// Colour (`c`, `#RRGGBB[AA]`).
    public var color: ColorValue
    /// Colour name: a palette colour key (`ck`) or user text (`cl`).
    public var colorName: TextValue?
    /// Emoji (`se`) or SF Symbol name (`si`).
    public var symbol: SubjectSymbol?
    /// Default room (`r`).
    public var defaultRoom: String?
    /// Default building (`bd`).
    public var defaultBuilding: String?
    /// Default teacher (`te`).
    public var defaultTeacher: String?
    /// Notes (`no`).
    public var notes: String?
    /// Display order (`o`): the dense rank of the source subject's `sortIndex` (0 ..< `ShareLimits.maxSubjects`;
    /// equal ranks allowed); `nil` = never ordered. Optional key added within `v` = 1 (P3-2, 2026-10-16): payloads
    /// without it import with `nil` (alphabetical), and older apps ignore it.
    public var sortIndex: Int?

    /// Creates a shared subject.
    public init(name: String, shortName: String? = nil, color: ColorValue, colorName: TextValue? = nil,
                symbol: SubjectSymbol? = nil, defaultRoom: String? = nil, defaultBuilding: String? = nil,
                defaultTeacher: String? = nil, notes: String? = nil, sortIndex: Int? = nil) {
        self.name = name
        self.shortName = shortName
        self.color = color
        self.colorName = colorName
        self.symbol = symbol
        self.defaultRoom = defaultRoom
        self.defaultBuilding = defaultBuilding
        self.defaultTeacher = defaultTeacher
        self.notes = notes
        self.sortIndex = sortIndex
    }
}

/// A shared bell schedule.
public struct ShareBellSchedule: Hashable, Sendable {
    /// Name (`n`).
    public var name: String
    /// Periods (`p`), ascending by start.
    public var periods: [SharePeriod]

    /// Creates a shared bell schedule.
    public init(name: String, periods: [SharePeriod]) {
        self.name = name
        self.periods = periods
    }
}

/// A period of a shared bell schedule.
public struct SharePeriod: Hashable, Sendable {
    /// Period key (`k`, ≥ 0): unique within the schedule, shared with the corresponding period of other
    /// schedules (the persisted period-ID convention); lessons refer to periods by key.
    public var key: Int
    /// Label (`l`).
    public var label: String?
    /// Start (`a`).
    public var start: LocalTime
    /// End (`z`).
    public var end: LocalTime
    /// Kind (`t`, omitted when `lesson`).
    public var kind: PeriodKind

    /// Creates a shared period.
    public init(key: Int, label: String? = nil, start: LocalTime, end: LocalTime, kind: PeriodKind = .lesson) {
        self.key = key
        self.label = label
        self.start = start
        self.end = end
        self.kind = kind
    }
}

/// Where a shared lesson sits in the day: period key + span (`p`, `n`) or explicit times (`a`, `z`).
public enum ShareLessonSlot: Hashable, Sendable {
    /// Starts at the period with `key` and covers `span` (1…`ShareLimits.maxSpan`) lesson periods.
    case period(key: Int, span: Int)
    /// Explicit wall-clock times.
    case time(start: LocalTime, end: LocalTime)
}

/// On which dates a shared lesson exists: always (keys absent), terms by index (`vt`), or a range (`vr`).
public enum ShareValidity: Hashable, Sendable {
    /// Every date.
    case always
    /// Only inside these terms (indices into `SharePayloadV1.terms`).
    case terms(Set<Int>)
    /// Only inside this inclusive range.
    case range(LocalDateRange)
}

/// A shared recurring lesson.
public struct ShareLesson: Hashable, Sendable {
    /// Subject index (`s`).
    public var subject: Int
    /// Day: weekday (`w`) or cycle day (`c`).
    public var day: DayKey
    /// Cycle weeks (`cw`, ascending); `nil` = every week.
    public var cycleWeeks: Set<Int>?
    /// Slot.
    public var slot: ShareLessonSlot
    /// Validity.
    public var validity: ShareValidity
    /// Room (`r`).
    public var room: String?
    /// Building (`bd`).
    public var building: String?
    /// Teacher (`te`).
    public var teacher: String?
    /// Lesson type (`ty`).
    public var lessonType: LessonType?
    /// Notes (`no`).
    public var notes: String?
    /// Bring list (`br`, omitted when empty).
    public var bringList: [String]

    /// Creates a shared lesson.
    public init(subject: Int, day: DayKey, cycleWeeks: Set<Int>? = nil, slot: ShareLessonSlot,
                validity: ShareValidity = .always, room: String? = nil, building: String? = nil,
                teacher: String? = nil, lessonType: LessonType? = nil, notes: String? = nil, bringList: [String] = []) {
        self.subject = subject
        self.day = day
        self.cycleWeeks = cycleWeeks
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

/// A shared term.
public struct ShareTerm: Hashable, Sendable {
    /// Name (`n`).
    public var name: String
    /// Inclusive range (`a`…`z`).
    public var range: LocalDateRange

    /// Creates a shared term.
    public init(name: String, range: LocalDateRange) {
        self.name = name
        self.range = range
    }
}

/// A shared holiday/break.
public struct ShareBreak: Hashable, Sendable {
    /// Name (`n`).
    public var name: String
    /// Inclusive range (`a`…`z`).
    public var range: LocalDateRange
    /// Kind (`t`, omitted when `holiday`).
    public var kind: BreakKind

    /// Creates a shared break.
    public init(name: String, range: LocalDateRange, kind: BreakKind = .holiday) {
        self.name = name
        self.range = range
        self.kind = kind
    }
}

/// A reference from a shared task to one occurrence of a shared lesson (`ll`: `{"l":index,"d":"date"}`).
public struct ShareLessonLink: Hashable, Sendable {
    /// Lesson index (`l`).
    public var lesson: Int
    /// Occurrence date (`d`).
    public var date: LocalDate

    /// Creates a link.
    public init(lesson: Int, date: LocalDate) {
        self.lesson = lesson
        self.date = date
    }
}

/// A shared task. Completion, attachments and reminder settings are personal and never shared.
public struct ShareTask: Hashable, Sendable {
    /// Title (`n`).
    public var title: String
    /// Kind (`t`, omitted when `homework`).
    public var kind: TaskKind
    /// Subject index (`s`).
    public var subject: Int?
    /// Due date (`dd`) and optional time (`dt`).
    public var due: TaskDue?
    /// Linked lesson occurrence (`ll`).
    public var linkedLesson: ShareLessonLink?
    /// Priority (`pr`, omitted when `normal`).
    public var priority: TaskPriority
    /// Notes (`no`).
    public var notes: String?
    /// Repetition (`rp`: `{"f":frequency,"i":interval,"w":[weekdays],"u":"until"}`).
    public var repeatRule: RepeatRule?
    /// Subtask titles in display order (`st`).
    public var subtasks: [String]

    /// Creates a shared task.
    public init(title: String, kind: TaskKind = .homework, subject: Int? = nil, due: TaskDue? = nil,
                linkedLesson: ShareLessonLink? = nil, priority: TaskPriority = .normal, notes: String? = nil,
                repeatRule: RepeatRule? = nil, subtasks: [String] = []) {
        self.title = title
        self.kind = kind
        self.subject = subject
        self.due = due
        self.linkedLesson = linkedLesson
        self.priority = priority
        self.notes = notes
        self.repeatRule = repeatRule
        self.subtasks = subtasks
    }
}

/// A shared exam. Completion and reminder settings are personal and never shared.
public struct ShareExam: Hashable, Sendable {
    /// Title (`n`).
    public var title: String
    /// Kind (`t`, omitted when `written`).
    public var kind: ExamKind
    /// Subject index (`s`).
    public var subject: Int?
    /// Date (`d`).
    public var date: LocalDate
    /// Start (`a`).
    public var start: LocalTime?
    /// End (`z`).
    public var end: LocalTime?
    /// Room (`r`).
    public var room: String?
    /// Building (`bd`).
    public var building: String?
    /// Topics (`tp`, omitted when empty).
    public var topics: [String]
    /// Notes (`no`).
    public var notes: String?

    /// Creates a shared exam.
    public init(title: String, kind: ExamKind = .written, subject: Int? = nil, date: LocalDate,
                start: LocalTime? = nil, end: LocalTime? = nil, room: String? = nil, building: String? = nil,
                topics: [String] = [], notes: String? = nil) {
        self.title = title
        self.kind = kind
        self.subject = subject
        self.date = date
        self.start = start
        self.end = end
        self.room = room
        self.building = building
        self.topics = topics
        self.notes = notes
    }
}
