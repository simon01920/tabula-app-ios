// A local draft of quiet-hours times (Phase 10 P14). Each settled value of a time picker used to be a separate
// `model.apply`: a save, a reminder re-plan, a widget snapshot and a Live Activity run per wheel stop. The rows now keep
// the edited times here and write once: `commitDelay` after the last change, when the rows disappear (the screen is
// left) or when the scene leaves `active`. Switching quiet hours on or off is written at once. Pure, Linux-tested.
import Foundation
import TimetableCore

public struct QuietHoursDraft: Equatable, Sendable {
    /// How long after the last time change the draft is written.
    public static let commitDelay: Duration = .milliseconds(800)

    /// What to write.
    public enum Commit: Equatable, Sendable {
        case none
        case write(QuietHours?)
    }

    private var hasEdit = false
    private var edited: QuietHours?

    public init() {}

    /// `true` while an edit waits to be written.
    public var isPending: Bool { hasEdit }

    /// What the rows show: the draft while one is pending, else the stored value.
    public func shown(stored: QuietHours?) -> QuietHours? { hasEdit ? edited : stored }

    /// Records a time edit (kept until `take(stored:)`).
    public mutating func edit(_ value: QuietHours?) {
        edited = value
        hasEdit = true
    }

    /// The value to write now (`.none` without an edit or when it equals `stored`); clears the draft.
    public mutating func take(stored: QuietHours?) -> Commit {
        defer {
            hasEdit = false
            edited = nil
        }
        guard hasEdit, edited != stored else { return .none }
        return .write(edited)
    }
}
