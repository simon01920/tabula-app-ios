// STUB (Phase 3 Stage A) of the per-item reminder override section. Stages B1 (task editor) and B2 (exam editor) embed
// it in their Form; stage B4 replaces the body (enable/disable, offsets, tier incl. the Loud-alarm opt-in with its
// AlarmKit permission request, follow-up — writing a `ReminderOverride`, DOMAIN_MODEL §3.9).
// KEEP THIS SIGNATURE:
//     ReminderOverrideSection(override: Binding<ReminderOverride?>, target: ReminderTarget)
// `target` is the item's rule target: `ReminderTarget(rawValue: task.kind.rawValue)` for tasks (homework / assignment /
// todo), `.exam` for exams — B4 uses it to show the matching rule's defaults. `nil` override = follow the rules.
// The body is a `Section`. Saving is the editor's job (`model.apply(.upsert(item))`), which re-plans automatically.
import SwiftUI
import TimetableCore

struct ReminderOverrideSection: View {
    @Binding var override: ReminderOverride?
    let target: ReminderTarget

    init(override: Binding<ReminderOverride?>, target: ReminderTarget) {
        _override = override
        self.target = target
    }

    var body: some View {
        Section {
            Label { Text(summaryKey) } icon: { Image(systemName: "bell") }
                .foregroundStyle(.secondary)
        } header: {
            Text("reminders.override.title")
        }
    }

    private var summaryKey: LocalizedStringKey {
        guard let override else { return "reminders.override.inherit" }
        if !override.isEnabled { return "reminders.override.off" }
        return "reminders.override.custom"
    }
}
