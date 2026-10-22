// Settings → Live Activities (route `settings.live-activities`, Phase 4 B2): switches for the current-lesson and the
// exam-day Live Activity, "Start automatically" (scheduled starts, which iOS announces), and an explanation with a
// link to the Settings app when the system has Live Activities turned off for Tabula. Pro gate: the Live Activity is
// `ProFeature.liveActivity` (MONETIZATION.md); without it the switches are disabled and say so (all-access for now).
// The choices are device-local (`LiveActivityController.setPreferences`, UserDefaults), not part of the synced data.
// Diagnostics (last run, next evaluation) are on Settings → Developer (DEBUG).
// APIs: Form, Section, Toggle, Button, EnvironmentValues.openURL, UIApplication.openSettingsURLString (UIKit).
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct SettingsLiveActivitiesView: View {
    @Environment(LiveActivityController.self) private var liveActivities
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            if !liveActivities.systemEnabled {
                Section {
                    Label {
                        Text("settings.liveActivities.disabled")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Text("health.action.openSettings")
                    }
                }
            }
            Section {
                Toggle(isOn: binding(\.lessonEnabled)) {
                    Label { Text("settings.liveActivities.lesson") } icon: { Image(systemName: "book.closed") }
                }
                Toggle(isOn: binding(\.examEnabled)) {
                    Label { Text("settings.liveActivities.exam") } icon: { Image(systemName: "graduationcap") }
                }
            } footer: {
                if liveActivities.isEntitled {
                    Text("settings.liveActivities.footer")
                } else {
                    Text("widget.pro.title")
                }
            }
            .disabled(!liveActivities.isEntitled)
            Section {
                Toggle(isOn: binding(\.autoStart)) {
                    Label { Text("settings.liveActivities.autoStart") } icon: { Image(systemName: "clock.badge.checkmark") }
                }
            } footer: {
                Text("settings.liveActivities.autoStart.footer")
            }
            .disabled(!liveActivities.isEntitled
                      || !(liveActivities.preferences.lessonEnabled || liveActivities.preferences.examEnabled))
        }
        .navigationTitle(Text("settings.liveActivities.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ keyPath: WritableKeyPath<LiveActivityPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { liveActivities.preferences[keyPath: keyPath] }, set: { value in
            var preferences = liveActivities.preferences
            preferences[keyPath: keyPath] = value
            liveActivities.setPreferences(preferences)
        })
    }
}
