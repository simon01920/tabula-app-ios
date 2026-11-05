import Foundation
import Testing
@testable import TimetableUI

/// Phase 10 WP3: PNG pixel budget (P1/B13), hour height of an exported time-block page (B1, P10-4) and the
/// width fallback of the week time-block view (U9).
@Suite("Export fit and time-block width")
struct ExportFitTests {
    // A4 landscape page in points (grid and week export).
    private let page = (width: 842.0, height: 595.0)

    // MARK: Image scale

    @Test func oneOrTwoPagesKeepScaleThree() {
        #expect(ExportPageFit.imageScale(width: page.width, height: page.height) == 3)
        #expect(ExportPageFit.imageScale(width: page.width, height: page.height * 2) == 3)
    }

    @Test func manyPagesStayWithinThePixelBudget() {
        for count in 1...ExportPlan.maximumImagePages {
            let height = page.height * Double(count)
            let scale = ExportPageFit.imageScale(width: page.width, height: height)
            let pixels = (page.width * scale) * (height * scale)
            #expect(pixels <= ExportPageFit.imagePixelBudget, "\(count) pages: \(pixels) px")
            #expect(scale >= 1.99 && scale <= 3, "\(count) pages: scale \(scale)")
        }
        // 3 pages: √(12 MP / 1.50 MP) = 2.83 → 2.82; 6 pages (old: 27 MP at scale 3) → 1.99.
        #expect(ExportPageFit.imageScale(width: page.width, height: page.height * 3) == 2.82)
        #expect(ExportPageFit.imageScale(width: page.width, height: page.height * 6) == 1.99)
        // Portrait day pages stack to the same area.
        #expect(ExportPageFit.imageScale(width: 595, height: 842 * 6) == 1.99)
    }

    @Test func sideLimitWinsAndEmptySizeKeepsPreferred() {
        #expect(ExportPageFit.imageScale(width: 100, height: 20_000) == 0.81)   // 16 384 / 20 000
        #expect(ExportPageFit.imageScale(width: 0, height: 595) == 3)
        #expect(ExportPageFit.imageScale(width: 842, height: 595, preferred: 2) == 2)
    }

    // MARK: Hour height

    @Test func aDayThatFitsKeepsTheScreenHourHeight() {
        #expect(ExportPageFit.hourHeight(availableHeight: 460, visibleMinutes: 6 * 60, preferred: 72) == 72)
    }

    @Test func aLongerDayShrinksToThePage() {
        // The B1 case: an 8-hour day at 72 pt (576 pt) on the ≈ 460 pt left of a landscape page.
        let eight = ExportPageFit.hourHeight(availableHeight: 460, visibleMinutes: 8 * 60, preferred: 72)
        #expect(eight == 57.5)
        #expect(eight * 8 <= 460)
        #expect(ExportPageFit.hourHeight(availableHeight: 460, visibleMinutes: 16 * 60, preferred: 72) == 28.75)
        // Day page (portrait, detailed 93.6 pt hour): 10 hours on ≈ 740 pt.
        #expect(ExportPageFit.hourHeight(availableHeight: 740, visibleMinutes: 10 * 60, preferred: 93.6) == 74)
    }

    @Test func aVeryLongDayStopsAtTheMinimum() {
        let full = ExportPageFit.hourHeight(availableHeight: 460, visibleMinutes: 24 * 60, preferred: 72)
        #expect(full == ExportPageFit.minimumHourHeight)
        #expect(ExportPageFit.hourHeight(availableHeight: -10, visibleMinutes: 60, preferred: 72) == 20)
        #expect(ExportPageFit.hourHeight(availableHeight: 460, visibleMinutes: 0, preferred: 72) == 72)
        #expect(ExportPageFit.hourHeight(availableHeight: 460, visibleMinutes: 24 * 60, preferred: 15) == 15)
    }

    // MARK: Week time-block width (U9)

    @Test func sevenDaysOnA375PointPhone() {
        // 375 pt − 2 × 8 pt padding = 359 pt; gutter 46 pt → 44.7 pt per day.
        #expect(TimeBlockFit.choose(columnCount: 7, maximumLaneCount: 1, availableWidth: 359, gutterWidth: 46) == .blocks)
        #expect(TimeBlockFit.choose(columnCount: 7, maximumLaneCount: 2, availableWidth: 359, gutterWidth: 46) == .fallback)
        // A larger (non-accessibility) text size widens the gutter: 62 pt → 42.4 pt per day.
        #expect(TimeBlockFit.choose(columnCount: 7, maximumLaneCount: 1, availableWidth: 359, gutterWidth: 62) == .fallback)
    }

    @Test func fiveDaysAndTheLargestPhone() {
        #expect(TimeBlockFit.choose(columnCount: 5, maximumLaneCount: 2, availableWidth: 359, gutterWidth: 46) == .blocks)
        #expect(TimeBlockFit.choose(columnCount: 5, maximumLaneCount: 3, availableWidth: 359, gutterWidth: 46) == .fallback)
        // 440 pt Pro Max: 54 pt per day, 27 pt lanes for two overlapping lessons.
        #expect(TimeBlockFit.choose(columnCount: 7, maximumLaneCount: 2, availableWidth: 424, gutterWidth: 46) == .blocks)
    }

    @Test func degenerateInputs() {
        #expect(TimeBlockFit.choose(columnCount: 0, maximumLaneCount: 1, availableWidth: 10, gutterWidth: 46) == .blocks)
        #expect(TimeBlockFit.choose(columnCount: 5, maximumLaneCount: 0, availableWidth: 359, gutterWidth: 46) == .blocks)
        #expect(TimeBlockFit.minimumColumnWidth == GridMode.minimumColumnWidth)
    }
}
