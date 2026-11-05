// Width rule of the week time-block view (Phase 10 WP3, U9). Pure, Linux-tested.
// Seven days on a 375 pt phone leave ≈ 44 pt per day; two overlapping lessons then get ≈ 22 pt lanes, too narrow
// for a name. Like `GridMode.choose` for the grid, the view falls back to the alternative layout (the periods × days
// grid, which itself becomes a list when its columns are too narrow) when a day column or an overlap lane would be
// narrower than the minimum.
import Foundation

public enum TimeBlockFit: Equatable, Sendable {
    /// Draw the proportional blocks.
    case blocks
    /// Show the alternative layout.
    case fallback

    /// Narrowest day column (the grid's rule: one 44 pt tap target per day).
    public static let minimumColumnWidth = GridMode.minimumColumnWidth
    /// Narrowest lane of overlapping lessons (the smallest drawn block is 24 × 24 pt).
    public static let minimumLaneWidth = 24.0

    /// `.fallback` when `columnCount` day columns next to the hour gutter are narrower than `minimumColumnWidth`, or
    /// when the most crowded overlap (`maximumLaneCount` lanes) leaves a lane narrower than `minimumLaneWidth`.
    /// `availableWidth` is the view's width without its horizontal padding.
    public static func choose(columnCount: Int, maximumLaneCount: Int, availableWidth: Double,
                              gutterWidth: Double) -> TimeBlockFit {
        guard columnCount > 0 else { return .blocks }
        let column = (availableWidth - gutterWidth) / Double(columnCount)
        guard column >= minimumColumnWidth else { return .fallback }
        return column / Double(max(1, maximumLaneCount)) >= minimumLaneWidth ? .blocks : .fallback
    }
}
