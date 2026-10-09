// The pure state of the onboarding flow (PHASE2_PLAN §1, PRODUCT.md "Onboarding"): what the user has answered so
// far, the defaults a profile preset pre-fills, validation of the term dates, and the translation into
// `OnboardingAnswers` / the first database. No SwiftUI, so it builds and is unit-tested on Linux.
//
// The views (App/Sources/Onboarding) only read and mutate an `OnboardingDraft` and call `makeDatabase` at the end.
import Foundation
import TimetableCore

/// The steps of the flow, in order. Raw values are the route suffixes (`onboarding.<rawValue>` except `welcome`).
public enum OnboardingStep: String, CaseIterable, Sendable, Hashable {
    case welcome
    case profile
    case rotation
    case time
    case fields
    case reminders
    case start

    /// 0-based position.
    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    /// Number of steps.
    public static var count: Int { allCases.count }
    /// The following step, `nil` after the last.
    public var next: OnboardingStep? { Self.allCases.indices.contains(index + 1) ? Self.allCases[index + 1] : nil }
    /// The preceding step, `nil` before the first.
    public var previous: OnboardingStep? { index > 0 ? Self.allCases[index - 1] : nil }
}

/// The answer to "Does your schedule change between weeks or days?".
public enum RotationChoice: String, CaseIterable, Sendable, Hashable {
    case none
    /// Day A / Day B (a 2-day cycle that advances on school days).
    case dayAB
    /// Odd / even ISO weeks.
    case oddEven
    /// A cycle of `OnboardingDraft.cycleLength` weeks.
    case cycle
    /// The schedule differs per semester: no rotation, but the term dates matter.
    case perSemester

    /// The choices shown for a preset's prompt level (PRODUCT.md "Rotation prompt").
    public static func available(for prompt: ProfilePreset.RotationPrompt) -> [RotationChoice] {
        switch prompt {
        case .light: return [.none, .oddEven, .dayAB]
        case .standard, .extended, .ask: return allCases
        }
    }
}

/// How lesson times are defined.
public enum TimeStructureKind: String, CaseIterable, Sendable, Hashable {
    case bellSchedule
    case freeForm
}

/// How the app starts.
public enum StartChoice: String, CaseIterable, Sendable, Hashable {
    case blank
    case sample
    /// Import pipeline (later phase): shown but not selectable.
    case photo
    /// Share codes (later phase): shown but not selectable.
    case code

    /// Whether the choice can be selected today.
    public var isAvailable: Bool { self == .blank || self == .sample }
}

/// Why the term dates cannot be used.
public enum TermIssue: Sendable, Hashable {
    /// The end is before the start.
    case endBeforeStart
    /// Longer than `OnboardingDraft.maxTermDays`.
    case tooLong
}

/// User-visible names the UI resolves from the String Catalog (core never invents text).
public struct OnboardingNames: Sendable, Hashable {
    public var timetable: String
    public var bellSchedule: String
    public var term: String

    public init(timetable: String, bellSchedule: String, term: String) {
        self.timetable = timetable
        self.bellSchedule = bellSchedule
        self.term = term
    }
}

/// Everything the user has answered so far.
public struct OnboardingDraft: Equatable, Sendable {
    // MARK: Limits (steppers and validation)

    public static let cycleLengths = WeekCycle.validLengths
    public static let lessonMinutesRange = 20...120
    public static let freeFormMinutesRange = 15...240
    public static let lessonCountRange = 1...14
    public static let breakMinutesRange = 0...60
    /// Longest term/semester accepted (days).
    public static let maxTermDays = 400

    // MARK: Answers

    /// `nil` until chosen (the profile step cannot be left without one).
    public private(set) var profile: UserProfile?
    public var rotation: RotationChoice = .none
    /// Length of the cycle for `.cycle` (2…6).
    public var cycleLength = 3
    public var termEnabled = false
    public var termStart: LocalDate
    public var termEnd: LocalDate
    public var timeKind: TimeStructureKind = .bellSchedule
    /// Start of the first lesson (minutes since midnight).
    public var firstStartMinutes = 8 * 60
    public var lessonMinutes = 45
    /// Break after most lessons.
    public var shortBreakMinutes = 10
    /// Break after the 2nd lesson.
    public var longBreakMinutes = 20
    public var lessonCount = 8
    /// Default block length of a free-form timetable.
    public var freeFormMinutes = 90
    public var visibleFields: Set<LessonField> = []
    /// Reminder kinds that start enabled (a subset of the preset's own rules).
    public var reminderTargets: Set<ReminderTarget> = []
    public var start: StartChoice = .blank

