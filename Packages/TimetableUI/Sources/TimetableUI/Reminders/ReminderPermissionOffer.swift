// The in-context offer of the notification pre-explainer (Phase 3 final QA fix Q1, PHASE3_PLAN §0.5: "a pre-explainer
// sheet the first time a reminder would be scheduled", never at launch). Pure, Linux-tested.
//
// The app (ReminderCoordinator) arms the offer when the user saves a task or exam (editor Save, quick add, lesson
// detail "Add homework", onboarding finish: `AppModel.apply(_:origin: .userSave)`). The re-plan that follows asks
// `shouldOffer`: only for that trigger, only while the permission is "not determined", only when the plan really has a
// reminder to deliver, and never again after the user closed the offer without allowing ("Not Now" or a swipe),
// which `UserDefaultsReminderPermissionOfferStore` remembers per install (App Group defaults, never synced).
// Launch, foreground, background refresh, timer and notification-action re-plans never offer it. The explicit entry
// points (the Settings reminder toggles, the override section, the health check's "Allow" action) are unaffected.
import Foundation

/// Decides whether the shell offers the notification pre-explainer after a re-plan.
public enum ReminderPermissionOffer {
    /// What caused the re-plan, as far as the offer cares.
    public enum Trigger: String, Sendable, Hashable, CaseIterable {
        /// The user saved a task or exam (editor, quick add, lesson detail "Add homework", onboarding finish).
        case userSave
        /// The store loaded at launch.
        case launch
        /// The scene became active, or the time zone / locale / day changed.
        case foreground
        /// `BGAppRefreshTask`.
        case backgroundRefresh
        /// A notification action (Mark done, Snooze).
        case notificationAction
        /// Anything else: other data changes, the in-app timer, permission or alarm-authorisation changes, manual.
        case other
    }

    /// `true` when the pre-explainer should be offered now.
    /// - Parameters:
    ///   - authorization: the current notification permission.
    ///   - trigger: why this re-plan ran.
    ///   - alreadyDeclined: the user closed an earlier offer without allowing (persisted per install).
    ///   - plannedRequestCount: planner requests (notifications + loud alarms) in the plan, before any add failed.
    public static func shouldOffer(authorization: NotificationAuthorization, trigger: Trigger, alreadyDeclined: Bool,
                                   plannedRequestCount: Int) -> Bool {
        trigger == .userSave && authorization == .notDetermined && !alreadyDeclined && plannedRequestCount > 0
    }

    /// `true` when closing the offer counts as "Not Now": the permission is still not determined afterwards (the user
    /// tapped Not Now or swiped the sheet away). After "Allow" the system answered, so nothing is recorded.
    public static func closingRecordsDecline(authorizationAfterClose: NotificationAuthorization) -> Bool {
        authorizationAfterClose == .notDetermined
    }
}

/// Remembers that the user declined the in-context offer (per install).
public protocol ReminderPermissionOfferStore: Sendable {
    var isDeclined: Bool { get }
    func recordDeclined()
}

/// In memory (tests, `-TabulaSeed`).
public final class InMemoryReminderPermissionOfferStore: ReminderPermissionOfferStore, @unchecked Sendable {
    // Guarded by `lock`; the class holds no other state.
    private let lock = NSLock()
    private var declined: Bool

    public init(declined: Bool = false) {
        self.declined = declined
    }

    public var isDeclined: Bool { lock.withLock { declined } }
    public func recordDeclined() { lock.withLock { declined = true } }
}

/// In UserDefaults (the App Group suite: per install, removed with the app, never synced).
public final class UserDefaultsReminderPermissionOfferStore: ReminderPermissionOfferStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; the class holds no other state.
    private let defaults: UserDefaults
    public static let key = "tabula.reminders.permissionOfferDeclined.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var isDeclined: Bool { defaults.bool(forKey: Self.key) }
    public func recordDeclined() { defaults.set(true, forKey: Self.key) }
}
