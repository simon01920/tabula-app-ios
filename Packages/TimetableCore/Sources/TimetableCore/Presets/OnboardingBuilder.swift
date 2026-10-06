import Foundation

/// The user's onboarding answers. `nil` answers fall back to the profile preset.
///
/// Names are user-visible text, so the UI passes them already localised (e.g. the catalog value of
/// "School" in the current language); core never invents user-facing strings.
public struct OnboardingAnswers: Hashable, Sendable {
    /// A term/semester entered during onboarding.
    public struct TermAnswer: Hashable, Sendable {
        /// Name (user text / localised by the UI).
        public var name: String
        /// Inclusive range.
        public var range: LocalDateRange

        /// Creates a term answer.
        public init(name: String, range: LocalDateRange) {
            self.name = name
            self.range = range
        }
    }

    /// Who the user is.
    public var profile: UserProfile
    /// Name of the first timetable.
    public var timetableName: String
    /// Optional emoji of the first timetable.
    public var timetableEmoji: String?
    /// Name of the generated bell schedule (if one is generated).
    public var bellScheduleName: String
    /// Rotation answer (default: none).
    public var rotation: RotationScheme
    /// Time structure; `nil` = preset (or the secondary template when the preset says "Ask").
    public var timeStructure: TimeStructureChoice?
    /// Fields to show; `nil` = preset.
    public var visibleFields: Set<LessonField>?
    /// School days; `nil` = preset.
    public var enabledDays: Set<Weekday>?
    /// Default view; `nil` = preset.
    public var defaultView: TimetableViewKind?
    /// Optional term/semester.
    public var term: TermAnswer?
    /// Reminder kinds to enable; `nil` = the preset's own enabled flags. Preset rules for other targets are
    /// still created, but disabled.
    public var enabledReminderTargets: Set<ReminderTarget>?
    /// Week start override.
    public var weekStartOverride: Weekday?
    /// 12/24 h.
    public var hourCycle: HourCycle
    /// Time-zone mode.
    public var timeZoneMode: TimeZoneMode
    /// Palette pack.
    public var palettePackID: PalettePackID

    /// Creates answers.
    public init(profile: UserProfile, timetableName: String, timetableEmoji: String? = nil,
                bellScheduleName: String, rotation: RotationScheme = .none,
                timeStructure: TimeStructureChoice? = nil, visibleFields: Set<LessonField>? = nil,
                enabledDays: Set<Weekday>? = nil, defaultView: TimetableViewKind? = nil, term: TermAnswer? = nil,
                enabledReminderTargets: Set<ReminderTarget>? = nil, weekStartOverride: Weekday? = nil,
                hourCycle: HourCycle = .auto, timeZoneMode: TimeZoneMode = .followDevice,
                palettePackID: PalettePackID = .classic) {
        self.profile = profile
        self.timetableName = timetableName
        self.timetableEmoji = timetableEmoji
        self.bellScheduleName = bellScheduleName
        self.rotation = rotation
        self.timeStructure = timeStructure
        self.visibleFields = visibleFields
        self.enabledDays = enabledDays
        self.defaultView = defaultView
        self.term = term
        self.enabledReminderTargets = enabledReminderTargets
        self.weekStartOverride = weekStartOverride
        self.hourCycle = hourCycle
        self.timeZoneMode = timeZoneMode
        self.palettePackID = palettePackID
    }
}

/// Builds the first database from onboarding answers. Deterministic: the same answers, generator state,
/// clock state and `now` always produce the same database.
public enum OnboardingBuilder {
    /// The fallback when neither the answers nor the preset choose a time structure ("Other" → "Ask").
    public static let fallbackTimeStructure = TimeStructureChoice.bellSchedule(.secondary)

