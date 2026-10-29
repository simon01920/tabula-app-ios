// The pure state of the onboarding flow (UX_OVERHAUL_PLAN D8, PRODUCT.md "Onboarding"): what the user has answered so
// far, the defaults a profile preset pre-fills, validation, and the translation into `OnboardingAnswers` / the first
// database. No SwiftUI, so it builds and is unit-tested on Linux.
//
// Four steps (Phase 4U U6, R5/F08): school type → how to start → your week → lesson times. Fields to show and the
// reminder rules are no longer asked: both come from the profile preset (fields: `ProfilePreset.visibleFields`;
// reminders: the preset rules with their own enabled flags, i.e. homework and exams on for every profile). The
// notification permission is asked in context (Phase 3 Q1).
//
// The views (App/Sources/Onboarding) only read and mutate an `OnboardingDraft` and call `makeDatabase` at the end.
import Foundation
import TimetableCore

/// The steps of the flow, in order.
public enum OnboardingStep: String, CaseIterable, Sendable, Hashable {
    /// Welcome + "Choose your school type" (+ the app-language row).
    case schoolType
    /// "How do you want to start?": set up my timetable, or just look around (sample data).
    case start
    /// "Your week": school days, how the timetable repeats, optional term dates.
    case week
    /// "Lesson times": fixed lesson periods or individual start and end times.
    case times

    /// 0-based position.
    public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    /// Number of steps.
    public static var count: Int { allCases.count }
    /// The following step, `nil` after the last.
    public var next: OnboardingStep? { Self.allCases.indices.contains(index + 1) ? Self.allCases[index + 1] : nil }
    /// The preceding step, `nil` before the first.
    public var previous: OnboardingStep? { index > 0 ? Self.allCases[index - 1] : nil }
    /// The navigation path that shows this step: every step after the root (`schoolType`) up to and including this
    /// one (`[]` for the root).
    public var path: [OnboardingStep] { Array(Self.allCases.dropFirst().prefix(index)) }
}

/// The answer to "How does your timetable repeat?" (F07). Term dates are a separate, optional answer.
public enum RotationChoice: String, CaseIterable, Sendable, Hashable {
    /// Same every week.
    case none
    /// Alternating weeks (Week A / Week B): a 2-week cycle, anchored by "Which week is this week?" or by calendar
    /// odd/even weeks.
    case alternatingWeeks
    /// Alternating days (Day A / Day B): a 2-day cycle that advances on school days.
    case alternatingDays
    /// A cycle of `OnboardingDraft.customCycleLength` weeks (3…6).
    case customCycle

    /// The choices shown for a preset's prompt level (PRODUCT.md "Rotation prompt"): elementary gets the short list.
    public static func available(for prompt: ProfilePreset.RotationPrompt) -> [RotationChoice] {
        switch prompt {
        case .light: return [.none, .alternatingWeeks, .alternatingDays]
        case .standard, .extended, .ask: return allCases
        }
    }
}

/// How lesson times are defined.
public enum TimeStructureKind: String, CaseIterable, Sendable, Hashable {
    /// "Fixed lesson periods": a bell schedule, the same lesson times each day.
    case bellSchedule
    /// "Individual start and end times": free-form lessons with a default length.
    case freeForm
}

/// How the app starts. Imports (photo, QR / share code) are not offered until they work (F09).
public enum StartChoice: String, CaseIterable, Sendable, Hashable {
    /// "Set up my timetable" (primary path): an empty timetable from the answers.
    case blank
    /// "Just look around": the profile's sample timetable, removable later (`SampleContent`).
    case sample
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

    /// Lengths offered for "Custom cycle" (2 weeks is "Alternating weeks").
    public static let customCycleLengths = 3...WeekCycle.validLengths.upperBound
    public static let lessonMinutesRange = 20...120
    public static let freeFormMinutesRange = 15...240
    public static let lessonCountRange = 1...14
    public static let breakMinutesRange = 0...60
    /// Longest term/semester accepted (days).
    public static let maxTermDays = 400

