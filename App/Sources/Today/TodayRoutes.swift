// Launch routes of the Today feature (owned by stage B2). Add entries here only; see Routing/RouteRegistry.swift.
// The `today.*` state routes (Phase 4U U3) fix Today's clock to one hero moment of the secondary scenario
// (`SampleScenarios.todayMomentClocks`); use them with `-TabulaSeed secondary`.
import SwiftUI
import TimetableUI

enum TodayRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        let clocks = SampleScenarios.todayMomentClocks
        return [
            AppRoute("today", .tabRoot(.today)) { TodayRootView() },
            AppRoute("today.before-school", .tabRoot(.today)) { TodayRootView(fixedNow: clocks.beforeSchool) },
            AppRoute("today.break", .tabRoot(.today)) { TodayRootView(fixedNow: clocks.breakTime) },
            AppRoute("today.after-school", .tabRoot(.today)) { TodayRootView(fixedNow: clocks.afterSchool) },
            AppRoute("today.holiday", .tabRoot(.today)) { TodayRootView(fixedNow: clocks.holiday) },
        ]
    }
}
