// Small building blocks shared by the onboarding steps: step scaffold with the bottom action bar, selectable choice
// row, grouped card, weekday chips, minute field (stepper + direct entry) and the terminology-dependent catalog keys.
// Standard controls only (Button, Toggle, Stepper, TextField, DatePicker), so iOS 26 applies its look automatically.
//
// Accessibility sizes (H13 / F01, HIG typography.md › "Consider adjusting your layout at large font sizes"): rows
// stack the icon above the text via `AnyLayout` and `dynamicTypeSize.isAccessibilitySize`, decorative icons are capped
// at AX1, nothing is shrunk or capped for text, the bottom button grows in height.
// adopt U1 AdaptiveStack (+ U1 tokens, `AppSymbol`, white choice cards) at merge: this file implements the AX stacking
// locally because U1 ran in parallel; spots are marked `// adopt U1 AdaptiveStack`.
// APIs: AnyLayout / HStackLayout / VStackLayout (iOS 16), EnvironmentValues.dynamicTypeSize +
//       DynamicTypeSize.isAccessibilitySize, View.dynamicTypeSize(_:) with a range, View.safeAreaInset(edge:content:),
//       TextField(value:format:), View.keyboardType(_:), FocusState, @ScaledMetric,
//       LazyVGrid / GridItem.adaptive, UIColor.systemGroupedBackground / secondarySystemGroupedBackground.
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

extension OnboardingDraft {
    /// `base` + the profile's terminology suffix (`.lesson` / `.classLecture`): "never concatenate fragments" does
    /// not apply, this selects between two complete catalog strings.
    func termKey(_ base: String) -> String { DynamicL10nKeys.term(base, preset.terminology) }
}

/// Page and card colours of the onboarding screens: white cards on the grouped background (M9), both semantic.
enum OnboardingColors {
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
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
        .background(OnboardingColors.page)
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
            .background(OnboardingColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
/// At accessibility sizes the icon sits above the text, so the title gets the full width (no word-internal breaks).
struct OnboardingChoiceRow: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var iconWidth = 32.0

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Button(action: action) {
            let layout = isStacked   // adopt U1 AdaptiveStack
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
            layout {
                if isStacked {
                    HStack(alignment: .center) {
                        icon
                        Spacer(minLength: 8)
                        checkmark
                    }
                } else {
                    icon.frame(width: min(iconWidth, 44))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !isStacked { checkmark }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(OnboardingColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.tint)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // decorative: capped (H13)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var checkmark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityHidden(true)
    }
}

/// School-day chips in the locale's week order. Selected chips are filled (prominent style: a luminance change, not
/// only a hue) and carry the "Selected" trait; each chip has the full weekday name for VoiceOver. The grid wraps at
/// large text sizes.
struct WeekdayChips: View {
    let days: [Weekday]
    let isOn: (Weekday) -> Bool
    let toggle: (Weekday) -> Void
    let shortName: (Weekday) -> String
    let fullName: (Weekday) -> String
    @ScaledMetric(relativeTo: .body) private var minimumChipWidth = 52.0

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumChipWidth), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(days, id: \.self) { day in
                if isOn(day) {
                    chip(day).buttonStyle(.borderedProminent)
                } else {
                    chip(day).buttonStyle(.bordered)
                }
            }
        }
    }

    private func chip(_ day: Weekday) -> some View {
        Button { toggle(day) } label: {
            Text(verbatim: shortName(day))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(Text(verbatim: fullName(day)))
        .accessibilityAddTraits(isOn(day) ? .isSelected : [])
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var fieldWidth = 56.0

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize   // adopt U1 AdaptiveStack
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Text(LocalizedStringKey(titleKey))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                TextField(value: clamped, format: .number) {
                    Text(LocalizedStringKey(titleKey))
                }
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .focused($isFocused)
                .frame(minWidth: fieldWidth, minHeight: 44)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityValue(Text(verbatim: valueText(value)))
                Text("onboarding.unit.minutes")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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
                    Button { isFocused = false } label: { Text("onboarding.action.doneTyping") }
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .font(.subheadline)
    }
}
