// Tasks and exams that belong to a lesson occurrence (Phase 3 C1, PHASE3_PLAN §0.10): the "2 tasks" / "Exam" badges
// on lesson tiles, grid cells, time blocks and list rows, the VoiceOver phrases, and the lesson detail's
// "Homework & tasks" list. Pure, Linux-tested; views read a prebuilt `LessonWorkIndex` from the environment.
//
// Matching rule (each task / exam is attached to AT MOST ONE occurrence, so nothing is counted twice):
//   1. A task with `linkedLesson` belongs to exactly that occurrence (recurring lesson ID + date), when that
//      occurrence is among the given lessons. A linked task never matches by subject.
//   2. Otherwise (no link, or the linked occurrence no longer exists that day, e.g. the lesson was deleted) a task
//      with a subject and a known due date belongs to the subject's *anchor* occurrence on the due date: the first
//      (by start time) non-cancelled occurrence of that subject that day, else the first cancelled one.
//      A date + time due still anchors by date (homework due "Mon 8:00" shows on Monday's first lesson of it).
//   3. An exam (subject + date) belongs to the occurrence of its subject that day whose time range contains the exam's
//      start (non-cancelled first), else to the anchor occurrence.
//   Tasks without subject and date, undated / unknown-due tasks and tombstones never match.
//   Badges count OPEN tasks only (a completed task is done; the detail still lists it, struck through). Exams show
//   whether completed or not: the exam is an event on that date (a past exam stays visible on its lesson).
// Only the lessons passed in are considered: pass whole days (every occurrence of each shown date), otherwise the
// anchor of a day may be missed.
import Foundation
import TimetableCore

/// What belongs to one lesson occurrence.
public struct LessonWork: Equatable, Sendable {
    /// Open tasks, in due / priority / title order.
    public var openTaskIDs: [TaskItem.ID] = []
    /// Completed tasks (listed in the lesson detail, never counted in the badge).
    public var completedTaskIDs: [TaskItem.ID] = []
    /// Exams on this occurrence.
    public var examIDs: [Exam.ID] = []

    public init(openTaskIDs: [TaskItem.ID] = [], completedTaskIDs: [TaskItem.ID] = [], examIDs: [Exam.ID] = []) {
        self.openTaskIDs = openTaskIDs
        self.completedTaskIDs = completedTaskIDs
        self.examIDs = examIDs
    }

    /// The badges this occurrence shows (`nil` when there is nothing to show: no empty badge, field-rule spirit).
    public var badges: LessonBadges? {
        let badges = LessonBadges(openTasks: openTaskIDs.count, hasExam: !examIDs.isEmpty)
        return badges.isEmpty ? nil : badges
    }
}

/// The visible badges of an occurrence: "2 tasks" and/or "Exam". Always icon + text (+ a VoiceOver phrase).
public struct LessonBadges: Equatable, Sendable {
    public var openTasks: Int
    public var hasExam: Bool

    public init(openTasks: Int, hasExam: Bool) {
        self.openTasks = openTasks
        self.hasExam = hasExam
    }

    public var isEmpty: Bool { openTasks <= 0 && !hasExam }

    /// SF Symbol of the task badge.
    public static let taskSymbol = "checklist"
    /// SF Symbol of the exam badge.
    public static let examSymbol = "graduationcap.fill"

    /// "2 tasks" (plural variations), `nil` when there are none.
    public func tasksText(renderer: LocalizedTextRenderer) -> String? {
        openTasks > 0 ? renderer.format(key: "lesson.badge.tasks", arguments: [.integer(Int64(openTasks))]) : nil
    }

    /// "Exam", `nil` without an exam.
    public func examText(renderer: LocalizedTextRenderer) -> String? {
        hasExam ? renderer.string(forKey: "lesson.badge.exam") : nil
    }

    /// The VoiceOver phrases appended to the lesson sentence ("2 open tasks", "exam").
    public func accessibilityParts(renderer: LocalizedTextRenderer) -> [String] {
        var parts: [String] = []
        if openTasks > 0 {
            parts.append(renderer.format(key: "a11y.lesson.tasks", arguments: [.integer(Int64(openTasks))]))
        }
        if hasExam { parts.append(renderer.string(forKey: "a11y.lesson.exam")) }
        return parts
    }
}

/// Tasks and exams per occurrence for a set of shown days.
public struct LessonWorkIndex: Equatable, Sendable {
    public private(set) var byOccurrence: [OccurrenceID: LessonWork]

    public init(byOccurrence: [OccurrenceID: LessonWork] = [:]) {
        self.byOccurrence = byOccurrence
    }

    /// No work anywhere (the environment default).
    public static let empty = LessonWorkIndex()

    /// The work of `occurrence` (empty when nothing belongs to it).
    public subscript(occurrence: OccurrenceID) -> LessonWork {
        byOccurrence[occurrence] ?? LessonWork()
    }

