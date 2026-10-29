// Phase 4U U1 (UX_OVERHAUL_PLAN D1): the "Exercise book" identity tokens. Pure values (Linux-tested); the SwiftUI
// bridge that resolves them per colour scheme and Increase Contrast is in DesignTokens+SwiftUI.swift.
//
// Roles (one meaning each, HIG color.md "Avoid using the same color to mean different things"):
// - ink         app tint: buttons, links, selection, progress. Royal-blue fountain-pen ink.
// - onInk       text/symbols drawn ON an ink fill (prominent buttons, selected chips).
// - correction  overdue, cancelled, destructive ONLY, plus the timetable's now line (iOS Calendar). The teacher's red pen.
// - highlighter the "Now" marker ONLY (NowMarker), always with black text (`onHighlighter`).
// - pencil      secondary text that carries data and must reach 4.5:1 on cards (system `.secondary` is only
//               3.44:1 on white, measured: Opus review §13 "Step 1 of 7" #8A8A8E on #FFFFFF). Plain labels may keep
//               `.secondary`; times and rooms use `.primary` (M9).
// Surfaces stay system grouped backgrounds (`Surface`); the reference values below are only for the contrast tests.
//
// Every token has light / dark / Increase Contrast light / Increase Contrast dark variants (HIG color.md "Make sure all
// your app's colors work well in light, dark, and increased contrast contexts").
import Foundation
import TimetableCore

/// One colour token in the four appearance variants.
public struct ColorToken: Equatable, Sendable {
    public let light: ColorValue
    public let dark: ColorValue
    public let lightIncreasedContrast: ColorValue
    public let darkIncreasedContrast: ColorValue

    public init(light: ColorValue, dark: ColorValue, lightIncreasedContrast: ColorValue? = nil,
                darkIncreasedContrast: ColorValue? = nil) {
        self.light = light
        self.dark = dark
        self.lightIncreasedContrast = lightIncreasedContrast ?? light
        self.darkIncreasedContrast = darkIncreasedContrast ?? dark
    }

    /// The variant for an appearance.
    public func resolved(isDark: Bool, increasedContrast: Bool) -> ColorValue {
        switch (isDark, increasedContrast) {
        case (false, false): return light
        case (true, false): return dark
        case (false, true): return lightIncreasedContrast
        case (true, true): return darkIncreasedContrast
        }
    }

    /// All four variants with their appearance (for exhaustive contrast tests).
    public var variants: [(isDark: Bool, increasedContrast: Bool, color: ColorValue)] {
        [(false, false, light), (true, false, dark), (false, true, lightIncreasedContrast),
         (true, true, darkIncreasedContrast)]
    }
}

/// The app's design tokens (D1). Use these instead of literal colours; never redefine them per screen.
public enum DesignTokens {
    private static func hex(_ string: String) -> ColorValue {
        guard let value = ColorValue(hex: string) else { preconditionFailure("bad token hex \(string)") }
        return value
    }

    /// App tint. 8.5:1 on white, 7.1:1 on #1C1C1E (tested).
    public static let ink = ColorToken(light: hex("#2541B2"), dark: hex("#8EA2FF"),
                                       lightIncreasedContrast: hex("#1A2F85"), darkIncreasedContrast: hex("#B4C2FF"))

    /// Text and symbols on an ink fill: white in light mode (8.5:1), black in dark mode (8.8:1). The dark ink is light
    /// enough for text on dark surfaces, so white on it would be only 2.4:1 (tested): prominent controls set this.
    public static let onInk = ColorToken(light: .white, dark: .black)

    /// Overdue, cancelled, destructive. 5.6:1 on white, 6.0:1 on #1C1C1E.
    /// Rule: only on the `Reference` surfaces (white / grouped-grey page, dark cards). Not as text on system grey
    /// fills (`.quaternary`, systemGray5/6 capsules): it drops to about 4.4:1 there. Use a card surface instead.
    public static let correction = ColorToken(light: hex("#C62828"), dark: hex("#FF6961"),
                                              lightIncreasedContrast: hex("#A11B1B"),
                                              darkIncreasedContrast: hex("#FF8F88"))

