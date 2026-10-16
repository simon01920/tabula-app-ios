import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4 C1 (P3-2): the subject-order mutations the subjects list, the accessibility move actions and the subject
// editor apply through `DatabaseMutation` (so every change is stamped by `MutationStamper`).

private let referenceNow = Date(timeIntervalSince1970: 1_791_879_600)
private let english = Locale(identifier: "en_US")

private func apply(_ mutation: DatabaseMutation, to database: TabulaDatabase,
                   clock: inout HybridLogicalClock, at seconds: TimeInterval = 0) throws -> TabulaDatabase {
    clock.receive(database.latestTimestamp, now: referenceNow)
    return try mutation.apply(to: database, clock: &clock, now: referenceNow.addingTimeInterval(seconds))
}

@Suite("Subject order mutations (P3-2)")
struct SubjectOrderMutationTests {
    /// The secondary sample (subjects never ordered: alphabetical) and its timetable.
    private func scenario() -> (TabulaDatabase, Timetable.ID) {
        let scenario = SampleScenarios.secondary()
        return (scenario.database, scenario.timetable.id)
    }

    private func names(_ database: TabulaDatabase, _ timetableID: Timetable.ID) -> [String] {
        TimetableManagement.subjects(of: timetableID, in: database, locale: english).map(\.name)
    }

    @Test func legacySubjectsAreAlphabeticalUntilReordered() {
        let (database, timetableID) = scenario()
        #expect(database.subjects.allSatisfy { $0.sortIndex == nil })
        let shown = names(database, timetableID)
        #expect(shown == shown.sorted { $0.compare($1, options: [.caseInsensitive], range: nil, locale: english) == .orderedAscending })
    }

    @Test func reorderWritesDenseIndicesThroughTheStamper() throws {
        let (database, timetableID) = scenario()
        var clock = HybridLogicalClock(node: 0xC1)
        let ids = TimetableManagement.subjects(of: timetableID, in: database, locale: english).map(\.id)
        var order = ids
        order.swapAt(0, ids.count - 1)
        let mutation = TimetableManagement.reorderSubjectsMutation(order, timetableID: timetableID, in: database, locale: english)
        #expect(mutation.label == "reorder subjects")
        let reordered = try apply(mutation, to: database, clock: &clock)
        #expect(TimetableManagement.subjects(of: timetableID, in: reordered, locale: english).map(\.id) == order)
        let live = reordered.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }
        #expect(live.compactMap(\.sortIndex).sorted() == Array(0..<live.count))
        // Every subject changed (nil → index): each one carries a `sortIndex` field clock = its `updatedAt`.
        #expect(live.allSatisfy { $0.meta.fieldClocks["sortIndex"] == $0.meta.updatedAt })
        #expect(reordered.validate().filter { $0.severity == .error }.isEmpty)

