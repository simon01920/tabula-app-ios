// iOS app entry point. Compiled on both paths (xtool and XcodeGen/CI).
// Module name is `TabulaApp` on both build paths (SwiftPM target name / PRODUCT_MODULE_NAME in project.yml),
// so the app type must not be called `TabulaApp` (type/module name shadowing) and no module may be called
// `App` (clashes with SwiftUI.App).
// APIs: SwiftUI.App, Scene, WindowGroup, UIApplicationDelegateAdaptor (iOS 14), Environment(\.scenePhase), ScenePhase,
//       View.environment(_:) for Observable objects, View.task(_:), View.onChange(of:_:) (two-parameter closure, iOS 17),
//       Scene.backgroundTask(_:action:) + BackgroundTask.appRefresh(_:) (iOS 16; the action's return completes the task,
//       SwiftUI registers the identifier), UIApplication.beginBackgroundTask(withName:expirationHandler:),
//       UIApplication.endBackgroundTask(_:), View.onOpenURL(perform:) (iOS 14; WidgetKit passes widgetURL / Link URLs to it:
//       "Linking to specific app scenes from your widget or Live Activity", checked 2026-10-16).
import SwiftUI
import TipKit
import UIKit
import TimetableUI

/// Launch options of this process, parsed once. Developer overrides (-TabulaScreen/-TabulaSeed/-TabulaNow/
/// -TabulaTimeZone/-TabulaReminders) only in DEBUG builds; Release ignores them all (PHASE2_PLAN §0.6, decision P2-6).
enum LaunchContext {
    static let options: LaunchOptions = {
        #if DEBUG
        let allowsDeveloperOverrides = true
        #else
        let allowsDeveloperOverrides = false
        #endif
        return LaunchOptions(arguments: LaunchArguments(ProcessInfo.processInfo.arguments),
                             allowsDeveloperOverrides: allowsDeveloperOverrides)
    }()
}

@main
struct TabulaRootApp: App {
    /// Owns `AppServices` (model, navigation, reminders) from before launch finishes (Environment/AppServices.swift).
    @UIApplicationDelegateAdaptor private var appDelegate: TabulaAppDelegate
    /// `-TabulaScreen <id>` resolved against the route registry (Routing/RouteRegistry.swift). Read once at launch;
    /// always "no route" in Release (LaunchOptions drops the argument).
    private let launchRoute = RouteRegistry.resolve(LaunchContext.options.screen)
    @Environment(\.scenePhase) private var scenePhase

    private var services: AppServices { appDelegate.services }

    var body: some Scene {
        let reminders = services.reminders
        let liveActivities = services.liveActivities
        WindowGroup {
            AppRootView(launchRoute: launchRoute)
                .environment(services.model)
                .environment(services.navigation)
                .environment(services.reminders)
                .environment(services.liveActivities)
                .task { await services.model.load() }
                // TipKit once per launch (the Timetable symbol legend, U4); its screenshot route shows every tip.
                .task {
                    if LaunchContext.options.screen == "timetable.grid-legend" { Tips.showAllTipsForTesting() }
                    try? Tips.configure()
                }
                // Widget taps (Phase 4 A): `tabula://open/…` (ItemLinkURL) → the same path as a notification tap.
                // Anything else is ignored (any app or web page can send the app a URL).
                .onOpenURL { url in
                    services.navigation.open(ItemLinkURL.link(from: url))
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.model.refreshEnvironment()   // day / time zone / locale may have changed; also re-plans reminders
            } else {
                BackgroundSave.flush(services.model)
                services.widgets.flushNow()           // a change made just before leaving reaches the widgets
            }
        }
        // The BGAppRefreshTask handler: loads the store if the app was launched for it, re-plans the reminders and
        // submits the next request (first, so a slow ActivityKit call can never cut the refresh chain; the request uses
        // the Live Activity hint of the previous run), then updates / ends the Live Activities (Phase 4 B2).
        // Returning completes the task (SwiftUI cancels it when the time is up).
        .backgroundTask(.appRefresh(BackgroundRefreshPolicy.taskIdentifier)) {
            await reminders.backgroundRefresh()
            await liveActivities.backgroundRefresh()
        }
    }
}

/// Writes pending changes when the scene leaves `active`, inside a UIKit background task so iOS does not suspend the
/// app in the middle of the write. Docs (2026-10-10): `beginBackgroundTask(withName:expirationHandler:)` returns
/// `.invalid` when background time is not granted; every begin must be balanced by exactly one
/// `endBackgroundTask(_:)`, also from the expiration handler (`@MainActor @Sendable`), else the app is killed.
@MainActor
enum BackgroundSave {
    @MainActor private final class Token {
        var id: UIBackgroundTaskIdentifier = .invalid
        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    static func flush(_ model: AppModel) {
        let token = Token()
        token.id = UIApplication.shared.beginBackgroundTask(withName: "tabula.save") {
            token.end()   // time is up: end the task; the store files stay consistent (atomic rename)
        }
        Task { @MainActor in
            await model.flush()
            token.end()
        }
    }
}
