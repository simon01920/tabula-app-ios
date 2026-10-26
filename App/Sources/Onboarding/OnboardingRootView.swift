// The onboarding flow (PHASE2_PLAN §1): welcome → profile → rotation → time → fields → reminders → start.
// The shell shows this view whenever no database exists or `settings.onboardingCompletedAt == nil`; finishing
// (OnboardingFlow.finish) writes the result and the shell then switches to the tabs on its own.
// `OnboardingRootView()` is the real entry; `init(step:prefill:)` is for the screenshot routes only.
// APIs: ScrollView, View.safeAreaInset(edge:content:), ProgressView(value:total:), View.alert(_:isPresented:actions:message:),
//       AccessibilityNotification.ScreenChanged, @Environment(\.accessibilityReduceMotion), @Bindable, ShapeStyle.bar.
import SwiftUI
import TimetableCore
import TimetableUI

struct OnboardingRootView: View {
    private let initialStep: OnboardingStep
    private let prefill: OnboardingPrefill
    @Environment(AppModel.self) private var model
    // Created on first appearance because it needs `today` from the environment (no `_state` assignment in init).
    @State private var flow: OnboardingFlow?

    init() {
        initialStep = .welcome
        prefill = { _ in }
    }

    /// Opens at `step` with pre-filled answers (screenshot routes).
    init(step: OnboardingStep, prefill: @escaping OnboardingPrefill) {
        initialStep = step
        self.prefill = prefill
    }

    var body: some View {
        if let flow {
            OnboardingFlowView(flow: flow)
        } else {
            ProgressView().task { flow = OnboardingFlow(today: model.today, step: initialStep, prefill: prefill) }
        }
    }
}

/// Progress header, the current step, and the Back/Next bar.
struct OnboardingFlowView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            ScrollView {
                stepContent
                    .padding(.vertical, 12)
                    .id(flow.step)
                    .transition(.opacity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Phase 4U U1: the grouped page behind the white option cards (C2 / M9; U6 restructures the flow).
        .pageSurface()
        .safeAreaInset(edge: .bottom) { buttonBar }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: flow.step)
        .onChange(of: flow.step) { AccessibilityNotification.ScreenChanged().post() }
        .alert(Text("onboarding.error.title"), isPresented: $flow.failureShown) {
            Button { } label: { Text("onboarding.error.ok") }
        } message: {
            Text("onboarding.error.message")
        }
    }

    private var progressText: String {
        model.renderer.format(key: "onboarding.progress", arguments: [
            .integer(Int64(flow.step.index + 1)), .integer(Int64(OnboardingStep.count))])
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(flow.step.index + 1), total: Double(OnboardingStep.count))
                .accessibilityHidden(true)
            Text(verbatim: progressText)
                .font(.footnote)
                .foregroundStyle(Color.pencil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: progressText))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .welcome: WelcomeStepView()
        case .profile: ProfileStepView(flow: flow)
        case .rotation: RotationStepView(flow: flow)
        case .time: TimeStepView(flow: flow)
        case .fields: FieldsStepView(flow: flow)
        case .reminders: RemindersStepView(flow: flow)
        case .start: StartStepView(flow: flow)
        }
    }

    private var buttonBar: some View {
        HStack(spacing: 12) {
            if flow.step.previous != nil {
                Button { flow.back() } label: {
                    Text("onboarding.action.back").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                // C2 (Phase 4U U1): the capsule was #FCFCFC on the #F7F7F7 bar (1.04:1, invisible); a hairline in the
                // secondary label colour (≥ 3:1 non-text) shows its edge. U6 replaces it with the navigation back.
                .buttonBorderShape(.capsule)
                .overlay(Capsule().strokeBorder(Color.secondary, lineWidth: 1))
            }
            Button {
                if flow.isLastStep { flow.finish(model: model) } else { flow.advance() }
            } label: {
                (flow.isLastStep ? Text("onboarding.action.finish") : Text("onboarding.action.next"))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .onInkLabel()   // white on light ink 8.5:1, black on dark ink 8.8:1 (white would be 2.4:1)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!flow.canAdvance)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
