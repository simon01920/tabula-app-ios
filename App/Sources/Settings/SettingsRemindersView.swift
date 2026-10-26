// Settings → Reminders (route `settings.reminders`; Phase 4U U5a, R4 / H9 / H10 / D7).
// One row per kind in the Apple-Settings style: `Homework   1 day before, 17:00 ›` / `Assignments   Off ›`. The row only
// NAVIGATES to the kind page (RemindersRuleEditorView), where the single "Remind me" switch lives; rows never appear or
// disappear when something is switched, and there are no repeated "Times and delivery" rows. Below: quiet hours for all
// reminders, loud alarms (Pro), the Time Sensitive limit (ONLY where the build supports the tier, D7) and the "Test
// reminders & troubleshoot" row. An attention row on top shows up ONLY for user-fixable problems (permissions, Focus,
// Background App Refresh; `ReminderHealthTriage`), never for app-side limits.
// Rules are `ReminderRule` entities written by the kind page with `model.apply(.upsert)`.
// Field rule: "pack tonight" is absent while the bring list is a disabled lesson field (unless such a rule is on).
// APIs: Form, Section, NavigationLink, LabeledContent, Toggle, Stepper, Label(title:icon:).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsRemindersView: View {
    @Environment(AppModel.self) private var model
    @Environment(ReminderCoordinator.self) private var reminders
    @State private var alarmAuthorization: AlarmAuthorization?

    private var rules: [ReminderRule] { model.database?.reminderRules ?? [] }
    private var terminology: ProfilePreset.Terminology { ProfilePreset.for(model.settings.profile).terminology }
    private var timeSensitiveAvailable: Bool {
        TimeSensitiveAvailability.isAvailable(reminders.health?.notifications.timeSensitive)
    }

    var body: some View {
        Form {
            attentionSection
            kindsSection
            quietSection
            alarmsSection
            timeSensitiveSection
            deliveryCheckSection
        }
        .navigationTitle(Text("settings.reminders.title"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
        .task { await reminders.refreshHealth() }
    }

    // MARK: Attention (user-fixable problems only)

    @ViewBuilder private var attentionSection: some View {
        let status = ReminderHealthTriage.summaryStatus(reminders.healthItems)
        if status >= .warning {
            Section {
                NavigationLink { RemindersHealthView() } label: {
                    Label {
                        Text(LocalizedStringKey(ReminderHealthPresentation.summaryKey(status)))
                    } icon: {
                        HealthStatusIcon(status: status)
                    }
                }
            }
        }
    }

    // MARK: Kinds

    private var kindsSection: some View {
        let targets = ReminderKindList.visibleTargets(
            bringListVisible: model.activeTimetable?.fieldVisibility.isVisible(.bringList) ?? false, rules: rules)
        return Section {
            ForEach(targets, id: \.self) { target in
                NavigationLink { RemindersRuleEditorView(target: target) } label: {
                    LabeledContent {
                        Text(verbatim: summary(of: ReminderRuleDefaults.rule(for: target, in: rules)))
                    } label: {
                        Label {
                            Text(LocalizedStringKey(ReminderKindList.titleKey(target, terminology: terminology)))
                        } icon: {
                            Image(systemName: Self.symbol(target))
                        }
                    }
                }
            }
        } header: {
            Text("settings.reminders.kinds.title")
        }
    }

    /// "1 day before, 17:00" / "2 reminders" / "Off". A rule that saved Time Sensitive reads as Standard where the tier is
    /// unavailable (D7), so the row never names a tier the build cannot deliver.
    private func summary(of rule: ReminderRule?) -> String {
        guard let rule, rule.isEnabled else { return model.renderer.string(forKey: "settings.value.off") }
        var shown = rule
        shown.tier = TimeSensitiveAvailability.displayedTier(rule.tier, timeSensitiveAvailable: timeSensitiveAvailable)
        let lines = ReminderRuleSummary.lines(shown).map { model.renderer.string($0) }
        return model.formatter.list(lines)
    }

    /// Adopt U1: `AppSymbol`.
    private static func symbol(_ target: ReminderTarget) -> String {
        switch target {
        case .homework: return "pencil"
        case .assignment: return "doc.text"
        case .exam: return "graduationcap"
        case .lesson: return "bell"
        case .packTonight: return "backpack"
        case .todo: return "checklist"
        default: return "bell"
        }
    }

    // MARK: Quiet hours (all reminders)

    private var quietSection: some View {
        Section {
            QuietHoursRows(toggleKey: "settings.reminders.quiet.toggle", quietHours: Binding(
                get: { model.settings.globalQuietHours },
                set: { value in model.apply(.settings { $0.globalQuietHours = value }) }))
        } footer: {
            Text("settings.reminders.quiet.footer")
        }
    }

    // MARK: Loud alarms

    private var alarmsSection: some View {
        let allowed = model.entitlements.isAllowed(.loudAlarms)
        return Section {
            Toggle(isOn: Binding(get: { model.settings.alarmPolicy.isEnabled }, set: { value in
                if value {
                    Task { alarmAuthorization = await ReminderAlarmOptIn.enable(model: model, reminders: reminders) }
                } else {
                    model.apply(.settings { $0.alarmPolicy.isEnabled = false })
                }
            })) {
                Text("settings.reminders.alarms.toggle")
            }
            .frame(minHeight: 44)
            .disabled(!allowed)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(allowed ? "settings.reminders.alarms.footer" : "reminders.tier.proOnly")
                if alarmAuthorization == .denied { Text("health.alarms.denied") }
            }
        }
    }

    // MARK: Time Sensitive (only where the build supports it, D7)

    @ViewBuilder private var timeSensitiveSection: some View {
        if timeSensitiveAvailable {
            let policy = model.settings.timeSensitivePolicy
            Section {
                Toggle(isOn: Binding(get: { policy.isEnabled }, set: { value in
                    model.apply(.settings { $0.timeSensitivePolicy.isEnabled = value })
                })) {
                    Text("settings.reminders.timeSensitive.toggle")
                }
                .frame(minHeight: 44)
                if policy.isEnabled {
                    Stepper(value: Binding(get: { policy.maxLeadMinutes }, set: { value in
                        model.apply(.settings { $0.timeSensitivePolicy.maxLeadMinutes = value })
                    }), in: ReminderTierInfo.leadRange, step: ReminderTierInfo.leadStep) {
                        RenderedText(LocalizedText(key: "settings.reminders.timeSensitive.lead",
                                                   args: [.integer(policy.maxLeadMinutes)]))
                    }
                }
            } footer: {
                Text("settings.reminders.timeSensitive.footer")
            }
        }
    }

    // MARK: Delivery check

    private var deliveryCheckSection: some View {
        Section {
            NavigationLink { RemindersHealthView() } label: {
                Label { Text("settings.reminders.delivery.row") } icon: { Image(systemName: "stethoscope") }
            }
        } header: {
            Text("settings.reminders.delivery.title")
        }
    }
}
