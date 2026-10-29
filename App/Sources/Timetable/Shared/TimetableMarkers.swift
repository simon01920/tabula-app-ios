// Small visual markers of the Timetable tab (Phase 4U stage U4): the current-lesson highlighter outline, the single
// badge slot of a grid cell, the quiet free-slot button style and the one-time symbol legend (TipKit). Colours, the
// "Now" marker and symbols are U1's (`DesignTokens`, `NowMarker`, `AppSymbol`); TipKit is configured at the app root.
//
// Legend: an inline `TipView` with a custom `TipViewStyle` (symbol rows), shown above the timetable the first time a
// week with change markers is on screen; closing it invalidates the tip (TipKit datastore, once per device).
// Inline rather than `.popoverTip`: HIG popovers.md › Mobile: "Avoid displaying popovers in compact views", and a
// popover anchored to one cell of an offset-positioned grid would be fragile. TipKit compiles on both build paths
// without macros (`Tip` conformance only; no `@Parameter` / `#Rule`, which xtool's OpenAppleMacros lacks).
// Screenshot mode (`-TabulaNow`) never shows it, except the `timetable.grid-legend` route
// (`Tips.showAllTipsForTesting()`).
// APIs (checked in the iOS 26 SDK `.swiftinterface`, docs/ENVIRONMENT.md): TipKit `Tip`, `TipView`, `TipViewStyle`,
//       `Tips.configure(_:)`, `Tips.showAllTipsForTesting()`, `Tip.invalidate(reason: .tipClosed)`; ButtonStyle.makeBody(configuration:)
//       `isPressed`; RoundedRectangle.strokeBorder(_:style:); ViewThatFits; @ScaledMetric.
import SwiftUI
import TipKit
import TimetableCore
import TimetableUI

// MARK: Now

/// The current-lesson outline: a black hairline outside a highlighter band, visible on every subject colour (black
/// edge on yellow subjects, yellow band on dark ones).
struct HighlighterOutline: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.onHighlighter, lineWidth: 4.5)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .inset(by: 1.5)
                .strokeBorder(Color.highlighter, lineWidth: 3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Cell badge

/// The one badge slot of a grid cell (`LessonCellBadge`): a symbol on a solid card-colour capsule in the bottom-trailing
/// corner (a material over the subject colour would not guarantee the red cancelled symbol 3:1; the card is a tested
/// `DesignTokens.Reference` surface);
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
        .background(Capsule().fill(DesignTokens.Surface.card))
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
            .foregroundStyle(badge == .cancelled ? Color.correction : Color.primary)
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
                        .foregroundStyle(row.symbol == AppSymbol.cancelled.name ? Color.correction : Color.primary)
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

    /// Symbol + existing catalog phrase (reason and status names): when, where, who first.
    static let rows: [Row] = [
        Row(symbol: AppSymbol.timeChanged.name, key: ModificationReason.timeChanged.l10nKey),
        Row(symbol: AppSymbol.roomChanged.name, key: ModificationReason.roomChanged.l10nKey),
        Row(symbol: AppSymbol.substitute.name, key: ModificationReason.teacherChanged.l10nKey),
        Row(symbol: AppSymbol.changed.name, key: "lesson.status.modified"),
        Row(symbol: AppSymbol.extraLesson.name, key: "lesson.status.added"),
        Row(symbol: AppSymbol.cancelled.name, key: "lesson.status.cancelled"),
        Row(symbol: LessonBadges.taskSymbol, key: "timetable.legend.tasks"),
        Row(symbol: LessonBadges.examSymbol, key: "lesson.badge.exam"),
    ]
}
