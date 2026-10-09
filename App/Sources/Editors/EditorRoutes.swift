// Launch routes of the editors (owned by stage B3): `editor.lesson`, `editor.subject`, `editor.subjects`,
// `editor.bellSchedule` → use ids like `editor.bell-schedule`, `editor.override`, `editor.timetables` …
// Editors are sheets: register them with `.sheet(over: .timetable)` and build them from the `-TabulaSeed` data,
// e.g. `AppRoute("editor.lesson", .sheet(over: .timetable)) { LessonEditorRoute() }` where the route view picks the
// first lesson of `model.activeTimetable`. Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum EditorRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] { [] }
}
