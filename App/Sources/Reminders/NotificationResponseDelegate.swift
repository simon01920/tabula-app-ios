// The app's `UNUserNotificationCenterDelegate` (Phase 3 Stage A, PHASE3_PLAN §0.4): notification actions (Mark done,
// Snooze 1 h / Tomorrow morning), taps (deep link) and foreground presentation (banner + list + sound).
// Set as the centre's delegate in `application(_:willFinishLaunchingWithOptions:)` (TabulaAppDelegate), as Apple
// requires "before your app finishes launching" so responses that launch the app are not lost.
// APIs (developer.apple.com DocC JSON, checked 2026-10-10):
//   UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:) — completion handler is
//     `@escaping @Sendable () -> Void`, must be called after processing;
//   userNotificationCenter(_:willPresent:withCompletionHandler:) — `@Sendable (UNNotificationPresentationOptions) -> Void`;
//   UNNotificationResponse.actionIdentifier, UNNotificationDefaultActionIdentifier, UNNotificationDismissActionIdentifier,
//   UNNotificationPresentationOptions (.banner, .list, .sound).
//
// Concurrency: the callbacks are `nonisolated`; they copy everything they need into Sendable values synchronously
// (UNNotificationResponse is not Sendable) and hop to the main actor for the work, then call the completion handler.
import Foundation
import TimetableCore
import TimetableUI
import UserNotifications

final class NotificationResponseDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    /// Main-actor handler (the reminder coordinator); `@MainActor` closures are Sendable.
    private let handler: @MainActor @Sendable (NotificationResponseAction, DeliveredNotification) async -> Void

    init(handler: @escaping @MainActor @Sendable (NotificationResponseAction, DeliveredNotification) async -> Void) {
        self.handler = handler
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let delivered = DeliveredNotification(response.notification)
        let action: NotificationResponseAction
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: action = .open
        case UNNotificationDismissActionIdentifier: action = .dismiss
        default: action = .custom(response.actionIdentifier)
        }
        let handler = self.handler
        Task { @MainActor in
            await handler(action, delivered)
            completionHandler()
        }
    }

    /// Foreground: show it like in the background (banner + Notification Center list + sound).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
