// Launch routes of the Exams feature (stage B2 owns this file). Id prefix `exams.`. Add entries here only; see
// Routing/RouteRegistry.swift.
//   exams               → the Exams tab (Upcoming)
//   exams.history       → the tab on the History segment
//   exams.detail        → sheet over the tab: the notification deep-link target (`AppNavigation.presentedItem`
//                         `.exam`); launched without an item it shows the next exam of the seed data
//   exams.editor        → sheet: the editor for that same sample exam (a new exam when the seed has none)
//   exams.editor-new    → sheet: the editor for a new exam
//   exams.selected      → the tab with the sample exam open (detail column on wide screens, else pushed)
// Seed data: every scenario of `-TabulaSeed` has at least one upcoming exam; since Phase 3 C1 `secondary` also has a
// past History test (History segment) and `university` an exam-period break with two finals (period header).
import SwiftUI
import TimetableCore

enum ExamsRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("exams", .tabRoot(.exams)) { ExamsRootView() },
            AppRoute("exams.history", .tabRoot(.exams)) { ExamsRootView(initialSegment: .history) },
            AppRoute("exams.detail", .sheet(over: .exams)) { ExamDetailRouteView() },
            AppRoute("exams.editor", .sheet(over: .exams)) { ExamEditorRouteView() },
            AppRoute("exams.editor-new", .sheet(over: .exams)) { ExamEditorView(target: .new) },
            AppRoute("exams.selected", .tabRoot(.exams)) { ExamsSelectedRouteView() },
        ]
    }
}

/// `exams.selected` (adaptive layout): the tab with the sample exam open (detail column when wide, else pushed).
private struct ExamsSelectedRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ExamsRootView(initialSelection: ExamSeedPicker.sample(in: model)?.id)
    }
}

/// `exams.editor` without an id: edits the sample exam, else opens a new one.
private struct ExamEditorRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let exam = ExamSeedPicker.sample(in: model) {
            ExamEditorView(target: .existing(exam.id))
        } else {
            ExamEditorView(target: .new)
        }
    }
}
