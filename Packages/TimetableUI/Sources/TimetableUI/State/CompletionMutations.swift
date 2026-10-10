// Completing tasks and exams (Phase 3 Stage A: the notification "Mark done" action; B1/B2 editors use the same
// mutations so the repeat rule is applied in exactly one place).
//
// DOMAIN_MODEL §3.9 caller rule: when a repeating task is completed, insert `TaskItem.nextOccurrence` only if NO task
// with that id exists, live or tombstoned (a tombstone means the user deleted that next occurrence). The check runs
// inside the mutation step, against the database the mutation is applied to, so it cannot race with other edits.
import Foundation
import TimetableCore

extension DatabaseMutation {
    /// Marks the task completed at `completedAt` and, for a repeating task, inserts its successor (caller rule above).
    /// Already completed → no change (idempotent: a second "Mark done" from another notification is harmless).
    /// Unknown or deleted task → `MutationError.notFound`.
    public static func completeTask(_ id: TaskItem.ID, at completedAt: Date) -> DatabaseMutation {
        DatabaseMutation(label: "complete task") { database, clock, now in
            guard let index = database.tasks.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
                throw MutationError.notFound(.task, id.uuid)
            }
            let old = database.tasks[index]
            guard !old.isCompleted else { return }
            var edited = old
            edited.completedAt = completedAt
            do {
                database.tasks[index] = try MutationStamper.stamp(old: old, new: edited, clock: &clock, now: now)
            } catch {
                throw MutationError.stampingFailed(String(describing: error))
            }
            // `meta` of the successor is replaced by the stamper (creation at the mutation timestamp).
            guard let next = old.nextOccurrence(createdAt: clock.last),
                  !database.tasks.contains(where: { $0.id == next.id }) else { return }
            do {
                database.tasks.append(try MutationStamper.stamp(old: nil, new: next, clock: &clock, now: now))
            } catch {
                throw MutationError.stampingFailed(String(describing: error))
            }
        }
    }

    /// Marks the exam completed at `completedAt` (already completed → no change; unknown/deleted → `notFound`).
    public static func completeExam(_ id: Exam.ID, at completedAt: Date) -> DatabaseMutation {
        DatabaseMutation(label: "complete exam") { database, clock, now in
            guard let index = database.exams.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
                throw MutationError.notFound(.exam, id.uuid)
            }
            let old = database.exams[index]
            guard !old.isCompleted else { return }
            var edited = old
            edited.completedAt = completedAt
            do {
                database.exams[index] = try MutationStamper.stamp(old: old, new: edited, clock: &clock, now: now)
            } catch {
                throw MutationError.stampingFailed(String(describing: error))
            }
        }
    }
}
