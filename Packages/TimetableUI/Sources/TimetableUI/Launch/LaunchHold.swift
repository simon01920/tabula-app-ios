// When the launch mark is shown and how long it is kept (Phase 10 P6). Pure, Linux-tested.
//
// The mark exists only while the store loads. QA (Phase 4U): a fast load showed it for one frame and faded it (a flash),
// so once it is on screen it stays for its one highlighter swipe (0.3 s). Phase 10:
// - a store that is already loaded when the root first renders (the app was launched in the background for a
//   notification action or a refresh, then opened) never shows the mark at all: no hold, no fade;
// - with Reduce Motion there is no swipe to finish, so there is no hold, and the hand-over is a cut, not a fade.
import Foundation

public enum LaunchHold {
    /// The highlighter swipe the mark is kept for once it has appeared.
    public static let swipeDuration: Duration = .milliseconds(300)
    /// The cross-fade from the mark to the app (seconds).
    public static let fadeSeconds: Double = 0.2

    /// How long the mark stays after it appeared (`.zero` = until loading ends).
    public static func holdDuration(reduceMotion: Bool) -> Duration {
        reduceMotion ? .zero : swipeDuration
    }

    /// The cross-fade length, `nil` for none (Reduce Motion).
    public static func fadeDuration(reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : fadeSeconds
    }

    /// Show the mark: while loading, or after loading until the hold of a mark that actually appeared has passed.
    public static func showsLaunch(isLoading: Bool, markAppeared: Bool, holdFinished: Bool) -> Bool {
        isLoading || (markAppeared && !holdFinished)
    }
}
