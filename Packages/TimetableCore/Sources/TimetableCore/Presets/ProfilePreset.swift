import Foundation

/// How a new timetable defines lesson times.
public enum TimeStructureChoice: Hashable, Sendable {
    /// A bell schedule generated from a template.
    case bellSchedule(BellScheduleTemplate)
    /// Free-form times with a default lesson length.
    case freeForm(defaultDurationMinutes: Int)
}

/// The per-profile defaults of PRODUCT.md "Profile presets" — data, not view code. Everything is changeable
/// later; nothing is locked by the onboarding choice.
public struct ProfilePreset: Hashable, Sendable {
    /// How insistently onboarding asks about rotations.
    public enum RotationPrompt: String, Hashable, Sendable, CaseIterable {
        /// One simple question ("Does your schedule change between weeks?").
        case light
        /// The full rotation question.
        case standard
        /// Full question plus semester date range and odd/even weeks.
        case extended
        /// "Other": ask without a recommendation.
        case ask
    }

    /// How prominent exams are in the UI.
    public enum ExamProminence: String, Hashable, Sendable, CaseIterable {
        case simple
        case prominent
        /// Prominent, plus the exam-period view (universities).
        case prominentWithExamPeriod
    }

    /// What lessons are called in onboarding and titles.
    public enum Terminology: String, Hashable, Sendable, CaseIterable {
        /// "Lesson".
        case lesson
        /// "Class/Lecture".
        case classLecture

        /// Catalog key of the term.
        public var l10nKey: String { "terminology.\(rawValue)" }
    }

    /// The profile.
    public let profile: UserProfile
    /// Suggested time structure; `nil` = "Ask" (no recommendation).
    public let timeStructure: TimeStructureChoice?
    /// Optional fields switched on.
    public let visibleFields: Set<LessonField>
    /// Rotation prompt level.
    public let rotationPrompt: RotationPrompt
    /// View the first timetable opens in.
    public let defaultView: TimetableViewKind
    /// Exam prominence.
    public let examProminence: ExamProminence
    /// Terminology.
    public let terminology: Terminology
    /// Weekdays enabled by default.
    public let enabledDays: Set<Weekday>
    /// Default reminder rules (never `.alarm`).
    public let reminderRules: [ReminderRulePreset]

    /// Catalog key of the terminology (`terminology.lesson` / `terminology.classLecture`).
    public var terminologyKey: String { terminology.l10nKey }

    /// The preset for `profile`.
    public static func `for`(_ profile: UserProfile) -> ProfilePreset {
        switch profile.effective {
        case .elementary: return elementary
        case .secondary: return secondary
        case .university: return university
        default: return other // .other; `effective` maps unknown profiles here
        }
    }

    // MARK: Table (PRODUCT.md "Profile presets")

    private static func time(_ hour: Int, _ minute: Int = 0) -> LocalTime { LocalTime(hour: hour, minute: minute)! }

    /// Elementary: bell schedule 45 min · Room, Teacher, Bring · light rotation prompt · big tiles · simple exams.
    public static let elementary = ProfilePreset(
        profile: .elementary,
        timeStructure: .bellSchedule(.elementary),
        visibleFields: [.room, .teacher, .bringList],
        rotationPrompt: .light,
        defaultView: .tiles,
        examProminence: .simple,
        terminology: .lesson,
        enabledDays: Weekday.workweek,
        reminderRules: [
            ReminderRulePreset(target: .homework, offsets: [.daysBefore(1, at: time(17))],
                               followUp: .nextMorning(at: time(7))),
            ReminderRulePreset(target: .packTonight, offsets: [.daysBefore(1, at: time(19))]),
            ReminderRulePreset(target: .exam, offsets: [.daysBefore(1, at: time(17))]),
            ReminderRulePreset(target: .lesson, offsets: [.minutesBefore(5)], isEnabled: false),
        ]
    )