        // The same order again changes nothing (empty batch, database unchanged).
        let again = try apply(TimetableManagement.reorderSubjectsMutation(order, timetableID: timetableID, in: reordered,
                                                                          locale: english), to: reordered, clock: &clock)
        #expect(again == reordered)
    }

    @Test func moveUpAndDownForVoiceOver() throws {
        let (database, timetableID) = scenario()
        var clock = HybridLogicalClock(node: 0xC1)
        let before = TimetableManagement.subjects(of: timetableID, in: database, locale: english).map(\.id)
        let second = before[1]
        let up = try #require(TimetableManagement.moveSubjectMutation(second, by: -1, in: database, locale: english))
        let moved = try apply(up, to: database, clock: &clock)
        let after = TimetableManagement.subjects(of: timetableID, in: moved, locale: english).map(\.id)
        #expect(after[0] == second && after[1] == before[0] && Array(after[2...]) == Array(before[2...]))
        // The first move gave every subject its first index (they had none); moving back swaps two of them.
        let down = try #require(TimetableManagement.moveSubjectMutation(second, by: 1, in: moved, locale: english))
        let back = try apply(down, to: moved, clock: &clock, at: 1)
        #expect(TimetableManagement.subjects(of: timetableID, in: back, locale: english).map(\.id) == before)
        let backIDs = back.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }
        // The second move rewrote exactly the two subjects whose index changed.
        let rewritten = backIDs.filter { subject in moved.subjects.first { $0.id == subject.id } != subject }
        #expect(Set(rewritten.map(\.id)) == [before[0], second])

        #expect(TimetableManagement.moveSubjectMutation(before[0], by: -1, in: database, locale: english) == nil)
        #expect(TimetableManagement.moveSubjectMutation(before.last!, by: 1, in: database, locale: english) == nil)
        #expect(TimetableManagement.moveSubjectMutation(Subject.ID(UUID()), by: 1, in: database, locale: english) == nil)
    }

    @Test func newSubjectsGoToTheEnd() throws {
        let (database, timetableID) = scenario()
        var clock = HybridLogicalClock(node: 0xC1)
        let timetable = try #require(database.timetables.first { $0.id == timetableID })
        let before = names(database, timetableID)
        var draft = SubjectDraft(newIn: timetable, pack: .classic, usedColors: [], id: Subject.ID(UUID()))
        draft.name = "Astronomy"                                     // alphabetically first, but added last
        let subject = try #require(draft.makeSubject())
        let mutation = TimetableManagement.saveSubjectMutation(subject, in: database, locale: english)
        let saved = try apply(mutation, to: database, clock: &clock)
        #expect(names(saved, timetableID) == before + ["Astronomy"])
        let live = saved.subjects.filter { !$0.isDeleted && $0.timetableID == timetableID }
        #expect(live.compactMap(\.sortIndex).sorted() == Array(0..<live.count))  // legacy order written down densely

        // The next one gets max + 1 and nothing else is rewritten.
        var next = SubjectDraft(newIn: timetable, pack: .classic, usedColors: [], id: Subject.ID(UUID()))
        next.name = "Botany"
        let botany = try #require(next.makeSubject())
        let second = try apply(TimetableManagement.saveSubjectMutation(botany, in: saved, locale: english), to: saved,
                               clock: &clock, at: 1)
        #expect(names(second, timetableID) == before + ["Astronomy", "Botany"])
        #expect(second.subjects.first { $0.id == botany.id }?.sortIndex == live.count)
        #expect(second.subjects.filter { $0.id != botany.id } == saved.subjects)
    }

    @Test func editingKeepsTheStoredOrder() throws {
        let (database, timetableID) = scenario()
        var clock = HybridLogicalClock(node: 0xC1)
        let ids = TimetableManagement.subjects(of: timetableID, in: database, locale: english).map(\.id)
        // The editor opens on the last subject (no index yet) …
        let opened = try #require(database.subjects.first { $0.id == ids.last })
        var draft = SubjectDraft(subject: opened)
        // … meanwhile it is moved to the top (e.g. synced from another device).
        let reordered = try apply(TimetableManagement.reorderSubjectsMutation([opened.id], timetableID: timetableID,
                                                                             in: database, locale: english),
                                  to: database, clock: &clock)
        draft.name = "Renamed"
        let edited = try #require(draft.makeSubject())
        #expect(edited.sortIndex == nil)                             // the editor's stale copy
        let saved = try apply(TimetableManagement.saveSubjectMutation(edited, in: reordered, locale: english), to: reordered,
                              clock: &clock, at: 1)
        let stored = try #require(saved.subjects.first { $0.id == opened.id })
        #expect(stored.name == "Renamed" && stored.sortIndex == 0)
        #expect(names(saved, timetableID).first == "Renamed")
        #expect(stored.meta.fieldClocks["sortIndex"] == reordered.subjects.first { $0.id == opened.id }?.meta.fieldClocks["sortIndex"])
    }

    @Test func quickAddAndTaskFilterFollowTheManualOrder() throws {
        let (database, timetableID) = scenario()
        var clock = HybridLogicalClock(node: 0xC1)
        let ids = TimetableManagement.subjects(of: timetableID, in: database, locale: english).map(\.id)
        let order = Array(ids.reversed())
        let reordered = try apply(TimetableManagement.reorderSubjectsMutation(order, timetableID: timetableID, in: database,
                                                                             locale: english), to: database, clock: &clock)
        #expect(QuickAddSubjects.list(reordered, timetableID: timetableID, locale: english).map(\.id) == order)
        let tasks = reordered.tasks.filter { !$0.isDeleted }
        let filter = TaskListModel.filterSubjects(tasks: tasks, subjects: reordered.subjects, timetableOrder: [timetableID],
                                                  locale: english)
        let used = Set(tasks.compactMap(\.subjectID))
        #expect(!filter.isEmpty)
        #expect(filter.map(\.id) == order.filter { used.contains($0) })
    }
}