    /// The date the term suggestion and cycle anchors are based on.
    public let today: LocalDate

    // MARK: Creation

    /// A draft with the secondary-school defaults (the usual fallback) and, when `profile` is given, its preset.
    public init(today: LocalDate, profile: UserProfile? = nil) {
        self.today = today
        termStart = today
        termEnd = today.adding(days: 120)
        applyPreset(of: .secondary)
        if let profile { select(profile) }
    }

    /// Chooses `profile` and pre-fills every answer from its preset (PRODUCT.md "Profile presets"). Choosing
    /// the profile that is already selected keeps the user's edits.
    public mutating func select(_ profile: UserProfile) {
        guard profile != self.profile else { return }
        self.profile = profile
        applyPreset(of: profile)
    }

    private mutating func applyPreset(of profile: UserProfile) {
        let preset = ProfilePreset.for(profile)
        var template = Self.fallbackTemplate
        switch preset.timeStructure {
        case .bellSchedule(let presetTemplate)?:
            template = presetTemplate
            timeKind = .bellSchedule
            freeFormMinutes = presetTemplate.lessonMinutes
        case .freeForm(let minutes)?:
            timeKind = .freeForm
            freeFormMinutes = minutes
        case nil:
            timeKind = .bellSchedule
            freeFormMinutes = 90
        }
        firstStartMinutes = template.firstStart.minuteOfDay
        lessonMinutes = template.lessonMinutes
        shortBreakMinutes = template.breakMinutes.first ?? 10
        longBreakMinutes = template.breakMinutes.dropFirst().first ?? shortBreakMinutes
        lessonCount = template.count
        visibleFields = preset.visibleFields
        reminderTargets = Set(preset.reminderRules.filter(\.isEnabled).map(\.target))
        rotation = .none
        termEnabled = preset.rotationPrompt == .extended
    }

    /// The template used when the preset has no bell schedule of its own.
    static var fallbackTemplate: BellScheduleTemplate {
        if case .bellSchedule(let template) = OnboardingBuilder.fallbackTimeStructure { return template }
        return .secondary
    }

    // MARK: Derived

    /// The preset of the chosen profile (secondary's before one is chosen).
    public var preset: ProfilePreset { ProfilePreset.for(profile ?? .secondary) }
    /// Rotation choices offered for the profile.
    public var availableRotations: [RotationChoice] { RotationChoice.available(for: preset.rotationPrompt) }
    /// The reminder kinds the preset defines, in preset order (without duplicates).
    public var offeredReminderTargets: [ReminderTarget] {
        var seen: Set<ReminderTarget> = []
        return preset.reminderRules.map(\.target).filter { seen.insert($0).inserted }
    }

    /// The bell schedule the answers describe.
    public var bellTemplate: BellScheduleTemplate {
        BellScheduleTemplate(firstStart: LocalTime(minuteOfDay: firstStartMinutes) ?? LocalTime(hour: 8, minute: 0)!,
                             lessonMinutes: lessonMinutes,
                             breakMinutes: [shortBreakMinutes, longBreakMinutes, shortBreakMinutes],
                             count: lessonCount)
    }

    /// Start/end of every lesson of the preview (fewer than `lessonCount` when the day would run past midnight).
    public var bellPreview: [(start: LocalTime, end: LocalTime)] { bellTemplate.lessonTimes() }

    /// The time structure answer.
    public var timeStructure: TimeStructureChoice {
        switch timeKind {
        case .bellSchedule: return .bellSchedule(bellTemplate)
        case .freeForm: return .freeForm(defaultDurationMinutes: freeFormMinutes)
        }
    }

