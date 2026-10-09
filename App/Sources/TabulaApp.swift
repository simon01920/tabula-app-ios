// iOS app entry point. Compiled on both paths (xtool and XcodeGen/CI).
// Module name is `TabulaApp` on both build paths (SwiftPM target name / PRODUCT_MODULE_NAME in project.yml),
// so the app type must not be called `TabulaApp` (type/module name shadowing) and no module may be called
// `App` (clashes with SwiftUI.App).
// APIs: SwiftUI.App, Scene, WindowGroup, State (macro in the Xcode 27 SDK; allowed per PHASE2_PLAN §0.1),
//       Environment(\.scenePhase), ScenePhase, View.environment(_:) for Observable objects, View.task(_:),
//       View.onChange(of:_:) (two-parameter closure, iOS 17).
import SwiftUI
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
            if phase != .active {
                Task { await model.flush() }
            }
        }
    }
}
