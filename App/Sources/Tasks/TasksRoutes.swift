// Launch routes of the Tasks feature (stage B1 owns this file). Id prefix `tasks.`. Add entries here only; see
// Routing/RouteRegistry.swift. Stage A registers only the tab root.
//   tasks          → the Tasks tab
// B1 adds e.g. `tasks.detail` (`.sheet(over: .tasks)`, also the notification deep-link target — see
// Routing/AppNavigation.swift) and `tasks.editor`.
import SwiftUI

enum TasksRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("tasks", .tabRoot(.tasks)) { TasksRootView() },
        ]
    }
}
