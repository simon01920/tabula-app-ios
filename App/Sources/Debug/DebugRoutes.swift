// Debug launch routes (DEBUG builds only). Ids are unchanged from Phase 0 so the CI screenshot list keeps working.
// Phase 4 A: the widget gallery routes (`widgets.gallery*`, Debug/WidgetGallery.swift).
// Phase 4 B2: the Live Activity gallery routes (`widgets.gallery-live*`, Debug/LiveActivityGallery.swift).
// Phase 4U U1: `debug.design` (Debug/DesignSystemDebugScreen.swift): tokens, AppSymbol existence check, NowMarker.
#if DEBUG
import SwiftUI

enum DebugRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        DebugArea.allCases.map { area in
            AppRoute(area.rawValue, .standalone) { DebugScreen(area: area) }
        } + [
            AppRoute("debug-developer", .standalone) { DeveloperScreen() },
            AppRoute("widgets.gallery", .standalone) { WidgetGalleryScreen(page: .daytime) },
            AppRoute("widgets.gallery-evening", .standalone) { WidgetGalleryScreen(page: .evening) },
            AppRoute("widgets.gallery-pro", .standalone) { WidgetGalleryScreen(page: .pro) },
            AppRoute("widgets.gallery-today", .standalone) { WidgetGalleryScreen(page: .today) },
            AppRoute("widgets.gallery-homework", .standalone) { WidgetGalleryScreen(page: .homework) },
            AppRoute("widgets.gallery-exam", .standalone) { WidgetGalleryScreen(page: .exam) },
            AppRoute("widgets.gallery-live", .standalone) { LiveActivityGalleryScreen(page: .lessons) },
            AppRoute("widgets.gallery-live-exam", .standalone) { LiveActivityGalleryScreen(page: .exams) },
            AppRoute("debug.design", .standalone) { DesignSystemDebugScreen() },
        ]
    }
}
#endif // DEBUG