    /// Text on a correction fill (the timetable's "10:20" now-line label, U4): white light (5.6:1), black dark.
    public static let onCorrection = ColorToken(light: .white, dark: .black)

    /// A changed value in the lesson detail (the moved time, Opus M15, U4). ≥ 4.5:1 on the white light card and the dark
    /// cards (tested); only 4.2:1 on the light grouped page, so use it on cards only.
    public static let changed = ColorToken(light: hex("#B35C00"), dark: hex("#FFB340"))

    /// The "Now" highlighter fill. The same yellow in every appearance (a real marker); text on it is always black.
    public static let highlighter = ColorToken(light: hex("#FFE04A"), dark: hex("#FFE04A"))

    /// Text on the highlighter: black, 16:1.
    public static let onHighlighter = ColorToken(light: .black, dark: .black)

    /// Secondary text that carries data on cards (≥ 4.5:1 on white and grouped grey, and on dark cards).
    /// Rule: only on the `Reference` surfaces. Not on system grey fills (`.quaternary`, systemGray5/6 capsules): it
    /// drops to about 4.1:1 there. Put the text on a card surface (`cardSurface()`) instead.
    public static let pencil = ColorToken(light: hex("#6C6C70"), dark: hex("#A1A1A6"),
                                          lightIncreasedContrast: hex("#48484A"), darkIncreasedContrast: hex("#C7C7CC"))

    /// Alpha of the ink tint behind the ProBadge word (≈ 12 %; the contrast tests composite the same value).
    public static let proBadgeFillAlpha: UInt8 = 31

    /// Contrast minimums used across the app (WCAG 2.2 AA; HIG accessibility.md › Color and effects).
    public enum Minimum {
        /// Text up to 17 pt.
        public static let text = 4.5
        /// Text ≥ 18 pt, or bold.
        public static let largeText = 3.0
        /// Meaningful non-text indicators (rings, outlines, icons that carry state): WCAG 1.4.11.
        public static let nonText = 3.0
    }

    /// Reference values of the iOS system surfaces and labels the tokens are drawn on (UIKit's documented defaults,
    /// not resolved at run time). Only the contrast tests use them; views use the semantic system colours.
    public enum Reference {
        /// systemBackground light / secondarySystemGroupedBackground light (white card).
        public static let lightCard = ColorValue.white
        /// systemGroupedBackground light (#F2F2F7).
        public static let lightGroupedPage = hex("#F2F2F7")
        /// systemBackground dark / systemGroupedBackground dark.
        public static let darkPage = ColorValue.black
        /// secondarySystemGroupedBackground dark (#1C1C1E).
        public static let darkCard = hex("#1C1C1E")
        /// tertiarySystemGroupedBackground dark (#2C2C2E), a card inside a card.
        public static let darkNestedCard = hex("#2C2C2E")
        /// secondaryLabel light: rgba(60, 60, 67, 0.6).
        public static let lightSecondaryLabel = ColorValue(red: 60, green: 60, blue: 67, alpha: 153)
        /// secondaryLabel dark: rgba(235, 235, 245, 0.6).
        public static let darkSecondaryLabel = ColorValue(red: 235, green: 235, blue: 245, alpha: 153)
        /// tertiaryLabel light: rgba(60, 60, 67, 0.3).
        public static let lightTertiaryLabel = ColorValue(red: 60, green: 60, blue: 67, alpha: 77)

        /// Light surfaces the tokens are used on.
        public static let lightSurfaces = [lightCard, lightGroupedPage]
        /// Dark surfaces the tokens are used on.
        public static let darkSurfaces = [darkPage, darkCard, darkNestedCard]

        /// The surfaces of one appearance.
        public static func surfaces(isDark: Bool) -> [ColorValue] { isDark ? darkSurfaces : lightSurfaces }
    }
}