    // MARK: Answers

    /// `nil` until chosen (the school-type step cannot be left without one).
    public private(set) var profile: UserProfile?
    public var start: StartChoice = .blank
    /// School days (at least one is required).
    public var enabledDays: Set<Weekday> = Weekday.workweek
    public var rotation: RotationChoice = .none
    /// Alternating weeks / custom cycle: the cycle week of the current week (1-based; 1 = Week A).
    public var currentCycleWeek = 1
    /// Alternating weeks only: follow calendar (ISO) odd/even weeks instead of counting from this week. The
    /// current week keeps the cycle week chosen in `currentCycleWeek`; the parity mapping follows from it.
    public var followsCalendarParity = false
    /// Alternating days: the cycle day (1 = Day A) of `dayCycleAnchorDate`.
    public var currentCycleDay = 1
    /// Length of the custom cycle (3…6 weeks).
    public var customCycleLength = 3
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
    /// Default lesson length of "Individual start and end times".
    public var freeFormMinutes = 90

    /// The date the term suggestion and the rotation anchors are based on.
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
        enabledDays = preset.enabledDays
        rotation = .none
        currentCycleWeek = 1
        followsCalendarParity = false
        currentCycleDay = 1
        customCycleLength = Self.customCycleLengths.lowerBound
        termEnabled = preset.rotationPrompt == .extended
        applyPresetTimes(of: profile)
    }

    /// Resets the lesson-time answers to the profile's suggestion ("I'll do this later").
    public mutating func applyPresetTimes() {
        applyPresetTimes(of: profile ?? .secondary)
    }

    private mutating func applyPresetTimes(of profile: UserProfile) {
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
    /// Fields shown on lesson summaries: derived from the profile (no step; F06/F12). School: room, teacher (+ the
    /// preset's bring list / notes); university: + building, type. Editable later in the timetable settings.
    public var visibleFields: Set<LessonField> { preset.visibleFields }

    /// The school days in display order for a week starting on `firstWeekday` (the chips of "Your week").
    public static func orderedWeekdays(firstWeekday: Weekday) -> [Weekday] { Weekday.week(startingAt: firstWeekday) }

    /// Turns a school day on or off.
    public mutating func set(_ day: Weekday, enabled: Bool) {
        if enabled { enabledDays.insert(day) } else { enabledDays.remove(day) }
    }

    /// The cycle weeks "Which week is this week?" offers: 2 for alternating weeks, the custom length otherwise.
    public var cycleWeekCount: Int {
        rotation == .customCycle ? clampedCustomLength : 2
    }

    private var clampedCustomLength: Int {
        min(max(customCycleLength, Self.customCycleLengths.lowerBound), Self.customCycleLengths.upperBound)
    }

    /// `currentCycleWeek` within 1…`cycleWeekCount` (a shorter custom cycle may leave it out of range).
    public var effectiveCycleWeek: Int { min(max(currentCycleWeek, 1), cycleWeekCount) }

    /// The ISO week of the current rotation week (shown next to "Follow calendar odd/even weeks").
    public func currentISOWeek(firstWeekday: Weekday) -> ISOWeek {
        WeekParity.representativeISOWeek(containing: today, firstWeekday: firstWeekday)
    }

    /// With calendar parity: `true` when Week A falls on odd calendar weeks.
    public func weekAIsOdd(firstWeekday: Weekday) -> Bool {
        let thisWeekIsOdd = currentISOWeek(firstWeekday: firstWeekday).week % 2 == 1
        return thisWeekIsOdd == (effectiveCycleWeek == 1)
    }

    /// The school day the "Alternating days" anchor refers to: today, or the next school day.
    public var dayCycleAnchorDate: LocalDate { Self.firstSchoolDay(onOrAfter: today, in: enabledDays) }

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

    /// Whether the step's answers are complete and valid, so the primary button may be offered.
    public func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .schoolType: return profile != nil
        case .start: return profile != nil
        case .week: return !enabledDays.isEmpty && termIssue == nil
        case .times:
            switch timeKind {
            case .bellSchedule: return !bellPreview.isEmpty
            case .freeForm: return Self.freeFormMinutesRange.contains(freeFormMinutes)
            }
        }
    }

    /// Whether the flow may finish now: the steps up to and including `step` are valid, and the later ones keep
    /// their (always valid) defaults. "Just look around" finishes from `.start`; "I'll do this later" from `.times`.
    public func canFinish(from step: OnboardingStep) -> Bool {
        OnboardingStep.allCases.prefix(step.index + 1).allSatisfy(canAdvance(from:))
            && canAdvance(from: .week) && canAdvance(from: .times)
    }

    // MARK: Output

    /// The rotation scheme of the answers, counted in rotation weeks that start on `firstWeekday` (the new
    /// timetable's `rotationWeekStart`).
    /// - Alternating weeks: this week is `currentCycleWeek` (`referenceWeek` on today), or with calendar parity an
    ///   `isoWeekParity` cycle whose `offset` makes this week `currentCycleWeek`.
    /// - Custom cycle: `referenceWeek` on today with the chosen week.
    /// - Alternating days: `dayCycleAnchorDate` is Day `currentCycleDay`; the cycle advances on the school days.
    public func rotationScheme(firstWeekday: Weekday) -> RotationScheme {
        switch rotation {
        case .none:
            return .none
        case .alternatingWeeks:
            let week = effectiveCycleWeek
            if followsCalendarParity {
                let iso = currentISOWeek(firstWeekday: firstWeekday)
                let offset = (0..<2).first {
                    WeekParity.cycleWeek(for: iso, policy: .strict, offset: $0, length: 2) == week
                } ?? 0
                return .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: offset)))
            }
            return .weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: today, cycleWeek: week)))
        case .customCycle:
            return .weekCycle(WeekCycle(length: clampedCustomLength,
                                        anchor: .referenceWeek(date: today, cycleWeek: effectiveCycleWeek)))
        case .alternatingDays:
            let days = enabledDays.isEmpty ? preset.enabledDays : enabledDays
            return .dayCycle(DayCycle(length: 2, anchorDate: Self.firstSchoolDay(onOrAfter: today, in: days),
                                      anchorIndex: min(max(currentCycleDay, 1), 2), schoolDays: days))
        }
    }

    /// `date` or the next date whose weekday is in `days` (`date` when `days` is empty).
    static func firstSchoolDay(onOrAfter date: LocalDate, in days: Set<Weekday>) -> LocalDate {
        guard !days.isEmpty else { return date }
        for offset in 0..<7 where days.contains(date.adding(days: offset).weekday) { return date.adding(days: offset) }
        return date
    }

    /// The answers for `OnboardingBuilder`. Reminder rules: `enabledReminderTargets == nil`, so every preset rule is
    /// created with the preset's own enabled flag (the defaults the removed reminders step started with).
    public func answers(names: OnboardingNames, localeFirstWeekday: Weekday) -> OnboardingAnswers {
        OnboardingAnswers(
            profile: profile ?? .secondary,
            timetableName: names.timetable,
            bellScheduleName: names.bellSchedule,
            rotation: rotationScheme(firstWeekday: localeFirstWeekday),
            timeStructure: timeStructure,
            visibleFields: visibleFields,
            enabledDays: enabledDays.isEmpty ? nil : enabledDays,
            term: termEnabled && termIssue == nil
                ? OnboardingAnswers.TermAnswer(name: names.term, range: LocalDateRange(start: termStart, end: termEnd))
                : nil,
            enabledReminderTargets: nil,
            localeFirstWeekday: localeFirstWeekday)
    }

    /// The first database: `OnboardingBuilder.makeInitialDatabase`, plus `SampleData` when "Just look around" is
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
