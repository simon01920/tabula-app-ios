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
    /// Notification centre, AlarmKit, applied-plan store, background refresh and device state for the reminder adapter.
    let reminders: ReminderDependencies
    /// Attachment files (stage B3): `<store directory>/Attachments`; a throwaway temp folder for seed runs.
    let attachments: any AttachmentStore
    /// The App Group container the widget snapshot is written to (Phase 4 A); `nil` without an App Group (free team:
    /// the widgets show "Open Tabula") and in seed mode (seed data must never reach the real widgets).
    let widgetContainer: URL?
    /// Live Activity preferences / ledger store; seed runs never touch ActivityKit (Phase 4 B2).
    let liveActivities: LiveActivityDependencies

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
                saveDebounce: .milliseconds(100),
                // Live seed runs keep their applied-plan state in their own suite, never next to the real store's.
                reminders: launchOptions.liveReminders
                    ? .live(defaults: UserDefaults(suiteName: "sk.simondev.tabula.seed-reminders") ?? .standard)
                    : .inMemory(),
                attachments: FileAttachmentStore(root: FileManager.default.temporaryDirectory
                    .appendingPathComponent("TabulaSeedAttachments", isDirectory: true)),
                widgetContainer: nil, liveActivities: .inMemory())
        }
        #endif
        // The real store always uses the real clock and the system zone: -TabulaNow/-TabulaTimeZone are honoured only
        // with -TabulaSeed (LaunchOptions drops them otherwise), so fake times never reach persisted data or the HLC.
        let location = StoreLocation.resolve()
        return AppEnvironment(
            persistence: PersistenceController(repository: FileRepository(directory: location.directory)),
            clockStore: UserDefaultsClockStore(defaults: location.defaults),
            nowProvider: .live, deviceTimeZone: { TimeZone.current }, locale: { Locale.current },
            catalogLookup: lookup, entitlements: AllAccessEntitlements(),
            dataSource: .file(directory: location.directory, isAppGroup: location.isAppGroup),
            launchOptions: launchOptions, saveDebounce: .milliseconds(400),
            reminders: .live(defaults: location.defaults),
            attachments: FileAttachmentStore(root: FileAttachmentStore.root(forStoreDirectory: location.directory)),
            widgetContainer: location.groupContainer, liveActivities: .live(defaults: location.defaults))
    }
}

/// Resolution of the on-disk location.
struct StoreLocation {
    let directory: URL
    let isAppGroup: Bool
    let defaults: UserDefaults
    /// The App Group container itself (`nil` for the Application Support fallback).
    let groupContainer: URL?

    /// `<App Group container>/Tabula`, else `<Application Support>/Tabula`.
    static func resolve(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> StoreLocation {
        let groupID = AppGroup.identifier(forBundleIdentifier: bundleIdentifier)
        let fileManager = FileManager.default
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return StoreLocation(directory: container.appendingPathComponent("Tabula", isDirectory: true), isAppGroup: true,
                                 defaults: UserDefaults(suiteName: groupID) ?? .standard, groupContainer: container)
        }
        let support = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
                                             create: true))
            ?? fileManager.temporaryDirectory
        return StoreLocation(directory: support.appendingPathComponent("Tabula", isDirectory: true), isAppGroup: false,
                             defaults: .standard, groupContainer: nil)
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

/// What the reminder adapter talks to (Phase 3 Stage A). Live: `UNUserNotificationCenter`, AlarmKit, the App Group
/// UserDefaults, `BGTaskScheduler`, UIKit/ProcessInfo. In memory (`-TabulaSeed` without `-TabulaReminders live`):
/// fakes, so screenshots and seed runs never schedule anything on the device or simulator.
struct ReminderDependencies: Sendable {
    let notifications: any NotificationCenterClient
    let alarms: any AlarmClient
    let stateStore: any ReminderStateStore
    let backgroundScheduler: any BackgroundRefreshScheduling
    let deviceState: @MainActor @Sendable () -> DeviceReminderState
    /// Remembers "Not Now" on the in-context notification pre-explainer (per install; QA fix Q1).
    let offerStore: any ReminderPermissionOfferStore
    /// `true` when the real system clients are used (debug screen).
    let isLive: Bool

    static func live(defaults: UserDefaults) -> ReminderDependencies {
        ReminderDependencies(notifications: LiveNotificationCenterClient(), alarms: LiveAlarmClient(),
                             stateStore: UserDefaultsReminderStateStore(defaults: defaults),
                             backgroundScheduler: LiveBackgroundRefreshScheduler(),
                             deviceState: { DeviceStateReader.live() },
                             offerStore: UserDefaultsReminderPermissionOfferStore(defaults: defaults), isLive: true)
    }

    /// Plausible fixed state for screenshots: everything allowed, Time Sensitive not available (as in xtool builds).
    static func inMemory() -> ReminderDependencies {
        ReminderDependencies(notifications: InMemoryNotificationCenterClient(authorization: .authorized,
                                                                             timeSensitive: .notSupported),
                             alarms: InMemoryAlarmClient(authorization: .authorized),
                             stateStore: InMemoryReminderStateStore(),
                             backgroundScheduler: RecordingBackgroundRefreshScheduler(),
                             deviceState: { DeviceReminderState(isLowPowerModeEnabled: false, backgroundRefresh: .available) },
                             offerStore: InMemoryReminderPermissionOfferStore(), isLive: false)
    }
}
