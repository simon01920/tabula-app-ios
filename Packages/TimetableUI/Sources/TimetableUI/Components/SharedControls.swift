// Small shared controls (Phase 4U U1). iOS + watchOS (scripts/watch-typecheck.sh).
//
// - SheetCloseButton (M7): the system Close button of a sheet. HIG toolbars.md › "Use the standard Back and Close
//   buttons": "Prefer the standard symbols for each, and don't use a text label that says Back or Close."
//   `Button(role: .close, action:)` draws the system "×" with its localised accessibility label (iOS 26 / watchOS 26,
//   Apple docs `ButtonRole.close` and `Button.init(role:action:)` "Creates a button that displays a default label",
//   checked 2026-10-23). Put it in `ToolbarItem(placement: .cancellationAction)`; the trailing item is Edit.
// - ProBadge (C2): the "Pro" marker on Pro-only choices. Was light-blue text on white (1.88:1, measured); now ink text
//   on a capsule filled with ink at 12 % opacity (plus a 35 % ink hairline), with explicit colours so a disabled parent
//   control cannot fade it (ink on white 8.5:1; on its own tinted fill ≥ 4.5:1 in every appearance, tested in
//   DesignTokenContrastTests.proBadgeTextOnItsTintedCapsule).
#if canImport(SwiftUI)
import SwiftUI

/// The standard Close button of a sheet; dismisses the presentation.
public struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    private let action: (() -> Void)?

    /// Dismisses the sheet.
    public init() { action = nil }

    /// Runs `action` instead of dismissing (for sheets whose presenter owns the dismissal).
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        Button(role: .close) {
            if let action { action() } else { dismiss() }
        }
    }
}

extension View {
    /// D4 / H1: shows a time `DatePicker` with the app's effective hour cycle (`TimeFormatLocale.locale`, which is
    /// `AppModel.formatter.locale`). Scoped to the picker on purpose: a root `\.locale` would also drive SwiftUI's
    /// string lookup and replace `Locale.current`, with the user's iOS region preferences, everywhere (RISKS #87).
    /// The app's own text already follows the setting through `TimetableFormatter`.
    public func hourCycleLocale(_ locale: Locale) -> some View {
        environment(\.locale, locale)
    }

    /// M1 (Opus review): a control whose label repeats its section header ("Rotation" header over a "Rotation" picker)
    /// shows only the header. The label stays the control's accessibility label, so VoiceOver still names it.
    ///
    ///     Section { Picker(selection: $x) { … } label: { Text("editor.rotation") }.labelledBySectionHeader() }
    ///     header: { Text("editor.rotation.header") }
    public func labelledBySectionHeader() -> some View {
        labelsHidden()
    }
}

/// "Pro" on a Pro-only option. Not a button: it explains why the option is unavailable.
public struct ProBadge: View {
    private let text: Text

    /// The catalog word `settings.appearance.palette.pro` ("Pro").
    public init() { text = Text("settings.appearance.palette.pro") }

    /// A pre-resolved word (widgets / other lookups).
    public init(label: String) { text = Text(verbatim: label) }

    public var body: some View {
        text
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.ink.opacity(Double(DesignTokens.proBadgeFillAlpha) / 255)))
            .overlay(Capsule().strokeBorder(Color.ink.opacity(0.35), lineWidth: 1))
    }
}
#endif
