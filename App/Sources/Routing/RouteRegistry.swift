// The route registry: every feature's `RouteProvider`, in one fixed list.
//
// HOW FEATURES ADD SCREENS (Phase 2 stages B1–B4; no edits to this file needed):
//   - Each feature folder already has its provider: Onboarding/OnboardingRoutes.swift, Today/TodayRoutes.swift,
//     Timetable/TimetableRoutes.swift, Editors/EditorRoutes.swift, Settings/SettingsRoutes.swift (+ Debug/DebugRoutes.swift
//     in DEBUG). Add `AppRoute("<prefix>.<name>", <placement>) { YourView() }` entries to YOUR provider only.
//   - Id prefix = your feature (`onboarding.`, `today`, `timetable.`, `editor.`, `settings.`); `validate.sh` fails on
//     duplicate or malformed ids across all providers.
//   - Add the id to the screenshot list of .github/workflows/ui-screenshots.yml (stage C2 owns that list).
//   - A new feature folder (Phase 3: Tasks, Exams) adds ONE line to `providers` below.
// Unknown or absent `-TabulaScreen` → the normal app shell; the developer screen shows the unknown id.
import SwiftUI
import TimetableUI

enum RouteRegistry {
    /// All providers in priority order (the first registration of an id wins).
    @MainActor static var providers: [any RouteProvider.Type] {
        var list: [any RouteProvider.Type] = [
            OnboardingRoutes.self,
            TodayRoutes.self,
            TimetableRoutes.self,
            EditorRoutes.self,
            SettingsRoutes.self,
        ]
        #if DEBUG
        list.append(DebugRoutes.self)
        #endif
        return list
    }

    /// All routes in registration order.
    @MainActor static var routes: [AppRoute] { providers.flatMap { $0.routes } }

    /// Resolves `-TabulaScreen`. Duplicate/invalid ids trip an assertion in DEBUG (validate.sh catches them earlier).
    @MainActor static func resolve(_ requested: String?) -> LaunchRoute {
        let all = routes
        let table = RouteTable(ids: all.map(\.id))
        assert(table.problems.isEmpty, "route registry: \(table.problems)")
        let resolution = table.resolve(requested)
        if case .matched(_, let position) = resolution { return LaunchRoute(route: all[position], resolution: resolution) }
        return LaunchRoute(route: nil, resolution: resolution)
    }
}
