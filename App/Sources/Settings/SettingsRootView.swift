// Settings root (Phase 4U U5a, R3): one grouped Form in four groups (Timetable, Notifications, General, About & Feedback),
// plus iCloud (Phase 6 S1, `CloudSyncSettingsSection` in Sync/CloudSyncViews.swift) after General.
// Every row PUSHES inside this NavigationStack (HIG modality: a sheet is for a self-contained task, not for browsing a
// hierarchy); the only sheet is the create flow "Add Another Timetable…". Sub-pages: SettingsCalendarView (Date & Time),
// SettingsColoursView (Colors), SettingsRemindersView, SettingsLiveActivitiesView, SettingsAboutView. The timetable
// editors (Subjects, Bell schedule, Terms, timetable settings, Manage timetables) are U5b's views, pushed in their
// embedded mode (no own stack; Back leaves). Every write goes through `model.apply(.settings { … })`.
// Keep the type name `SettingsRootView` and its no-argument init (the app shell uses it) and keep
//     #if DEBUG
//     DeveloperSettingsLink()
//     #endif
// as the last section.
// Field rule: a row with nothing to show is absent (no active timetable → the timetable rows; no bell schedule → no
// period count; no App Store listing → no Rate row). "Lessons are called" is not a setting of its own: the wording follows
// School type (ProfilePreset terminology), so it is not a row.
// APIs: NavigationStack, Form, Section, Picker(selection:content:label:), NavigationLink(destination:label:),
//       LabeledContent, Label(title:icon:), View.sheet(isPresented:content:), EnvironmentValues.openURL,
//       UIApplication.openSettingsURLString (UIKit, iOS 8+).
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(LiveActivityController.self) private var liveActivities
    @Environment(\.openURL) private var openURL
    @State private var addingTimetable = false

    var body: some View {
        NavigationStack {
            Form {
                timetableSection
                notificationsSection
                generalSection
                CloudSyncSettingsSection()
                proSection
                Section {
                    NavigationLink { SettingsAboutView() } label: {
                        SettingsRowLabel("settings.aboutfeedback.title", symbol: "info.circle.fill", color: .gray)
                    }
                }
                #if DEBUG
                DeveloperSettingsLink()
                #endif
            }
            .navigationTitle(Text("shell.tab.settings"))
            .sheet(isPresented: $addingTimetable) { NewTimetableSheet() }
            .closesForDeepLink { addingTimetable = false }   // QA fix Q6
        }
    }

    // MARK: Timetable

    private var canAddTimetable: Bool {
        guard let database = model.database else { return false }
        return TimetableManagement.canAdd(to: database, limit: model.entitlements.limit(.maxTimetables))
    }

    @ViewBuilder private var timetableSection: some View {
        Section {
            if let timetable = model.activeTimetable, let database = model.database {
                NavigationLink {
                    TimetableEditorView(embedded: true)
                } label: {
                    LabeledContent {
                        if model.timetables.count >= 2 { Text("editor.timetables.active") }
                    } label: {
                        Label {
                            Text(verbatim: timetable.name)
                        } icon: {
                            if let emoji = timetable.emoji {
                                Text(verbatim: emoji).frame(width: 29, height: 29).accessibilityHidden(true)
                            } else {
                                SettingsIconTile(symbol: "rectangle.stack.fill", color: .blue)
                            }
                        }
                    }
                }
                NavigationLink {
                    SubjectsListView(embedded: true)
                } label: {
                    LabeledContent {
                        Text(verbatim: SettingsSummaries.subjectCount(of: timetable.id, in: database)
                            .formatted(.number.locale(model.formatter.locale)))
                    } label: {
                        SettingsRowLabel("editor.subjects.title", symbol: "books.vertical.fill", color: .indigo)
                    }
                }
                NavigationLink {
                    BellScheduleEditorView(embedded: true)
                } label: {
                    LabeledContent {
                        if let periods = SettingsSummaries.periodCount(of: timetable, in: database) {
                            Text(verbatim: model.renderer.format(key: "settings.bell.periods",
                                                                 arguments: [.integer(Int64(periods))]))
                        }
                    } label: {
                        SettingsRowLabel("settings.bell.row", symbol: "bell.fill", color: .pink)
                    }
                }
                NavigationLink {
                    TermsEditorView(embedded: true)
                } label: {
                    SettingsRowLabel("settings.terms.row", symbol: "calendar", color: .teal)
                }
            }
            if model.timetables.count >= 2 {
                NavigationLink {
                    TimetablesManagerView(embedded: true)
                } label: {
                    LabeledContent {
                        Text(verbatim: model.timetables.count.formatted(.number.locale(model.formatter.locale)))
                    } label: {
                        SettingsRowLabel("settings.timetables.manage", symbol: "square.stack.3d.up.fill", color: .gray)
                    }
                }
            }
            Button { addingTimetable = true } label: {
                Label { Text("settings.timetables.add") } icon: { Image(systemName: "plus.circle.fill") }
            }
            .disabled(!canAddTimetable)
        } header: {
            Text("settings.section.timetable")
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            NavigationLink { SettingsRemindersView() } label: {
                LabeledContent {
                    Text(verbatim: remindersSummary)
                } label: {
                    SettingsRowLabel("settings.reminders.title", symbol: "bell.badge.fill", color: .red)
                }
            }
            NavigationLink { SettingsLiveActivitiesView() } label: {
                LabeledContent {
                    Text(LocalizedStringKey(liveActivitiesAreOn ? "settings.value.on" : "settings.value.off"))
                } label: {
                    SettingsRowLabel("settings.liveActivities.title", symbol: "timer", color: .purple)
                }
            }
        } header: {
            Text("settings.section.notifications")
        }
    }

    private var remindersSummary: String {
        let count = SettingsSummaries.enabledReminderKinds(model.database?.reminderRules ?? [])
        if count == 0 { return model.renderer.string(forKey: "settings.value.off") }
        return model.renderer.format(key: "settings.reminders.summary.on", arguments: [.integer(Int64(count))])
    }

    private var liveActivitiesAreOn: Bool {
        liveActivities.isEntitled && (liveActivities.preferences.lessonEnabled || liveActivities.preferences.examEnabled)
    }

    // MARK: General

    private var generalSection: some View {
        let current = PalettePackChoice.displayedPack(for: model.settings.palettePackID)
        return Section {
            Picker(selection: profile) {
                ForEach(ProfileChoices.offered, id: \.self) { option in
                    Text(LocalizedStringKey(DynamicL10nKeys.profile(option))).tag(option)
                }
            } label: {
                SettingsRowLabel("settings.schooltype.title", symbol: "graduationcap.fill", color: .indigo)
            }
            .disabled(model.isReadOnly)
            NavigationLink { SettingsCalendarView() } label: {
                LabeledContent {
                    Text(LocalizedStringKey(SettingsSummaries.hourCycleKey(model.settings.hourCycle)))
                } label: {
                    SettingsRowLabel("settings.datetime.row", symbol: "clock.fill", color: .blue)
                }
            }
            NavigationLink { SettingsColoursView() } label: {
                LabeledContent {
                    Text(LocalizedStringKey(current.nameKey))
                } label: {
                    SettingsRowLabel("settings.colors.title", symbol: "paintpalette.fill", color: .pink)
                }
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                LabeledContent {
                    HStack(spacing: 4) {
                        Text(verbatim: languageName)
                        Image(systemName: "arrow.up.forward").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                    }
                } label: {
                    SettingsRowLabel("settings.language.title", symbol: "globe", color: .teal)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityHint(Text("settings.language.footer"))
        } header: {
            Text("settings.section.general")
        } footer: {
            Text("settings.profile.footer")
        }
    }

    private var profile: Binding<UserProfile> {
        Binding(get: { ProfileChoices.selection(for: model.settings.profile) }, set: { value in
            model.apply(.settings { $0.profile = value })
        })
    }

    /// The language the app runs in, written in that language ("Slovenčina"); nothing when the system cannot name it.
    private var languageName: String {
        let locale = model.formatter.locale
        guard let code = locale.language.languageCode?.identifier else { return "" }
        return locale.localizedString(forLanguageCode: code)?.localizedCapitalized ?? ""
    }

    // MARK: Pro

    private var proSection: some View {
        Section {
            LabeledContent {
                if model.entitlements.tier == .pro { Text("settings.pro.tier.pro") } else { Text("settings.pro.tier.free") }
            } label: {
                SettingsRowLabel("settings.pro.plan", symbol: "star.fill", color: .purple)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("settings.pro.title")
        } footer: {
            if ProFeature.allCases.allSatisfy(model.entitlements.isAllowed) {
                Text("settings.pro.unlocked")
            }
        }
    }
}
