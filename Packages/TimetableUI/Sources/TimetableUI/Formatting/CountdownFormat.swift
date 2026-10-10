// Static "m:ss" / "h:mm:ss" text of a remaining time (used when the clock is fixed for screenshots, where the
// system's paused `Text(timerInterval:)` is not reliable). Pure, Linux-tested.
import Foundation

public enum CountdownFormat {
    /// "25:00", "5:07", "1:02:03"; negative values clamp to "0:00".
    public static func string(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }
}
