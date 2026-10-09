// PLACEHOLDER (Stage A) — stage B2 replaces this file with the real timetable views (grid, week, day, tiles).
// Keep the type name `TimetableRootView` and its no-argument init: the app shell uses it.
// APIs: NavigationStack, ContentUnavailableView(label:description:actions:), navigationTitle(_:).
import SwiftUI
import TimetableUI

struct TimetableRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label { Text("timetable.placeholder.title") } icon: { Image(systemName: "calendar") }
            } description: {
                if let timetable = model.activeTimetable {
                    Text(verbatim: timetable.name)
                }
            } actions: {
                EmptyView()
            }
            .navigationTitle(Text("shell.tab.timetable"))
        }
    }
}