    /// Creates settings, one timetable, its bell schedule (if any), the optional term and the preset
    /// reminder rules. Timestamps are drawn in this order: settings, timetable, bell schedule, term, rules; IDs:
    /// timetable, bell schedule + periods, term, rules. The settings singleton is
    /// `AppSettings.untouchedDefaults` (`createdAt == .zero`) with only the answered fields that differ from
    /// the defaults stamped (DOMAIN_MODEL §2.2), so an untouched answer never overwrites another device's edit.
    public static func makeInitialDatabase<G: IDGenerator, C: TimestampClock>(
        answers: OnboardingAnswers, ids: inout G, clock: inout C, now: Date
    ) -> TabulaDatabase {
        let preset = ProfilePreset.for(answers.profile)

        let timetableID: Timetable.ID = ids.next()
        let settings = makeSettings(answers: answers, activeTimetableID: timetableID, clock: &clock, now: now)
        let timetableMeta = EntityMeta.created(at: clock.tick(now: now))

        var bellSchedules: [BellSchedule] = []
        let timeStructure: TimeStructure
        switch answers.timeStructure ?? preset.timeStructure ?? fallbackTimeStructure {
        case .bellSchedule(let template):
            let scheduleID: BellSchedule.ID = ids.next()
            let meta = EntityMeta.created(at: clock.tick(now: now))
            let periods = template.makePeriods(ids: &ids)
            bellSchedules.append(BellSchedule(id: scheduleID, meta: meta, timetableID: timetableID,
                                              name: answers.bellScheduleName, periods: periods))
            timeStructure = .bellSchedule(defaultID: scheduleID, perWeekday: [:])
        case .freeForm(let minutes):
            timeStructure = .freeForm(defaultDurationMinutes: minutes)
        }

        let timetable = Timetable(
            id: timetableID, meta: timetableMeta, name: answers.timetableName, emoji: answers.timetableEmoji,
            enabledDays: answers.enabledDays ?? preset.enabledDays, rotation: answers.rotation,
            timeStructure: timeStructure, fieldVisibility: FieldVisibility(answers.visibleFields ?? preset.visibleFields),
            defaultView: answers.defaultView ?? preset.defaultView, density: .comfortable, palettePackID: nil,
            sortIndex: 0)

        var terms: [Term] = []
        if let term = answers.term {
            terms.append(Term(id: ids.next(), meta: .created(at: clock.tick(now: now)), timetableID: timetableID,
                              name: term.name, range: term.range))
        }

        var rules: [ReminderRule] = []
        for rulePreset in preset.reminderRules {
            let enabled = answers.enabledReminderTargets.map { $0.contains(rulePreset.target) }
            rules.append(rulePreset.makeRule(id: ids.next(), meta: .created(at: clock.tick(now: now)), isEnabled: enabled))
        }

        return TabulaDatabase(settings: settings, timetables: [timetable], bellSchedules: bellSchedules,
                              terms: terms, reminderRules: rules)
    }

    /// The settings singleton after onboarding: `AppSettings.untouchedDefaults` with the answered fields, stamped
    /// at one tick. Only fields whose value differs from the default get a field clock; the others stay at the
    /// zero `createdAt` (the same metadata `MutationStamper.stamp(old: .untouchedDefaults, new: …)` writes; a
    /// test checks the equivalence).
    static func makeSettings<C: TimestampClock>(answers: OnboardingAnswers, activeTimetableID: Timetable.ID,
                                                clock: inout C, now: Date) -> AppSettings {
        let defaults = AppSettings.untouchedDefaults
        var settings = defaults
        settings.profile = answers.profile
        settings.onboardingCompletedAt = now
        settings.activeTimetableID = activeTimetableID
        settings.weekStartOverride = answers.weekStartOverride
        settings.hourCycle = answers.hourCycle
        settings.timeZoneMode = answers.timeZoneMode
        settings.palettePackID = answers.palettePackID

        var changed: [String] = []
        if settings.profile != defaults.profile { changed.append("profile") }
        if settings.onboardingCompletedAt != defaults.onboardingCompletedAt { changed.append("onboardingCompletedAt") }
        if settings.activeTimetableID != defaults.activeTimetableID { changed.append("activeTimetableID") }
        if settings.weekStartOverride != defaults.weekStartOverride { changed.append("weekStartOverride") }
        if settings.hourCycle != defaults.hourCycle { changed.append("hourCycle") }
        if settings.timeZoneMode != defaults.timeZoneMode { changed.append("timeZoneMode") }
        if settings.palettePackID != defaults.palettePackID { changed.append("palettePackID") }

        let t = clock.tick(now: now)
        settings.meta = EntityMeta(createdAt: defaults.meta.createdAt, updatedAt: t,
                                   fieldClocks: Dictionary(uniqueKeysWithValues: changed.map { ($0, t) }))
        return settings
    }
}
