// Onboarding steps 3, 4 and 6: rotation + term dates, time structure, reminders overview.
// APIs: DatePicker(selection:displayedComponents:label:), View.environment(\.timeZone, _), Stepper, Text(_:format:),
//       Toggle(isOn:label:). Dates are edited as `Date` in the device zone and converted with CalendarContext.
import SwiftUI
import TimetableCore
import TimetableUI

// MARK: 3 · Rotation

struct RotationStepView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model

    private var isLight: Bool { flow.draft.preset.rotationPrompt == .light }

    var body: some View {
        StepScaffold(title: isLight ? "onboarding.rotation.title.light" : "onboarding.rotation.title",
                     subtitle: "onboarding.rotation.subtitle") {
            VStack(spacing: 12) {
                ForEach(flow.draft.availableRotations, id: \.self) { choice in
                    OnboardingChoiceRow(title: Self.title(of: choice), detail: Self.detail(of: choice),
                                        systemImage: Self.symbol(of: choice), isSelected: flow.draft.rotation == choice) {
                        flow.draft.choose(rotation: choice)
                    }
                }
            }
            if flow.draft.rotation == .cycle { cycleCard }
            termCard
        }
    }

    private var cycleCard: some View {
        OnboardingCard {
            OnboardingStepper(titleKey: "onboarding.rotation.cycleLength", value: $flow.draft.cycleLength,
                              range: OnboardingDraft.cycleLengths) { weeks in
                model.renderer.format(key: "onboarding.rotation.cycleLength.value", arguments: [.integer(Int64(weeks))])
            }
            Text("onboarding.rotation.anchorNote").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var termCard: some View {
        OnboardingCard {
            Text("onboarding.term.title").font(.headline).accessibilityAddTraits(.isHeader)
            Toggle(isOn: $flow.draft.termEnabled) { Text("onboarding.term.toggle") }
                .frame(minHeight: 44)
            if flow.draft.termEnabled {
                DatePicker(selection: dateBinding(\.termStart), displayedComponents: .date) {
                    Text("onboarding.term.start")
                }
                .frame(minHeight: 44)
                DatePicker(selection: dateBinding(\.termEnd), displayedComponents: .date) {
                    Text("onboarding.term.end")
                }
                .frame(minHeight: 44)
                switch flow.draft.termIssue {
                case .endBeforeStart?: OnboardingErrorLine(text: "onboarding.term.error.endBeforeStart")
                case .tooLong?: OnboardingErrorLine(text: "onboarding.term.error.tooLong")
                case nil: EmptyView()
                }
            }
            Text("onboarding.term.footer").font(.footnote).foregroundStyle(.secondary)
        }
        .environment(\.timeZone, model.calendarContext.timeZone)
        .environment(\.calendar, model.calendarContext.calendar)
    }

    private func dateBinding(_ keyPath: WritableKeyPath<OnboardingDraft, LocalDate>) -> Binding<Date> {
        let context = model.calendarContext
        return Binding(get: { context.startOfDay(flow.draft[keyPath: keyPath]) },
                       set: { flow.draft[keyPath: keyPath] = context.localDate(of: $0) })
    }

    private static func title(of choice: RotationChoice) -> LocalizedStringKey {
        switch choice {
        case .none: return "onboarding.rotation.none"
        case .dayAB: return "onboarding.rotation.dayAB"
        case .oddEven: return "onboarding.rotation.oddEven"
        case .cycle: return "onboarding.rotation.cycle"
        case .perSemester: return "onboarding.rotation.perSemester"
        }
    }

    private static func detail(of choice: RotationChoice) -> LocalizedStringKey? {
        switch choice {
        case .none: return nil
        case .dayAB: return "onboarding.rotation.dayAB.detail"
        case .oddEven: return "onboarding.rotation.oddEven.detail"
        case .cycle: return "onboarding.rotation.cycle.detail"
        case .perSemester: return "onboarding.rotation.perSemester.detail"
        }
    }

    private static func symbol(of choice: RotationChoice) -> String {
        switch choice {
        case .none: return "calendar"
        case .dayAB: return "arrow.left.arrow.right"
        case .oddEven: return "number"
        case .cycle: return "repeat"
        case .perSemester: return "calendar.badge.clock"
        }
    }
}

// MARK: 4 · Time structure

struct TimeStepView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model

    private var draft: OnboardingDraft { flow.draft }

    var body: some View {
        StepScaffold(title: LocalizedStringKey(draft.termKey("onboarding.time.title")),
                     subtitle: "onboarding.time.subtitle") {
            VStack(spacing: 12) {
                OnboardingChoiceRow(title: "onboarding.time.kind.bell", systemImage: "bell",
                                    isSelected: draft.timeKind == .bellSchedule) { flow.draft.timeKind = .bellSchedule }
                OnboardingChoiceRow(title: "onboarding.time.kind.free", detail: "onboarding.time.free.message",
                                    systemImage: "clock", isSelected: draft.timeKind == .freeForm) {
                    flow.draft.timeKind = .freeForm
                }
            }
            switch draft.timeKind {
            case .bellSchedule:
                bellEditor
                preview
            case .freeForm:
                OnboardingCard {
                    OnboardingStepper(titleKey: draft.termKey("onboarding.time.length"), value: $flow.draft.freeFormMinutes,
                                      range: OnboardingDraft.freeFormMinutesRange, step: 5, valueText: minutes)
                }
            }
        }
    }

    private func minutes(_ value: Int) -> String {
        model.renderer.format(key: "onboarding.minutes", arguments: [.integer(Int64(value))])
    }

    private var bellEditor: some View {
        OnboardingCard {
            DatePicker(selection: firstStart, displayedComponents: .hourAndMinute) {
                Text(LocalizedStringKey(draft.termKey("onboarding.time.firstStart")))
            }
            .environment(\.timeZone, model.calendarContext.timeZone)
            .environment(\.calendar, model.calendarContext.calendar)
            .frame(minHeight: 44)
            OnboardingStepper(titleKey: draft.termKey("onboarding.time.length"), value: $flow.draft.lessonMinutes,
                              range: OnboardingDraft.lessonMinutesRange, step: 5, valueText: minutes)
            OnboardingStepper(titleKey: draft.termKey("onboarding.time.count"), value: $flow.draft.lessonCount,
                              range: OnboardingDraft.lessonCountRange) { $0.formatted() }
            OnboardingStepper(titleKey: "onboarding.time.shortBreak", value: $flow.draft.shortBreakMinutes,
                              range: OnboardingDraft.breakMinutesRange, step: 5, valueText: minutes)
            OnboardingStepper(titleKey: draft.termKey("onboarding.time.longBreak"), value: $flow.draft.longBreakMinutes,
                              range: OnboardingDraft.breakMinutesRange, step: 5, valueText: minutes)
        }
    }

    private var firstStart: Binding<Date> {
        let context = model.calendarContext
        return Binding(
            get: { context.date(flow.draft.today, LocalTime(minuteOfDay: flow.draft.firstStartMinutes) ?? .midnight) },
            set: { flow.draft.firstStartMinutes = context.local(from: $0).time.minuteOfDay })
    }

    @ViewBuilder
    private var preview: some View {
        let times = draft.bellPreview
        OnboardingCard {
            Text("onboarding.time.preview.title").font(.headline).accessibilityAddTraits(.isHeader)
            if times.isEmpty {
                OnboardingErrorLine(text: "onboarding.time.error.empty")
            }
            ForEach(Array(times.enumerated()), id: \.offset) { index, slot in
                let range = model.formatter.timeRange(slot.start, slot.end)
                HStack(spacing: 12) {
                    Text(index + 1, format: .number)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 32, minHeight: 32)
                        .background(.quaternary, in: Circle())
                    Text(verbatim: range).font(.body.monospacedDigit())
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: model.renderer.format(
                    key: draft.termKey("onboarding.time.preview.row"),
                    arguments: [.integer(Int64(index + 1)), .text(range)])))
            }
            if !times.isEmpty && times.count < draft.lessonCount {
                Text("onboarding.time.preview.truncated").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: 6 · Reminders overview

struct RemindersStepView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        StepScaffold(title: "onboarding.reminders.title", subtitle: "onboarding.reminders.subtitle") {
            if !flow.draft.offeredReminderTargets.isEmpty {
                OnboardingCard {
                    Text("onboarding.reminders.kinds").font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(flow.draft.offeredReminderTargets, id: \.rawValue) { target in
                        Toggle(isOn: binding(for: target)) { Text(LocalizedStringKey(key(of: target))) }
                            .frame(minHeight: 44)
                    }
                }
            }
            Text("onboarding.reminders.tiers.title").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            tier("bell", "onboarding.reminders.tier.standard.title", "onboarding.reminders.tier.standard.body")
            tier("bell.badge", "onboarding.reminders.tier.timeSensitive.title",
                 "onboarding.reminders.tier.timeSensitive.body")
            tier("alarm", "onboarding.reminders.tier.alarm.title", "onboarding.reminders.tier.alarm.body")
            Text("onboarding.reminders.footer").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func binding(for target: ReminderTarget) -> Binding<Bool> {
        Binding(get: { flow.draft.reminderTargets.contains(target) },
                set: { flow.draft.set(reminder: target, enabled: $0) })
    }

    private func key(of target: ReminderTarget) -> String {
        target == .lesson ? flow.draft.termKey("onboarding.reminders.target") : "onboarding.reminders.target.\(target.rawValue)"
    }

    private func tier(_ symbol: String, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        OnboardingCard {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.tint)
            }
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
