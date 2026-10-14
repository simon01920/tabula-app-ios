// Settings → Reminders → <kind> (route `settings.reminder-rule`, seed: the homework rule). Edits one `ReminderRule`:
// on/off, offsets, follow-up ("only if not done"), delivery tier with honest explanations, quiet hours.
// Every change is written at once through `model.apply(.upsert(rule))` and marks the rule user-made (`origin = .user`,
// which the planner requires for loud alarms). A kind without a rule yet shows the default (profile preset) switched
// off; switching it on creates the rule. Picking "Loud alarm" turns the alarm policy on and asks for the AlarmKit
// permission; switching a rule on while notifications are "not determined" shows the pre-explainer first.
// APIs: Form, Section, Toggle, Picker, Button, NavigationLink, EnvironmentValues.openURL.
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct RemindersRuleEditorView: View {
    let target: ReminderTarget
    @Environment(AppModel.self) private var model
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(\.openURL) private var openURL
    @State private var newID = ReminderRule.ID(UUID())
    @State private var showsExplainer = false
    @State private var alarmAuthorization: AlarmAuthorization?

    private var existing: ReminderRule? {
        ReminderRuleDefaults.rule(for: target, in: model.database?.reminderRules ?? [])
    }

    /// The stored rule, or the default switched off.
    private var rule: ReminderRule {
        if let existing { return existing }
        var made = ReminderRuleDefaults.rule(for: target, profile: model.settings.profile, id: newID)
        made.isEnabled = false
        return made
    }

    private var terminology: ProfilePreset.Terminology { ProfilePreset.for(model.settings.profile).terminology }
    private var alarmsAllowed: Bool { model.entitlements.isAllowed(.loudAlarms) }

    var body: some View {
        let current = rule
        Form {
            Section {
                Toggle(isOn: Binding(get: { current.isEnabled }, set: { setEnabled($0) })) {
                    Text("reminders.rule.enabled")
                }
                .frame(minHeight: 44)
            } footer: {
                if ReminderRuleEditing.isIncomplete(current) { Text("reminders.rule.incomplete") }
            }
            if current.isEnabled {
                offsetsSection(current)
                followUpSection(current)
                tierSection(current)
                quietSection(current)
            }
        }
        .navigationTitle(Text(LocalizedStringKey(ReminderKindList.titleKey(target, terminology: terminology))))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
        .reminderPermissionSheet(isPresented: $showsExplainer)
    }

    // MARK: Sections

    private func offsetsSection(_ current: ReminderRule) -> some View {
        Section {
            ReminderOffsetsRows(offsets: Binding(get: { current.offsets }, set: { value in edit { $0.offsets = value } }))
        } header: {
            Text("reminders.rule.offsets.title")
        } footer: {
            Text("reminders.rule.offsets.footer")
        }
    }

    private func followUpSection(_ current: ReminderRule) -> some View {
        Section {
            FollowUpRows(
                forOverride: false,
                kind: Binding(get: { FollowUpEditing.kind(of: current.followUp) }, set: { kind in
                    edit { $0.followUp = FollowUpEditing.followUp(choosing: kind, current: $0.followUp) }
                }),
                followUp: Binding(get: { current.followUp }, set: { value in edit { $0.followUp = value } }))
        } header: {
            Text("reminders.followUp.title")
        } footer: {
            Text("reminders.followUp.footer")
        }
    }

    private func tierSection(_ current: ReminderRule) -> some View {
        Section {
            ForEach(ReminderTierInfo.choices, id: \.self) { tier in
                ReminderTierRow(tier: tier, isSelected: current.tier.effective == tier,
                                isAvailable: tier != .alarm || alarmsAllowed) { select(tier) }
            }
        } header: {
            Text("reminders.tier.title")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if current.tier.effective == .timeSensitive {
                    RenderedText(ReminderTierInfo.timeSensitivePolicyText(model.settings.timeSensitivePolicy))
                }
                if current.tier.effective == .alarm {
                    Text("reminders.tier.alarm.footer")
                    if alarmAuthorization == .denied || alarmAuthorization == .unavailable {
                        Text("health.alarms.denied")
                        Button { openAppSettings() } label: { Text("health.action.openSettings") }
                    }
                }
            }
        }
    }

    private func quietSection(_ current: ReminderRule) -> some View {
        Section {
            QuietHoursRows(toggleKey: "reminders.quiet.rule", quietHours: Binding(
                get: { current.quietHours }, set: { value in edit { $0.quietHours = value } }))
        } header: {
            Text("reminders.quiet.title")
        } footer: {
            Text("reminders.quiet.rule.footer")
        }
    }

    // MARK: Writes

    private func edit(_ change: (inout ReminderRule) -> Void) {
        var copy = rule
        change(&copy)
        model.apply(.upsert(ReminderRuleEditing.touched(copy)))
    }

    private func setEnabled(_ enabled: Bool) {
        edit { $0.isEnabled = enabled }
        if enabled {
            Task {
                if await reminders.shouldExplainNotificationPermission() { showsExplainer = true }
                if rule.tier.effective == .alarm { alarmAuthorization = await reminders.engine.alarms.authorization() }
            }
        }
    }

    private func select(_ tier: DeliveryTier) {
        edit { $0.tier = tier }
        guard tier == .alarm else { return }
        Task { alarmAuthorization = await ReminderAlarmOptIn.enable(model: model, reminders: reminders) }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
