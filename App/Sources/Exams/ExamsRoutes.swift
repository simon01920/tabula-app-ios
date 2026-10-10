// Launch routes of the Exams feature (stage B2 owns this file). Id prefix `exams.`. Add entries here only; see
// Routing/RouteRegistry.swift. Stage A registers only the tab root.
//   exams          → the Exams tab
// B2 adds e.g. `exams.detail` (`.sheet(over: .exams)`, also the notification deep-link target — see
// Routing/AppNavigation.swift), `exams.editor` and the exam-period view.
import SwiftUI

enum ExamsRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("exams", .tabRoot(.exams)) { ExamsRootView() },
        ]
    }
}
