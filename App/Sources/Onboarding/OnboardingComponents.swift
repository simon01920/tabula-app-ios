// Small building blocks shared by the onboarding steps: step scaffold with the bottom action bar, selectable choice
// row, grouped card, minute field (stepper + direct entry) and the terminology-dependent catalog keys. School days use
// the editors' `WeekdayChips` (U5b).
// Standard controls only (Button, Toggle, Stepper, TextField, DatePicker), so iOS 26 applies its look automatically.
//
// Accessibility sizes (H13 / F01, HIG typography.md › "Consider adjusting your layout at large font sizes"): rows
// stack the icon above the text (U1 `AdaptiveStack`, capped `ScaledIcon`), nothing is shrunk or capped for text, the
// bottom button grows in height. Surfaces, colours and symbols are U1's (`pageSurface`, `cardSurface`, `DesignTokens`,
// `AppSymbol`).
// APIs: TimetableUI AdaptiveStack / ScaledIcon / cardSurface / pageSurface, View.safeAreaInset(edge:content:),
//       TextField(value:format:), View.keyboardType(_:), FocusState, @ScaledMetric, UIColor.tertiarySystemFill.
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

extension OnboardingDraft {
    /// `base` + the profile's terminology suffix (`.lesson` / `.classLecture`): "never concatenate fragments" does
    /// not apply, this selects between two complete catalog strings.
    func termKey(_ base: String) -> String { DynamicL10nKeys.term(base, preset.terminology) }
}

/// One step: a scrolling column with a large title and a one-sentence introduction, and one full-width primary
/// button in the bottom safe-area inset (content scrolls fully above it; the button grows in height at large text).
struct StepScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let actionTitle: LocalizedStringKey
    var actionEnabled = true
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageSurface()
        .safeAreaInset(edge: .bottom) {
            OnboardingPrimaryButton(title: actionTitle, isEnabled: actionEnabled, action: action)
        }
    }
}

/// The one full-width primary button (F01: whole words only; the label wraps between words and the button grows).
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .onInkLabel()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// A grouped card for related controls.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }
}

/// A section heading inside a step (sentence case, D12).
struct OnboardingSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A large, selectable row (single choice). Selection is shown by a checkmark and an outline, never colour alone.
/// White card surface, the detail in `pencil` (≥ 4.5:1), and at accessibility text sizes the icon sits above the text
/// (AdaptiveStack, capped ScaledIcon) so the title gets the full width (H13 / F01). The check stays beside the text.
struct OnboardingChoiceRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let systemImage: String
    let isSelected: Bool
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
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(isSelected ? AppSymbol.completed : AppSymbol.notCompleted)
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityHidden(true)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A whole-minute value with a stepper AND direct number entry (F11: large changes are common, e.g. 45 → 90).
/// The typed value is clamped to `range`; the unit is always shown.
struct OnboardingMinutesField: View {
    let titleKey: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 5
    /// "%lld min" (the value with its unit) for VoiceOver.
    let valueText: (Int) -> String
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var fieldWidth = 44.0

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        AdaptiveStack(spacing: 12) {
            Text(LocalizedStringKey(titleKey))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // At AX sizes the field and the stepper get a line each (D2: the row overflowed the screen sideways).
            AdaptiveStack(spacing: 8) {
                HStack(spacing: 8) {
                    // A set width (scaled): a fixed-size TextField takes its huge ideal width, which squeezed the unit
                    // out (F11 / D17) and pushed the row off screen at AX sizes (D2).
                    TextField(value: clamped, format: .number) {
                        Text(LocalizedStringKey(titleKey))
                    }
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    .focused($isFocused)
                    .frame(width: fieldWidth)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityValue(Text(verbatim: valueText(value)))
                    Text("onboarding.unit.minutes")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                Stepper(value: clamped, in: range, step: step) {
                    Text(LocalizedStringKey(titleKey))
                }
                .labelsHidden()
                .accessibilityValue(Text(verbatim: valueText(value)))
            }
        }
        .frame(minHeight: 44)
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { isFocused = false } label: { Text("editor.common.done") }
                }
            }
        }
    }
}

/// A stepper over a small count whose label is a catalog key and whose value is shown next to it.
struct OnboardingStepper: View {
    let titleKey: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    /// Formats the value for display and VoiceOver.
    let valueText: (Int) -> String

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LocalizedStringKey(titleKey))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(verbatim: valueText(value))
                    .font(.body.monospacedDigit())
            }
        }
        .frame(minHeight: 44)
        .accessibilityValue(Text(verbatim: valueText(value)))
    }
}

/// An error line: a red warning icon plus primary text (readable on any background; not colour alone).
struct OnboardingErrorLine: View {
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(AppSymbol.warning).foregroundStyle(Color.correction)
        }
        .font(.subheadline)
    }
}
