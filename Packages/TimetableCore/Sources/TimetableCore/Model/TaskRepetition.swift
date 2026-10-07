import Foundation

// Deterministic repetition of tasks (DOMAIN_MODEL §3.9 "Repetition"). Normative: changing a date rule or the
// ID derivation below changes which task two devices create, so it is a breaking change.

extension RepeatRule {
    /// The due date of the repetition that follows an occurrence due on `date`, or `nil` when the series ends
    /// or cannot continue. Depends only on `date` and the rule — never on when or where the task was completed —
    /// so every device computes the same date.
    ///
    /// - `daily`: `date + interval` days.
    /// - `weekly`: the repeat days are `weekdays`, or `date`'s weekday when empty. Weeks run Monday–Sunday
    ///   (ISO, = RFC 5545 `WKST=MO`; independent of the user's week start). The next date is the first repeat
    ///   day later in `date`'s week; otherwise the first repeat day of the week `interval` weeks later.
    /// - `monthly`: the same day of the month as `date`, `interval` months later; months without that day are
    ///   **skipped** (RFC 5545 `BYMONTHDAY` behaviour): due 31 Jan, monthly → 31 Mar. No clamping, so a series
    ///   never drifts (31 → 30 → 30 …). At most 400 steps are tried (covers 29 Feb with any interval).
    /// - `nil` when: the frequency is unknown (newer app version), `interval < 1`, the result is after `until`
    ///   (inclusive bound), or the result leaves years 1…9999.
    /// `weekdays` is ignored for `daily`/`monthly`.
    public func nextDate(after date: LocalDate) -> LocalDate? {
        guard interval >= 1 else { return nil }
        let next: LocalDate?
        switch frequency {
        case .daily:
            next = date.addingIfValid(days: interval)
        case .weekly:
            next = Self.nextWeekly(after: date, interval: interval, weekdays: weekdays)
        case .monthly:
            next = Self.nextMonthly(after: date, interval: interval)
        default:
            next = nil
        }
        guard let next else { return nil }
        if let until, next > until { return nil }
        return next
    }

    private static func nextWeekly(after date: LocalDate, interval: Int, weekdays: Set<Weekday>) -> LocalDate? {
        let days = weekdays.isEmpty ? [date.weekday] : weekdays.sorted()
        let monday = date.adding(days: -(date.weekday.rawValue - 1))
        if let later = days.first(where: { $0 > date.weekday }) {
            return monday.addingIfValid(days: later.rawValue - 1)
        }
        let (weeks, overflow) = interval.multipliedReportingOverflow(by: 7)
        guard !overflow, let first = days.first, let nextMonday = monday.addingIfValid(days: weeks) else { return nil }
        return nextMonday.addingIfValid(days: first.rawValue - 1)
    }

    private static func nextMonthly(after date: LocalDate, interval: Int) -> LocalDate? {
        let start = date.year * 12 + (date.month - 1)
        for step in 1...400 {
            let (offset, overflow1) = interval.multipliedReportingOverflow(by: step)
            let (index, overflow2) = start.addingReportingOverflow(offset)
            guard !overflow1, !overflow2 else { return nil }
            let year = index / 12, month = index % 12 + 1
            guard LocalDate.validYears.contains(year) else { return nil }
            if date.day <= LocalDate.daysInMonth(year: year, month: month) {
                return LocalDate(year: year, month: month, day: date.day)
            }
        }
        return nil
    }
}

extension TaskItem {
    /// The ID of the task that `nextOccurrence(createdAt:)` creates from the task with ID `id`: a name-based
    /// UUID (version 8, RFC 9562) from the SHA-256 of `"tabula.task.next.v1|<UPPERCASE-UUID>"`.
    ///
    /// Derived from the predecessor alone (a task has at most one successor), so two devices that complete
    /// the same occurrence concurrently — or one device that completes, reopens and completes it again —
    /// create the **same** next task, which the sync merge then collapses by ID.
    public static func nextOccurrenceID(after id: ID) -> ID {
        ID(DerivedUUID.make("tabula.task.next.v1|" + id.uuidString))
    }

    /// The next task of a repeating series, created when this one is completed, or `nil` when there is none
    /// (no `repeatRule`, no or an unknown `due`, the rule's `nextDate(after:)` is `nil`).
    ///
    /// - `id` = `TaskItem.nextOccurrenceID(after: id)`; `meta` = `EntityMeta.created(at: timestamp)`.
    /// - `due`: same kind and wall-clock time, on `repeatRule.nextDate(after: due.date)`.
    /// - Copied: `title`, `kind`, `subjectID`, `timetableID`, `priority`, `notes`, `repeatRule`,
    ///   `reminderOverride`. Reset: `completedAt` (open), `linkedLesson` (it named one occurrence of a lesson),
    ///   `attachments` (empty: files belong to the completed occurrence).
    /// - `subtasks`: the live ones, reopened, same titles and `sortIndex`, IDs derived from the new task ID and
    ///   the old subtask ID (`"tabula.subtask.next.v1|<NEW-TASK>|<OLD-SUBTASK>"`), each with the same `meta`.
    ///
    /// The caller inserts the result **only if no task with that ID exists yet, live or tombstoned**: a
    /// tombstone means the user deleted that next occurrence, and recreating it would resurrect it.
    /// Completion time is irrelevant on purpose (devices complete at different instants).
    public func nextOccurrence(createdAt timestamp: HLCTimestamp) -> TaskItem? {
        guard let rule = repeatRule, let due, let dueDate = due.date, let nextDate = rule.nextDate(after: dueDate) else {
            return nil
        }
        let nextDue: TaskDue
        if let time = due.time { nextDue = .dateTime(nextDate, time) } else { nextDue = .date(nextDate) }
        let nextID = Self.nextOccurrenceID(after: id)
        let meta = EntityMeta.created(at: timestamp)
        let nextSubtasks = subtasks.filter { !$0.meta.isDeleted }.map { subtask in
            Subtask(id: Subtask.ID(DerivedUUID.make("tabula.subtask.next.v1|\(nextID.uuidString)|\(subtask.id.uuidString)")),
                    meta: meta, title: subtask.title, completedAt: nil, sortIndex: subtask.sortIndex)
        }
        return TaskItem(id: nextID, meta: meta, title: title, kind: kind, subjectID: subjectID, timetableID: timetableID,
                        due: nextDue, linkedLesson: nil, priority: priority, notes: notes, repeatRule: repeatRule,
                        completedAt: nil, subtasks: nextSubtasks, attachments: [], reminderOverride: reminderOverride)
    }
}

/// Name-based UUIDs: the first 16 bytes of SHA-256(UTF-8 name) with the RFC 9562 version-8 and variant bits.
/// Deterministic on every platform (pure-Swift SHA-256, no Foundation hashing).
enum DerivedUUID {
    static func make(_ name: String) -> UUID {
        var bytes = Array(TabulaSHA256.digest(Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80 // version 8
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variant 0b10
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
