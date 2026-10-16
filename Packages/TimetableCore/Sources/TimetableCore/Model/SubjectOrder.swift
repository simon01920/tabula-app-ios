import Foundation

/// The canonical display order of subjects and the planning of order changes (P3-2, DOMAIN_MODEL §3.3).
///
/// **Order** (a total order, so every list and picker shows the same sequence for the same data and locale):
/// 1. `sortIndex` ascending; subjects without one (`nil`, never ordered) come after every indexed subject;
/// 2. name, compared case-insensitively with the rules of the given locale;
/// 3. ID (UUID byte order).
///
/// Ties in step 1 are normal for data that was never reordered (all `nil`, so the list is alphabetical as before
/// P3-2) and after concurrent reorders on two devices (the merge picks each subject's index by its own field clock,
/// DOMAIN_MODEL §2.2); steps 2 and 3 then decide deterministically, and the next reorder writes dense indices again.
///
/// Every function is pure and deterministic (the locale is explicit); mutations are applied by the caller through
/// `MutationStamper` (the app's `DatabaseMutation.upsert`), which stamps only the subjects whose index changed.
public enum SubjectOrder {
    /// `true` when `lhs` is shown before `rhs`.
    public static func precedes(_ lhs: Subject, _ rhs: Subject, locale: Locale) -> Bool {
        switch (lhs.sortIndex, rhs.sortIndex) {
        case let (left?, right?) where left != right: return left < right
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        let byName = lhs.name.compare(rhs.name, options: [.caseInsensitive], range: nil, locale: locale)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.id < rhs.id
    }

    /// `subjects` in canonical order (deleted ones are kept; filter first).
    public static func sorted<S: Sequence>(_ subjects: S, locale: Locale) -> [Subject] where S.Element == Subject {
        subjects.sorted { precedes($0, $1, locale: locale) }
    }

    /// Subjects of several timetables: grouped by timetable in `timetableOrder` (timetables not listed follow,
    /// ordered by ID), canonical order within each timetable. Used by lists that mix timetables (the Tasks filter,
    /// a task or exam editor showing a subject of another timetable).
    public static func sorted<S: Sequence>(_ subjects: S, timetableOrder: [Timetable.ID],
                                           locale: Locale) -> [Subject] where S.Element == Subject {
        var rank: [Timetable.ID: Int] = [:]
        for (index, id) in timetableOrder.enumerated() where rank[id] == nil { rank[id] = index }
        return subjects.sorted { lhs, rhs in
            if lhs.timetableID != rhs.timetableID {
                switch (rank[lhs.timetableID], rank[rhs.timetableID]) {
                case let (left?, right?): return left < right
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return lhs.timetableID < rhs.timetableID
                }
            }
            return precedes(lhs, rhs, locale: locale)
        }
    }

    /// The live subjects of `timetableID` in canonical order.
    public static func live(_ database: TabulaDatabase, timetableID: Timetable.ID, locale: Locale) -> [Subject] {
        sorted(database.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }, locale: locale)
    }

    /// Reorder plan: the live subjects of `timetableID` take `order` and get the dense indices `0..<n`.
    ///
    /// IDs in `order` that are not live subjects of the timetable, and repeated IDs, are ignored; live subjects
    /// missing from `order` keep their canonical relative order behind the named ones (a concurrent addition on
    /// another device is not lost). Returns only the subjects whose `sortIndex` changes, in their new order;
    /// unchanged subjects are not rewritten, so their field clocks stay as they are.
    public static func reordered(_ order: [Subject.ID], in database: TabulaDatabase, timetableID: Timetable.ID,
                                 locale: Locale) -> [Subject] {
        let current = live(database, timetableID: timetableID, locale: locale)
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Subject.ID>()
        var arranged: [Subject] = []
        for id in order {
            guard let subject = byID[id], seen.insert(id).inserted else { continue }
            arranged.append(subject)
        }
        arranged += current.filter { !seen.contains($0.id) }
        var changed: [Subject] = []
        for (index, subject) in arranged.enumerated() where subject.sortIndex != index {
            var edited = subject
            edited.sortIndex = index
            changed.append(edited)
        }
        return changed
    }

    /// Where a new subject of `timetableID` goes: always at the end of the list.
    public struct Insertion: Hashable, Sendable {
        /// The new subject's `sortIndex`.
        public var sortIndex: Int
        /// Existing subjects that are renumbered in the same change (only when some live subject had no index:
        /// the current canonical order is written down densely first, so the new subject really is last).
        public var renumbered: [Subject]
    }

    /// The `sortIndex` for a new subject of `timetableID`.
    ///
    /// When every live subject has an index, the new one gets `max + 1` (0 in an empty timetable) and nothing else
    /// changes. When some have none (data from before P3-2, an import of an older share link, or a subject added
    /// by an older app version), the visible order is first written down densely (`reordered` of the canonical
    /// order) and the new subject gets the count — so a new subject is always added at the end.
    public static func insertion(in database: TabulaDatabase, timetableID: Timetable.ID, locale: Locale) -> Insertion {
        let current = live(database, timetableID: timetableID, locale: locale)
        if current.allSatisfy({ $0.sortIndex != nil }) {
            let next = (current.compactMap(\.sortIndex).max() ?? -1) + 1
            return Insertion(sortIndex: next, renumbered: [])
        }
        let renumbered = reordered(current.map(\.id), in: database, timetableID: timetableID, locale: locale)
        return Insertion(sortIndex: current.count, renumbered: renumbered)
    }

    /// `ids` with `id` moved by `offset` positions (negative = towards the start), or `nil` when `id` is not in
    /// `ids`, `offset` is 0 or the move would leave the list (the accessibility "Move up" / "Move down" actions).
    public static func moving(_ id: Subject.ID, by offset: Int, in ids: [Subject.ID]) -> [Subject.ID]? {
        guard offset != 0, let from = ids.firstIndex(of: id) else { return nil }
        let to = from + offset
        guard ids.indices.contains(to) else { return nil }
        var result = ids
        result.remove(at: from)
        result.insert(id, at: to)
        return result
    }

    /// Dense ranks of the indexed subjects among `subjects` (equal `sortIndex` values share a rank; subjects without
    /// an index have none). The share export writes these ranks (`s[i].o`, SHARE_FORMAT §4.3), which keeps the
    /// order, its ties and the payload small, independent of any locale.
    public static func denseRanks<C: Collection>(_ subjects: C) -> [Subject.ID: Int] where C.Element == Subject {
        let values = Set(subjects.compactMap(\.sortIndex)).sorted()
        let rankOfValue = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element, $0.offset) })
        var result: [Subject.ID: Int] = [:]
        for subject in subjects {
            if let value = subject.sortIndex, let rank = rankOfValue[value] { result[subject.id] = rank }
        }
        return result
    }
}

extension Sequence where Element == Subject {
    /// The subjects in canonical display order (`SubjectOrder`).
    public func sortedForDisplay(locale: Locale) -> [Subject] { SubjectOrder.sorted(self, locale: locale) }
}
