// Settings → Reminders → Check that reminders work (route `settings.reminder-health`). Lays out the rows of
// `ReminderCoordinator.healthItems` (permission states, Time Sensitive, loud alarms, Focus hint, Silent mode / Action
// button, Low Power, Background App Refresh, scheduled x of 64, saturation and alarm-overflow notices) and the test
// buttons. Status is shown by symbol shape AND a spoken/visible word (never colour only).
// Actions: request notifications (pre-explainer first), request alarms, open (notification) settings.
// The rows refresh when the screen appears and whenever the coordinator reports a change.
// APIs: List, Section, Label, Button, EnvironmentValues.openURL, View.task, UIApplication.openSettingsURLString /
//       openNotificationSettingsURLString.
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct RemindersHealthView: View {
    @Environment(AppModel.self) private var model
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(\.openURL) private var openURL
    @State private var showsExplainer = false
    @State private var testMessage: String?
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                summary
            }
            Section {
                ForEach(reminders.healthItems) { item in
                    HealthRow(item: item) { perform($0) }
                }
            } header: {
                Text("health.rows.title")
            }
            testsSection
        }
        .navigationTitle(Text("settings.reminder-health.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reminders.refreshHealth() }
        .refreshable { await reminders.refreshHealth() }
        .reminderPermissionSheet(isPresented: $showsExplainer)
    }

    private var summary: some View {
        let status = ReminderHealthCheck.overall(reminders.healthItems)
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(ReminderHealthPresentation.summaryKey(status))).font(.headline)
                Text("health.summary.footer").font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: ReminderHealthPresentation.symbol(status == .info ? .ok : status))
                .foregroundStyle(HealthRow.color(status))
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var testsSection: some View {
        Section {
            Button {
                run {
                    let outcome = await reminders.sendTestNotification()
                    return model.renderer.string(forKey: ReminderHealthPresentation.testNotificationKey(outcome))
                }
            } label: {
                Label { Text("health.test.notification") } icon: { Image(systemName: "bell.badge") }
                    .frame(minHeight: 44, alignment: .leading)
            }
            .disabled(isTesting)
            if reminders.health?.alarmAuthorization == .authorized {
                Button {
                    run {
                        let outcome = await reminders.sendTestAlarm()
                        return model.renderer.string(forKey: ReminderHealthPresentation.testAlarmKey(outcome))
                    }
                } label: {
                    Label { Text("health.test.alarm") } icon: { Image(systemName: "alarm") }
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disabled(isTesting)
            }
            if let testMessage {
                Text(verbatim: testMessage).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text("health.tests.title")
        } footer: {
            Text("health.tests.footer")
        }
    }

    private func run(_ test: @escaping () async -> String) {
        isTesting = true
        testMessage = nil
        Task {
            testMessage = await test()
            isTesting = false
        }
    }

    private func perform(_ action: ReminderHealthAction) {
        switch action {
        case .requestNotifications:
            showsExplainer = true
        case .requestAlarms:
            Task { _ = await reminders.requestAlarmAuthorization() }
        case .openNotificationSettings:
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        case .openAppSettings:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}

private struct HealthRow: View {
    let item: ReminderHealthItem
    let perform: (ReminderHealthAction) -> Void
    @Environment(AppModel.self) private var model

    static func color(_ status: ReminderHealthStatus) -> Color {
        switch status {
        case .ok: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .problem: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(item.titleKey)).font(.headline)
                        Spacer(minLength: 8)
                        Text(LocalizedStringKey(ReminderHealthPresentation.statusKey(item.status)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(verbatim: model.renderer.string(item.detail)).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: ReminderHealthPresentation.symbol(item.status)).foregroundStyle(Self.color(item.status))
            }
            .accessibilityElement(children: .combine)
            if let action = item.action {
                Button { perform(action) } label: {
                    Text(LocalizedStringKey(action.titleKey)).frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
