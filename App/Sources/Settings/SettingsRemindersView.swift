// Settings → Reminders: an explanatory page about the three delivery tiers, the silent switch and Focus.
// Informational only: no permission is requested and nothing is scheduled here (configuration arrives in a later
// update). Static text, so it is checked on a device for wording rather than behaviour.
// APIs: Form, Section, Label(title:icon:), Text; no framework calls beyond SwiftUI.
import SwiftUI

struct SettingsRemindersView: View {
    var body: some View {
        Form {
            Section {
                TierRow(title: "settings.reminders.standard.title", detail: "settings.reminders.standard.detail",
                        symbol: "bell")
                TierRow(title: "settings.reminders.timesensitive.title", detail: "settings.reminders.timesensitive.detail",
                        symbol: "bell.badge")
                TierRow(title: "settings.reminders.alarm.title", detail: "settings.reminders.alarm.detail",
                        symbol: "alarm")
            } header: {
                Text("settings.reminders.tiers.title")
            }
            Section {
                Text("settings.reminders.silent.detail")
                Text("settings.reminders.focus.detail")
            } header: {
                Text("settings.reminders.silentfocus.title")
            }
            Section {
                Text("settings.reminders.later")
            }
        }
        .navigationTitle(Text("settings.reminders.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TierRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text(title).font(.headline) } icon: { Image(systemName: symbol) }
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
