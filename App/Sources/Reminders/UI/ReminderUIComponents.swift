// Shared building blocks of the reminder screens (Phase 3 Stage B4): offset list + editor, follow-up rows, quiet-hours
// rows, tier radio rows, the permission trigger and the loud-alarm opt-in. Used by the rule editor, the settings list and
// `ReminderOverrideSection`.
// Strings with arguments are rendered by `model.renderer` (one catalog format each; plural variations in the catalog),
// never built from fragments. Controls are standard SwiftUI (Liquid Glass applies by itself).
// APIs: Form rows, Picker, Stepper, DatePicker via TimeRow, Menu, NavigationLink(destination:label:), onDelete,
//       Toggle(isOn:label:), accessibilityElement(children:), accessibilityAddTraits(.isSelected).
import SwiftUI
import TimetableCore
import TimetableUI

/// Text of a `LocalizedText` (key + typed arguments) in the user's language.
struct RenderedText: View {
    @Environment(AppModel.self) private var model
    let text: LocalizedText

    init(_ text: LocalizedText) { self.text = text }

    var body: some View { Text(verbatim: model.renderer.string(text)) }
}

// MARK: - Permission + alarm opt-in

extension ReminderCoordinator {
    /// `true` when the notification prompt has not been shown yet, so the pre-explainer should come first.
    func shouldExplainNotificationPermission() async -> Bool {
        await refreshHealth()
        return health?.notifications.authorization == .notDetermined
    }
}

extension View {
    /// Presents the notification pre-explainer (`reminders.permission`) as a sheet.
    func reminderPermissionSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { ReminderPermissionSheet() }
    }
}

enum ReminderAlarmOptIn {
    /// Turns the loud-alarm policy on and asks for the AlarmKit permission (explicit user action only).
    @MainActor
    static func enable(model: AppModel, reminders: ReminderCoordinator) async -> AlarmAuthorization {
        if !model.settings.alarmPolicy.isEnabled {
            model.apply(.settings { $0.alarmPolicy.isEnabled = true })
        }
        return await reminders.requestAlarmAuthorization()
    }
}

// MARK: - Offsets

/// The offsets of a rule or override as rows: each opens an editor, swipe or Edit mode removes, a menu adds.
/// Place inside a `Section`.
struct ReminderOffsetsRows: View {
    @Binding var offsets: [ReminderOffset]

    var body: some View {
        ForEach(Array(offsets.enumerated()), id: \.offset) { index, offset in
            if ReminderOffsetEditing.kind(of: offset) != nil {
                NavigationLink {
                    ReminderOffsetEditorView(offset: Binding(
                        get: { offsets.indices.contains(index) ? offsets[index] : offset },
                        set: { if offsets.indices.contains(index) { offsets[index] = $0 } }))
                } label: {
                    RenderedText(ReminderOffsetEditing.text(offset)).frame(minHeight: 44, alignment: .leading)
                }
            } else {
                RenderedText(ReminderOffsetEditing.text(offset))
                    .foregroundStyle(.secondary).frame(minHeight: 44, alignment: .leading)
            }
        }
        .onDelete { offsets.remove(atOffsets: $0) }
        Menu {
            ForEach(ReminderOffsetEditing.availablePresets(excluding: offsets), id: \.self) { preset in
                Button { offsets = ReminderOffsetEditing.adding(preset, to: offsets) } label: {
                    RenderedText(ReminderOffsetEditing.text(preset))
                }
            }
            Button { offsets = ReminderOffsetEditing.adding(.minutesBefore(30), to: offsets) } label: {
                Text("reminders.offsets.addCustom")
            }
        } label: {
            Label { Text("reminders.offsets.add") } icon: { Image(systemName: "plus.circle") }
                .frame(minHeight: 44, alignment: .leading)
        }
    }
}

/// Edits one offset: kind picker, amount stepper, clock time for "days before".
struct ReminderOffsetEditorView: View {
    @Binding var offset: ReminderOffset

