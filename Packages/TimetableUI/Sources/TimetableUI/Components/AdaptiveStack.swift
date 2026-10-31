// Accessibility layout helpers (Phase 4U U1; Opus review H13, Astra F01 and §4 sizing).
// HIG typography.md › "Consider adjusting your layout at large font sizes": "consider using a stacked layout where
// text appears above secondary items". At accessibility text sizes an icon column steals the width the words need
// ("Elemen-tary" hyphenated, a 170 pt emoji tile), so:
// - `AdaptiveStack` is an HStack normally and a leading-aligned VStack (icon above text) at accessibility sizes.
// - `ScaledIcon` / `.scaledIconFrame(…)` scale a decorative icon with Dynamic Type up to a cap, so it never grows
//   into the text's space. Text is never capped or shrunk (Astra F01: "Do not cap Dynamic Type").
// iOS + watchOS (scripts/watch-typecheck.sh).
// APIs (Apple docs, checked 2026-10-23): AnyLayout (iOS 16, watchOS 9), HStackLayout / VStackLayout (iOS 16,
//   watchOS 9), DynamicTypeSize.isAccessibilitySize (iOS 15, watchOS 8), ScaledMetric(wrappedValue:relativeTo:)
//   (iOS 14, watchOS 7; a property wrapper, not a macro), Environment(\.dynamicTypeSize).
#if canImport(SwiftUI)
import SwiftUI

/// An HStack that becomes a VStack (leading-aligned, icon above text) at accessibility text sizes.
///
///     AdaptiveStack(spacing: 12) {
///         ScaledIcon(.room)
///         VStack(alignment: .leading) { Text(title); Text(detail) }
///     }
public struct AdaptiveStack<Content: View>: View {
    private let horizontalAlignment: VerticalAlignment
    private let stackedAlignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - horizontalAlignment: vertical alignment of the side-by-side layout (default `.center`).
    ///   - stackedAlignment: horizontal alignment of the stacked layout (default `.leading`).
    ///   - spacing: spacing in both layouts (`nil` = system default).
    public init(horizontalAlignment: VerticalAlignment = .center, stackedAlignment: HorizontalAlignment = .leading,
                spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.horizontalAlignment = horizontalAlignment
        self.stackedAlignment = stackedAlignment
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = AdaptiveLayout.isStacked(dynamicTypeSize)
            ? AnyLayout(VStackLayout(alignment: stackedAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: horizontalAlignment, spacing: spacing))
        layout { content }
    }
}

/// A `Label` style for list rows: the platform's label normally, the icon above a full-width title at accessibility
/// text sizes, so a row title never breaks inside a word ("Home-work", "Gymnázi-um"; verification D7).
public struct AdaptiveLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        AdaptiveLabel(configuration: configuration)
    }

    private struct AdaptiveLabel: View {
        let configuration: LabelStyleConfiguration
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if AdaptiveLayout.isStacked(dynamicTypeSize) {
                VStack(alignment: .leading, spacing: 6) {
                    configuration.icon
                    configuration.title
                }
            } else {
                Label(configuration)
            }
        }
    }
}

extension LabelStyle where Self == AdaptiveLabelStyle {
    /// `AdaptiveLabelStyle`: icon above the title at accessibility text sizes.
    public static var adaptive: AdaptiveLabelStyle { AdaptiveLabelStyle() }
}

/// The switch point of the adaptive layouts (one place, so every screen stacks at the same size).
public enum AdaptiveLayout {
    /// `true` at accessibility text sizes (AX1 … AX5).
    public static func isStacked(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }
}

/// A decorative SF Symbol that scales with Dynamic Type up to `maximum` points (its frame), hidden from VoiceOver
/// (the text next to it carries the meaning).
public struct ScaledIcon: View {
    private let symbol: String
    private let maximum: CGFloat
    @ScaledMetric private var side: CGFloat

    /// - Parameters:
    ///   - symbol: the app symbol.
    ///   - base: frame side at the default text size (default 28 pt).
    ///   - maximum: the cap (default 44 pt, the minimum hit size: the icon never outgrows a control).
    ///   - textStyle: the text style it scales with (default `.title3`).
    public init(_ symbol: AppSymbol, base: CGFloat = 28, maximum: CGFloat = 44, relativeTo textStyle: Font.TextStyle = .title3) {
        self.init(systemName: symbol.rawValue, base: base, maximum: maximum, relativeTo: textStyle)
    }

    /// The same for a symbol that is not an `AppSymbol` (e.g. an onboarding choice illustration).
    public init(systemName: String, base: CGFloat = 28, maximum: CGFloat = 44,
                relativeTo textStyle: Font.TextStyle = .title3) {
        symbol = systemName
        self.maximum = maximum
        _side = ScaledMetric(wrappedValue: base, relativeTo: textStyle)
    }

    public var body: some View {
        let length = min(side, maximum)
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .frame(width: length, height: length)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Caps a decorative view (an emoji tile, a badge) at `maximum` points while it scales with Dynamic Type from
    /// `base`. Use for icons beside text; never for the text itself.
    public func scaledIconFrame(base: CGFloat, maximum: CGFloat, relativeTo textStyle: Font.TextStyle = .title3) -> some View {
        modifier(ScaledIconFrame(base: base, maximum: maximum, textStyle: textStyle))
    }
}

private struct ScaledIconFrame: ViewModifier {
    let maximum: CGFloat
    @ScaledMetric private var side: CGFloat

    init(base: CGFloat, maximum: CGFloat, textStyle: Font.TextStyle) {
        self.maximum = maximum
        _side = ScaledMetric(wrappedValue: base, relativeTo: textStyle)
    }

    func body(content: Content) -> some View {
        let length = min(side, maximum)
        content.frame(width: length, height: length)
    }
}
#endif
