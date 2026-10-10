// The Tasks tab root — Phase 3 Stage A PLACEHOLDER (empty state only). Stage B1 replaces the body.
// Keep the type name `TasksRootView` and its no-argument init: the app shell (AppShell/AppRootView.swift) and the
// `tasks` route use them.
// APIs: NavigationStack, ContentUnavailableView (iOS 17), navigationTitle(_:).
import SwiftUI

struct TasksRootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label { Text("tasks.empty.title") } icon: { Image(systemName: "checklist") }
            } description: {
                Text("tasks.empty.detail")
            }
            .navigationTitle(Text("tasks.title"))
        }
    }
}
