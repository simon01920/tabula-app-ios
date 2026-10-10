// When to ask iOS for the next background app refresh (Phase 3 Stage A). Pure, Linux-tested.
//
// Apple (BGTaskRequest.earliestBeginDate, checked 2026-10-10): the system guarantees only that the task does not
// start EARLIER than the date; it may run much later or not at all. BGTaskScheduler allows one pending refresh request
// per app (submitting again replaces it). So the request asks for the planner's `nextReplanDate` minus a lead (so a
// late launch still lands before the plan runs out), never sooner than 15 minutes from now, and never later than
// 12 hours from now (the plan's day-relative wording and the lesson window slide daily; frequent foreground use
// re-plans anyway).
import Foundation
import TimetableCore

public enum BackgroundRefreshPolicy {
    /// `BGTaskSchedulerPermittedIdentifiers` entry (Config/App-Info.plist) and SwiftUI `.backgroundTask(.appRefresh(_:))`
    /// identifier. Must stay in sync with the plist (validate_config.py checks it).
    public static let taskIdentifier = "sk.simondev.tabula.reminders.refresh"
    public static let minimumDelay: TimeInterval = 15 * 60
    public static let maximumDelay: TimeInterval = 12 * 60 * 60
    public static let lead: TimeInterval = 60 * 60

    /// `earliestBeginDate` for the next refresh request. `nextReplanDate == nil` (no plan yet) → `now` + 1 h.
    public static func earliestBeginDate(nextReplanDate: Date?, now: Date) -> Date {
        guard let nextReplanDate else { return now.addingTimeInterval(lead) }
        let wanted = nextReplanDate.addingTimeInterval(-lead)
        let lower = now.addingTimeInterval(minimumDelay)
        let upper = now.addingTimeInterval(maximumDelay)
        return min(max(wanted, lower), upper)
    }
}
