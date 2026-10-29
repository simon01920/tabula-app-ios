// Onboarding step 4 · "Lesson times" (F11): "Fixed lesson periods" (same times each day: generator + live preview) or
// "Individual start and end times" (default length). Minute values have a stepper AND direct number entry; the lesson
// count is a stepper. "I'll Do This Later" finishes with the profile's suggested times. The last button reads
// "Start Using Tabula" (F10: the outcome is named, never an ambiguous "Get started").
// HIG: steppers.md / entering-data.md (choices and direct entry, units shown), buttons.md › Content (verb labels).
// APIs: DatePicker(selection:displayedComponents:label:), View.environment(\.timeZone, _), Text(_:format:).
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct TimesStepView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model
    @Environment(SampleContentController.self) private var samples

    private var draft: OnboardingDraft { flow.draft }

    var body: some View {
        StepScaffold(title: LocalizedStringKey(draft.termKey("onboarding.time.title")),
                     subtitle: "onboarding.time.subtitle",
                     actionTitle: "onboarding.action.start", actionEnabled: draft.canFinish(from: .times)) {
            flow.finish(from: .times, model: model, samples: samples)
        } content: {
            VStack(spacing: 12) {
                OnboardingChoiceRow(title: "onboarding.time.kind.fixed", detail: "onboarding.time.kind.fixed.detail",
                                    systemImage: "bell", isSelected: draft.timeKind == .bellSchedule) {
                    flow.draft.timeKind = .bellSchedule
                }
                OnboardingChoiceRow(title: "onboarding.time.kind.individual",
                                    detail: "onboarding.time.kind.individual.detail",
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
                    OnboardingMinutesField(titleKey: draft.termKey("onboarding.time.length"),
                                           value: $flow.draft.freeFormMinutes,
                                           range: OnboardingDraft.freeFormMinutesRange, valueText: minutes)
                }
            }
            laterLink
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
            .hourCycleLocale(model.formatter.locale)   // D4 / H1: the app's 12/24-hour clock (U1)
            .frame(minHeight: 44)
            OnboardingMinutesField(titleKey: draft.termKey("onboarding.time.length"), value: $flow.draft.lessonMinutes,
                                   range: OnboardingDraft.lessonMinutesRange, valueText: minutes)
            OnboardingStepper(titleKey: draft.termKey("onboarding.time.count"), value: $flow.draft.lessonCount,
                              range: OnboardingDraft.lessonCountRange) { $0.formatted() }
            OnboardingMinutesField(titleKey: "onboarding.time.shortBreak", value: $flow.draft.shortBreakMinutes,
                                   range: OnboardingDraft.breakMinutesRange, valueText: minutes)
            OnboardingMinutesField(titleKey: draft.termKey("onboarding.time.longBreak"),
                                   value: $flow.draft.longBreakMinutes,
                                   range: OnboardingDraft.breakMinutesRange, valueText: minutes)
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
                        .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    Text(verbatim: range)
                        .font(.body.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: model.renderer.format(
                    key: draft.termKey("onboarding.time.preview.row"),
                    arguments: [.integer(Int64(index + 1)), .text(range)])))
            }
            if !times.isEmpty && times.count < draft.lessonCount {
                Text("onboarding.time.preview.truncated")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "I'll Do This Later": a secondary, borderless action under the content (the primary button stays the finish).
    private var laterLink: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                flow.finishWithSuggestedTimes(model: model, samples: samples)
            } label: {
                Text("onboarding.time.later")
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(Text("onboarding.time.later.detail"))
            Text("onboarding.time.later.detail")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }
}
