// Onboarding steps 1, 2, 5 and 7: welcome + language note, profile, visible fields, start.
// APIs: Environment(\.openURL), UIApplication.openSettingsURLString (UIKit), Locale.localizedString(forLanguageCode:),
//       Toggle(isOn:label:), Image(systemName:).
import SwiftUI
import TimetableCore
import TimetableUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: 1 · Welcome

struct WelcomeStepView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 56.0

    private var languageName: String {
        let locale = model.formatter.locale
        guard let code = locale.language.languageCode?.identifier else { return locale.identifier }
        return locale.localizedString(forLanguageCode: code) ?? code
    }

    var body: some View {
        StepScaffold(title: "onboarding.welcome.title", subtitle: "onboarding.welcome.message") {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            OnboardingCard {
                Text("onboarding.welcome.language.title")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("onboarding.welcome.language.message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: model.renderer.format(key: "onboarding.welcome.language.current",
                                                     arguments: [.text(languageName)]))
                    .font(.subheadline.weight(.semibold))
                #if canImport(UIKit)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text("onboarding.welcome.language.open").frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                #endif
            }
        }
    }
}

// MARK: 2 · Profile

struct ProfileStepView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        StepScaffold(title: "onboarding.profile.title", subtitle: "onboarding.profile.subtitle") {
            VStack(spacing: 12) {
                row(.elementary, "onboarding.profile.elementary", "onboarding.profile.elementary.detail", "backpack")
                row(.secondary, "onboarding.profile.secondary", "onboarding.profile.secondary.detail", "studentdesk")
                row(.university, "onboarding.profile.university", "onboarding.profile.university.detail", "graduationcap")
                row(.other, "onboarding.profile.other", "onboarding.profile.other.detail", "sparkles")
            }
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

// MARK: 5 · Fields

struct FieldsStepView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        StepScaffold(title: "onboarding.fields.title", subtitle: "onboarding.fields.subtitle") {
            OnboardingCard {
                ForEach(LessonField.knownValues, id: \.rawValue) { field in
                    Toggle(isOn: binding(for: field)) {
                        Text(Self.title(of: field))
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func binding(for field: LessonField) -> Binding<Bool> {
        Binding(get: { flow.draft.visibleFields.contains(field) },
                set: { flow.draft.set(field, visible: $0) })
    }

    private static func title(of field: LessonField) -> LocalizedStringKey {
        switch field {
        case .room: return "onboarding.fields.room"
        case .building: return "onboarding.fields.building"
        case .teacher: return "onboarding.fields.teacher"
        case .lessonType: return "onboarding.fields.lessonType"
        case .notes: return "onboarding.fields.notes"
        default: return "onboarding.fields.bringList"
        }
    }
}

// MARK: 7 · Start

struct StartStepView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        StepScaffold(title: "onboarding.start.title") {
            VStack(spacing: 12) {
                OnboardingChoiceRow(title: "onboarding.start.blank", detail: "onboarding.start.blank.detail",
                                    systemImage: "square.dashed", isSelected: flow.draft.start == .blank) {
                    flow.draft.start = .blank
                }
                OnboardingChoiceRow(title: "onboarding.start.sample", detail: "onboarding.start.sample.detail",
                                    systemImage: "wand.and.stars", isSelected: flow.draft.start == .sample) {
                    flow.draft.start = .sample
                }
                OnboardingChoiceRow(title: "onboarding.start.photo", systemImage: "camera", isSelected: false,
                                    isEnabled: false, badge: "onboarding.start.comingSoon") {}
                OnboardingChoiceRow(title: "onboarding.start.code", systemImage: "qrcode", isSelected: false,
                                    isEnabled: false, badge: "onboarding.start.comingSoon") {}
            }
        }
    }
}
