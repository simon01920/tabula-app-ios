// Launch routes of sharing (Phase 7 H1): `share.sheet` (Share Timetable over the Timetable tab, the seed's active
// timetable; secondary fits inline, so no network), `share.import` (the entry choices), `share.import-preview` (the
// seed's active timetable as if it had arrived by link, tasks included). Add entries here only; see
// Routing/RouteRegistry.swift.
import SwiftUI

enum SharingRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("share.sheet", .sheet(over: .timetable)) { ShareTimetableRouteView() },
            AppRoute("share.import", .sheet(over: .settings)) { ShareImportView() },
            AppRoute("share.import-preview", .sheet(over: .settings)) { ShareImportPreviewRouteView() },
        ]
    }
}
