// Launch routes of the Tasks feature (stage B1 owns this file). Id prefix `tasks.`. Add entries here only; see
// Routing/RouteRegistry.swift.
//   tasks               → the Tasks tab (Today segment)
//   tasks.upcoming      → the tab with the Upcoming segment selected
//   tasks.overdue       → the tab with the Overdue segment selected
//   tasks.completed     → the tab with the Completed segment selected
//   tasks.editor        → sheet: the editor of a task from the `-TabulaSeed` data (the first open task by due date)
//   tasks.editor-new    → sheet: the editor for a new task; opened by the lesson detail ("Add homework for this
//                         lesson", Phase 3 C1) with `EditorContext(.newTask(TaskPrefill))` in the environment, which
//                         prefills subject, due = the lesson's date and the linked occurrence
//   tasks.detail        → sheet: the detail of the task a notification deep link asked for
//                         (`AppNavigation.presentedItem`); without one (screenshot launch) a sample task from the seed
// The detail route is also the notification deep-link target (Routing/AppNavigation.swift).
import SwiftUI
import TimetableCore
import TimetableUI

enum TasksRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("tasks", .tabRoot(.tasks)) { TasksRootView() },
            AppRoute("tasks.upcoming", .tabRoot(.tasks)) { TasksRootView(initialSegment: .upcoming) },
            AppRoute("tasks.overdue", .tabRoot(.tasks)) { TasksRootView(initialSegment: .overdue) },
            AppRoute("tasks.completed", .tabRoot(.tasks)) { TasksRootView(initialSegment: .completed) },
            AppRoute("tasks.editor", .sheet(over: .tasks)) { TaskEditorRouteView() },
            AppRoute("tasks.editor-new", .sheet(over: .tasks)) { TaskEditorNewRouteView() },
            AppRoute("tasks.detail", .sheet(over: .tasks)) { TaskDetailRouteView() },
        ]
    }
}

/// Picks seed data for the routes opened without ids: the first open task by due date, else any task.
@MainActor
private enum TaskSeedPicker {
    static func sampleTask(in model: AppModel) -> TaskItem? {
        let tasks = (model.database?.tasks ?? []).filter { !$0.isDeleted }
        let now = model.calendarContext.local(from: model.now)
        let open = TaskListModel.tasks(in: .today, from: tasks, now: now) + TaskListModel.tasks(in: .overdue, from: tasks, now: now)
            + TaskListModel.tasks(in: .upcoming, from: tasks, now: now)
        return open.first ?? tasks.first
    }
}

/// `tasks.detail`: the deep-linked task, else a sample task from the seed.
private struct TaskDetailRouteView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        if case .task(let id)? = navigation.presentedItem {
            TaskDetailView(taskID: id)
        } else if let task = TaskSeedPicker.sampleTask(in: model) {
            TaskDetailView(taskID: task.id)
        } else {
            ContentUnavailableView {
                Label { Text("tasks.detail.missing") } icon: { Image(systemName: "tray") }
            } description: {
                EmptyView()
            }
        }
    }
}

/// `tasks.editor`: edits a sample task from the seed.
private struct TaskEditorRouteView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let task = TaskSeedPicker.sampleTask(in: model) {
            TaskEditorView(mode: .edit(task.id))
        } else {
            EditorUnavailableView(messageKey: "tasks.editor.unavailable")
        }
    }
}

/// `tasks.editor-new`: a new task (the ID is generated once per presentation), prefilled when the presenter passed an
/// `EditorContext` with a `.newTask` target (Phase 3 C1, lesson detail).
private struct TaskEditorNewRouteView: View {
    @State private var newID = TaskItem.ID(UUID())
    @Environment(\.editorContext) private var editorContext

    var body: some View {
        if case .newTask(let prefill)? = editorContext?.target {
            TaskEditorView(mode: .new(newID), prefill: prefill, prefillTimetableID: editorContext?.timetableID)
        } else {
            TaskEditorView(mode: .new(newID))
        }
    }
}
