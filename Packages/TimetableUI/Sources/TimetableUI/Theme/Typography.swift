// Type scale and number styling (Phase 4U U1; Opus review §9 "Type", HIG typography.md).
//
// Scale (system SF Pro, Dynamic Type text styles only, never fixed sizes for real data):
//   Large Title  screen titles (navigation bar)
//   TypeScale.currentLesson  = .title2 semibold   the lesson happening now (Today hero, Live Activity)
//   TypeScale.rowTitle       = .headline          row / card titles (subject name, task title in a card)
//   TypeScale.detail         = .body              room, teacher, values people read
//   TypeScale.metadata       = .footnote          labels, secondary metadata
// Nothing below `.footnote` carries real data (caption sizes are for badges whose words are repeated elsewhere and in
// VoiceOver). Times, countdowns and period numbers use SF Pro Rounded with monospaced digits (`.timeStyle()`,
// `.countdownStyle()`): friendly for 7-year-olds, still serious for university, and digits do not jiggle while a
// countdown ticks.
//
// APIs (Apple docs JSON, checked 2026-10-23): View.fontDesign(_:) (iOS 16.1, watchOS 9.1), View.monospacedDigit()
//   (iOS 15, watchOS 8), View.fontWeight(_:) (iOS 16, watchOS 9), Font.weight(_:).
#if canImport(SwiftUI)
import SwiftUI

/// The documented type scale. Use these roles instead of picking text styles per screen.
public enum TypeScale {
    /// The current lesson's title (Today hero, Live Activity lock screen).
    public static let currentLesson: Font = .title2.weight(.semibold)
    /// Row and card titles.
    public static let rowTitle: Font = .headline
    /// Room, teacher and other values people read.
    public static let detail: Font = .body
    /// Labels and secondary metadata. The smallest style for real data.
    public static let metadata: Font = .footnote
}

extension View {
    /// Times and time ranges ("8:55 – 9:40"): SF Pro Rounded, monospaced digits. Sets the design only; pick the size
    /// with `.font(…)` (any text style) so Dynamic Type keeps working.
    public func timeStyle() -> some View {
        fontDesign(.rounded).monospacedDigit()
    }

    /// Countdowns ("25 min left", "in 9 days"), period numbers and other numbers that matter: rounded, monospaced
    /// digits, semibold so the number leads the line.
    public func countdownStyle() -> some View {
        fontDesign(.rounded).monospacedDigit().fontWeight(.semibold)
    }
}
#endif
