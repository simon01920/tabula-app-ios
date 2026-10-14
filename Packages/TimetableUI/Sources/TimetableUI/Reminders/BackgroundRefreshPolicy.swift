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

    /// Distance kept between a re-plan and any planned fire instant.
    public static let fireInstantGap: TimeInterval = 60

    /// The plan's `nextReplanDate`, moved later in 1-minute steps until it is at least `fireInstantGap` away from every
    /// planned alarm and notification fire instant (the planner's next re-plan is often the last fire date itself; a
    /// re-plan at that instant must not race the delivery — QA Stage A finding 1). Used by the in-app timer and the
    /// background refresh request.
    public static func replanDate(for plan: ReminderPlan) -> Date {
        let fires = plan.alarms.map(\.fireDate) + plan.notifications.map(\.fireDate)
        var date = plan.nextReplanDate
        var steps = 0
        while steps <= fires.count, fires.contains(where: { abs($0.timeIntervalSince(date)) < fireInstantGap }) {
            date = date.addingTimeInterval(fireInstantGap)
            steps += 1
        }
        return date
    }

    /// `earliestBeginDate` for the next refresh request. `nextReplanDate == nil` (no plan yet) → `now` + 1 h.
    public static func earliestBeginDate(nextReplanDate: Date?, now: Date) -> Date {
        guard let nextReplanDate else { return now.addingTimeInterval(lead) }
        let wanted = nextReplanDate.addingTimeInterval(-lead)
        let lower = now.addingTimeInterval(minimumDelay)
        let upper = now.addingTimeInterval(maximumDelay)
        return min(max(wanted, lower), upper)
    }
}
