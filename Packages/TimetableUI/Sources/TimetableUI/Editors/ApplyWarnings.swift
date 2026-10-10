// What an editor tells the user after a change was applied WITH validation warnings (errors reject the change and are
// shown inline instead). Warnings are deduplicated into lines; the one with a specific consequence gets its own text:
// period-based lessons in a free-form timetable (the resolver cannot place them: `periodNotInSchedule`).
// Pure, Linux-tested.
import Foundation
import TimetableCore

/// One line of the "saved with warnings" alert.
public struct ApplyWarningLine: Equatable, Sendable, Identifiable {
    /// Catalog key of the message.
    public let messageKey: String
    /// Catalog key of the entity type's name, or `nil` when the message names its subject itself.
    public let entityKey: String?
    /// Number of warnings folded into this line.
    public let count: Int
    /// `true` when `messageKey` takes the count as its one `%lld` argument (plural variations).
    public let takesCount: Bool

    public var id: String { messageKey + "|" + (entityKey ?? "") }
}

public enum ApplyWarnings {
    /// Catalog key (plural on `%lld`) for lessons that sit in bell-schedule periods of a free-form timetable.
    public static let periodInFreeFormKey = "editor.warning.periodInFreeForm"

    /// Warning-severity issues folded into lines, in first-seen order. Info issues are not worth an alert.
    public static func lines(from issues: [ValidationIssue]) -> [ApplyWarningLine] {
        var order: [String] = []
        var byID: [String: ApplyWarningLine] = [:]
        for issue in issues where issue.severity == .warning {
            let line: ApplyWarningLine
            if issue.code == .invalidValue, issue.value == "freeForm" {
                line = ApplyWarningLine(messageKey: periodInFreeFormKey, entityKey: nil, count: 1, takesCount: true)
            } else {
                line = ApplyWarningLine(messageKey: issue.code.l10nKey, entityKey: issue.entityType.l10nKey, count: 1,
                                        takesCount: false)
            }
            if let existing = byID[line.id] {
                byID[line.id] = ApplyWarningLine(messageKey: existing.messageKey, entityKey: existing.entityKey,
                                                 count: existing.count + 1, takesCount: existing.takesCount)
            } else {
                byID[line.id] = line
                order.append(line.id)
            }
        }
        return order.compactMap { byID[$0] }
    }
}
