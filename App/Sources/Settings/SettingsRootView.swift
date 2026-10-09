// PLACEHOLDER (Stage A) — stage B4 replaces this file with the real Settings screen.
// Keep the type name `SettingsRootView` and its no-argument init: the app shell uses it.
// Contains the appearance picker (exercises AppModel.apply → stamping → debounced save → relaunch persistence) and
// the DEBUG-only Developer entry (`DeveloperSettingsLink`, Debug/DeveloperSettingsLink.swift). B4: keep
//     #if DEBUG
//     DeveloperSettingsLink()
//     #endif
// as the last section of the real Settings list.
// APIs: NavigationStack, Form, Section, Picker(selection:content:label:), pickerStyle(.inline), Binding(get:set:).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: appearance) {
                        Text("settings.appearance.system").tag(Appearance.auto)
                        Text("settings.appearance.light").tag(Appearance.light)
                        Text("settings.appearance.dark").tag(Appearance.dark)
                    } label: {
                        Text("settings.appearance.title")
                    }
                    .pickerStyle(.inline)
                    .disabled(model.isReadOnly)
                } header: {
                    Text("settings.appearance.title")
                }
                #if DEBUG
                DeveloperSettingsLink()
                #endif
            }
            .navigationTitle(Text("shell.tab.settings"))
        }
    }

    private var appearance: Binding<Appearance> {
        Binding(get: { model.settings.appearance.effective }, set: { value in
            model.apply(.settings { $0.appearance = value })
        })
    }
}
