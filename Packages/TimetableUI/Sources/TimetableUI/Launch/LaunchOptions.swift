// Launch options for deterministic screenshot / developer mode (PHASE2_PLAN §0.6).
// Pure Swift + Foundation (no SwiftUI): builds and is unit-tested on Linux (Tests/TimetableUITests).
//
//   -TabulaScreen <route id>                      first screen (route registry, App/Sources/Routing)
//   -TabulaSeed empty|blank|elementary|secondary|university
//                                                 in-memory repository with deterministic sample data
//   -TabulaNow <ISO-8601 instant> | live          fixed clock ("live" = real clock); only together with -TabulaSeed
//   -TabulaTimeZone <IANA id>                     device time zone override, only with -TabulaSeed (default: the
//                                                 scenario's zone, Europe/Bratislava)
//   -TabulaReminders fake|live                    reminder clients with -TabulaSeed: `fake` (default, in-memory: nothing
//                                                 reaches the real notification centre / AlarmKit) or `live`
//
// Release builds ignore ALL of them (`allowsDeveloperOverrides: false`, Phase 2 decision P2-6, PHASE3_PLAN §0.11):
// the app passes `allowsDeveloperOverrides: true` only under `#if DEBUG`, so a shipped build always starts in the
// normal shell.
import Foundation

/// Which deterministic data set `-TabulaSeed` loads into an in-memory repository.
public enum SeedKind: String, CaseIterable, Sendable, Equatable {
    /// No database at all: first launch, onboarding is shown.
    case empty
    /// Onboarding finished (secondary profile) but nothing entered yet: empty states of Today/Timetable.
    case blank
    /// Primary school (ZŠ), big vertical tiles.
    case elementary
    /// Secondary school (gymnázium) with A/B weeks and overrides — the same data as Tools/EngineDemo.
    case secondary
    /// University (free-form times, lectures/seminars/labs, buildings).
    case university
}

/// How the app gets the current instant.
public enum ClockOverride: Sendable, Equatable {
    /// The real clock.
    case live
    /// Always this instant (screenshots: countdowns and "today" are stable).
    case fixed(Date)
}

/// Parsed developer/screenshot launch options.
public struct LaunchOptions: Sendable, Equatable {
    /// `-TabulaSeed`.
    public static let seedKey = "TabulaSeed"
    /// `-TabulaNow`.
    public static let nowKey = "TabulaNow"
    /// `-TabulaTimeZone`.
    public static let timeZoneKey = "TabulaTimeZone"
    /// `-TabulaReminders`.
    public static let remindersKey = "TabulaReminders"

    /// Requested first screen (`-TabulaScreen`), unvalidated. Resolve it with a `RouteTable`.
    public var screen: String?
    /// Seed data set, or `nil` for the real on-disk store.
    public var seed: SeedKind?
    /// Clock override; `nil` = default (live without a seed, the scenario's reference instant with a seed).
    public var clock: ClockOverride?
    /// Device time-zone override.
    public var timeZone: TimeZone?
    /// `true` with `-TabulaSeed … -TabulaReminders live`: the seed app uses the real notification centre and AlarmKit.
    /// Without a seed the real store always uses the real clients.
    public var liveReminders: Bool
    /// Problems with the given arguments (unknown seed, unparsable date, unknown zone, ignored in Release), in
    /// argument order. Developer-facing text, shown by the debug screen.
    public var problems: [String]

    /// Creates options directly (tests, previews).
    public init(screen: String? = nil, seed: SeedKind? = nil, clock: ClockOverride? = nil, timeZone: TimeZone? = nil,
                liveReminders: Bool = false, problems: [String] = []) {
        self.screen = screen
        self.seed = seed
        self.clock = clock
        self.timeZone = timeZone
        self.liveReminders = liveReminders
        self.problems = problems
    }

    /// Parses `arguments`. With `allowsDeveloperOverrides == false` (Release) every option — screen, seed, clock,
    /// time zone, reminders — is ignored and reported in `problems`.
    public init(arguments: LaunchArguments, allowsDeveloperOverrides: Bool) {
        self.init()
        let rawScreen = arguments.value(for: LaunchArguments.screenKey)
        let rawSeed = arguments.value(for: Self.seedKey)
        let rawNow = arguments.value(for: Self.nowKey)
        let rawZone = arguments.value(for: Self.timeZoneKey)
        let rawReminders = arguments.value(for: Self.remindersKey)
        guard allowsDeveloperOverrides else {
            for (key, value) in [(LaunchArguments.screenKey, rawScreen), (Self.seedKey, rawSeed), (Self.nowKey, rawNow),
                                 (Self.timeZoneKey, rawZone), (Self.remindersKey, rawReminders)] where value != nil {
                problems.append("-\(key) ignored in Release builds")
            }
            return
        }
        screen = rawScreen
        if let rawSeed {
            if let kind = SeedKind(rawValue: rawSeed) {
                seed = kind
            } else {
                problems.append("-\(Self.seedKey) \"\(rawSeed)\" unknown (\(SeedKind.allCases.map(\.rawValue).joined(separator: "|")))")
            }
        }
        // A fixed clock or zone would stamp the real on-disk data (and the persisted HLC) with fake times: both
        // apply only to the in-memory seed store. Reminder clients are always live for the real store.
        guard seed != nil else {
            for (key, value) in [(Self.nowKey, rawNow), (Self.timeZoneKey, rawZone), (Self.remindersKey, rawReminders)]
            where value != nil {
                problems.append("-\(key) ignored without -\(Self.seedKey) (only the in-memory seed store may use it)")
            }
            return
        }
        if let rawNow {
            if rawNow == "live" {
                clock = .live
            } else if let date = Self.parseInstant(rawNow) {
                clock = .fixed(date)
            } else {
                problems.append("-\(Self.nowKey) \"\(rawNow)\" is not ISO-8601 (e.g. 2026-10-13T10:20:00+02:00)")
            }
        }
        if let rawZone {
            if let zone = TimeZone(identifier: rawZone) {
                timeZone = zone
            } else {
                problems.append("-\(Self.timeZoneKey) \"\(rawZone)\" is not a known time zone")
            }
        }
        switch rawReminders {
        case nil, "fake"?: liveReminders = false
        case "live"?: liveReminders = true
        case let other?: problems.append("-\(Self.remindersKey) \"\(other)\" unknown (fake|live)")
        }
    }

    /// Parses an ISO-8601 instant with a UTC offset or `Z`, with or without fractional seconds.
    /// A value without an offset is rejected (it would silently depend on the machine's zone).
    public static func parseInstant(_ text: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime],
                                                      [.withInternetDateTime, .withFractionalSeconds]] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
