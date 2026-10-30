// Per-item reminder override section (Phase 3 B4), embedded by the task (B1) and exam (B2) editors in their Form.
// KEEP THIS SIGNATURE:
//     ReminderOverrideSection(override: Binding<ReminderOverride?>, target: ReminderTarget)
// `target` = `ReminderTarget(rawValue: task.kind.rawValue)` for tasks, `.exam` for exams; it selects the default rule
// shown as "Default: …". `nil` override = follow the rules ("Use default reminders" on). Saving is the editor's job
// (`model.apply(.upsert(item))`), which re-plans automatically.
// Custom: "Remind me" toggle (off = no reminders for this item), offsets (same as default / custom), tier (same as
// default / Standard / Time Sensitive / Loud alarm) and follow-up (same as default / none / after N min / next morning).
// Choosing Loud alarm turns the alarm policy on and asks for the AlarmKit permission (explicit action only).
// APIs: Section, Toggle, Picker, Binding(get:set:).
import SwiftUI
import TimetableCore
import TimetableUI

struct ReminderOverrideSection: View {
    @Binding var override: ReminderOverride?
    let target: ReminderTarget
    @Environment(AppModel.self) private var model
    @Environment(ReminderCoordinator.self) private var reminders
    @State private var showsExplainer = false

    init(override: Binding<ReminderOverride?>, target: ReminderTarget) {
        _override = override
        self.target = target
    }

    private var defaultRule: ReminderRule? {
        ReminderRuleDefaults.rule(for: target, in: model.database?.reminderRules ?? []).flatMap { $0.isEnabled ? $0 : nil }
    }

    private var custom: ReminderOverride { override ?? ReminderOverride() }

    private var timeSensitiveAvailable: Bool {
        TimeSensitiveAvailability.isAvailable(reminders.health?.notifications.timeSensitive)
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { override == nil }, set: { useDefault in
                override = useDefault ? nil : ReminderOverride()
                if !useDefault { askPermissionIfNeeded() }
            })) {
                Text("reminders.override.useDefault")
            }
            .frame(minHeight: 44)
            if let override {
                customRows(override)
            }
        } header: {
            Text("reminders.override.title")
        } footer: {
            footer
        }
        .reminderPermissionSheet(isPresented: $showsExplainer)
    }

    @ViewBuilder private func customRows(_ value: ReminderOverride) -> some View {
        Toggle(isOn: Binding(get: { value.isEnabled }, set: { newValue in update { $0.isEnabled = newValue } })) {
            Text("reminders.override.enabled")
        }
        .frame(minHeight: 44)
        if value.isEnabled {
            Picker(selection: Binding(get: { value.offsets != nil }, set: { isCustom in
                let seed = defaultRule?.offsets ?? [.daysBefore(1, at: ReminderOffsetEditing.defaultEvening)]
                update { $0.offsets = isCustom ? seed : nil }
            })) {
                Text("reminders.override.offsets.inherit").tag(false)
                Text("reminders.override.offsets.custom").tag(true)
            } label: {
                Text("reminders.override.offsets")
            }
            if value.offsets != nil {
                ReminderOffsetsRows(offsets: Binding(get: { value.offsets ?? [] },
                                                      set: { newValue in update { $0.offsets = newValue } }))
            }
            // U2-12 / D7: Time Sensitive is offered only where the build has it (U5a's detection); a stored one shows as
            // Standard there and is not rewritten until the user picks something.
            Picker(selection: Binding(get: { value.tier.map { TimeSensitiveAvailability.displayedTier($0, timeSensitiveAvailable: timeSensitiveAvailable) } },
                                      set: { setTier($0) })) {
                Text("reminders.override.tier.inherit").tag(DeliveryTier?.none)
                ForEach(TimeSensitiveAvailability.offeredTiers(timeSensitiveAvailable: timeSensitiveAvailable), id: \.self) { tier in
                    Text(LocalizedStringKey(ReminderTierInfo.titleKey(tier))).tag(Optional(tier))
                }
            } label: {
                Text("reminders.override.tier")
            }
            FollowUpRows(
                forOverride: true,
                kind: Binding(get: { FollowUpEditing.kind(of: value.followUp) }, set: { kind in
                    update { $0.followUp = FollowUpEditing.override(choosing: kind, current: $0.followUp) }
                }),
                followUp: Binding(get: { FollowUpEditing.followUp(of: value.followUp) }, set: { newValue in
                    update { edit in edit.followUp = newValue.map(FollowUpOverride.custom) ?? edit.followUp }
                }))
        }
    }

    @ViewBuilder private var footer: some View {
        if let rule = defaultRule, override == nil || override?.isEnabled == true {
            VStack(alignment: .leading, spacing: 2) {
                Text("reminders.override.defaultIs")
                ForEach(Array(ReminderRuleSummary.lines(rule).enumerated()), id: \.offset) { _, line in
                    RenderedText(line)
                }
            }
        } else if defaultRule == nil, override == nil {
            Text("reminders.override.noDefault")
        }
    }

    /// Applies an edit to a copy of the current override.
    private func update(_ edit: @escaping (inout ReminderOverride) -> Void) {
        var copy = custom
        edit(&copy)
        override = copy
    }

    private func setTier(_ tier: DeliveryTier?) {
        update { $0.tier = tier }
        if tier == .alarm {
            Task { _ = await ReminderAlarmOptIn.enable(model: model, reminders: reminders) }
        }
    }

    private func askPermissionIfNeeded() {
        Task { if await reminders.shouldExplainNotificationPermission() { showsExplainer = true } }
    }
}
