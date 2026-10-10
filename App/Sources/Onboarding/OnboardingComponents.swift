// Small building blocks shared by the onboarding steps: step scaffold, selectable choice row, card container,
// minutes stepper, and the terminology-dependent catalog keys.
// Standard controls only (Button, Toggle, Stepper, DatePicker), so iOS 26 applies its look automatically.
// APIs: LocalizedStringKey, @ScaledMetric, ShapeStyle.quaternary, View.accessibilityAddTraits(_:),
//       View.accessibilityElement(children:), Stepper(value:in:step:label:), Text(_:format:).
import SwiftUI
import TimetableCore
import TimetableUI

extension OnboardingDraft {
    /// `base` + the profile's terminology suffix (`.lesson` / `.classLecture`): "never concatenate fragments" does
    /// not apply, this selects between two complete catalog strings.
    func termKey(_ base: String) -> String { DynamicL10nKeys.term(base, preset.terminology) }
}

/// Title, optional subtitle and content of one step.
struct StepScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.body).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// A rounded group background for related controls.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A large, selectable row (single choice). Selection is shown by a checkmark and an outline, never colour alone.
struct OnboardingChoiceRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let systemImage: String
    let isSelected: Bool
    var isEnabled = true
    var badge: LocalizedStringKey?
    let action: () -> Void
    @ScaledMetric(relativeTo: .title2) private var iconWidth = 32.0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A stepper over whole minutes (or counts) whose label is a catalog key and whose value is shown next to it.
struct OnboardingStepper: View {
    let titleKey: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    /// Formats the value for display and VoiceOver.
    let valueText: (Int) -> String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(titleKey))
                Text(verbatim: valueText(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityValue(Text(verbatim: valueText(value)))
    }
}

/// An error line: icon plus text, so it does not rely on colour.
struct OnboardingErrorLine: View {
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text).foregroundStyle(.red)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .font(.subheadline)
    }
}
