// Launch routes of Settings (owned by stage B4): `settings`, later `settings.appearance`, `settings.reminders` …
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum SettingsRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("settings", .tabRoot(.settings)) { SettingsRootView() },
        ]
    }
}
