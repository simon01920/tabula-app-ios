// Validation policy for `AppModel.apply(_:)` (PHASE2_PLAN §0.4): a mutation that *introduces* an `.error`
// issue is rejected (the database stays as it was); new warnings are accepted and surfaced to the UI.
// Errors that already existed before the mutation never block (otherwise one bad import would make every later
// edit impossible). Pure, Linux-tested.
import Foundation
import TimetableCore

/// The decision for one mutation.
public enum MutationVerdict: Equatable, Sendable {
    /// Accepted; `newWarnings` are warnings that did not exist before (show them, never block).
    case accepted(newWarnings: [ValidationIssue])
    /// Rejected because of errors the mutation would introduce.
    case rejected(newErrors: [ValidationIssue])
}

/// Compares validation results before and after a mutation.
public enum MutationValidation {
    /// Identity of an issue independent of its order in the result list.
    struct IssueKey: Hashable {
        let severity: ValidationIssue.Severity
        let code: ValidationIssue.Code
        let entityType: EntityType
        let entityID: UUID
        let childID: UUID?
        let field: String?
        let relatedID: UUID?

        init(_ issue: ValidationIssue) {
            severity = issue.severity
            code = issue.code
            entityType = issue.entityType
            entityID = issue.entityID
            childID = issue.childID
            field = issue.field
            relatedID = issue.relatedID
        }
    }

    /// The verdict for going from `before` (issues of the stored database) to `after` (issues of the candidate).
    public static func verdict(before: [ValidationIssue], after: [ValidationIssue]) -> MutationVerdict {
        let known = Set(before.map(IssueKey.init))
        let introduced = after.filter { !known.contains(IssueKey($0)) }
        let errors = introduced.filter { $0.severity == .error }
        if !errors.isEmpty { return .rejected(newErrors: errors) }
        return .accepted(newWarnings: introduced.filter { $0.severity == .warning })
    }
}
