// Debug launch routes (DEBUG builds only). Ids are unchanged from Phase 0 so the CI screenshot list keeps working.
#if DEBUG
import SwiftUI

enum DebugRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        DebugArea.allCases.map { area in
            AppRoute(area.rawValue, .standalone) { DebugScreen(area: area) }
        } + [
            AppRoute("debug-developer", .standalone) { DeveloperScreen() },
        ]
    }
}
#endif // DEBUG
