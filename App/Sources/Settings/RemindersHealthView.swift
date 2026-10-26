// Settings → Reminders → Test reminders & troubleshoot (route `settings.reminder-health`; Phase 4U U5a, H9 / M4 / M28).
// Lays out `ReminderCoordinator.healthItems` through `ReminderHealthTriage`:
//   - the summary counts ONLY user-fixable problems (permissions, Time Sensitive turned off in iOS, Background App Refresh,
//     Low Power Mode); app-side limits never turn it into a warning;
//   - "Checks": one row per user-facing check, status shown by symbol shape + colour with the status word as the
//     accessibility label (no printed "OK / Check / Info"); one warning colour; "Focus" gets an Open Settings button;
//   - "Technical details" (collapsed `DisclosureGroup`): scheduled reminders x of 64, reminder / alarm limits, Silent mode,
//     hidden or locked app;
//   - the Time Sensitive row is absent in builds without the entitlement (D7).
// Actions: request notifications (pre-explainer first), request alarms, open (notification) settings, send tests.
// The rows refresh when the screen appears and whenever the coordinator reports a change.
// APIs: List, Section, DisclosureGroup, Label, Button, EnvironmentValues.openURL, View.task, UIApplication
//       .openSettingsURLString / openNotificationSettingsURLString.
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
    @State private var showsTechnical = false

    var body: some View {
        let items = reminders.healthItems
        let technical = ReminderHealthTriage.technical(items)
        List {
            Section {
                summary(items)
            }
            Section {
                ForEach(ReminderHealthTriage.checks(items)) { item in
                    HealthRow(item: item, action: ReminderHealthTriage.fallbackAction(for: item)) { perform($0) }
                }
            } header: {
                Text("health.checks.title")
            }
            if !technical.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsTechnical) {
                        ForEach(technical) { item in
                            HealthRow(item: item, action: ReminderHealthTriage.fallbackAction(for: item)) { perform($0) }
                        }
                    } label: {
                        Text("health.technical.title")
                    }
                }
            }
            testsSection
        }
        .navigationTitle(Text("settings.reminder-health.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reminders.refreshHealth() }
        .refreshable { await reminders.refreshHealth() }
        .reminderPermissionSheet(isPresented: $showsExplainer)
    }

    private func summary(_ items: [ReminderHealthItem]) -> some View {
        let status = ReminderHealthTriage.summaryStatus(items)
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(ReminderHealthPresentation.summaryKey(status))).font(.headline)
                Text("health.summary.footer").font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            HealthStatusIcon(status: status)
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
    /// The button of the row (the item's own, or the Open Settings button of the Focus row).
    let action: ReminderHealthAction?
    let perform: (ReminderHealthAction) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(item.titleKey)).font(.headline)
                    Text(verbatim: model.renderer.string(item.detail)).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                HealthStatusIcon(status: item.status)
            }
            .accessibilityElement(children: .combine)
            if let action {
                Button { perform(action) } label: {
                    Text(LocalizedStringKey(action.titleKey)).frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
