// iOS app entry point. UNCOMPILED (no Darwin SDK in the WSL environment yet).
// Module name is `TabulaApp` on both build paths (SwiftPM target name / PRODUCT_MODULE_NAME in project.yml),
// so the app type must not be called `TabulaApp` (type/module name shadowing) and no module may be called
// `App` (clashes with SwiftUI.App).
// APIs: SwiftUI.App, Scene, WindowGroup, NavigationStack (docs checked, see docs/ENVIRONMENT.md).
import SwiftUI

@main
struct TabulaRootApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                // Phase 0: the only screen is the debug/probe screen. Real UI starts in Phase 2.
                DebugScreen()
            }
        }
    }
}
