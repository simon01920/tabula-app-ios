// iOS app entry point. Compiled on both paths (xtool and XcodeGen/CI).
// Module name is `TabulaApp` on both build paths (SwiftPM target name / PRODUCT_MODULE_NAME in project.yml),
// so the app type must not be called `TabulaApp` (type/module name shadowing) and no module may be called
// `App` (clashes with SwiftUI.App).
// APIs: SwiftUI.App, Scene, WindowGroup, State (macro in the Xcode 27 SDK; allowed per PHASE2_PLAN §0.1),
//       Environment(\.scenePhase), ScenePhase, View.environment(_:) for Observable objects, View.task(_:),
//       View.onChange(of:_:) (two-parameter closure, iOS 17), UIApplication.beginBackgroundTask(withName:expirationHandler:),
//       UIApplication.endBackgroundTask(_:).
import SwiftUI
import UIKit
import TimetableUI

/// Launch options of this process, parsed once. Developer overrides (-TabulaSeed/-TabulaNow/-TabulaTimeZone) only in
/// DEBUG builds; Release ignores them (PHASE2_PLAN §0.6).
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
    @State private var model = AppModel(environment: .make(launchOptions: LaunchContext.options))
    /// `-TabulaScreen <id>` resolved against the route registry (Routing/RouteRegistry.swift). Read once at launch.
    private let launchRoute = RouteRegistry.resolve(LaunchContext.options.screen)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView(launchRoute: launchRoute)
                .environment(model)
                .task { await model.load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshEnvironment()   // day / time zone / locale may have changed while suspended
            } else {
                BackgroundSave.flush(model)
            }
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
