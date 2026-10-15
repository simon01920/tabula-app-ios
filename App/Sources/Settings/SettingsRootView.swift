// Settings root (stage B4): one grouped Form; sub-pages are SettingsCalendarView, SettingsAppearanceView,
// SettingsRemindersView, SettingsAboutView. Every write goes through `model.apply(.settings { … })`.
// Keep the type name `SettingsRootView` and its no-argument init (the app shell uses it) and keep
//     #if DEBUG
//     DeveloperSettingsLink()
//     #endif
// as the last section.
// Field rule: a row with nothing to show (e.g. build number missing, Timetables editor not registered) is absent.
// APIs: NavigationStack, Form, Section, Picker(selection:content:label:), NavigationLink(destination:label:),
//       LabeledContent, Label(title:icon:), View.sheet(isPresented:content:), EnvironmentValues.openURL,
//       UIApplication.openSettingsURLString (UIKit, iOS 8+).
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var showsTimetables = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                Section {
                    NavigationLink { SettingsCalendarView() } label: {
                        Label { Text("settings.calendar.row") } icon: { Image(systemName: "calendar") }
                    }
                } header: {
                    Text("settings.calendar.title")
                }
                Section {
                    NavigationLink { SettingsAppearanceView() } label: {
                        Label { Text("settings.appearance.row") } icon: { Image(systemName: "paintpalette") }
                    }
                } header: {
                    Text("settings.appearance.title")
                }
                timetablesSection
                Section {
                    NavigationLink { SettingsRemindersView() } label: {
                        Label { Text("settings.reminders.row") } icon: { Image(systemName: "bell") }
                    }
                } header: {
                    Text("settings.reminders.title")
                }
                languageSection
                proSection
                Section {
                    NavigationLink { SettingsAboutView() } label: {
                        Label { Text("settings.about.row") } icon: { Image(systemName: "info.circle") }
                    }
                } header: {
                    Text("settings.about.title")
                }
                #if DEBUG
                DeveloperSettingsLink()
                #endif
            }
            .navigationTitle(Text("shell.tab.settings"))
        }
    }

    // MARK: Profile

    private var profileSection: some View {
        let selected = ProfileChoices.selection(for: model.settings.profile)
        return Section {
            Picker(selection: profile) {
                ForEach(ProfileChoices.offered, id: \.self) { option in
                    Text(LocalizedStringKey(DynamicL10nKeys.profile(option))).tag(option)
                }
            } label: {
                Text("settings.profile.picker")
            }
            .disabled(model.isReadOnly)
            LabeledContent {
                Text(LocalizedStringKey(ProfileChoices.terminologyKey(for: selected)))
            } label: {
                Text("settings.profile.terminology")
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("settings.profile.title")
        } footer: {
            Text("settings.profile.footer")
        }
    }

    private var profile: Binding<UserProfile> {
        Binding(get: { ProfileChoices.selection(for: model.settings.profile) }, set: { value in
            model.apply(.settings { $0.profile = value })
        })
    }

    // MARK: Timetables (lights up when stage B3 registers `editor.timetables`)

    @ViewBuilder private var timetablesSection: some View {
        if let route = RouteRegistry.routes.first(where: { $0.id == "editor.timetables" }) {
            Section {
                Button { showsTimetables = true } label: {
                    Label { Text("settings.timetables.manage") } icon: { Image(systemName: "rectangle.stack") }
                        .foregroundStyle(.primary)
                }
                .sheet(isPresented: $showsTimetables) { route.makeView() }
                .closesForDeepLink { showsTimetables = false }   // QA fix Q6
            } header: {
                Text("settings.timetables.title")
            }
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label { Text("settings.language.open") } icon: { Image(systemName: "globe") }
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("settings.language.title")
        } footer: {
            Text("settings.language.footer")
        }
    }

    // MARK: Pro

    private var proSection: some View {
        Section {
            LabeledContent {
                if model.entitlements.tier == .pro { Text("settings.pro.tier.pro") } else { Text("settings.pro.tier.free") }
            } label: {
                Text("settings.pro.plan")
            }
        } header: {
            Text("settings.pro.title")
        } footer: {
            if ProFeature.allCases.allSatisfy(model.entitlements.isAllowed) {
                Text("settings.pro.unlocked")
            }
        }
    }
}
