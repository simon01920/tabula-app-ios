import Foundation

/// WCAG 2.x contrast math for choosing legible text on user-chosen colours.
///
/// Relative luminance uses the sRGB transfer function with the 0.04045 threshold (WCAG 2.2 text; the
/// older 0.03928 differs only below 1/255 and never changes a result at 8-bit precision).
public enum Contrast {
    /// Text size classes of WCAG 2.x success criterion 1.4.3.
    public enum TextSize: Sendable {
        /// Body text: AA needs ≥ 4.5:1.
        case normal
        /// ≥ 18 pt regular or ≥ 14 pt bold: AA needs ≥ 3:1.
        case large

        /// Minimum AA contrast ratio for this size.
        public var minimumAARatio: Double {
            switch self {
            case .normal: return 4.5
            case .large: return 3.0
            }
        }
    }

    /// Relative luminance (0 = black … 1 = white) of the colour's RGB channels (alpha ignored).
    public static func relativeLuminance(_ color: ColorValue) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let c = Double(channel) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// Contrast ratio (1…21) between two colours; order does not matter. A translucent `foreground` is
    /// composited over `background` first; `background` is treated as opaque.
    public static func ratio(_ foreground: ColorValue, _ background: ColorValue) -> Double {
        let opaqueBackground = ColorValue(red: background.red, green: background.green, blue: background.blue)
        let a = relativeLuminance(foreground.composited(over: opaqueBackground))
        let b = relativeLuminance(opaqueBackground)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `true` when `foreground` on `background` meets WCAG AA for `size`.
    public static func meetsAA(foreground: ColorValue, background: ColorValue, size: TextSize = .normal) -> Bool {
        ratio(foreground, background) >= size.minimumAARatio
    }

    /// Black or white, whichever contrasts more with `background` (ties → black).
    /// For any opaque background the winner reaches at least ≈ 4.58:1.
    public static func preferredTextColor(on background: ColorValue) -> ColorValue {
        ratio(.black, background) >= ratio(.white, background) ? .black : .white
    }
}

extension ColorValue {
    /// WCAG relative luminance (alpha ignored).
    public var relativeLuminance: Double { Contrast.relativeLuminance(self) }

    /// Contrast ratio with `other`.
    public func contrastRatio(with other: ColorValue) -> Double { Contrast.ratio(self, other) }

    /// Black or white text colour for this background.
    public var preferredTextColor: ColorValue { Contrast.preferredTextColor(on: self) }
}
