// Small visual markers of the Timetable tab (Phase 4U stage U4): the local "Exercise book" colours (until U1's shared
// tokens merge), the highlighter "Now" tag, the single badge slot of a grid cell, the quiet free-slot button style
// and the one-time symbol legend (TipKit).
//
// Legend: an inline `TipView` with a custom `TipViewStyle` (symbol rows), shown above the timetable the first time a
// week with change markers is on screen; closing it invalidates the tip (TipKit datastore, once per device).
// Inline rather than `.popoverTip`: HIG popovers.md › Mobile: "Avoid displaying popovers in compact views", and a
// popover anchored to one cell of an offset-positioned grid would be fragile. TipKit compiles on both build paths
// without macros (`Tip` conformance only; no `@Parameter` / `#Rule`, which xtool's OpenAppleMacros lacks).
// Screenshot mode (`-TabulaNow`) never shows it, except the `timetable.grid-legend` route
// (`Tips.showAllTipsForTesting()`).
// APIs (checked in the iOS 26 SDK `.swiftinterface`, docs/ENVIRONMENT.md): TipKit `Tip`, `TipView`, `TipViewStyle`,
//       `Tips.configure(_:)`, `Tips.showAllTipsForTesting()`, `Tip.invalidate(reason: .tipClosed)`; UIColor(dynamicProvider:)
//       with `UITraitCollection.userInterfaceStyle` / `.accessibilityContrast`; ButtonStyle.makeBody(configuration:)
//       `isPressed`; RoundedRectangle.strokeBorder(_:style:); ViewThatFits; @ScaledMetric.
import SwiftUI
import TipKit
import TimetableCore
import TimetableUI
import UIKit

// MARK: Colours

/// The plan's exact token values (UX_OVERHAUL_PLAN D1), resolved for light / dark / Increase Contrast.
// adopt U1: DesignTokens.ink / .correction / .highlighter replace this enum.
enum TimetableColor {
    static let ink = dynamic(light: TimetableMarkerColors.inkLight, dark: TimetableMarkerColors.inkDark,
                             increasedContrastLight: TimetableMarkerColors.inkIncreasedContrast)
    static let onInk = dynamic(light: TimetableMarkerColors.onInkLight, dark: TimetableMarkerColors.onInkDark)
    static let correction = dynamic(light: TimetableMarkerColors.correctionLight, dark: TimetableMarkerColors.correctionDark)
    static let onCorrection = dynamic(light: TimetableMarkerColors.onCorrectionLight,
                                      dark: TimetableMarkerColors.onCorrectionDark)
    static let highlighter = Color(TimetableMarkerColors.highlighter)
    static let onHighlighter = Color(TimetableMarkerColors.onHighlighter)
    static let changeText = dynamic(light: TimetableMarkerColors.changeTextLight, dark: TimetableMarkerColors.changeTextDark)

    private static func dynamic(light: ColorValue, dark: ColorValue, increasedContrastLight: ColorValue? = nil) -> Color {
        Color(UIColor { traits in
            if traits.userInterfaceStyle == .dark { return uiColor(dark) }
            if traits.accessibilityContrast == .high, let increasedContrastLight { return uiColor(increasedContrastLight) }
            return uiColor(light)
        })
    }

    private static func uiColor(_ value: ColorValue) -> UIColor {
        let rgba = RGBA(value)
        return UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.opacity)
    }
}

// MARK: Now

/// The highlighter "NOW" tag (black on #FFE04A, 16:1 in both appearances): the one signature element (Opus §9).
// adopt U1: NowMarker
struct HighlighterNowTag: View {
    var font: Font = .caption.weight(.heavy)

    var body: some View {
        Text("timetable.now")
            .font(font)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(TimetableColor.onHighlighter)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(TimetableColor.highlighter))
            .accessibilityHidden(true)   // the lesson's accessibility value says "now"
    }
}

