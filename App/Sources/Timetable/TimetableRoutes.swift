// Launch routes of the Timetable feature (owned by stage B2): `timetable`, later `timetable.grid|week|day|tiles`.
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum TimetableRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("timetable", .tabRoot(.timetable)) { TimetableRootView() },
        ]
    }
}
