// The "no timetable yet" state of Today and Timetable (Phase 10 U13): a title, a description and an "Add Timetable"
// action that opens the same `NewTimetableSheet` Settings and the timetables manager use. It owns its sheet state so the
// two root views only swap their ContentUnavailableView for this one line.
// APIs: ContentUnavailableView(label:description:actions:) (iOS 17), sheet(isPresented:).
import SwiftUI
import TimetableCore
import TimetableUI

struct NoTimetableView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        ContentUnavailableView {
            Label { Text(titleKey) } icon: { Image(systemName: "calendar.badge.exclamationmark") }
        } description: {
            Text(messageKey)
        } actions: {
            Button { adding = true } label: {
                Text("editor.timetables.add")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isReadOnly || model.database == nil)
        }
        .sheet(isPresented: $adding) { NewTimetableSheet() }
        .closesForDeepLink { adding = false }
    }
}
