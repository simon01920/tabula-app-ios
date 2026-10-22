// The app's object graph (PHASE2_PLAN §0.5 dependency container, extended in Phase 3 Stage A): the model, the
// navigation state, the reminder coordinator and the notification delegate. Owned by the UIKit app delegate so it
// exists before the app finishes launching — a notification action or a background refresh can launch the app without
// any window, and the delegate must be set by then (UNUserNotificationCenter.delegate docs).
// APIs: SwiftUI.UIApplicationDelegateAdaptor (iOS 14; "define it only in your App declaration, and only once"),
//       UIApplicationDelegate.application(_:willFinishLaunchingWithOptions:), UNUserNotificationCenter.current().delegate
//       (weak — retained here). Docs checked 2026-10-10.
import Foundation
import TimetableUI
import UIKit
import UserNotifications

@MainActor
final class AppServices {
    let model: AppModel
    let navigation: AppNavigation
    let reminders: ReminderCoordinator
    let notificationDelegate: NotificationResponseDelegate
    /// Widget snapshot writer (Phase 4 A): App Group snapshot + WidgetKit reload after every change.
    let widgets: WidgetSnapshotWriter
    /// Lesson + exam-day Live Activities (Phase 4 B2): start / schedule / update / end after every change.
    let liveActivities: LiveActivityController
    /// What App Intents run in this process (Phase 4 B3): Mark done, "What's next?", "Add homework".
    let intents: AppIntentHost

    init(environment: AppEnvironment) {
        let model = AppModel(environment: environment)
        let navigation = AppNavigation()
        let engine = ReminderEngine(notifications: environment.reminders.notifications,
                                    alarms: environment.reminders.alarms, store: environment.reminders.stateStore)
        let reminders = ReminderCoordinator(engine: engine, model: model, navigation: navigation,
                                            backgroundScheduler: environment.reminders.backgroundScheduler,
                                            deviceState: environment.reminders.deviceState,
                                            offerStore: environment.reminders.offerStore)
        self.model = model
        self.navigation = navigation
        self.reminders = reminders
        notificationDelegate = NotificationResponseDelegate { action, delivered in
            await reminders.handle(action, delivered)   // both live as long as the app (no cycle: the coordinator does not hold the delegate)
        }
        reminders.attach()
        AttachmentMaintenance.install(on: model)   // orphan attachment cleanup after load + changes (B3); chains onChange
        widgets = WidgetSnapshotWriter.install(on: model)   // widget snapshot after load + changes (Phase 4 A); chains onChange
        let liveActivities = LiveActivityController.install(on: model)   // Live Activities (Phase 4 B2); chains onChange
        self.liveActivities = liveActivities
        // A background refresh near the next lesson boundary / exam start while an activity runs.
        reminders.additionalRefreshDate = { [weak liveActivities] in liveActivities?.backgroundRefreshHint }
        // App Intents (Phase 4 B3): registered here, before launch finishes, so an intent that launched the app in the
        // background (widget checkbox, alarm "Done") finds the services; the widget extension never registers any.
        intents = AppIntentHost(model: model, reminders: reminders, navigation: navigation, widgets: widgets)
        IntentHost.register(intents)
    }
}

/// UIKit app delegate: owns `AppServices` and installs the notification delegate before launch finishes.
@MainActor
final class TabulaAppDelegate: NSObject, UIApplicationDelegate {
    let services = AppServices(environment: .make(launchOptions: LaunchContext.options))

    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = services.notificationDelegate
        return true
    }
}
