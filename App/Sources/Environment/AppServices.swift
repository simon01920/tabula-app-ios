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

    init(environment: AppEnvironment) {
        let model = AppModel(environment: environment)
        let navigation = AppNavigation()
        let engine = ReminderEngine(notifications: environment.reminders.notifications,
                                    alarms: environment.reminders.alarms, store: environment.reminders.stateStore)
        let reminders = ReminderCoordinator(engine: engine, model: model, navigation: navigation,
                                            backgroundScheduler: environment.reminders.backgroundScheduler,
                                            deviceState: environment.reminders.deviceState)
        self.model = model
        self.navigation = navigation
        self.reminders = reminders
        notificationDelegate = NotificationResponseDelegate { action, delivered in
            await reminders.handle(action, delivered)   // both live as long as the app (no cycle: the coordinator does not hold the delegate)
        }
        reminders.attach()
        AttachmentMaintenance.install(on: model)   // orphan attachment cleanup after load + changes (B3); chains onChange
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
