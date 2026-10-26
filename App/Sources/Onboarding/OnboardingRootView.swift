// The onboarding flow (UX_OVERHAUL_PLAN D8 / Opus R5): school type → how to start → your week → lesson times, in a
// NavigationStack (the standard back chevron and swipe-back; M7). Each step has one full-width primary button in the
// bottom safe-area inset (StepScaffold). The shell shows this view whenever no database exists, no live timetable
// exists or `settings.onboardingCompletedAt == nil`; finishing (OnboardingFlow.finish) writes the result and the
// shell then switches to the tabs on its own.
// `OnboardingRootView()` is the real entry; `init(step:prefill:)` is for the screenshot routes only.
// HIG: onboarding.md (brief, defaults over setup, permission in context), toolbars.md › Navigation (standard Back),
//      buttons.md › Style (one prominent button, title-style verb labels), typography.md › Supporting Dynamic Type.
// APIs: NavigationStack(path:root:), View.navigationDestination(for:destination:), View.toolbarRole(_:) (iOS 16),
//       View.navigationTitle(_:), View.navigationBarTitleDisplayMode(_:), View.alert(_:isPresented:actions:message:),
//       Environment(\.openURL), UIApplication.openSettingsURLString, Locale.localizedString(forLanguageCode:).
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct OnboardingRootView: View {
    private let initialStep: OnboardingStep
    private let prefill: OnboardingPrefill
    @Environment(AppModel.self) private var model
    @Environment(SampleContentController.self) private var samples
    // Created on first appearance because it needs `today` from the environment (no `_state` assignment in init).
    @State private var flow: OnboardingFlow?

    init() {
        initialStep = .schoolType
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
            ProgressView().task {
                flow = OnboardingFlow(today: model.today, step: initialStep, prefill: prefill,
                                      localStore: samples.localStore)
            }
        }
    }
}

/// The navigation stack of the four steps.
struct OnboardingFlowView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack(path: $flow.path) {
            page(.schoolType)
                .navigationDestination(for: OnboardingStep.self) { page($0) }
        }
        .alert(Text("onboarding.error.title"), isPresented: $flow.failureShown) {
            Button { } label: { Text("onboarding.error.ok") }
        } message: {
            Text("onboarding.error.message")
        }
    }

    private func progressText(_ step: OnboardingStep) -> String {
        model.renderer.format(key: "onboarding.progress", arguments: [
            .integer(Int64(step.index + 1)), .integer(Int64(OnboardingStep.count))])
    }

    private func page(_ step: OnboardingStep) -> some View {
        stepView(step)
            .navigationTitle(Text(verbatim: progressText(step)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarRole(.editor)   // back button without the previous step's title: just the standard chevron
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .schoolType: SchoolTypeStepView(flow: flow)
        case .start: StartStepView(flow: flow)
        case .week: WeekStepView(flow: flow)
        case .times: TimesStepView(flow: flow)
        }
    }
}

// MARK: 1 · Welcome · School type

struct SchoolTypeStepView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        StepScaffold(title: "onboarding.schoolType.title", subtitle: "onboarding.schoolType.subtitle",
                     actionTitle: "onboarding.action.continue",
                     actionEnabled: flow.draft.canAdvance(from: .schoolType)) {
            flow.advance(from: .schoolType)
        } content: {
            VStack(spacing: 12) {
                row(.elementary, "onboarding.profile.elementary", "onboarding.profile.elementary.detail", "backpack")
                row(.secondary, "onboarding.profile.secondary", "onboarding.profile.secondary.detail", "studentdesk")
                row(.university, "onboarding.profile.university", "onboarding.profile.university.detail", "graduationcap")
                row(.other, "onboarding.profile.other", "onboarding.profile.other.detail", "sparkles")
            }
            AppLanguageRow(flow: flow)
        }
    }

    private func row(_ profile: UserProfile, _ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                     _ symbol: String) -> some View {
        OnboardingChoiceRow(title: title, detail: detail, systemImage: symbol,
                            isSelected: flow.draft.profile == profile) {
            flow.draft.select(profile)
        }
    }
}

/// "App language: English · Change" (F13): compact and secondary; opens this app's page in iOS Settings, where the
/// per-app language is chosen. The school type is remembered first (a language change relaunches the app).
struct AppLanguageRow: View {
    let flow: OnboardingFlow
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var languageName: String {
        let locale = model.formatter.locale
        guard let code = locale.language.languageCode?.identifier else { return locale.identifier }
        return locale.localizedString(forLanguageCode: code) ?? code
    }

    private var currentText: String {
        model.renderer.format(key: "onboarding.language.current", arguments: [.text(languageName)])
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize   // adopt U1 AdaptiveStack
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        Button {
            flow.rememberProgressForLanguageChange()
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
            layout {
                Text(verbatim: currentText)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("onboarding.language.change")
                    .foregroundStyle(.tint)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: currentText))
        .accessibilityHint(Text("onboarding.language.hint"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: 2 · How do you want to start?

struct StartStepView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model
    @Environment(SampleContentController.self) private var samples

    private var isSample: Bool { flow.draft.start == .sample }

    var body: some View {
        StepScaffold(title: "onboarding.start.title",
                     actionTitle: isSample ? "onboarding.start.action.lookAround" : "onboarding.action.continue",
                     actionEnabled: flow.draft.canAdvance(from: .start)) {
            if isSample {
                flow.lookAround(model: model, samples: samples)
            } else {
                flow.advance(from: .start)
            }
        } content: {
            VStack(spacing: 12) {
                OnboardingChoiceRow(title: "onboarding.start.setUp", detail: "onboarding.start.setUp.detail",
                                    systemImage: "square.and.pencil", isSelected: !isSample) {
                    flow.draft.start = .blank
                }
                OnboardingChoiceRow(title: "onboarding.start.lookAround", detail: "onboarding.start.lookAround.detail",
                                    systemImage: "binoculars", isSelected: isSample) {
                    flow.draft.start = .sample
                }
            }
        }
    }
}
