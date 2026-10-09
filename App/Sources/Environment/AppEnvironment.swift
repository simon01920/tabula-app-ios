// Dependency container (PHASE2_PLAN §0.5). No singletons: one `AppEnvironment` is built at launch from the launch
// options and handed to `AppModel`; views reach the model through the SwiftUI environment.
//
// Live:   FileRepository in the App Group container (group id from AppGroup.identifier(forBundleIdentifier:), so xtool's
//         XTL- re-signed builds work), falling back to Application Support when the container is nil (free teams,
//         xtool PR #284); HLC in the App Group UserDefaults; real clock; device time zone + locale.
// Seed:   (DEBUG only, `-TabulaSeed`) InMemoryRepository with SampleScenarios data, in-memory HLC with a fixed node,
//         fixed clock (`-TabulaNow`, default = the scenario's reference instant) and the scenario's time zone.
// APIs: FileManager.containerURL(forSecurityApplicationGroupIdentifier:), FileManager.url(for:in:appropriateFor:create:),
//       UserDefaults(suiteName:), Bundle.main.bundleIdentifier / localizedString(forKey:value:table:), Locale.current,
//       TimeZone.current (docs checked, see docs/ENVIRONMENT.md §12).
import Foundation
import TimetableCore
import TimetableUI

/// The current instant.
struct NowProvider: Sendable {
    /// Returns "now".
    let now: @Sendable () -> Date
    /// `true` when the clock is frozen (screenshot mode): views should pause live countdowns at `now()`.
    let isFixed: Bool

    static let live = NowProvider(now: { Date() }, isFixed: false)
    static func fixed(_ date: Date) -> NowProvider { NowProvider(now: { date }, isFixed: true) }
}

/// Where the data lives (shown on the developer screen).
enum DataSource: Equatable, Sendable {
    /// On disk; `isAppGroup == false` means the Application Support fallback (widgets cannot read it).
    case file(directory: URL, isAppGroup: Bool)
    /// In memory, from `-TabulaSeed`.
    case seed(SeedKind)
}

/// Everything the app depends on, injected once.
struct AppEnvironment: Sendable {
    let persistence: PersistenceController
    let clockStore: any ClockStore
    let nowProvider: NowProvider
    /// Device time zone (re-read whenever the calendar context is rebuilt).
    let deviceTimeZone: @Sendable () -> TimeZone
    /// Device locale (language, region, first weekday, 12/24 h default).
    let locale: @Sendable () -> Locale
    /// Catalog lookup for `LocalizedTextRenderer` (main bundle → per-app language and `-AppleLanguages` apply).
    let catalogLookup: LocalizedTextRenderer.Lookup
    /// Free/Pro gating; everything allowed until Phase 10.
    let entitlements: any EntitlementsProvider
    let dataSource: DataSource
    let launchOptions: LaunchOptions
    /// Delay between the last change and the save (coalesces bursts of edits).
    let saveDebounce: Duration

    /// The environment for this process.
    static func make(launchOptions: LaunchOptions) -> AppEnvironment {
        let lookup: LocalizedTextRenderer.Lookup = { key in Bundle.main.localizedString(forKey: key, value: nil, table: nil) }
        #if DEBUG
        if let seed = launchOptions.seed {
            let scenario = SampleScenarios.make(seed)
            let zone = launchOptions.timeZone ?? scenario.timeZone
            let now: NowProvider
            switch launchOptions.clock {
            case .live?: now = .live
            case .fixed(let date)?: now = .fixed(date)
            case nil: now = .fixed(scenario.referenceNow)
            }
            return AppEnvironment(
                persistence: PersistenceController(repository: InMemoryRepository(scenario.database)),
                clockStore: InMemoryClockStore(HybridLogicalClock(node: 0x5EED)),
                nowProvider: now, deviceTimeZone: { zone }, locale: { Locale.current }, catalogLookup: lookup,
                entitlements: AllAccessEntitlements(), dataSource: .seed(seed), launchOptions: launchOptions,
                saveDebounce: .milliseconds(100))
        }
        #endif
        let location = StoreLocation.resolve()
        let zoneOverride = launchOptions.timeZone
        let now: NowProvider
        if case .fixed(let date)? = launchOptions.clock { now = .fixed(date) } else { now = .live }
        return AppEnvironment(
            persistence: PersistenceController(repository: FileRepository(directory: location.directory)),
            clockStore: UserDefaultsClockStore(defaults: location.defaults),
            nowProvider: now, deviceTimeZone: { zoneOverride ?? TimeZone.current }, locale: { Locale.current },
            catalogLookup: lookup, entitlements: AllAccessEntitlements(),
            dataSource: .file(directory: location.directory, isAppGroup: location.isAppGroup),
            launchOptions: launchOptions, saveDebounce: .milliseconds(400))
    }
}

/// Resolution of the on-disk location.
struct StoreLocation {
    let directory: URL
    let isAppGroup: Bool
    let defaults: UserDefaults

    /// `<App Group container>/Tabula`, else `<Application Support>/Tabula`.
    static func resolve(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> StoreLocation {
        let groupID = AppGroup.identifier(forBundleIdentifier: bundleIdentifier)
        let fileManager = FileManager.default
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return StoreLocation(directory: container.appendingPathComponent("Tabula", isDirectory: true), isAppGroup: true,
                                 defaults: UserDefaults(suiteName: groupID) ?? .standard)
        }
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                                             create: true))
            ?? fileManager.temporaryDirectory
        return StoreLocation(directory: support.appendingPathComponent("Tabula", isDirectory: true), isAppGroup: false,
                             defaults: .standard)
    }
}

/// The HLC kept in UserDefaults (App Group suite when available) as JSON under one key.
final class UserDefaultsClockStore: ClockStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; the class holds no other state.
    private let defaults: UserDefaults
    static let key = "tabula.hlc.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> HybridLogicalClock? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(HybridLogicalClock.self, from: data)
    }

    func save(_ clock: HybridLogicalClock) {
        guard let data = try? JSONEncoder().encode(clock) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
