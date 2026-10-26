// Small building blocks shared by the onboarding steps: step scaffold, selectable choice row, card container,
// minutes stepper, and the terminology-dependent catalog keys.
// Standard controls only (Button, Toggle, Stepper, DatePicker), so iOS 26 applies its look automatically.
// APIs: LocalizedStringKey, TimetableUI AdaptiveStack / ScaledIcon / cardSurface, View.accessibilityAddTraits(_:),
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

/// A rounded group background for related controls: a white card (dark grey in dark mode) on the grouped page
/// background (Phase 4U U1, C2 / M9: tinted text on the old grey `.quaternary` fill measured 2.22:1).
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

/// A large, selectable row (single choice). Selection is shown by a checkmark and an outline, never colour alone.
/// Phase 4U U1: white card surface, the detail in `pencil` (≥ 4.5:1; the grey-on-grey detail measured 3.06:1, Astra
/// F04), and at accessibility text sizes the icon sits above the text (AdaptiveStack, capped ScaledIcon) so the title
/// gets the full width (H13 / F01: "Elemen-tary" was hyphenated). The checkmark stays beside the text block.
struct OnboardingChoiceRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let systemImage: String
    let isSelected: Bool
    var isEnabled = true
    var badge: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                AdaptiveStack(spacing: 12) {
                    ScaledIcon(systemName: systemImage, base: 28, maximum: 40, relativeTo: .title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(TypeScale.rowTitle).foregroundStyle(Color.primary)
                        if let detail {
                            Text(detail).font(.subheadline).foregroundStyle(Color.pencil)
                        }
                        if let badge {
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(DesignTokens.Surface.page, in: Capsule())
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(AppSymbol.completed)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .cardSurface()
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Surface.cornerRadius, style: .continuous)
                    .strokeBorder(.tint, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Surface.cornerRadius, style: .continuous))
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
                    .font(.subheadline)
                    .timeStyle()
                    .foregroundStyle(Color.pencil)
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
            Text(text).foregroundStyle(Color.correction)
        } icon: {
            Image(AppSymbol.warning).foregroundStyle(Color.correction)
        }
        .font(.subheadline)
    }
}
