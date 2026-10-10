// In-app navigation state shared by the shell and deep links (Phase 3 Stage A): the selected tab and the item a
// notification tap asked for. Views read it with `@Environment(AppNavigation.self)`.
//
// Deep links (notification tap → item):
//   task  → Tasks tab, then the route `tasks.detail` as a sheet if a feature registered it (stage B1)
//   exam  → Exams tab, then `exams.detail` (stage B2)
//   lesson → Timetable tab; pack tonight → Today tab (no detail sheet)
// Contract for B1/B2: register `AppRoute("tasks.detail", .sheet(over: .tasks)) { TaskDetailRouteView() }` (resp.
// `exams.detail`) in your *Routes.swift. The route's view reads `navigation.presentedItem` (`.task(id)` / `.exam(id)`)
// and shows that item; when it is `nil` (launched with `-TabulaScreen tasks.detail` for screenshots) it picks a
// sample from the seed data, like `timetable.lesson-detail` does.
// APIs: Observation.Observable (macro; allowed in app code outside Debug, PHASE2_PLAN §0.1).
import Observation
import TimetableCore
import TimetableUI

@MainActor
@Observable
final class AppNavigation {
    /// The tab the user (or a deep link) selected; `nil` = not changed yet → the launch route's tab.
    var selectedTab: AppTab?
    /// The item a deep link presents with its feature's detail route (sheet over the item's tab).
    var presentedItem: ItemLink?

    /// Opens `link`: selects its tab and, when the feature registered a detail route, presents it.
    func open(_ link: ItemLink?) {
        guard let link else { return }
        selectedTab = Self.tab(for: link)
        presentedItem = Self.detailRouteID(for: link).flatMap { RouteRegistry.route(id: $0) } == nil ? nil : link
    }

    /// The tab that shows `link`.
    static func tab(for link: ItemLink) -> AppTab {
        switch link {
        case .task: return .tasks
        case .exam: return .exams
        case .lesson: return .timetable
        case .packTonight: return .today
        }
    }

    /// The detail route id for `link` (registered by the feature stages), or `nil`.
    static func detailRouteID(for link: ItemLink) -> String? {
        switch link {
        case .task: return "tasks.detail"
        case .exam: return "exams.detail"
        case .lesson, .packTonight: return nil
        }
    }
}
