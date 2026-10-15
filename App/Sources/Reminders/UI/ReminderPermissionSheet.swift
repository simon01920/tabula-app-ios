// Pre-explainer for the notification permission (route `reminders.permission`). Shown in context: the first time a
// reminder rule is switched on, from the health check while the permission is "not determined", and once after the
// user saves a task or exam that would get a reminder (QA fix Q1: ReminderCoordinator.permissionOffer, presented by
// the shell's root presenter). Closing it from any entry point without allowing is remembered per install
// (`ReminderCoordinator.permissionExplainerClosed()`), so a later save does not offer it again. Never at launch.
// "Allow notifications" is the only place that triggers the system prompt (`requestNotificationAuthorization()`).
// If the permission was already refused, the sheet offers the system settings instead of a prompt that cannot appear.
// APIs: NavigationStack, Form/List, Button, EnvironmentValues.dismiss, EnvironmentValues.openURL,
//       UIApplication.openNotificationSettingsURLString (iOS 16+).
import SwiftUI
import TimetableCore
import UIKit

struct ReminderPermissionSheet: View {
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false

    private var isDenied: Bool { reminders.health?.notifications.authorization == .denied }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label { Text("reminders.permission.why") } icon: { Image(systemName: "bell.badge") }
                        .frame(minHeight: 44, alignment: .leading)
                }
                Section {
                    point("reminders.permission.point.due", "checklist")
                    point("reminders.permission.point.exams", "pencil.and.list.clipboard")
                    point("reminders.permission.point.control", "slider.horizontal.3")
                } header: {
                    Text("reminders.permission.delivered.title")
                } footer: {
                    Text(isDenied ? "reminders.permission.denied" : "reminders.permission.footer")
                }
                Section {
                    Button {
                        if isDenied {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            dismiss()
                        } else {
                            isRequesting = true
                            Task {
                                await reminders.requestNotificationAuthorization()
                                isRequesting = false
                                dismiss()
                            }
                        }
                    } label: {
                        Text(isDenied ? "health.action.openSettings" : "reminders.permission.allow")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequesting)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    Button { dismiss() } label: {
                        Text("reminders.permission.notNow").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(Text("reminders.permission.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await reminders.refreshHealth() }
        }
        .presentationDetents([.large])
        // Every entry point (root offer, override section, Settings toggles, rule editor, health check): closing while
        // the permission is still not determined records the decline, so the root offer never repeats it.
        .onDisappear { Task { await reminders.permissionExplainerClosed() } }
    }

    private func point(_ key: LocalizedStringKey, _ symbol: String) -> some View {
        Label { Text(key) } icon: { Image(systemName: symbol) }
            .frame(minHeight: 44, alignment: .leading)
    }
}
