// Launch routes of the Today feature (owned by stage B2). Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum TodayRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("today", .tabRoot(.today)) { TodayRootView() },
        ]
    }
}
