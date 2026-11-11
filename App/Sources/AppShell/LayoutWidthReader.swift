// The SwiftUI side of `LayoutWidth` (TimetableUI, Linux-tested; docs/specs/ADAPTIVE_LAYOUT.md). In the app target
// because TimetableUI stays free of `@State` (macro policy, validate_config.py).
// - `.readsLayoutWidth()` on each tab's root measures the available width (minus the leading / trailing safe area, where
//   iPhone Duo puts its bars) and publishes `\.layoutWidth` (with the size classes) and `\.layoutContainerWidth`;
// - `.readableWidth()` on a List / Form / NavigationStack centres its rows in at most `LayoutWidth.readableMaximum`
//   points by adding safe-area padding, so the scroll view (its background and scroll gesture) still spans the whole
//   width. In compact layouts the padding is 0, i.e. iPhones render exactly as before.
// APIs (Apple docs JSON, checked 2026-11-11): View.onGeometryChange(for:of:action:) (iOS 16), GeometryProxy.size /
//   .safeAreaInsets (iOS 13), EnvironmentValues.horizontalSizeClass / .verticalSizeClass (iOS 13),
//   View.safeAreaPadding(_:_:) (iOS 17), EnvironmentKey (no @Entry macro: CLAUDE.md rule 5), DynamicTypeSize.isAccessibilitySize.
import SwiftUI
import TimetableUI

private struct LayoutWidthKey: EnvironmentKey {
    static let defaultValue = LayoutWidth.compact
}

private struct LayoutContainerWidthKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    /// The width class of the enclosing tab (set by `readsLayoutWidth()`; `.compact` elsewhere, e.g. in sheets).
    var layoutWidth: LayoutWidth {
        get { self[LayoutWidthKey.self] }
        set { self[LayoutWidthKey.self] = newValue }
    }

    /// The measured width behind `layoutWidth` (points, without the side safe areas; 0 before the first layout).
    var layoutContainerWidth: Double {
        get { self[LayoutContainerWidthKey.self] }
        set { self[LayoutContainerWidthKey.self] = newValue }
    }
}

extension View {
    /// Measures this view and publishes `\.layoutWidth` to its content.
    func readsLayoutWidth() -> some View { modifier(LayoutWidthReader()) }

    /// Caps the rows of a scrolling list or form at a readable width (no effect in compact layouts).
    func readableWidth() -> some View { modifier(ReadableWidth()) }

    /// The list column of a list + detail split view (`LayoutWidth.listColumn`).
    func listColumnWidth() -> some View {
        let column = LayoutWidth.listColumn
        return navigationSplitViewColumnWidth(min: CGFloat(column.min), ideal: CGFloat(column.ideal), max: CGFloat(column.max))
    }

    /// An inspector column as wide as a split view's list column (`LayoutWidth.listColumn`).
    func sidePanelWidth() -> some View {
        let column = LayoutWidth.listColumn
        return inspectorColumnWidth(min: CGFloat(column.min), ideal: CGFloat(column.ideal), max: CGFloat(column.max))
    }
}

private struct LayoutWidthReader: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width: Double = 0

    func body(content: Content) -> some View {
        content
            .environment(\.layoutWidth, LayoutWidth(width: width, isHorizontallyRegular: horizontal == .regular,
                                                    isVerticallyRegular: vertical == .regular,
                                                    isAccessibilityText: typeSize.isAccessibilitySize))
            .environment(\.layoutContainerWidth, width)
            // The width without the side safe areas (Duo side bars, landscape sensor housings).
            .onGeometryChange(for: Double.self) { proxy in
                Double(max(0, proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing))
            } action: { width = $0 }
    }
}

private struct ReadableWidth: ViewModifier {
    @Environment(\.layoutWidth) private var layoutWidth
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width: Double = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.horizontal, CGFloat(layoutWidth.readableInset(containerWidth: width,
                                                                           isAccessibilitySize: typeSize.isAccessibilitySize)))
            .onGeometryChange(for: Double.self) { proxy in
                Double(max(0, proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing))
            } action: { width = $0 }
    }
}
