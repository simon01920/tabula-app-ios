// Launch routes of Settings (stage B4): `settings` (root), `settings.calendar`, `settings.appearance`,
// `settings.reminders`, `settings.reminder-rule`, `settings.reminder-health`, `reminders.permission` (sheet),
// `settings.about`. Sub-pages are wrapped in their own NavigationStack so they can be opened
// directly (`-TabulaScreen settings.appearance`); data comes from the `-TabulaSeed` settings.
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum SettingsRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("settings", .tabRoot(.settings)) { SettingsRootView() },
            AppRoute("settings.calendar", .tabRoot(.settings)) { NavigationStack { SettingsCalendarView() } },
            AppRoute("settings.appearance", .tabRoot(.settings)) { NavigationStack { SettingsAppearanceView() } },
            AppRoute("settings.reminders", .tabRoot(.settings)) { NavigationStack { SettingsRemindersView() } },
            AppRoute("settings.reminder-rule", .tabRoot(.settings)) {
                NavigationStack { RemindersRuleEditorView(target: .homework) }
            },
            AppRoute("settings.reminder-health", .tabRoot(.settings)) { NavigationStack { RemindersHealthView() } },
            AppRoute("reminders.permission", .sheet(over: .settings)) { ReminderPermissionSheet() },
            AppRoute("settings.about", .tabRoot(.settings)) { NavigationStack { SettingsAboutView() } },
        ]
    }
}