    /// The term problem, `nil` when the term is off or valid.
    public var termIssue: TermIssue? {
        guard termEnabled else { return nil }
        if termEnd < termStart { return .endBeforeStart }
        if termEnd.daysSinceEpoch - termStart.daysSinceEpoch + 1 > Self.maxTermDays { return .tooLong }
        return nil
    }

    /// Whether the step's answers are complete and valid, so "Next" may be offered.
    public func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .fields, .reminders, .start: return true
        case .profile: return profile != nil
        case .rotation: return termIssue == nil
        case .time:
            switch timeKind {
            case .bellSchedule: return !bellPreview.isEmpty
            case .freeForm: return Self.freeFormMinutesRange.contains(freeFormMinutes)
            }
        }
    }

    /// Switching to "Different per semester" turns the term on (its dates are what the choice is about).
    public mutating func choose(rotation choice: RotationChoice) {
        rotation = choice
        if choice == .perSemester { termEnabled = true }
    }

    /// Toggles a lesson field.
    public mutating func set(_ field: LessonField, visible: Bool) {
        if visible { visibleFields.insert(field) } else { visibleFields.remove(field) }
    }

    /// Toggles a reminder kind.
    public mutating func set(reminder target: ReminderTarget, enabled: Bool) {
        if enabled { reminderTargets.insert(target) } else { reminderTargets.remove(target) }
    }

    // MARK: Output

    /// The rotation scheme of the answers. Cycles are anchored to the term start (or today without a term).
    public var rotationScheme: RotationScheme {
        let reference = termEnabled && termIssue == nil ? termStart : today
        switch rotation {
        case .none, .perSemester:
            return .none
        case .oddEven:
            return .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0)))
        case .cycle:
            let length = min(max(cycleLength, Self.cycleLengths.lowerBound), Self.cycleLengths.upperBound)
            return .weekCycle(WeekCycle(length: length, anchor: .referenceWeek(date: reference, cycleWeek: 1)))
        case .dayAB:
            let days = preset.enabledDays
            return .dayCycle(DayCycle(length: 2, anchorDate: Self.firstSchoolDay(onOrAfter: reference, in: days),
                                      anchorIndex: 1, schoolDays: days))
        }
    }

    /// `date` or the next date whose weekday is in `days` (`date` when `days` is empty).
    static func firstSchoolDay(onOrAfter date: LocalDate, in days: Set<Weekday>) -> LocalDate {
        guard !days.isEmpty else { return date }
        for offset in 0..<7 where days.contains(date.adding(days: offset).weekday) { return date.adding(days: offset) }
        return date
    }

    /// The answers for `OnboardingBuilder`.
    public func answers(names: OnboardingNames, localeFirstWeekday: Weekday) -> OnboardingAnswers {
        OnboardingAnswers(
            profile: profile ?? .secondary,
            timetableName: names.timetable,
            bellScheduleName: names.bellSchedule,
            rotation: rotationScheme,
            timeStructure: timeStructure,
            visibleFields: visibleFields,
            term: termEnabled && termIssue == nil
                ? OnboardingAnswers.TermAnswer(name: names.term, range: LocalDateRange(start: termStart, end: termEnd))
                : nil,
            enabledReminderTargets: reminderTargets,
            localeFirstWeekday: localeFirstWeekday)
    }

    /// The first database: `OnboardingBuilder.makeInitialDatabase`, plus `SampleData` when "Use sample data" is
    /// chosen. `localize` turns the sample's catalog keys into the user's language.
    public func makeDatabase<G: IDGenerator, C: TimestampClock>(
        names: OnboardingNames, localeFirstWeekday: Weekday, localize: (LocalizedText) -> String,
        ids: inout G, clock: inout C, now: Date
    ) -> TabulaDatabase {
        let answers = answers(names: names, localeFirstWeekday: localeFirstWeekday)
        let database = OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: now)
        guard start == .sample, let timetable = database.timetables.first else { return database }
        let content = SampleData.make(
            profile: answers.profile, timetable: timetable, bellSchedule: database.bellSchedules.first,
            today: today, localize: localize, ids: &ids, clock: &clock, now: now)
        return content.merged(into: database)
    }
}
