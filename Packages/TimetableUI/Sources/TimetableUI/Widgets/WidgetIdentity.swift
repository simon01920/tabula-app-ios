// Small SwiftUI pieces shared by the widget and Live Activity views (Phase 4U U7): the highlighter "NOW" marker, the ink
// foreground, the countdown text with its unit word, and the Homework checkbox mark. Compiled into the widget
// extension and the app (DEBUG gallery) like the other views; avoids iOS-only API (watchOS typecheck).
//
// U1 runs in parallel and builds the shared design tokens and `NowMarker`; U7 must not create competing shared tokens, so
// the values here are local (`WidgetInkTokens`, plan D1 / Opus §9) and every use is marked so the orchestrator can swap
// them for U1's:  // adopt U1 NowMarker   // adopt U1 tokens
//
// HIG (apple-design skill, references/hig/):
//   widgets.md › Rendering modes: in the accented and vibrant modes the system recolours everything, so the yellow
//     highlighter becomes an outlined capsule there ("use opaque grayscale ... for the best vibrant material effect").
//   widgets.md › Adding interactivity: "Pay attention to the size of targets": the checkbox keeps its 44 pt target.
//   color.md: one colour, one meaning (highlighter = "Now" only; ink = the tint; red = overdue only).
//   typography.md: numbers that matter use rounded monospaced digits.
//
// Live countdown values: `Text(timerInterval:)` below an hour, `Text(date, style: .relative)` (minutes, live, no
// seconds) from an hour on and for exams, always followed by the unit word (H2). `pauseTime` (the gallery's fixed clock)
// shows the static value instead.
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

/// The highlighter "NOW" marker: black text on a short yellow marker stroke (#FFE04A, 16:1). In the tinted and vibrant
/// widget modes colour carries no meaning, so it is an outlined capsule in the primary colour.
// adopt U1 NowMarker
struct NowHighlighterTag: View {
    let text: String
    var font: Font = .caption2
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(verbatim: text.uppercased())
            .font(font.weight(.heavy))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(renderingMode == .fullColor ? Color(WidgetInkTokens.onHighlighter) : Color.primary)
            .background {
                if renderingMode == .fullColor {
                    // A marker stroke: slightly rounded, not a pill.
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color(WidgetInkTokens.highlighter))
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.primary, lineWidth: 1)
                }
            }
            .widgetAccentable()
            .accessibilityHidden(true)   // the widget's one VoiceOver sentence already says "Now"
    }
}

/// `ink` as the foreground colour of accent glyphs, in the full-colour mode only (the tinted and vibrant modes recolour
/// the accent group themselves). Increase Contrast uses the darker ink.
// adopt U1 tokens
struct InkForeground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content.foregroundStyle(Color(ink))
        } else {
            content
        }
    }

    private var ink: ColorValue {
        if colorScheme == .dark { return WidgetInkTokens.inkDark }
        return contrast == .increased ? WidgetInkTokens.inkHighContrast : WidgetInkTokens.inkLight
    }
}

extension View {
    /// Foreground `ink` (U7 local token).
    // adopt U1 tokens
    func inkForeground() -> some View { modifier(InkForeground()) }
}

/// The `correction` red of overdue marks (overdue, cancelled and destructive only).
// adopt U1 tokens
struct CorrectionForeground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(Color(colorScheme == .dark ? WidgetInkTokens.correctionDark : WidgetInkTokens.correctionLight))
    }
}

/// A countdown value with its unit word (H2): "24:59 left", "25 min left", "1 h 30 min until start".
struct WidgetCountdownText: View {
    /// Unit below the value (big numbers) or beside it (one-line families).
    enum Layout { case stacked, inline, valueOnly }

    let countdown: WidgetCountdown
    let pauseTime: Date?
    var layout: Layout = .stacked
    /// Alignment of the stacked layout.
    var alignment: HorizontalAlignment = .leading
    /// Minutes only even under an hour (compact Dynamic Island, inline: no room for mm:ss plus a unit word).
    var minutesOnly = false
    /// Font of the unit word.
    var unitFont: Font = .caption2

    var body: some View {
        switch layout {
        case .stacked:
            VStack(alignment: alignment, spacing: 0) {
                value
                unit
            }
        case .inline:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                value
                unit
            }
        case .valueOnly:
            value
        }
    }

    private var unit: some View {
        Text(verbatim: countdown.unitLabel)
            .font(unitFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var value: some View {
        if let pauseTime {
            Text(verbatim: staticValue(at: pauseTime))
        } else {
            switch minutesOnly ? .minutes : countdown.mode {
            case .timer:
                Text(timerInterval: countdown.interval, countsDown: true, showsHours: true)
            case .minutes:
                // Live, minutes only, localised by the system; the hour mode never shows seconds.
                Text(countdown.interval.upperBound, style: .relative)
            }
        }
    }

    private func staticValue(at instant: Date) -> String {
        switch minutesOnly ? .minutes : countdown.mode {
        case .timer:
            return CountdownFormat.string(remaining: countdown.interval.upperBound.timeIntervalSince(
                max(instant, countdown.interval.lowerBound)))
        case .minutes:
            return countdown.durationText
        }
    }
}

/// The Homework checkbox glyph: a 44 × 44 pt target (HIG minimum) whose 22 pt circle sits on the widget's leading margin
/// edge, so the gap to the subject badge is 11 pt instead of the former 28 (M31). Used by the real `Button(intent:)`
/// (WidgetExtension, `TABULA_APP_INTENTS` builds) and by the gallery's static copy.
public struct HomeworkCheckboxMark: View {
    public init() {}

    public var body: some View {
        Image(systemName: "circle")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .padding(.leading, -11)   // the 44 pt target starts 11 pt left of the circle; layout width is 33 pt
    }
}
#endif
