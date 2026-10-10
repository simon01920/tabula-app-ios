// Launch routes of the Timetable feature (owned by stage B2). Add entries here only; see Routing/RouteRegistry.swift.
//   timetable                 → the tab with the timetable's remembered view
//   timetable.grid|week|day|tiles → the tab forced to that view (not persisted)
//   timetable.lesson-detail   → sheet: a changed lesson of the shown week (else the first lesson)
//   timetable.quick-add       → sheet: the subject picker for the first free slot of the shown week
// Sheets pick their subject from the `-TabulaSeed` data; with no matching data they show an empty state.
import SwiftUI
import TimetableCore
import TimetableUI

enum TimetableRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("timetable", .tabRoot(.timetable)) { TimetableRootView() },
            AppRoute("timetable.grid", .tabRoot(.timetable)) { TimetableRootView(initialView: .grid) },
            AppRoute("timetable.week", .tabRoot(.timetable)) { TimetableRootView(initialView: .timeBlocks) },
            AppRoute("timetable.day", .tabRoot(.timetable)) { TimetableRootView(initialView: .day) },
            AppRoute("timetable.tiles", .tabRoot(.timetable)) { TimetableRootView(initialView: .tiles) },
            AppRoute("timetable.lesson-detail", .sheet(over: .timetable)) { LessonDetailRouteView() },
            AppRoute("timetable.quick-add", .sheet(over: .timetable)) { QuickAddRouteView() },
        ]
    }
}

/// Picks a sample occurrence for the lesson-detail route.
private struct LessonDetailRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let target {
            LessonDetailView(target: target)
        } else {
            RouteEmptyView()
        }
    }

    private var target: LessonDetailTarget? {
        guard let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) else { return nil }
        let start = TimetableCore.GridLayout.displayWeekStart(today: model.today, resolver: resolver)
        let entries = (0..<7).flatMap { resolver.day(start.adding(days: $0)).entries }
        let pick = entries.first { $0.status == .modified } ?? entries.first { $0.status != .scheduled }
            ?? resolver.day(model.today).entries.first ?? entries.first
        return pick.map(LessonDetailTarget.init)
    }
}

/// Picks the first free slot of the shown week for the quick-add route.
private struct QuickAddRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let target {
            QuickAddSheet(target: target)
        } else {
            RouteEmptyView()
        }
    }

    private var target: QuickAddTarget? {
        guard let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) else { return nil }
        let start = TimetableCore.GridLayout.displayWeekStart(today: model.today, resolver: resolver)
        let layout = TimetableCore.GridLayout.week(containing: start, resolver: resolver)
        return layout.emptySlots.lazy.compactMap {
            QuickAddTarget.make(layout: layout, column: $0.column, row: $0.row, timetable: timetable)
        }.first
    }
}

/// Shown by a sheet route when the seed has nothing to show.
private struct RouteEmptyView: View {
    var body: some View {
        ContentUnavailableView {
            Label { Text("timetable.route.nothingToShow") } icon: { Image(systemName: "tray") }
        } description: {
            EmptyView()
        } actions: {
            EmptyView()
        }
    }
}
