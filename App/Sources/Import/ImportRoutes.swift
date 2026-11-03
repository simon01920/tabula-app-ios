// Launch routes of the photo import (Phase 9 I2), all as sheets over the Timetable tab:
//   import.capture            the source choices
//   import.processing         DEBUG: the fixture picture, "Finding the table" running
//   import.review             DEBUG: the parsed Slovak aSc fixture, scrolled to the grid
//   import.review-questions   DEBUG: the same, at the top (counts and Questions)
// `settings.import-model` is in SettingsRoutes. Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum ImportRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        var routes = [AppRoute("import.capture", .sheet(over: .timetable)) { PhotoImportView() }]
        #if DEBUG
        routes += [
            AppRoute("import.processing", .sheet(over: .timetable)) {
                PhotoImportView(flow: ImportFixtures.model(stage: .processing, step: .finding))
            },
            AppRoute("import.review", .sheet(over: .timetable)) {
                PhotoImportView(flow: ImportFixtures.model(stage: .review, anchor: "grid"))
            },
            AppRoute("import.review-questions", .sheet(over: .timetable)) {
                PhotoImportView(flow: ImportFixtures.model(stage: .review))
            },
        ]
        #endif
        return routes
    }
}
