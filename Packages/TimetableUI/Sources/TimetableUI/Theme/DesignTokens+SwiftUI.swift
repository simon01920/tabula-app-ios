// SwiftUI bridge of DesignTokens (Phase 4U U1, D1). iOS + watchOS (watch-typecheck.sh) + macOS (package build).
//
// iOS: every token is a dynamic `UIColor { traits in … }` wrapped in `Color(uiColor:)`, so it resolves per colour
// scheme (`userInterfaceStyle`) and Increase Contrast (`accessibilityContrast == .high`) wherever SwiftUI draws it,
// including widgets and Live Activities. An asset catalog would do the same, but xtool cannot compile `.xcassets`
// (docs/ENVIRONMENT.md, xtool PR #219), so both build paths use this code.
// watchOS: `UIColor(dynamicProvider:)` is not available there (Apple docs list iOS, iPadOS, Mac Catalyst, tvOS,
// visionOS only, checked 2026-10-23); the watch is always dark, so the dark variants are used.
// macOS (only to build the package): the light variants.
//
// APIs (Apple docs JSON, checked 2026-10-23): UIColor.init(dynamicProvider:) (iOS 13), UITraitCollection
//   .userInterfaceStyle / .accessibilityContrast (iOS 13), UIColor.init(red:green:blue:alpha:), Color.init(uiColor:)
//   (iOS 15), UIColor.systemGroupedBackground / .secondarySystemGroupedBackground / .tertiarySystemGroupedBackground
//   (iOS 13), View.background(_:in:), RoundedRectangle(cornerRadius:style:).
#if canImport(SwiftUI)
import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ColorToken {
    /// The token as a SwiftUI colour that adapts to light / dark and Increase Contrast.
    public var color: Color {
        #if os(iOS)
        let token = self
        return Color(uiColor: UIColor { traits in
            let value = token.resolved(isDark: traits.userInterfaceStyle == .dark,
                                       increasedContrast: traits.accessibilityContrast == .high)
            let rgba = RGBA(value)
            return UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.opacity)
        })
        #elseif os(watchOS)
        return Color(dark)
        #else
        return Color(light)
        #endif
    }
}

extension Color {
    /// App tint (`.tint(.ink)` at the app and widget roots). Buttons, links, selection, progress.
    public static let ink = DesignTokens.ink.color
    /// Text / symbols on an ink fill (prominent buttons, selected chips).
    public static let onInk = DesignTokens.onInk.color
    /// Overdue, cancelled, destructive only.
    public static let correction = DesignTokens.correction.color
    /// Text on a correction fill (the now-line time label).
    public static let onCorrection = DesignTokens.onCorrection.color
    /// A changed value (the moved time in the lesson detail).
    public static let changed = DesignTokens.changed.color
    /// The "Now" highlighter fill (NowMarker only).
    public static let highlighter = DesignTokens.highlighter.color
    /// Text on the highlighter (black).
    public static let onHighlighter = DesignTokens.onHighlighter.color
    /// Secondary text that carries data and must reach 4.5:1 on cards.
    public static let pencil = DesignTokens.pencil.color
}

extension ShapeStyle where Self == Color {
    /// `.foregroundStyle(.ink)`.
    public static var ink: Color { Color.ink }
    /// `.foregroundStyle(.onInk)`.
    public static var onInk: Color { Color.onInk }
    /// `.foregroundStyle(.correction)`.
    public static var correction: Color { Color.correction }
    /// `.background(.highlighter)`.
    public static var highlighter: Color { Color.highlighter }
    /// `.foregroundStyle(.onHighlighter)`.
    public static var onHighlighter: Color { Color.onHighlighter }
    /// `.foregroundStyle(.pencil)`.
    public static var pencil: Color { Color.pencil }
}

extension DesignTokens {
    /// Surface roles: "paper". Pages use the grouped background; content sits on white (light) / dark-grey cards,
    /// never grey cards on white (Opus review M9: grey-on-grey text failed 3.3:1).
    public enum Surface {
        /// The page behind cards (systemGroupedBackground).
        public static var page: Color {
            #if os(iOS)
            Color(uiColor: .systemGroupedBackground)
            #elseif os(watchOS)
            Color.black
            #else
            Color(.sRGB, red: 242 / 255, green: 242 / 255, blue: 247 / 255)
            #endif
        }

        /// A card on the page (secondarySystemGroupedBackground: white in light mode).
        public static var card: Color {
            #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
            #elseif os(watchOS)
            Color(.sRGB, red: 28 / 255, green: 28 / 255, blue: 30 / 255)
            #else
            Color.white
            #endif
        }

        /// A card inside a card (tertiarySystemGroupedBackground).
        public static var nestedCard: Color {
            #if os(iOS)
            Color(uiColor: .tertiarySystemGroupedBackground)
            #elseif os(watchOS)
            Color(.sRGB, red: 44 / 255, green: 44 / 255, blue: 46 / 255)
            #else
            Color(.sRGB, red: 242 / 255, green: 242 / 255, blue: 247 / 255)
            #endif
        }

        /// Default corner radius of a card.
        public static let cornerRadius: CGFloat = 16
    }
}

extension View {
    /// Draws the view on a card surface (white in light mode, dark grey in dark mode) with a continuous rounded shape.
    /// Put the card on `DesignTokens.Surface.page` (or in a grouped `List` / `Form`).
    public func cardSurface(cornerRadius: CGFloat = DesignTokens.Surface.cornerRadius) -> some View {
        background(DesignTokens.Surface.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// The page background behind cards, extended under the safe areas.
    public func pageSurface() -> some View {
        background(DesignTokens.Surface.page.ignoresSafeArea())
    }

    /// Label of a prominent (ink-filled) control: `Color.onInk`, so the dark-mode ink fill keeps 8.8:1 instead of the
    /// 2.4:1 of white text. Apply inside the label of `.borderedProminent` buttons and selected chips.
    public func onInkLabel() -> some View {
        foregroundStyle(Color.onInk)
    }
}
#endif
