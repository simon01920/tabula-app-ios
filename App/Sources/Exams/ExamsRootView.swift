// The Exams tab root — Phase 3 Stage A PLACEHOLDER (empty state only). Stage B2 replaces the body.
// Keep the type name `ExamsRootView` and its no-argument init: the app shell (AppShell/AppRootView.swift) and the
// `exams` route use them.
// APIs: NavigationStack, ContentUnavailableView (iOS 17), navigationTitle(_:).
import SwiftUI

struct ExamsRootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label { Text("exams.empty.title") } icon: { Image(systemName: "graduationcap") }
            } description: {
                Text("exams.empty.detail")
            }
            .navigationTitle(Text("exams.title"))
        }
    }
}
