// Colour decisions for subject-coloured UI (tiles, grid cells, badges). Pure, Linux-tested; the SwiftUI
// bridge is in ColorValue+SwiftUI.swift.
//
// Rules (PHASE2_PLAN §0.7, REFERENCE_ANALYSIS §3):
// - The tile keeps the user's colour; its text is black or white from `ColorValue.preferredTextColor` (WCAG
//   contrast, ≥ 4.5:1 for every opaque colour). Secondary text uses the same colour (never a lower-contrast tint).
// - A tile whose colour is almost the page background (pastel on white, navy on black) gets a hairline outline so
//   its edge stays visible.
import Foundation
import TimetableCore

/// Light/dark appearance preference mapped from `AppSettings.appearance`.
public enum AppearancePreference: Equatable, Sendable {
    /// Follow the system.
    case system
    case light
    case dark

    /// The preference for a stored appearance (unknown values follow the system).
    public init(_ appearance: Appearance) {
        switch appearance.effective {
        case .light: self = .light
        case .dark: self = .dark
        default: self = .system
        }
    }
}

/// sRGB components in 0…1, as SwiftUI's `Color(.sRGB, red:green:blue:opacity:)` expects.
public struct RGBA: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    /// Components of `color`.
    public init(_ color: ColorValue) {
        red = Double(color.red) / 255
        green = Double(color.green) / 255
        blue = Double(color.blue) / 255
        opacity = Double(color.alpha) / 255
    }
}

/// Colours of one subject-coloured surface.
public struct LessonTileStyle: Equatable, Sendable {
    /// Approximate page backgrounds used for the outline decision (iOS systemBackground).
    public static let lightPageBackground = ColorValue.white
    public static let darkPageBackground = ColorValue.black
    /// Below this tile-vs-page contrast an outline is drawn.
    public static let outlineThreshold = 1.5

    /// The tile fill (the subject colour, made opaque).
    public let background: ColorValue
    /// Text and icon colour on the tile.
    public let foreground: ColorValue
    /// Contrast ratio of `foreground` on `background`.
    public let textContrast: Double
    /// Draw an outline in light mode.
    public let needsOutlineInLight: Bool
    /// Draw an outline in dark mode.
    public let needsOutlineInDark: Bool

    /// The style for a subject colour. A translucent colour is composited over the page background of light mode
    /// first (tiles are opaque, so text contrast is computed on what is actually shown).
    public init(color: ColorValue) {
        let opaque = color.composited(over: Self.lightPageBackground)
        background = opaque
        foreground = opaque.preferredTextColor
        textContrast = foreground.contrastRatio(with: opaque)
        needsOutlineInLight = opaque.contrastRatio(with: Self.lightPageBackground) < Self.outlineThreshold
        needsOutlineInDark = opaque.contrastRatio(with: Self.darkPageBackground) < Self.outlineThreshold
    }

    /// Whether to outline for the given appearance.
    public func needsOutline(isDark: Bool) -> Bool { isDark ? needsOutlineInDark : needsOutlineInLight }
}
