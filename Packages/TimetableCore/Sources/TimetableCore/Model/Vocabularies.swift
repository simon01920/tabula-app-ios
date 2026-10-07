import Foundation

// Open vocabularies (see `OpenVocabulary`). Any string decodes and round-trips; `isKnown` is false for
// values introduced by a newer app version. Raw values are persisted — never rename one.

/// Kind of teaching session (university-style "Type" field). Open.
public struct LessonType: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let lecture = LessonType(rawValue: "lecture")
    public static let seminar = LessonType(rawValue: "seminar")
    public static let lab = LessonType(rawValue: "lab")
    public static let tutorial = LessonType(rawValue: "tutorial")

    public static let knownValues: [LessonType] = [.lecture, .seminar, .lab, .tutorial]
}

/// Optional per-lesson fields that a timetable can show or hide. Open.
public struct LessonField: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let room = LessonField(rawValue: "room")
    public static let building = LessonField(rawValue: "building")
    public static let teacher = LessonField(rawValue: "teacher")
    public static let lessonType = LessonField(rawValue: "lessonType")
    public static let notes = LessonField(rawValue: "notes")
    public static let bringList = LessonField(rawValue: "bringList")

    public static let knownValues: [LessonField] = [.room, .building, .teacher, .lessonType, .notes, .bringList]
}

/// The views a timetable can open in. Open.
public struct TimetableViewKind: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Classic periods × days grid.
    public static let grid = TimetableViewKind(rawValue: "grid")
    /// Weekly proportional time blocks.
    public static let timeBlocks = TimetableViewKind(rawValue: "timeBlocks")
    /// Single day list.
    public static let day = TimetableViewKind(rawValue: "day")
    /// Big vertical tiles.
    public static let tiles = TimetableViewKind(rawValue: "tiles")
    /// Agenda / Now & Next.
    public static let agenda = TimetableViewKind(rawValue: "agenda")

    public static let knownValues: [TimetableViewKind] = [.grid, .timeBlocks, .day, .tiles, .agenda]
}

/// Kind of a bell-schedule period. Open (deviation from the plan's closed list: safer for growth).
public struct PeriodKind: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let lesson = PeriodKind(rawValue: "lesson")
    /// A short break. Raw value `"break"`.
    public static let breakTime = PeriodKind(rawValue: "break")
    public static let lunch = PeriodKind(rawValue: "lunch")

    public static let knownValues: [PeriodKind] = [.lesson, .breakTime, .lunch]
}

/// Kind of a calendar break (holiday range). Open.
public struct BreakKind: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let holiday = BreakKind(rawValue: "holiday")
    public static let vacation = BreakKind(rawValue: "vacation")
    public static let examPeriod = BreakKind(rawValue: "examPeriod")
    public static let noSchool = BreakKind(rawValue: "noSchool")

    public static let knownValues: [BreakKind] = [.holiday, .vacation, .examPeriod, .noSchool]
}

/// Kind of a task. Open.
public struct TaskKind: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let homework = TaskKind(rawValue: "homework")
    public static let assignment = TaskKind(rawValue: "assignment")
    public static let todo = TaskKind(rawValue: "todo")

    public static let knownValues: [TaskKind] = [.homework, .assignment, .todo]
}

/// Kind of an exam. Open.
public struct ExamKind: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let written = ExamKind(rawValue: "written")
    public static let oral = ExamKind(rawValue: "oral")
    public static let test = ExamKind(rawValue: "test")
    public static let quiz = ExamKind(rawValue: "quiz")
    public static let practical = ExamKind(rawValue: "practical")
    public static let midterm = ExamKind(rawValue: "midterm")
    public static let final = ExamKind(rawValue: "final")

    public static let knownValues: [ExamKind] = [.written, .oral, .test, .quiz, .practical, .midterm, .final]
}

/// Kind of a task attachment. Open.
public struct AttachmentKind: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let photo = AttachmentKind(rawValue: "photo")
    public static let file = AttachmentKind(rawValue: "file")
    public static let link = AttachmentKind(rawValue: "link")
    public static let voiceNote = AttachmentKind(rawValue: "voiceNote")

    public static let knownValues: [AttachmentKind] = [.photo, .file, .link, .voiceNote]
}

/// What a reminder rule applies to. Open.
public struct ReminderTarget: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let homework = ReminderTarget(rawValue: "homework")
    public static let assignment = ReminderTarget(rawValue: "assignment")
    public static let exam = ReminderTarget(rawValue: "exam")
    public static let lesson = ReminderTarget(rawValue: "lesson")
    /// Evening reminder to pack the next school day's bring-list.
    public static let packTonight = ReminderTarget(rawValue: "packTonight")
    public static let todo = ReminderTarget(rawValue: "todo")

    public static let knownValues: [ReminderTarget] = [.homework, .assignment, .exam, .lesson, .packTonight, .todo]
}

