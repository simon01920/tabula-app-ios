// The "Exercise book" colours the Timetable tab needs (UX plan D1, Opus §9), defined locally by stage U4 because
// stage U1 builds the shared `DesignTokens` in parallel. Exact values from the plan; the contrast of every pair is
// asserted in `TimetableU4Tests`. Pure (ColorValue), so the pairs are Linux-tested.
// adopt U1: replace with DesignTokens.ink / .correction / .highlighter when U1 merges.
import Foundation
import TimetableCore

public enum TimetableMarkerColors {
    /// Ink (app tint): today marker fill. Light #2541B2, dark #8EA2FF, Increase Contrast #1A2F85.
    public static let inkLight = ColorValue(red: 0x25, green: 0x41, blue: 0xB2)
    public static let inkDark = ColorValue(red: 0x8E, green: 0xA2, blue: 0xFF)
    public static let inkIncreasedContrast = ColorValue(red: 0x1A, green: 0x2F, blue: 0x85)
    /// Text on ink: white in light mode, black on the light dark-mode ink.
    public static let onInkLight = ColorValue.white
    public static let onInkDark = ColorValue.black

    /// Correction red: cancelled, and the now line (overdue / destructive elsewhere). Light #C62828, dark #FF6961.
    public static let correctionLight = ColorValue(red: 0xC6, green: 0x28, blue: 0x28)
    public static let correctionDark = ColorValue(red: 0xFF, green: 0x69, blue: 0x61)
    /// Text on correction (the "10:20" now label): white in light mode, black in dark mode.
    public static let onCorrectionLight = ColorValue.white
    public static let onCorrectionDark = ColorValue.black

    /// Highlighter: the "Now" marker only, with black text, in both appearances.
    public static let highlighter = ColorValue(red: 0xFF, green: 0xE0, blue: 0x4A)
    public static let onHighlighter = ColorValue.black

    /// The changed time in the lesson detail ("badge colour", Opus M15): a darker orange than system orange so the text
    /// passes 4.5:1 on the grouped cell background (light #B35C00 on white, dark #FFB340 on #1C1C1E).
    public static let changeTextLight = ColorValue(red: 0xB3, green: 0x5C, blue: 0x00)
    public static let changeTextDark = ColorValue(red: 0xFF, green: 0xB3, blue: 0x40)

    /// System cell backgrounds the pairs are checked against (light white, dark secondarySystemGroupedBackground).
    public static let lightCell = ColorValue.white
    public static let darkCell = ColorValue(red: 0x1C, green: 0x1C, blue: 0x1E)
}
