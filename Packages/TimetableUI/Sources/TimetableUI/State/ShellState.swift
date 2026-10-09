// Derivations the app shell needs from the loaded database (pure, Linux-tested):
// - which top-level phase to show (loading / onboarding / main tabs / blocking problem),
// - which timetable is active,
// - the calendar context from settings + device time zone + locale first weekday.
import Foundation
import TimetableCore

/// What the root of the app shows.
public enum ShellPhase: Equatable, Sendable {
    /// The store is still loading.
    case loading
    /// No data or onboarding not completed.
    case onboarding
    /// The tab bar (Today · Timetable · Settings).
    case main
    /// Nothing can be shown; never offers onboarding (it would overwrite recoverable data).
    case blocked(StoreProblem)

    /// The phase for a load state and the current database.
    public static func derive(isLoading: Bool, problem: StoreProblem?, database: TabulaDatabase?) -> ShellPhase {
        if let problem { return .blocked(problem) }
        if isLoading { return .loading }
        guard let database, database.settings.onboardingCompletedAt != nil,
              database.timetables.contains(where: { !$0.isDeleted }) else { return .onboarding }
        return .main
    }
}

/// The timetable the app opens with.
public enum ActiveTimetable {
    /// Live timetables in display order (`sortIndex`, then name, then ID for a total order).
    public static func ordered(_ database: TabulaDatabase) -> [Timetable] {
        database.timetables.filter { !$0.isDeleted }.sorted {
            ($0.sortIndex, $0.name, $0.id.uuidString) < ($1.sortIndex, $1.name, $1.id.uuidString)
        }
    }

    /// `settings.activeTimetableID` when it names a live timetable, else the first live timetable in display order.
    public static func resolve(_ database: TabulaDatabase) -> Timetable? {
        let live = ordered(database)
        if let id = database.settings.activeTimetableID, let match = live.first(where: { $0.id == id }) { return match }
        return live.first
    }
}

/// Builds `CalendarContext`s from the device environment (PHASE2_PLAN §0.5).
public enum CalendarEnvironment {
    /// The locale's first weekday (`Locale.firstDayOfWeek`, which includes the user's "First Day of Week"
    /// preference for `Locale.current` on iOS).
    public static func firstWeekday(of locale: Locale) -> Weekday {
        switch locale.firstDayOfWeek {
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        case .sunday: return .sunday
        @unknown default: return .monday
        }
    }

    /// The context for `settings` on a device in `deviceTimeZone` with `locale`.
    public static func context(settings: AppSettings, deviceTimeZone: TimeZone, locale: Locale) -> CalendarContext {
        CalendarContext(settings: settings, deviceTimeZone: deviceTimeZone, localeFirstWeekday: firstWeekday(of: locale))
    }
}