/// How often a task repeats. Open.
public struct RepeatFrequency: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let daily = RepeatFrequency(rawValue: "daily")
    public static let weekly = RepeatFrequency(rawValue: "weekly")
    public static let monthly = RepeatFrequency(rawValue: "monthly")

    public static let knownValues: [RepeatFrequency] = [.daily, .weekly, .monthly]
}

/// Identifier of a palette pack (see `PalettePack`). Open.
public struct PalettePackID: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let classic = PalettePackID(rawValue: "classic")
    public static let ocean = PalettePackID(rawValue: "ocean")
    public static let sunset = PalettePackID(rawValue: "sunset")
    public static let pastel = PalettePackID(rawValue: "pastel")

    public static let knownValues: [PalettePackID] = [.classic, .ocean, .sunset, .pastel]
}

// MARK: - Settings-like open vocabularies (opened before the Phase 1 freeze)
//
// These were closed enums until the pre-freeze QA. Opening them lets a newer app version add a value without a
// schema bump: an older app keeps and re-encodes the unknown string, reports it as `unknownValue` (info) and
// behaves as `effective` says (DOMAIN_MODEL §5 "Degradation of unknown values").

/// Visual density of timetable views. Open; an unknown value is applied as `.comfortable` (`effective`).
public struct Density: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let compact = Density(rawValue: "compact")
    public static let comfortable = Density(rawValue: "comfortable")

    public static let knownValues: [Density] = [.compact, .comfortable]

    /// The density to apply: `self` when known, else the default `.comfortable`.
    public var effective: Density { isKnown ? self : .comfortable }
}

/// Who the user is; drives onboarding presets. Open; an unknown profile uses the `.other` presets (`effective`).
public struct UserProfile: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let elementary = UserProfile(rawValue: "elementary")
    public static let secondary = UserProfile(rawValue: "secondary")
    public static let university = UserProfile(rawValue: "university")
    public static let other = UserProfile(rawValue: "other")

    public static let knownValues: [UserProfile] = [.elementary, .secondary, .university, .other]

    /// The profile whose presets apply: `self` when known, else `.other`.
    public var effective: UserProfile { isKnown ? self : .other }
}

/// 12/24-hour clock preference. Open; an unknown value follows the locale like `.auto` (`effective`).
public struct HourCycle: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Follow the locale.
    public static let auto = HourCycle(rawValue: "auto")
    public static let h12 = HourCycle(rawValue: "h12")
    public static let h24 = HourCycle(rawValue: "h24")

    public static let knownValues: [HourCycle] = [.auto, .h12, .h24]

    /// The preference to apply: `self` when known, else `.auto` (system default).
    public var effective: HourCycle { isKnown ? self : .auto }
}

/// Light/dark appearance preference. Open; an unknown value follows the system like `.auto` (`effective`).
public struct Appearance: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Follow the system.
    public static let auto = Appearance(rawValue: "auto")
    public static let light = Appearance(rawValue: "light")
    public static let dark = Appearance(rawValue: "dark")

    public static let knownValues: [Appearance] = [.auto, .light, .dark]

    /// The appearance to apply: `self` when known, else `.auto` (system default).
    public var effective: Appearance { isKnown ? self : .auto }
}

/// Notification delivery tier, ordered `standard < timeSensitive < alarm`. Open.
///
/// `alarm` = AlarmKit loud alarm. Presets never use it; only user-created rules may (NOTIFICATIONS.md).
/// An unknown tier (from a newer app version) is preserved and **planned as `.standard`** (`effective`): the
/// quietest delivery, so an older app never escalates a reminder it does not understand.
/// Order: by the rank of `effective`, ties by raw value (a total order consistent with `==`).
public struct DeliveryTier: OpenVocabulary {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let standard = DeliveryTier(rawValue: "standard")
    public static let timeSensitive = DeliveryTier(rawValue: "timeSensitive")
    public static let alarm = DeliveryTier(rawValue: "alarm")

    public static let knownValues: [DeliveryTier] = [.standard, .timeSensitive, .alarm]

    /// The tier the planner uses: `self` when known, else `.standard`.
    public var effective: DeliveryTier { isKnown ? self : .standard }

    private var rank: Int {
        switch effective.rawValue {
        case "timeSensitive": return 1
        case "alarm": return 2
        default: return 0
        }
    }

    public static func < (lhs: DeliveryTier, rhs: DeliveryTier) -> Bool {
        (lhs.rank, lhs.rawValue) < (rhs.rank, rhs.rawValue)
    }
}

// MARK: - Closed enums (adding a case requires a schemaVersion bump)

/// Task priority, ordered `low < normal < high < urgent`. Closed.
public enum TaskPriority: String, CaseIterable, Codable, Comparable, Sendable {
    case low, normal, high, urgent

    private var rank: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        case .urgent: return 3
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.rank < rhs.rank }
}

/// Whether a reminder rule came from a profile preset or was created/edited by the user. Closed.
public enum RuleOrigin: String, CaseIterable, Codable, Sendable {
    case preset, user
}
