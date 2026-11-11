import Testing
@testable import TimetableUI

// Adaptive layout (docs/specs/ADAPTIVE_LAYOUT.md): the breakpoints come from width + size classes only. The widths
// below are examples of real windows (points), not device checks.
@Suite struct LayoutWidthTests {
    private func width(_ w: Double, h: Bool, v: Bool) -> LayoutWidth {
        LayoutWidth(width: w, isHorizontallyRegular: h, isVerticallyRegular: v)
    }

    @Test func phonesStayCompact() {
        #expect(width(440, h: false, v: true) == .compact)    // large iPhone, portrait
        #expect(width(375, h: false, v: true) == .compact)    // small iPhone, portrait
        #expect(width(852, h: false, v: false) == .compact)   // iPhone landscape: compact width + height
        #expect(width(956, h: true, v: false) == .compact)    // Pro Max landscape: regular width, compact height
    }

    @Test func compactSizeClassWinsOverWidth() {
        #expect(width(900, h: false, v: true) == .compact)    // a wide but compact-width window (Duo outer display)
    }

    @Test func regularWindowsByWidth() {
        #expect(width(599, h: true, v: true) == .compact)
        #expect(width(600, h: true, v: true) == .medium)
        #expect(width(699, h: true, v: true) == .medium)
        #expect(width(700, h: true, v: true) == .expanded)
        #expect(width(1376, h: true, v: true) == .expanded)   // 13-inch iPad, landscape
        #expect(LayoutWidth.expanded.showsSplit && !LayoutWidth.medium.showsSplit && !LayoutWidth.compact.showsSplit)
        #expect(LayoutWidth.compact < .medium && LayoutWidth.medium < .expanded)
    }

    @Test func accessibilityTextNeverSplits() {
        #expect(LayoutWidth(width: 1376, isHorizontallyRegular: true, isVerticallyRegular: true, isAccessibilityText: true) == .medium)
        #expect(LayoutWidth(width: 440, isHorizontallyRegular: false, isVerticallyRegular: true, isAccessibilityText: true) == .compact)
    }

    @Test func splitColumnsFitTheExpandedMinimum() {
        // The list column at its minimum plus a 380 pt detail must fit the expanded breakpoint.
        #expect(LayoutWidth.listColumn.min + 380 <= LayoutWidth.expandedMinimum)
        #expect(LayoutWidth.listColumn.min <= LayoutWidth.listColumn.ideal && LayoutWidth.listColumn.ideal <= LayoutWidth.listColumn.max)
    }

    @Test func sidePanelNeedsRoomForTheContent() {
        #expect(LayoutWidth.expanded.fitsSidePanel(containerWidth: 1032))     // 13-inch iPad, portrait
        #expect(!LayoutWidth.expanded.fitsSidePanel(containerWidth: 834))     // 11-inch iPad, portrait: sheet
        #expect(LayoutWidth.expanded.fitsSidePanel(containerWidth: 960) && !LayoutWidth.expanded.fitsSidePanel(containerWidth: 959))
        #expect(!LayoutWidth.medium.fitsSidePanel(containerWidth: 1200))      // never outside the split class
        #expect(!LayoutWidth.compact.fitsSidePanel(containerWidth: 956))      // Pro Max landscape keeps the sheet
    }

    @Test func readableInsetCentresOneColumn() {
        #expect(LayoutWidth.expanded.readableInset(containerWidth: 1032, isAccessibilitySize: false) == 180)
        #expect(LayoutWidth.medium.readableInset(containerWidth: 673, isAccessibilitySize: false) == 0)  // 0.5 rounds down
        #expect(LayoutWidth.medium.readableInset(containerWidth: 650, isAccessibilitySize: false) == 0)
        #expect(LayoutWidth.compact.readableInset(containerWidth: 956, isAccessibilitySize: false) == 0)  // phones unchanged
        #expect(LayoutWidth.expanded.readableInset(containerWidth: 1376, isAccessibilitySize: true) == 0) // AX text: full width
    }
}
