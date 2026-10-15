// Settings → Reminders (route `settings.reminders`): the health check link, one switch per reminder kind (each with a
// "timing and delivery" row that opens the rule editor), the Time Sensitive policy, the loud-alarm opt-in, global quiet
// hours and the explanation of the three delivery tiers, the silent switch and Focus.
// Rules are `ReminderRule` entities written with `model.apply(.upsert)` (user edits make `origin = .user`). Switching a
// kind on while notifications are "not determined" shows the pre-explainer; nothing is requested at launch or here.
// Field rule: "pack tonight" is absent while the bring list is a disabled lesson field; a kind without a rule yet shows
// "off" and creates its rule (profile preset values) when switched on.
// APIs: Form, Section, Toggle, Stepper, NavigationLink, Label(title:icon:).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsRemindersView: View {
    @Environment(AppModel.self) private var model
    @Environment(ReminderCoordinator.self) private var reminders
    @State private var showsExplainer = false
    @State private var alarmAuthorization: AlarmAuthorization?
    @State private var newIDs: [ReminderTarget: ReminderRule.ID] = [:]

    private var rules: [ReminderRule] { model.database?.reminderRules ?? [] }
    private var terminology: ProfilePreset.Terminology { ProfilePreset.for(model.settings.profile).terminology }

    var body: some View {
        Form {
            healthSection
            kindsSection
            timeSensitiveSection
            alarmsSection
            quietSection
            tiersSection
        }
        .navigationTitle(Text("settings.reminders.title"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
        .reminderPermissionSheet(isPresented: $showsExplainer)
        .task { await reminders.refreshHealth() }
    }

    // MARK: Health

    private var healthSection: some View {
        let status = ReminderHealthCheck.overall(reminders.healthItems)
        return Section {
            NavigationLink { RemindersHealthView() } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.reminder-health.row")
                        if !reminders.healthItems.isEmpty {
                            Text(LocalizedStringKey(ReminderHealthPresentation.summaryKey(status)))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: ReminderHealthPresentation.symbol(status == .info ? .ok : status))
                }
                .frame(minHeight: 44, alignment: .leading)
            }
        }
    }

    // MARK: Kinds

    private var kindsSection: some View {
        let targets = ReminderKindList.visibleTargets(
            bringListVisible: model.activeTimetable?.fieldVisibility.isVisible(.bringList) ?? false, rules: rules)
        return Section {
            ForEach(targets, id: \.self) { target in
                kindRows(target)
            }
        } header: {
            Text("settings.reminders.kinds.title")
        } footer: {
            Text("settings.reminders.kinds.footer")
        }
    }

    @ViewBuilder private func kindRows(_ target: ReminderTarget) -> some View {
        let rule = ReminderRuleDefaults.rule(for: target, in: rules)
        let enabled = rule?.isEnabled ?? false
        Toggle(isOn: Binding(get: { enabled }, set: { setEnabled(target, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(ReminderKindList.titleKey(target, terminology: terminology)))
                if let rule {
                    ForEach(Array(ReminderRuleSummary.lines(rule).enumerated()), id: \.offset) { _, line in
                        RenderedText(line).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minHeight: 44)
        if enabled {
            NavigationLink { RemindersRuleEditorView(target: target) } label: {
                Text("settings.reminders.kind.edit").frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityLabel(Text(verbatim: model.renderer.format(key: "settings.reminders.kind.edit.a11y", arguments: [
                .text(model.renderer.string(forKey: ReminderKindList.titleKey(target, terminology: terminology))),
            ])))
        }
    }

    private func setEnabled(_ target: ReminderTarget, _ enabled: Bool) {
        var rule: ReminderRule
        if let stored = ReminderRuleDefaults.rule(for: target, in: rules) {
            rule = stored
        } else if enabled {
            let id = newIDs[target] ?? ReminderRule.ID(UUID())
            newIDs[target] = id
            rule = ReminderRuleDefaults.rule(for: target, profile: model.settings.profile, id: id)
        } else {
            return
        }
        rule.isEnabled = enabled
        model.apply(.upsert(ReminderRuleEditing.touched(rule)))
        if enabled {
            Task { if await reminders.shouldExplainNotificationPermission() { showsExplainer = true } }
        }
    }

    // MARK: Time Sensitive

    private var timeSensitiveSection: some View {
        let policy = model.settings.timeSensitivePolicy
        return Section {
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
        } header: {
            Text("settings.reminders.timesensitive.title")
        } footer: {
            Text("settings.reminders.timeSensitive.footer")
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
        } header: {
            Text("settings.reminders.alarm.title")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(allowed ? "settings.reminders.alarms.footer" : "reminders.tier.proOnly")
                if alarmAuthorization == .denied { Text("health.alarms.denied") }
            }
        }
    }

    // MARK: Quiet hours

    private var quietSection: some View {
        Section {
            QuietHoursRows(toggleKey: "settings.reminders.quiet.toggle", quietHours: Binding(
                get: { model.settings.globalQuietHours },
                set: { value in model.apply(.settings { $0.globalQuietHours = value }) }))
        } header: {
            Text("reminders.quiet.title")
        } footer: {
            Text("settings.reminders.quiet.footer")
        }
    }

    // MARK: Explanations

    private var tiersSection: some View {
        Group {
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
        }
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
