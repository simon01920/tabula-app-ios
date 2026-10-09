// Launch-route types (`-TabulaScreen <id>`): how a screen can be opened directly for CI simulator screenshots, manual
// QA and later deep links. See RouteRegistry.swift for how features contribute routes.
import SwiftUI
import TimetableUI

/// The tabs of the app shell (PHASE2_PLAN §0.3). Phase 3 adds `.tasks` and `.exams`.
enum AppTab: String, CaseIterable, Hashable, Sendable {
    case today
    case timetable
    case settings
}

/// Where a route's view appears.
enum RoutePlacement: Sendable {
    /// As the root of `tab` (the tab is selected; other tabs keep their normal roots).
    case tabRoot(AppTab)
    /// Presented as a sheet over the normal root of `tab` (editors).
    case sheet(over: AppTab)
    /// In place of the onboarding root (shown even if onboarding was completed: screenshots of single steps).
    case onboarding
    /// Instead of the whole shell, inside a NavigationStack (debug screens).
    case standalone
}

/// One launchable screen.
struct AppRoute: Sendable {
    /// Stable id (`RouteTable.isValidID`): lowercase words joined by "." or "-", prefixed with the feature,
    /// e.g. `today`, `timetable.week`, `editor.lesson`, `settings.appearance`, `onboarding.rotation`.
    let id: String
    let placement: RoutePlacement
    /// Builds the view. Views read `AppModel` from the environment; data-driven screens must render something
    /// meaningful from the `-TabulaSeed` data (never from whatever is on the simulator).
    let makeView: @MainActor @Sendable () -> AnyView

    init<V: View>(_ id: String, _ placement: RoutePlacement, @ViewBuilder view: @escaping @MainActor @Sendable () -> V) {
        self.id = id
        self.placement = placement
        self.makeView = { AnyView(view()) }
    }
}

/// A feature's routes. Each feature folder owns exactly one provider file (e.g. Today/TodayRoutes.swift).
protocol RouteProvider {
    @MainActor static var routes: [AppRoute] { get }
}

/// The resolved launch route for this process.
struct LaunchRoute {
    let route: AppRoute?
    let resolution: RouteTable.Resolution
}
