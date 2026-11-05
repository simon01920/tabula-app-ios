// Sizing rules of the image and PDF export (Phase 10 WP3). No SwiftUI, so they run in the Linux tests.
// - PNG pixel budget (P1/B13): the stacked pages were rasterised at scale 3 whatever their number (6 landscape A4
//   pages ≈ 2526 × 10710 px ≈ 27 MP ≈ 108 MB RGBA, plus the encoder's copy). The scale now drops so the bitmap stays
//   within `imagePixelBudget`.
// - Hour height of a time-block page (B1, decision P10-4 "fit to page"): the week and day views use a 72 pt
//   (day: 94 pt) hour, so an 8-hour day did not fit the 595 pt landscape page and was clipped. On a page the hour
//   height is the available height ÷ the hours shown, never above the on-screen height (a short day looks as on
//   screen) and never below `minimumHourHeight`.
import Foundation

public enum ExportPageFit {
    // MARK: Image scale

    /// Rasterisation scale of a PNG that fits the budget (crisp on a 3x screen).
    public static let preferredImageScale = 3.0
    /// Largest PNG bitmap, in pixels: 12 MP ≈ 48 MB RGBA. One or two pages keep scale 3; the maximum of
    /// `ExportPlan.maximumImagePages` (6) landscape pages gets scale 2.
    public static let imagePixelBudget = 12_000_000.0
    /// Longest bitmap side (CoreGraphics / UIKit limit without tiling).
    public static let maximumImageSide = 16_384.0
    /// Lowest scale the budget may force (text below 1x is unreadable); `maximumImageSide` still wins.
    public static let minimumImageScale = 1.0

    /// The scale for a bitmap of `width` × `height` points: `preferred`, lowered until width × height × scale²
    /// ≤ `pixelBudget` and the longer side × scale ≤ `maximumSide`; at least `minimumImageScale` unless the side limit needs less.
    /// Rounded down to 1/100 so the pixel count never exceeds the budget through rounding.
    public static func imageScale(width: Double, height: Double, preferred: Double = preferredImageScale,
                                  pixelBudget: Double = imagePixelBudget,
                                  maximumSide: Double = maximumImageSide) -> Double {
        guard width > 0, height > 0 else { return preferred }
        let byBudget = (pixelBudget / (width * height)).squareRoot()
        let bySide = maximumSide / max(width, height)
        let scale = min(bySide, max(minimumImageScale, min(preferred, byBudget)))
        return (scale * 100).rounded(.down) / 100
    }

    // MARK: Hour height

    /// Lowest hour height on a page, in points. Below it a day of more than (available height ÷ 20) hours runs past
    /// the page bottom and its last hours are clipped (a 16-hour day still fits a landscape page).
    public static let minimumHourHeight = 20.0

    /// The hour height that fits `visibleMinutes` into `availableHeight` points: `preferred` when the day already
    /// fits, else the height that fills the page exactly, never below `minimum`.
    public static func hourHeight(availableHeight: Double, visibleMinutes: Int, preferred: Double,
                                  minimum: Double = minimumHourHeight) -> Double {
        guard visibleMinutes > 0 else { return preferred }
        let fit = max(0, availableHeight) / (Double(visibleMinutes) / 60)
        return min(preferred, max(minimum, fit))
    }
}
