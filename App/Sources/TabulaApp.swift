// iOS app entry point. Compiled on both paths (xtool: VERIFIED 2026-10-06; XcodeGen/CI: first CI run).
// Module name is `TabulaApp` on both build paths (SwiftPM target name / PRODUCT_MODULE_NAME in project.yml),
// so the app type must not be called `TabulaApp` (type/module name shadowing) and no module may be called
// `App` (clashes with SwiftUI.App).
// APIs: SwiftUI.App, Scene, WindowGroup, NavigationStack (docs checked, see docs/ENVIRONMENT.md).
import SwiftUI
import TimetableUI

@main
struct TabulaRootApp: App {
    /// `-TabulaScreen <id>` selects the first screen (Routing/AppScreen.swift). Read once at launch.
    private let route = ScreenRoute<AppScreen>.forCurrentProcess()

    var body: some Scene {
        WindowGroup {
            // Phase 0: the only screen is the debug/probe screen. Real UI starts in Phase 2.
            AppRootView(route: route)
        }
    }
}