/// The current-lesson outline: a black hairline outside a highlighter band, visible on every subject colour (black
/// edge on yellow subjects, yellow band on dark ones).
struct HighlighterOutline: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(TimetableColor.onHighlighter, lineWidth: 4.5)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: 1.5)
                .strokeBorder(TimetableColor.highlighter, lineWidth: 3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Cell badge

/// The one badge slot of a grid cell (`LessonCellBadge`): a symbol on a material disc in the bottom-trailing corner;
/// tasks add their count when it fits. Decorative: the cell's VoiceOver sentence names the state.
struct CellBadgeView: View {
    let badge: LessonCellBadge
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 10

    var body: some View {
        ViewThatFits(in: .horizontal) {
            symbolAndCount
            symbol
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(.regularMaterial))
        .padding(1.5)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var symbolAndCount: some View {
        if case .tasks(let count) = badge {
            HStack(spacing: 1) {
                symbol
                Text(verbatim: count.formatted())
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
            }
            .fixedSize()
        } else {
            symbol
        }
    }

    private var symbol: some View {
        Image(systemName: badge.symbolName)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(badge == .cancelled ? TimetableColor.correction : Color.primary)
            .fixedSize()
    }
}

// MARK: Free slot

/// Empty grid slots stay quiet (Opus M14): plain background; the dashed outline and "+" appear only while pressed.
/// The outline uses the secondary label colour (≥ 3:1 on the background, unlike the old 1.7:1 dashes, Opus C2).
struct QuietFreeSlotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.clear)
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .contentShape(Rectangle())
    }
}

// MARK: Legend tip

/// "Symbols in the timetable": shown once, the first time a week with change markers is on screen.
struct ChangeLegendTip: Tip {
    var id: String { "timetable.changeLegend" }
    var title: Text { Text("timetable.legend.title") }
}

/// The legend's look: title, one row per change symbol (the same symbols as the grid, detail and Today), close button.
struct ChangeLegendTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (configuration.title ?? Text("timetable.legend.title"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    configuration.tip.invalidate(reason: .tipClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("timetable.legend.close"))
            }
            ForEach(Self.rows) { row in
                Label {
                    Text(LocalizedStringKey(row.key))
                } icon: {
                    Image(systemName: row.symbol)
                        .foregroundStyle(row.symbol == LessonChangeSymbol.cancelled ? TimetableColor.correction : Color.primary)
                }
                .font(.subheadline)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .padding(.vertical, 6)
    }

    struct Row: Identifiable {
        let symbol: String
        let key: String
        var id: String { key }
    }

    /// Symbol + existing catalog phrase (reason and status names), in `LessonChangeSymbol.priority` order.
    static let rows: [Row] = [
        Row(symbol: LessonChangeSymbol.timeChanged, key: ModificationReason.timeChanged.l10nKey),
        Row(symbol: LessonChangeSymbol.roomChanged, key: ModificationReason.roomChanged.l10nKey),
        Row(symbol: LessonChangeSymbol.substitute, key: ModificationReason.teacherChanged.l10nKey),
        Row(symbol: LessonChangeSymbol.added, key: "lesson.status.added"),
        Row(symbol: LessonChangeSymbol.cancelled, key: "lesson.status.cancelled"),
        Row(symbol: LessonBadges.taskSymbol, key: "timetable.legend.tasks"),
        Row(symbol: LessonBadges.examSymbol, key: "lesson.badge.exam"),
    ]
}

/// TipKit set-up for the Timetable tab.
// adopt U1: move `Tips.configure()` to the app root once U1 owns it (it may be called only once per launch).
@MainActor
enum TimetableTips {
    private static var configured = false

    /// Configures TipKit once. `forceShow` (screenshot route) shows every tip regardless of history.
    static func configure(forceShow: Bool) {
        guard !configured else { return }
        configured = true
        if forceShow { Tips.showAllTipsForTesting() }
        do {
            try Tips.configure()
        } catch {
            // Already configured elsewhere (a later root-level set-up): tips still work.
        }
    }
}