    var body: some View {
        Form {
            Section {
                Picker(selection: kind) {
                    ForEach(ReminderOffsetKind.allCases, id: \.self) { kind in
                        Text(LocalizedStringKey(kind.titleKey)).tag(kind)
                    }
                } label: {
                    Text("reminders.offset.kind")
                }
                if let minutes = ReminderOffsetEditing.minutes(of: offset) {
                    Stepper(value: Binding(get: { minutes }, set: { offset = .minutesBefore($0) }),
                            in: ReminderOffsetEditing.minutesRange, step: minutes >= 60 ? 15 : 5) {
                        RenderedText(ReminderOffsetEditing.text(offset))
                    }
                } else if let days = ReminderOffsetEditing.days(of: offset) {
                    let time = ReminderOffsetEditing.time(of: offset) ?? ReminderOffsetEditing.defaultEvening
                    Stepper(value: Binding(get: { days }, set: { offset = .daysBefore($0, at: time) }),
                            in: ReminderOffsetEditing.daysRange) {
                        RenderedText(ReminderOffsetEditing.text(.daysBefore(days, at: time)))
                    }
                    TimeRow(titleKey: "reminders.offset.time",
                            time: Binding(get: { time }, set: { offset = .daysBefore(days, at: $0) }))
                }
            } footer: {
                Text("reminders.offset.footer")
            }
        }
        .navigationTitle(Text("reminders.offset.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var kind: Binding<ReminderOffsetKind> {
        Binding(get: { ReminderOffsetEditing.kind(of: offset) ?? .minutesBefore },
                set: { offset = ReminderOffsetEditing.converting(offset, to: $0) })
    }
}

// MARK: - Follow-up

/// The follow-up picker and its detail row. `kind` and `followUp` adapt rules and overrides to one control.
struct FollowUpRows: View {
    let forOverride: Bool
    @Binding var kind: FollowUpMenuKind
    @Binding var followUp: FollowUp?

    var body: some View {
        Picker(selection: $kind) {
            ForEach(FollowUpEditing.options(forOverride: forOverride, current: kind), id: \.self) { option in
                Text(LocalizedStringKey(option.titleKey)).tag(option)
            }
        } label: {
            Text("reminders.followUp.title")
        }
        if let minutes = FollowUpEditing.minutes(of: followUp) {
            Picker(selection: Binding(get: { minutes }, set: { followUp = .afterMinutes($0) })) {
                ForEach(FollowUpEditing.minuteOptions(including: minutes), id: \.self) { value in
                    RenderedText(FollowUpEditing.delayText(minutes: value)).tag(value)
                }
            } label: {
                Text("reminders.followUp.delay")
            }
        } else if let time = FollowUpEditing.time(of: followUp) {
            TimeRow(titleKey: "reminders.followUp.time",
                    time: Binding(get: { time }, set: { followUp = .nextMorning(at: $0) }))
        }
    }
}

// MARK: - Quiet hours

struct QuietHoursRows: View {
    let toggleKey: LocalizedStringKey
    @Binding var quietHours: QuietHours?

    var body: some View {
        Toggle(isOn: Binding(get: { quietHours != nil },
                             set: { quietHours = $0 ? (quietHours ?? ReminderRuleEditing.defaultQuietHours) : nil })) {
            Text(toggleKey)
        }
        .frame(minHeight: 44)
        if let hours = quietHours {
            TimeRow(titleKey: "reminders.quiet.start",
                    time: Binding(get: { hours.start }, set: { quietHours = QuietHours(start: $0, end: hours.end) }))
            TimeRow(titleKey: "reminders.quiet.end",
                    time: Binding(get: { hours.end }, set: { quietHours = QuietHours(start: hours.start, end: $0) }))
        }
    }
}

// MARK: - Tier

/// One selectable tier with its honest explanation (title + detail, check mark when selected).
struct ReminderTierRow: View {
    let tier: DeliveryTier
    let isSelected: Bool
    var isAvailable = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: ReminderTierInfo.symbol(tier)).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(ReminderTierInfo.titleKey(tier))).font(.headline)
                    Text(LocalizedStringKey(ReminderTierInfo.detailKey(tier)))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !isAvailable {
                        Text("reminders.tier.proOnly").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
