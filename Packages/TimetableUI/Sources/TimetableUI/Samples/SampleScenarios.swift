// Deterministic sample data for `-TabulaSeed` (screenshot / developer mode) and for Tools/EngineDemo, built
// only with the public TimetableCore API. Shared so that CI screenshots and the engine report show the same data.
//
// Determinism: every ID comes from a `SequentialIDGenerator` with a per-scenario namespace and every timestamp
// from a `HybridLogicalClock` fed with fixed instants; the same build yields byte-identical databases (tested).
// Names, rooms and teachers are realistic Slovak *user data* (what a user would type), not UI strings, so they
// are intentionally not in the String Catalog.
//
// Reference instant of every scenario: Tuesday 2026-10-13 10:20 Europe/Bratislava (CEST, UTC+2) — a school
// day mid-morning, so Today shows a lesson in progress and a next lesson.
import Foundation
import TimetableCore

/// One sample data set plus the environment it is meant to be viewed in.
public struct SampleScenario: Sendable {
    /// Which seed this is.
    public let kind: SeedKind
    /// The database; `nil` for `.empty` (first launch → onboarding).
    public let database: TabulaDatabase?
    /// Time zone the scenario's wall-clock times are written for.
    public let timeZone: TimeZone
    /// The fixed "now" used when no `-TabulaNow` is given.
    public let referenceNow: Date
    /// The local date of `referenceNow`.
    public let today: LocalDate
    /// First weekday assumed for the scenario's locale.
    public let localeFirstWeekday: Weekday
}

/// The scenarios behind `-TabulaSeed`.
public enum SampleScenarios {
    /// Time zone of every scenario.
    public static let timeZoneIdentifier = "Europe/Bratislava"

    /// The scenario's zone. Traps if the system has no tz database entry (Linux without tzdata).
    public static var timeZone: TimeZone {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
            preconditionFailure("\(timeZoneIdentifier) is not a known time zone on this system (install tzdata)")
        }
        return zone
    }

    /// Context used to turn the scenarios' fixed wall-clock instants into `Date`s.
    static var bootstrapContext: CalendarContext { CalendarContext(timeZone: timeZone, firstWeekday: .monday) }

    static func d(_ y: Int, _ m: Int, _ day: Int) -> LocalDate { LocalDate(year: y, month: m, day: day)! }
    static func t(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }

    /// The shared "today" of every scenario.
    public static let today = LocalDate(year: 2026, month: 10, day: 13)!

    /// Tue 2026-10-13 10:20 in `timeZone`.
    public static var referenceNow: Date { bootstrapContext.date(today, t(10, 20)) }

    /// Builds the scenario for `kind`.
    public static func make(_ kind: SeedKind) -> SampleScenario {
        let database: TabulaDatabase?
        switch kind {
        case .empty: database = nil
        case .blank: database = blank()
        case .elementary: database = elementary()
        case .secondary: database = secondary().database
        case .university: database = university()
        }
        return SampleScenario(kind: kind, database: database, timeZone: timeZone, referenceNow: referenceNow,
                              today: today, localeFirstWeekday: .monday)
    }

    // MARK: - Blank

    /// Onboarding finished (secondary profile, defaults), nothing entered: the "start blank" outcome.
    public static func blank() -> TabulaDatabase {
        var ids = SequentialIDGenerator(namespace: 0x7AB0_B1A0)
        var clock = HybridLogicalClock(node: 0xB1A0)
        let answers = OnboardingAnswers(
            profile: .secondary, timetableName: "Škola", bellScheduleName: "Zvonenie",
            localeFirstWeekday: .monday, hourCycle: .auto)
        return OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock,
                                                     now: bootstrapContext.date(d(2026, 9, 1), t(18)))
    }
}
