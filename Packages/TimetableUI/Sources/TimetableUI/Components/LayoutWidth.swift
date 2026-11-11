// Shared width rules for iPhone, iPhone Duo and iPad (docs/specs/ADAPTIVE_LAYOUT.md). Pure Swift, Linux-tested
// (LayoutWidthTests). Decided from the available container width and the size classes, never from the device model,
// the idiom or the orientation: HIG layout.md › Size classes, "Determine layout based on size classes, not device type
// or orientation"; designing-for-iphone-duo.md › Device poses, "A compact width layout for the outer display and a
// regular width layout for the inner display". The SwiftUI side (environment values + readers) is App/Sources/AppShell/LayoutWidthReader.swift.

/// How much horizontal room a screen has. Content-driven breakpoints:
/// - `expanded`: a list column (≥ 320 pt) fits beside a detail column (≥ 380 pt), so list + detail screens split.
///   Needs regular width AND regular height: a landscape iPhone (compact height) keeps its one-column phone layout.
/// - `medium`: one column with room to spare (narrow iPad windows); long content is capped at a readable width.
/// - `compact`: every iPhone in portrait or landscape, the Duo outer display, Slide Over: today's phone layout, unchanged.
public enum LayoutWidth: Int, Sendable, Comparable, CaseIterable {
    case compact, medium, expanded

    /// List (320) + detail (380): below this two columns would truncate rows (HIG split-views.md › Phone).
    public static let expandedMinimum: Double = 700
    /// Below this a single column is phone-like; caps would only add margins.
    public static let mediumMinimum: Double = 600
    /// Readable line length for one column of rows (UIKit's readable content width at the default text size).
    public static let readableMaximum: Double = 672
    /// The list column of a list + detail split: min / ideal / max points (`navigationSplitViewColumnWidth`).
    public static let listColumn = (min: 320.0, ideal: 360.0, max: 440.0)

    /// - Parameters:
    ///   - width: available width in points, without the leading / trailing safe area (bars on the side on Duo).
    ///   - isHorizontallyRegular / isVerticallyRegular: the environment's size classes.
    ///   - isAccessibilityText: accessibility text sizes (AX1–AX5) need the whole width for one column: a 360 pt list
    ///     column broke words ("Upcom-ing", "Labo-ratórny") on an 11-inch iPad, so they never split.
    public init(width: Double, isHorizontallyRegular: Bool, isVerticallyRegular: Bool, isAccessibilityText: Bool = false) {
        guard isHorizontallyRegular, isVerticallyRegular, width >= Self.mediumMinimum else {
            self = .compact
            return
        }
        self = width >= Self.expandedMinimum && !isAccessibilityText ? .expanded : .medium
    }

    /// Wide content that keeps a side panel beside it (the timetable grid beside a lesson's detail) needs this much.
    public static let wideContentMinimum: Double = 600

    /// `true` when list + detail screens show both side by side.
    public var showsSplit: Bool { self == .expanded }

    /// `true` when a side panel of `listColumn.ideal` points fits beside `wideContentMinimum` points of content
    /// (e.g. 13-inch iPad portrait and any iPad landscape; an 11-inch iPad in portrait keeps the sheet).
    public func fitsSidePanel(containerWidth: Double) -> Bool {
        showsSplit && containerWidth >= Self.wideContentMinimum + Self.listColumn.ideal
    }

    public static func < (lhs: LayoutWidth, rhs: LayoutWidth) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Extra leading and trailing inset that centres one column of at most `readableMaximum` points in a container of
    /// `containerWidth`. Zero in compact layouts (phones are unchanged) and at accessibility text sizes (large text
    /// needs the width, HIG typography.md: text is never capped).
    public func readableInset(containerWidth: Double, isAccessibilitySize: Bool) -> Double {
        guard self != .compact, !isAccessibilitySize, containerWidth > Self.readableMaximum else { return 0 }
        return ((containerWidth - Self.readableMaximum) / 2).rounded(.down)
    }
}
