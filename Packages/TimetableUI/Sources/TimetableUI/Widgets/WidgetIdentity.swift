// Small SwiftUI pieces shared by the widget and Live Activity views (Phase 4U U7): the countdown text with its unit word
// and the Homework checkbox mark. Compiled into the widget extension and the app (DEBUG gallery) like the other views;
// avoids iOS-only API (watchOS typecheck). The "NOW" marker is U1's `NowMarker` (it draws an outline in the accented
// and vibrant rendering modes); colours are U1's tokens (`Color.ink`, `Color.correction`).
//
// HIG (apple-design skill, references/hig/):
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
