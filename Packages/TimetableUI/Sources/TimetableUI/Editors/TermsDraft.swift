// Edit state of the terms & breaks editor. Pure, Linux-tested.
// A term that lessons are limited to (`LessonValidity.terms`) cannot be deleted (the lessons would silently stop
// occurring); breaks and unused terms can.
import Foundation
import TimetableCore

/// The terms & breaks editor's state.
public struct TermsDraft: Equatable, Sendable {
    /// A problem that blocks saving.
    public enum Issue: Equatable, Sendable {
        case emptyName(Term.ID)
        case invalidTermRange(Term.ID)
        case invalidBreakRange(CalendarBreak.ID)
        case emptyBreakName(CalendarBreak.ID)
    }

    public let timetableID: Timetable.ID
    public var terms: [Term]
    public var breaks: [CalendarBreak]
    private let originalTermIDs: Set<Term.ID>
    private let originalBreakIDs: Set<CalendarBreak.ID>

    /// Loads the live terms and the breaks of `timetableID` (global breaks have `timetableID == nil` and are not
    /// edited here).
    public init(timetableID: Timetable.ID, database: TabulaDatabase) {
        self.timetableID = timetableID
        terms = database.terms.filter { !$0.isDeleted && $0.timetableID == timetableID }
            .sorted { ($0.range.start, $0.id) < ($1.range.start, $1.id) }
        breaks = database.breaks.filter { !$0.isDeleted && $0.timetableID == timetableID }
            .sorted { ($0.range.start, $0.id) < ($1.range.start, $1.id) }
        originalTermIDs = Set(terms.map(\.id))
        originalBreakIDs = Set(breaks.map(\.id))
    }

    /// Adds a term starting at `start` (default length 120 days).
    public mutating func addTerm(name: String, start: LocalDate, id: Term.ID) {
        terms.append(Term(id: id, meta: EditorEntities.placeholderMeta, timetableID: timetableID, name: name,
                          range: LocalDateRange(start: start, end: start.adding(days: 120))))
    }

    /// Adds a break starting at `start` (default length 7 days).
    public mutating func addBreak(name: String, kind: BreakKind, start: LocalDate, id: CalendarBreak.ID) {
        breaks.append(CalendarBreak(id: id, meta: EditorEntities.placeholderMeta, timetableID: timetableID, name: name,
                                    range: LocalDateRange(start: start, end: start.adding(days: 6)), kind: kind))
    }

    /// Term IDs that lessons are limited to (not deletable).
    public static func lockedTerms(lessons: [Lesson], timetableID: Timetable.ID) -> Set<Term.ID> {
        var ids = Set<Term.ID>()
        for lesson in lessons where !lesson.isDeleted && lesson.timetableID == timetableID {
            if case .terms(let set) = lesson.validity { ids.formUnion(set) }
        }
        return ids
    }

    /// Problems that block saving.
    public var issues: [Issue] {
        var found: [Issue] = []
        for term in terms {
            if EditorText.trimmedOrNil(term.name) == nil { found.append(.emptyName(term.id)) }
            if term.range.isEmpty { found.append(.invalidTermRange(term.id)) }
        }
        for item in breaks {
            if EditorText.trimmedOrNil(item.name) == nil { found.append(.emptyBreakName(item.id)) }
            if item.range.isEmpty { found.append(.invalidBreakRange(item.id)) }
        }
        return found
    }

    /// `true` when nothing blocks saving.
    public var canSave: Bool { issues.isEmpty }

    /// Mutations that store the edited terms and breaks and delete the removed ones.
    public func mutations() -> [DatabaseMutation] {
        var steps: [DatabaseMutation] = []
        for var term in terms {
            term.name = EditorText.trimmedOrNil(term.name) ?? term.name
            steps.append(.upsert(term))
        }
        for var item in breaks {
            item.name = EditorText.trimmedOrNil(item.name) ?? item.name
            steps.append(.upsert(item))
        }
        let keptTerms = Set(terms.map(\.id))
        for id in originalTermIDs.subtracting(keptTerms).sorted() { steps.append(.delete(id)) }
        let keptBreaks = Set(breaks.map(\.id))
        for id in originalBreakIDs.subtracting(keptBreaks).sorted() { steps.append(.delete(id)) }
        return steps
    }
}
