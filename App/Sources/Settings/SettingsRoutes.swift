// Launch routes of Settings: `settings` (root), `settings.calendar` (Date & Time), `settings.colours` (Colors; the old id
// `settings.appearance` stays as an alias), `settings.reminders`, `settings.reminder-rule` (a kind's page: the "Remind me"
// switch, times, delivery; seed: the homework rule), `settings.reminder-health`, `reminders.permission` (sheet),
// `settings.about` (About & Feedback), `settings.live-activities`, `settings.timetable-new` (the create sheet, over
// Settings). Sub-pages are wrapped in their own NavigationStack so they can be opened directly
// (`-TabulaScreen settings.colours`); data comes from the `-TabulaSeed` settings.
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum SettingsRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("settings", .tabRoot(.settings)) { SettingsRootView() },
            AppRoute("settings.calendar", .tabRoot(.settings)) { NavigationStack { SettingsCalendarView() } },
            AppRoute("settings.colours", .tabRoot(.settings)) { NavigationStack { SettingsColoursView() } },
            AppRoute("settings.appearance", .tabRoot(.settings)) { NavigationStack { SettingsColoursView() } },
            AppRoute("settings.reminders", .tabRoot(.settings)) { NavigationStack { SettingsRemindersView() } },
            AppRoute("settings.reminder-rule", .tabRoot(.settings)) {
                NavigationStack { RemindersRuleEditorView(target: .homework) }
            },
            AppRoute("settings.reminder-health", .tabRoot(.settings)) { NavigationStack { RemindersHealthView() } },
            AppRoute("reminders.permission", .sheet(over: .settings)) { ReminderPermissionSheet() },
            AppRoute("settings.about", .tabRoot(.settings)) { NavigationStack { SettingsAboutView() } },
            AppRoute("settings.live-activities", .tabRoot(.settings)) { NavigationStack { SettingsLiveActivitiesView() } },
            AppRoute("settings.timetable-new", .sheet(over: .settings)) { SettingsNewTimetableSheet() },
        ]
    }
}