    /// Secondary: bell schedule 45 min · Room, Teacher, Notes · rotation prompt · grid · prominent exams.
    public static let secondary = ProfilePreset(
        profile: .secondary,
        timeStructure: .bellSchedule(.secondary),
        visibleFields: [.room, .teacher, .notes],
        rotationPrompt: .standard,
        defaultView: .grid,
        examProminence: .prominent,
        terminology: .lesson,
        enabledDays: Weekday.workweek,
        reminderRules: [
            ReminderRulePreset(target: .homework, offsets: [.daysBefore(1, at: time(17))],
                               followUp: .nextMorning(at: time(7))),
            ReminderRulePreset(target: .exam, offsets: [.daysBefore(3, at: time(17)), .daysBefore(1, at: time(17))]),
            ReminderRulePreset(target: .lesson, offsets: [.minutesBefore(5)], tier: .timeSensitive, isEnabled: false),
            ReminderRulePreset(target: .packTonight, offsets: [.daysBefore(1, at: time(20))], isEnabled: false),
        ]
    )

    /// University: free-form 90 min · Building, Room, Teacher, Type, Notes · extended rotation prompt ·
    /// week time-blocks · prominent exams + exam period · "Class/Lecture".
    public static let university = ProfilePreset(
        profile: .university,
        timeStructure: .freeForm(defaultDurationMinutes: 90),
        visibleFields: [.building, .room, .teacher, .lessonType, .notes],
        rotationPrompt: .extended,
        defaultView: .timeBlocks,
        examProminence: .prominentWithExamPeriod,
        terminology: .classLecture,
        enabledDays: Weekday.workweek,
        reminderRules: [
            ReminderRulePreset(target: .assignment, offsets: [.daysBefore(3, at: time(18)), .daysBefore(1, at: time(18))],
                               followUp: .afterMinutes(120)),
            ReminderRulePreset(target: .homework, offsets: [.daysBefore(1, at: time(18))]),
            ReminderRulePreset(target: .exam, offsets: [.daysBefore(7, at: time(18)), .daysBefore(3, at: time(18)),
                                                        .daysBefore(1, at: time(18))]),
            ReminderRulePreset(target: .lesson, offsets: [.minutesBefore(15)], tier: .timeSensitive),
        ]
    )

    /// Other: ask about time structure · all fields off · ask about rotation · grid · simple exams.
    public static let other = ProfilePreset(
        profile: .other,
        timeStructure: nil,
        visibleFields: [],
        rotationPrompt: .ask,
        defaultView: .grid,
        examProminence: .simple,
        terminology: .lesson,
        enabledDays: Weekday.workweek,
        reminderRules: [
            ReminderRulePreset(target: .homework, offsets: [.daysBefore(1, at: time(18))]),
            ReminderRulePreset(target: .exam, offsets: [.daysBefore(1, at: time(18))]),
        ]
    )
}

/// A default reminder rule of a profile preset. Presets never use `DeliveryTier.alarm`.
public struct ReminderRulePreset: Hashable, Sendable {
    /// Target kind.
    public let target: ReminderTarget
    /// Offsets.
    public let offsets: [ReminderOffset]
    /// Follow-up.
    public let followUp: FollowUp?
    /// Tier (`.standard` or `.timeSensitive` only).
    public let tier: DeliveryTier
    /// Whether the rule starts enabled.
    public let isEnabled: Bool

    /// Creates a preset rule. Traps on `.alarm` (presets must never request loud alarms).
    public init(target: ReminderTarget, offsets: [ReminderOffset], followUp: FollowUp? = nil,
                tier: DeliveryTier = .standard, isEnabled: Bool = true) {
        precondition(tier != .alarm, "Preset reminder rules must never use the alarm tier")
        self.target = target
        self.offsets = offsets
        self.followUp = followUp
        self.tier = tier
        self.isEnabled = isEnabled
    }

    /// Materialises the rule (`origin == .preset`).
    public func makeRule(id: ReminderRule.ID, meta: EntityMeta, isEnabled: Bool? = nil) -> ReminderRule {
        ReminderRule(id: id, meta: meta, target: target, offsets: offsets, followUp: followUp, tier: tier,
                     quietHours: nil, isEnabled: isEnabled ?? self.isEnabled, origin: .preset)
    }
}
