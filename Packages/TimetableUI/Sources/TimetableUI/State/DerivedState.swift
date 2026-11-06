// What `AppModel` rebuilds after a change (Phase 10 WP1, findings P2 and P5). Pure, Linux-tested.
//
// P2: `AppModel` is `@Observable`, and Observation notifies a property's readers on EVERY assignment, also of an equal
// value. Rebuilding the calendar context, formatter, renderer and resolvers on every `apply` and every scene activation
// therefore invalidated every view that reads them (every tab). `DerivedStateRebuild.needed(from:to:)` decides what
// actually changed:
//   context    the settings' zone / first weekday or the device zone / locale week start changed
//   formatter  locale (incl. its hour cycle), the 12/24 h setting or the context's zone changed (renderer follows it)
//   resolvers  the context or a timetable-relevant collection changed (`ScheduleInputs`: exactly what
//              `ScheduleResolver.init(database:timetableID:context:)` reads). Array `==` returns at once for arrays
//              that share storage, which is what a task / exam / settings change leaves the lesson arrays with.
//
// P5: a short `.inactive → .active` blip (Notification Centre pulled down, Face ID, a call banner) refreshed the
// environment and fanned out to reminders, widgets and Live Activities. `ForegroundRefreshPolicy` refreshes after a
// real background stay (unchanged: permissions or pending notifications may have changed meanwhile), and after a blip
// only when the environment fingerprint changed or the last refresh is older than `blipRefreshAge`. System
// notifications (zone, locale, significant time change) always refresh, outside this policy.
import Foundation
import TimetableCore

/// The database collections the schedule resolvers are built from.
public struct ScheduleInputs: Equatable, Sendable {
    public var timetables: [Timetable]
    public var subjects: [Subject]
    public var bellSchedules: [BellSchedule]
    public var lessons: [Lesson]
    public var terms: [Term]
    public var breaks: [CalendarBreak]
    public var overrides: [ScheduleOverride]

    public init(_ database: TabulaDatabase) {
        timetables = database.timetables
        subjects = database.subjects
        bellSchedules = database.bellSchedules
        lessons = database.lessons
        terms = database.terms
        breaks = database.breaks
        overrides = database.overrides
    }
}

/// What `TimetableFormatter(settings:context:locale:)` depends on.
public struct FormatterInputs: Equatable, Sendable {
    public var locale: Locale
    public var localeIdentifier: String
    /// The locale's own hour cycle (the iOS 24-Hour Time switch), compared in addition to `locale`.
    public var localeHourCycle: Locale.HourCycle?
    public var hourCycle: HourCycle
    public var timeZone: TimeZone

    public init(locale: Locale, hourCycle: HourCycle, timeZone: TimeZone) {
        self.locale = locale
        localeIdentifier = locale.identifier
        localeHourCycle = Locale.Components(locale: locale).hourCycle
        self.hourCycle = hourCycle
        self.timeZone = timeZone
    }
}

/// Every input of `AppModel`'s derived state.
public struct DerivedStateInputs: Equatable, Sendable {
    public var context: CalendarContext
    public var formatter: FormatterInputs
    /// `nil` without a database.
    public var schedule: ScheduleInputs?

    public init(settings: AppSettings, database: TabulaDatabase?, deviceTimeZone: TimeZone, locale: Locale) {
        let context = CalendarEnvironment.context(settings: settings, deviceTimeZone: deviceTimeZone, locale: locale)
        self.context = context
        formatter = FormatterInputs(locale: locale, hourCycle: settings.hourCycle, timeZone: context.timeZone)
        schedule = database.map(ScheduleInputs.init)
    }
}

/// Which derived values to rebuild (and assign).
public struct DerivedStateRebuild: Equatable, Sendable {
    public var context: Bool
    public var formatter: Bool
    public var resolvers: Bool

    public init(context: Bool, formatter: Bool, resolvers: Bool) {
        self.context = context
        self.formatter = formatter
        self.resolvers = resolvers
    }

    public static let everything = DerivedStateRebuild(context: true, formatter: true, resolvers: true)
    public static let nothing = DerivedStateRebuild(context: false, formatter: false, resolvers: false)

    /// `old == nil` (first build) rebuilds everything.
    public static func needed(from old: DerivedStateInputs?, to new: DerivedStateInputs) -> DerivedStateRebuild {
        guard let old else { return .everything }
        let context = old.context != new.context
        return DerivedStateRebuild(context: context, formatter: old.formatter != new.formatter,
                                   resolvers: context || old.schedule != new.schedule)
    }
}

/// What the app's environment looked like at a refresh.
public struct EnvironmentFingerprint: Equatable, Sendable {
    public var deviceTimeZoneIdentifier: String
    public var secondsFromGMT: Int
    public var formatter: FormatterInputs
    public var context: CalendarContext
    /// The local day of `now` in `context`.
    public var today: LocalDate

    public init(settings: AppSettings, deviceTimeZone: TimeZone, locale: Locale, now: Date) {
        deviceTimeZoneIdentifier = deviceTimeZone.identifier
        secondsFromGMT = deviceTimeZone.secondsFromGMT(for: now)
        let context = CalendarEnvironment.context(settings: settings, deviceTimeZone: deviceTimeZone, locale: locale)
        self.context = context
        formatter = FormatterInputs(locale: locale, hourCycle: settings.hourCycle, timeZone: context.timeZone)
        today = context.localDate(of: now)
    }
}

/// Whether the scene becoming active should refresh the environment (and fan out to reminders, widgets, Live
/// Activities).
public enum ForegroundRefreshPolicy {
    /// After a blip, refresh anyway once the last refresh is this old.
    public static let blipRefreshAge: TimeInterval = 5 * 60

    /// - `returningFromBackground`: the scene was in `.background` since it was last active (or this is the first
    ///   activation). Always refreshes, as before.
    /// - Otherwise (`.inactive → .active`): only when the fingerprint changed, nothing was refreshed yet, the last
    ///   refresh is at least `blipRefreshAge` old, or the clock went backwards.
    public static func shouldRefresh(returningFromBackground: Bool, last: EnvironmentFingerprint?,
                                     lastRefreshAt: Date?, current: EnvironmentFingerprint, now: Date) -> Bool {
        if returningFromBackground { return true }
        guard let last, let lastRefreshAt else { return true }
        if last != current { return true }
        let age = now.timeIntervalSince(lastRefreshAt)
        return age < 0 || age >= blipRefreshAge
    }
}
