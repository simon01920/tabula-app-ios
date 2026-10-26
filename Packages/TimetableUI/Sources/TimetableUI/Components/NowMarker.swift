// The highlighter "Now" marker (Phase 4U U1, D1; Opus review §9 "Signature element"): the one bold element of the
// identity. A short yellow marker swipe behind the word NOW in black (16:1, tested in DesignTokensTests), slightly
// rounded and skewed like a real highlighter stroke. It replaces the red "recording" dot and the black current-lesson
// borders wherever the present moment is shown: Today hero, grid cell, Week/Day now line, tiles, widgets, Live
// Activities. Screens adopt it in U3 (Today), U4 (Timetable) and U7 (widgets).
//
// - Static: no animation, so Reduce Motion needs nothing (the stroke never moves).
// - Meaning is carried by the word, not the colour: it shows "NOW" (catalog key `now.marker`, uppercased for display)
//   and VoiceOver reads the same key without the case change ("Now", never spelled out letter by letter).
// - Text scales with Dynamic Type (`.caption.bold()` small, `.subheadline.bold()` regular) and never truncates.
// - iOS + watchOS + widgets: plain Text + Shape, no iOS-only modifiers (scripts/watch-typecheck.sh).
// - Widgets in accented / vibrant rendering: WidgetKit may desaturate the fill; the word stays readable because it
//   is the text that carries the meaning (U7 checks the rendering modes on the device).
//
// APIs: Shape, Path (addCurve, closeSubpath), Text.textCase(_:) (iOS 14, watchOS 7), accessibilityLabel(_:),
//   accessibilityAddTraits(.isStaticText), fixedSize(horizontal:vertical:).
#if canImport(SwiftUI)
import SwiftUI

/// The highlighter "Now" marker.
public struct NowMarker: View {
    /// Size of the marker.
    public enum Size: Sendable {
        /// Grid cells, widget rows, Live Activity lines.
        case small
        /// Rows, cards, the Today hero.
        case regular
    }

    private let size: Size
    private let text: Text
    private let accessibilityText: Text

    /// The standard marker: the catalog word `now.marker` ("Now", shown uppercase).
    public init(size: Size = .regular) {
        self.size = size
        text = Text("now.marker")
        accessibilityText = Text("now.marker")
    }

    /// A marker with pre-resolved words, for contexts that localise through their own lookup (widgets and Live
    /// Activities resolve strings from the App Group snapshot in the app's language).
    public init(size: Size = .regular, label: String) {
        self.size = size
        text = Text(verbatim: label)
        accessibilityText = Text(verbatim: label)
    }

    public var body: some View {
        text
            .font(size == .small ? .caption.weight(.heavy) : .subheadline.weight(.heavy))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(Color.onHighlighter)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size == .small ? 6 : 9)
            .padding(.vertical, size == .small ? 1 : 3)
            .background(HighlighterStroke().fill(Color.highlighter))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The marker's shape: a band with softly rounded, slightly slanted ends and a faint wave along the edges, like one
/// pass of a chisel-tip highlighter. Fills its rect; usable on its own (e.g. behind a grid cell's time).
public struct HighlighterStroke: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let slant = min(rect.height * 0.25, rect.width * 0.08)
        let wave = rect.height * 0.06
        let cap = min(rect.height * 0.45, rect.width * 0.2)
        var path = Path()
        // Top edge, left to right (starts a little in, the left end leans forward).
        path.move(to: CGPoint(x: rect.minX + slant + cap * 0.3, y: rect.minY + wave))
        path.addCurve(to: CGPoint(x: rect.maxX - cap * 0.3, y: rect.minY),
                      control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY - wave),
                      control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + wave * 2))
        // Right cap.
        path.addCurve(to: CGPoint(x: rect.maxX - slant, y: rect.maxY - wave),
                      control1: CGPoint(x: rect.maxX + cap * 0.2, y: rect.minY + rect.height * 0.2),
                      control2: CGPoint(x: rect.maxX - slant + cap * 0.2, y: rect.maxY - rect.height * 0.15))
        // Bottom edge, right to left.
        path.addCurve(to: CGPoint(x: rect.minX + cap * 0.3, y: rect.maxY),
                      control1: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.maxY + wave),
                      control2: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY - wave * 2))
        // Left cap.
        path.addCurve(to: CGPoint(x: rect.minX + slant + cap * 0.3, y: rect.minY + wave),
                      control1: CGPoint(x: rect.minX - cap * 0.2, y: rect.maxY - rect.height * 0.2),
                      control2: CGPoint(x: rect.minX + slant - cap * 0.2, y: rect.minY + rect.height * 0.15))
        path.closeSubpath()
        return path
    }
}
#endif