    /// The badges of `occurrence`, or `nil`.
    public func badges(for occurrence: OccurrenceID) -> LessonBadges? {
        byOccurrence[occurrence]?.badges
    }

    /// Builds the index for `lessons` (whole days) from the database's tasks and exams (tombstones are ignored).
    public static func make(lessons: [ResolvedLesson], tasks: [TaskItem], exams: [Exam]) -> LessonWorkIndex {
        guard !lessons.isEmpty else { return .empty }
        let ordered = lessons.sorted { ($0.date, $0.startTime, $0.endTime, $0.id) < ($1.date, $1.startTime, $1.endTime, $1.id) }
        var byLink: [LessonLink: OccurrenceID] = [:]
        var anchors: [DaySubject: OccurrenceID] = [:]
        var cancelledAnchors: [DaySubject: OccurrenceID] = [:]
        var bySubjectDay: [DaySubject: [ResolvedLesson]] = [:]
        for lesson in ordered {
            if case .lesson(let id) = lesson.source {
                let link = LessonLink(lessonID: id, date: lesson.date)
                if byLink[link] == nil { byLink[link] = lesson.id }
            }
            let key = DaySubject(date: lesson.date, subjectID: lesson.subject.id)
            bySubjectDay[key, default: []].append(lesson)
            if lesson.status == .cancelled {
                if cancelledAnchors[key] == nil { cancelledAnchors[key] = lesson.id }
            } else if anchors[key] == nil {
                anchors[key] = lesson.id
            }
        }
        func anchor(_ date: LocalDate, _ subjectID: Subject.ID) -> OccurrenceID? {
            let key = DaySubject(date: date, subjectID: subjectID)
            return anchors[key] ?? cancelledAnchors[key]
        }

        var result: [OccurrenceID: LessonWork] = [:]
        let liveTasks = tasks.filter { !$0.isDeleted }.sorted(by: taskOrder)
        for task in liveTasks {
            guard let occurrence = occurrence(of: task, byLink: byLink, anchor: anchor) else { continue }
            if task.isCompleted {
                result[occurrence, default: LessonWork()].completedTaskIDs.append(task.id)
            } else {
                result[occurrence, default: LessonWork()].openTaskIDs.append(task.id)
            }
        }
        let liveExams = exams.filter { !$0.isDeleted }
            .sorted { ($0.date, $0.start ?? .midnight, $0.title, $0.id) < ($1.date, $1.start ?? .midnight, $1.title, $1.id) }
        for exam in liveExams {
            guard let subjectID = exam.subjectID else { continue }
            let key = DaySubject(date: exam.date, subjectID: subjectID)
            var target: OccurrenceID?
            if let start = exam.start, let candidates = bySubjectDay[key] {
                let containing = candidates.filter { $0.startTime <= start && start < $0.endTime }
                target = (containing.first { $0.status != .cancelled } ?? containing.first)?.id
            }
            guard let occurrence = target ?? anchor(exam.date, subjectID) else { continue }
            result[occurrence, default: LessonWork()].examIDs.append(exam.id)
        }
        return LessonWorkIndex(byOccurrence: result)
    }

    /// The occurrence `task` belongs to (rules 1 and 2), if it is among the indexed lessons.
    static func occurrence(of task: TaskItem, byLink: [LessonLink: OccurrenceID],
                           anchor: (LocalDate, Subject.ID) -> OccurrenceID?) -> OccurrenceID? {
        if let link = task.linkedLesson, let linked = byLink[link] { return linked }
        guard let subjectID = task.subjectID, let date = task.due?.date else { return nil }
        return anchor(date, subjectID)
    }

    /// Due date/time ascending (undated last), then priority (highest first), title, id — as the Tasks tab sorts.
    static func taskOrder(_ a: TaskItem, _ b: TaskItem) -> Bool {
        func dueKey(_ task: TaskItem) -> Int {
            guard let due = task.due, let date = due.date else { return Int.max }
            return date.daysSinceEpoch * 1_440 + (due.time?.minuteOfDay ?? 1_439)
        }
        if dueKey(a) != dueKey(b) { return dueKey(a) < dueKey(b) }
        if a.priority != b.priority { return a.priority > b.priority }
        return (a.title, a.id) < (b.title, b.id)
    }

    private struct DaySubject: Hashable {
        let date: LocalDate
        let subjectID: Subject.ID
    }
}

#if canImport(SwiftUI)
import SwiftUI

private struct LessonWorkIndexKey: EnvironmentKey {
    static let defaultValue = LessonWorkIndex.empty
}

extension EnvironmentValues {
    /// Tasks and exams of the lessons on screen (set by Today and the Timetable tab; empty elsewhere).
    public var lessonWork: LessonWorkIndex {
        get { self[LessonWorkIndexKey.self] }
        set { self[LessonWorkIndexKey.self] = newValue }
    }
}
#endif
