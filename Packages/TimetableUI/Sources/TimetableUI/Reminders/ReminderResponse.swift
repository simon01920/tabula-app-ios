// What to do with a notification response (Phase 3 Stage A, PHASE3_PLAN §0.4): Mark done, Snooze 1 h / Tomorrow
// morning, or a tap that opens the item. Pure decision logic; the app's `UNUserNotificationCenterDelegate` extracts
// the Sendable `DeliveredNotification` and executes the command. Linux-tested.
import Foundation
import TimetableCore

/// The item a notification (or a later deep link) points to.
public enum ItemLink: Hashable, Sendable {
    case task(TaskItem.ID)
    case exam(Exam.ID)
    case lesson(OccurrenceID)
    case packTonight(LocalDate)

    public init(_ source: ReminderSource) {
        switch source {
        case .task(let id): self = .task(id)
        case .exam(let id): self = .exam(id)
        case .lesson(let id): self = .lesson(id)
        case .packTonight(let date): self = .packTonight(date)
        }
    }
}

/// Which button the user pressed (`UNNotificationResponse.actionIdentifier`, mapped by the app).
public enum NotificationResponseAction: Hashable, Sendable {
    /// `UNNotificationDefaultActionIdentifier`: the notification itself was tapped.
    case open
    /// `UNNotificationDismissActionIdentifier` (only with `.customDismissAction`, which we do not set).
    case dismiss
    /// One of our `ReminderAction`s (or an unknown identifier).
    case custom(String)
}

/// What the app should do.
public enum ReminderResponseCommand: Hashable, Sendable {
    /// Complete the task/exam (`DatabaseMutation.completeTask` / `.completeExam`), which triggers a re-plan.
    case markDone(ReminderSource)
    /// Add the snooze request.
    case snooze(DeliveredNotification, ReminderAction)
    /// Open the item (deep link); `nil` = just open the app.
    case open(ItemLink?)
    case none
}

public enum ReminderResponseInterpreter {
    public static func command(for action: NotificationResponseAction, delivered: DeliveredNotification) -> ReminderResponseCommand {
        let source = delivered.source
        switch action {
        case .open:
            return .open(source.map(ItemLink.init))
        case .dismiss:
            return .none
        case .custom(let identifier):
            guard let reminderAction = ReminderAction(rawValue: identifier) else { return .open(source.map(ItemLink.init)) }
            switch reminderAction {
            case .markDone:
                guard let source, source.isCompletable else { return .none }
                return .markDone(source)
            case .snoozeOneHour, .snoozeTomorrow:
                return .snooze(delivered, reminderAction)
            }
        }
    }

    /// The mutation for `.markDone` (completed at `now`; a repeating task gets its successor per the caller rule).
    public static func mutation(for source: ReminderSource, now: Date) -> DatabaseMutation? {
        switch source {
        case .task(let id): return .completeTask(id, at: now)
        case .exam(let id): return .completeExam(id, at: now)
        case .lesson, .packTonight: return nil
        }
    }
}

extension ItemLink: Identifiable {
    /// The link itself (for `sheet(item:)`).
    public var id: ItemLink { self }
}
