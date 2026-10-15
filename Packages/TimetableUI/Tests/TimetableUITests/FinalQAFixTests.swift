import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 3 final QA fixes: Q1 in-context permission offer, Q5 editor save merge, Q6 root presentation policy.

@Suite("Q1: in-context notification permission offer")
struct ReminderPermissionOfferTests {
    @Test func offersOnlyAfterAUserSaveWhileNotDeterminedWithAPlannedReminder() {
        #expect(ReminderPermissionOffer.shouldOffer(authorization: .notDetermined, trigger: .userSave,
                                                    alreadyDeclined: false, plannedRequestCount: 1))
        // Every other trigger: never (launch, foreground, background refresh, actions, timer/other).
        for trigger in ReminderPermissionOffer.Trigger.allCases where trigger != .userSave {
            #expect(!ReminderPermissionOffer.shouldOffer(authorization: .notDetermined, trigger: trigger,
                                                         alreadyDeclined: false, plannedRequestCount: 5), "\(trigger)")
        }
        // Already answered by the system (any state but notDetermined): never.
        for authorization in NotificationAuthorization.allCases where authorization != .notDetermined {
            #expect(!ReminderPermissionOffer.shouldOffer(authorization: authorization, trigger: .userSave,
                                                         alreadyDeclined: false, plannedRequestCount: 5), "\(authorization)")
        }
        // "Not Now" before: never again from this trigger.
        #expect(!ReminderPermissionOffer.shouldOffer(authorization: .notDetermined, trigger: .userSave,
                                                     alreadyDeclined: true, plannedRequestCount: 5))
        // Nothing would be scheduled (no rule, no due date, everything in the past): no offer.
        #expect(!ReminderPermissionOffer.shouldOffer(authorization: .notDetermined, trigger: .userSave,
                                                     alreadyDeclined: false, plannedRequestCount: 0))
    }

    @Test func closingWithoutAnAnswerCountsAsNotNow() {
        #expect(ReminderPermissionOffer.closingRecordsDecline(authorizationAfterClose: .notDetermined))
        #expect(!ReminderPermissionOffer.closingRecordsDecline(authorizationAfterClose: .authorized))
        #expect(!ReminderPermissionOffer.closingRecordsDecline(authorizationAfterClose: .denied))
        #expect(!ReminderPermissionOffer.closingRecordsDecline(authorizationAfterClose: .provisional))
    }

    @Test func anyExplainerClosedWithoutAnAnswerSuppressesTheRootOffer() {
        // Phase 3 polish: fresh install → new task → "Use default" off → the override section's explainer → Not Now →
        // Save. The save's re-plan must not offer the same explainer again.
        let store = InMemoryReminderPermissionOfferStore()
        #expect(ReminderPermissionOffer.recordClose(authorizationAfterClose: .notDetermined, in: store))   // drop armed offer
        #expect(store.isDeclined)
        #expect(!ReminderPermissionOffer.shouldOffer(authorization: .notDetermined, trigger: .userSave,
                                                     alreadyDeclined: store.isDeclined, plannedRequestCount: 3))

        // "Allow" (the system answered either way): nothing recorded, nothing dropped.
        for answered in NotificationAuthorization.allCases where answered != .notDetermined {
            let fresh = InMemoryReminderPermissionOfferStore()
            #expect(!ReminderPermissionOffer.recordClose(authorizationAfterClose: answered, in: fresh), "\(answered)")
            #expect(!fresh.isDeclined, "\(answered)")
        }
    }

    @Test func declineIsRememberedPerInstall() throws {
        let memory = InMemoryReminderPermissionOfferStore()
        #expect(!memory.isDeclined)
        memory.recordDeclined()
        #expect(memory.isDeclined)

        let suite = "q1.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!UserDefaultsReminderPermissionOfferStore(defaults: defaults).isDeclined)
        UserDefaultsReminderPermissionOfferStore(defaults: defaults).recordDeclined()
        #expect(UserDefaultsReminderPermissionOfferStore(defaults: defaults).isDeclined)   // a new instance reads it back
    }

    @MainActor
    @Test func plannedRequestCountIgnoresFailedAdds() async {
        // First run: what the planner wants (alarms not authorised either, so loud alarms become notifications).
        let reference = ReminderEngine(notifications: InMemoryNotificationCenterClient(),
                                       alarms: InMemoryAlarmClient(authorization: .notDetermined),
                                       store: InMemoryReminderStateStore())
        let planned = await reference.run(Fixture.input(Fixture.database()))
        let wanted = planned.plan.notifications.count + planned.plan.alarms.count
        #expect(wanted > 0)
        #expect(planned.plannedRequestCount == wanted)

        // Not determined and every add failing: the applied plan is short, the planned count is not.
        let center = InMemoryNotificationCenterClient(authorization: .notDetermined)
        await center.setFailing(Set(planned.plan.notifications.map(\.id.rawValue)))
        let engine = ReminderEngine(notifications: center, alarms: InMemoryAlarmClient(authorization: .notDetermined),
                                    store: InMemoryReminderStateStore())
        let result = await engine.run(Fixture.input(Fixture.database()))
        #expect(result.plan.notifications.isEmpty)
        #expect(result.plannedRequestCount > 0)
        #expect(ReminderPermissionOffer.shouldOffer(authorization: .notDetermined, trigger: .userSave,
                                                    alreadyDeclined: false, plannedRequestCount: result.plannedRequestCount))

        // No open task or exam: nothing planned, nothing offered.
        let empty = await engine.run(Fixture.input(Fixture.database(tasks: [], exams: [])))
        #expect(empty.plannedRequestCount == 0)
    }

    @Test func healthTextNoLongerPromisesAPromptForRules() {
        let english = EnglishCatalog.lookup("health.notifications.notDetermined")
        #expect(english != "health.notifications.notDetermined")
        #expect(!english.contains("set up a reminder"))
    }
}

@Suite("Q5: editor save merges with the stored entity")
struct EditorSaveMergeTests {
    private let now = Fixture.now
    private let doneAt = Fixture.now.addingTimeInterval(-60)

    private func database(tasks: [TaskItem] = [], exams: [Exam] = []) throws -> TabulaDatabase {
        var clock = HybridLogicalClock(node: 0x05)
        var database = Fixture.database(tasks: [], exams: [])
        for task in tasks { database = try DatabaseMutation.upsert(task).apply(to: database, clock: &clock, now: now) }
        for exam in exams { database = try DatabaseMutation.upsert(exam).apply(to: database, clock: &clock, now: now) }
        return database
    }

    @Test func markDoneWhileEditingIsKeptAndTheSuccessorIsNotDuplicated() throws {
        var clock = HybridLogicalClock(node: 0x15)
        var database = try database(tasks: [Fixture.weekly])
        let opened = try #require(database.tasks.first { $0.id == Fixture.weekly.id })
        var draft = TaskDraft(task: opened, today: Fixture.today)
        draft.title = "Vocabulary, unit 4"

        // "Mark as Done" from a notification while the editor is open.
        database = try DatabaseMutation.completeTask(Fixture.weekly.id, at: doneAt).apply(to: database, clock: &clock, now: now)
        #expect(database.tasks.count == 2)                                   // the task and its successor

        let stored = database.tasks.first { $0.id == Fixture.weekly.id }
        guard case .save(let merged)? = draft.taskForSave(now: now, stored: stored) else {
            Issue.record("expected .save")
            return
        }
        #expect(merged.completedAt == doneAt)                                // not resurrected
        #expect(merged.title == "Vocabulary, unit 4")                        // the edit is kept
        database = try DatabaseMutation.upsert(merged).apply(to: database, clock: &clock, now: now)
        let saved = try #require(database.tasks.first { $0.id == Fixture.weekly.id })
        #expect(saved.isCompleted && saved.title == "Vocabulary, unit 4")
        #expect(database.tasks.filter { !$0.isDeleted && !$0.isCompleted }.count == 1)   // only the successor is open
    }

    @Test func deletedWhileEditingIsNeverResurrected() throws {
        var clock = HybridLogicalClock(node: 0x25)
        var database = try database(tasks: [Fixture.homework], exams: [Fixture.exam])
        let task = try #require(database.tasks.first)
        let exam = try #require(database.exams.first)
        var taskDraft = TaskDraft(task: task, today: Fixture.today)
        taskDraft.title = "Edited"
        var examDraft = ExamDraft(exam: exam)
        examDraft.title = "Edited"
        database = try DatabaseMutation.delete(task.id).apply(to: database, clock: &clock, now: now)
        database = try DatabaseMutation.delete(exam.id).apply(to: database, clock: &clock, now: now)

        #expect(taskDraft.taskForSave(now: now, stored: database.tasks.first) == .deletedMeanwhile)
        #expect(examDraft.examForSave(visibility: .all, stored: database.exams.first) == .deletedMeanwhile)
        // Gone entirely (not even a tombstone) while editing an existing one: also nothing written.
        #expect(taskDraft.taskForSave(now: now, stored: nil) == .deletedMeanwhile)
        #expect(examDraft.examForSave(visibility: .all, stored: nil) == .deletedMeanwhile)
    }

    @Test func newItemsAndUntouchedCompletionSaveAsEdited() throws {
        let id = TaskItem.ID(UUID())
        var draft = TaskDraft(newWithID: id, today: Fixture.today, timetableID: nil)
        draft.title = "New"
        guard case .save(let task)? = draft.taskForSave(now: now, stored: nil) else {
            Issue.record("expected .save")
            return
        }
        #expect(task.id == id && task.completedAt == nil)
        var examDraft = ExamDraft(newOn: Fixture.today, timetableID: nil)
        examDraft.title = "New exam"
        guard case .save(let exam)? = examDraft.examForSave(visibility: .all, stored: nil) else {
            Issue.record("expected .save")
            return
        }
        #expect(exam.completedAt == nil)
        // Invalid draft: nothing to save (the editor keeps Save disabled).
        #expect(TaskDraft(newWithID: id, today: Fixture.today, timetableID: nil).taskForSave(now: now, stored: nil) == nil)
    }

    @Test func examDoneWhileEditingIsKept() throws {
        var clock = HybridLogicalClock(node: 0x35)
        var database = try database(exams: [Fixture.exam])
        let opened = try #require(database.exams.first)
        var draft = ExamDraft(exam: opened)
        draft.room = "101"
        database = try DatabaseMutation.completeExam(opened.id, at: doneAt).apply(to: database, clock: &clock, now: now)
        guard case .save(let merged)? = draft.examForSave(visibility: .all, stored: database.exams.first) else {
            Issue.record("expected .save")
            return
        }
        #expect(merged.completedAt == doneAt && merged.room == "101")
    }

    @Test func completionChangedInTheEditorWins() {
        let opened: Date? = nil
        let stored: Date? = doneAt
        #expect(EditorStoreMerge.completion(edited: nil, opened: opened, stored: stored) == doneAt)   // untouched
        #expect(EditorStoreMerge.completion(edited: now, opened: opened, stored: stored) == now)     // user completed
        #expect(EditorStoreMerge.completion(edited: doneAt, opened: doneAt, stored: nil) == nil)    // reopened elsewhere
        #expect(EditorStoreMerge.completion(edited: nil, opened: now, stored: doneAt) == nil)        // user reopened
    }
}

@Suite("Q6 + Q1: root presentation policy")
struct RootPresentationPolicyTests {
    typealias Policy = RootPresentationPolicy

    @Test func presentsAtOnceWhenNothingIsOnScreen() {
        for request in Policy.Request.allCases {
            #expect(Policy.step(for: request, screen: .init(isAnySheetShown: false), age: 0) == .present)
            // A stale unsaved-work entry must not block when nothing is presented.
            #expect(Policy.step(for: request, screen: .init(isAnySheetShown: false, hasUnsavedWork: true), age: 0) == .present)
        }
    }

    @Test func deepLinkClosesCleanSheetsOnceThenWaits() {
        let open = Policy.Screen(isAnySheetShown: true)
        #expect(Policy.step(for: .deepLink, screen: open, age: 1) == .dismissSheets)
        var asked = open
        asked.dismissRequested = true
        #expect(Policy.step(for: .deepLink, screen: asked, age: 1) == .wait)
        // The shell's own sheet only: replaced at once.
        #expect(Policy.step(for: .deepLink, screen: .init(isAnySheetShown: true, rootSheet: .shown), age: 1) == .present)
    }

    @Test func unsavedWorkIsNeverClosed() {
        let dirty = Policy.Screen(isAnySheetShown: true, hasUnsavedWork: true)
        #expect(Policy.step(for: .deepLink, screen: dirty, age: 1) == .wait)
        #expect(Policy.step(for: .permissionOffer, screen: dirty, age: 1) == .wait)
        let dirtyOverRoot = Policy.Screen(isAnySheetShown: true, rootSheet: .shown, hasUnsavedWork: true)
        #expect(Policy.step(for: .deepLink, screen: dirtyOverRoot, age: 1) == .wait)
    }

    @Test func permissionOfferNeverClosesAnything() {
        #expect(Policy.step(for: .permissionOffer, screen: .init(isAnySheetShown: true), age: 1) == .wait)
        #expect(Policy.step(for: .permissionOffer, screen: .init(isAnySheetShown: true, rootSheet: .shown), age: 1) == .wait)
    }

    @Test func permissionOfferNeverOverwritesARootSheetThatIsSetButNotShownYet() {
        // Phase 3 polish: a deep link's sheet was just set (UIKit shows nothing yet): the offer must wait for it.
        let linkOnItsWay = Policy.Screen(isAnySheetShown: false, rootSheet: .pending(age: 0.1))
        #expect(Policy.step(for: .permissionOffer, screen: linkOnItsWay, age: 1) == .wait)
        // The root sheet is up (even if UIKit briefly reports nothing, e.g. mid-animation): still wait.
        #expect(Policy.step(for: .permissionOffer, screen: .init(isAnySheetShown: false, rootSheet: .shown), age: 1) == .wait)
        // A newer deep link also waits for the sheet on its way up instead of replacing it mid-presentation.
        #expect(Policy.step(for: .deepLink, screen: linkOnItsWay, age: 1) == .wait)
        // Only an empty screen with no root sheet presents the offer.
        #expect(Policy.step(for: .permissionOffer, screen: .init(isAnySheetShown: false, rootSheet: .none), age: 1) == .present)
    }

    @Test func aRootSheetThatNeverAppearedIsClearedSoTheLinkIsRetried() {
        // Phase 3 polish: the root sheet lost a race with a tab sheet opening in the same tick; the binding stays set.
        let stale = Policy.RootSheetState.pending(age: Policy.appearTimeout + 0.5)
        #expect(Policy.rootSheetStep(stale) == .clearStaleRootSheet)
        #expect(Policy.rootSheetStep(.pending(age: Policy.appearTimeout)) == .wait)
        #expect(Policy.rootSheetStep(.pending(age: .infinity)) == .clearStaleRootSheet)
        #expect(Policy.rootSheetStep(.none) == nil)
        #expect(Policy.rootSheetStep(.shown) == nil)
        // A link over an open tab sheet with a stale root sheet: clear it first (the old binding said "shown" and the
        // link took `.present` and was lost)...
        let overTabSheet = Policy.Screen(isAnySheetShown: true, rootSheet: stale)
        #expect(Policy.step(for: .deepLink, screen: overTabSheet, age: 1) == .clearStaleRootSheet)
        #expect(Policy.step(for: .permissionOffer, screen: overTabSheet, age: 1) == .clearStaleRootSheet)
        // ...then, with the root sheet cleared, the tab sheet is asked to close and the link is shown afterwards.
        #expect(Policy.step(for: .deepLink, screen: .init(isAnySheetShown: true, rootSheet: .none), age: 3) == .dismissSheets)
        #expect(Policy.step(for: .deepLink, screen: .init(isAnySheetShown: false, rootSheet: .none), age: 3) == .present)
        // A root sheet that only exists in the binding is not "shown": a link over a tab sheet never takes `.present`.
        #expect(Policy.step(for: .deepLink, screen: .init(isAnySheetShown: true, rootSheet: .pending(age: 0.2)), age: 1)
                == .wait)
        // Expiry still wins (a retried link keeps its original request time).
        #expect(Policy.step(for: .deepLink, screen: overTabSheet, age: Policy.maxAge + 1) == .expire)
    }

    @Test func oldRequestsExpire() {
        for request in Policy.Request.allCases {
            #expect(Policy.step(for: request, screen: .init(isAnySheetShown: false), age: Policy.maxAge + 1) == .expire)
            #expect(Policy.step(for: request, screen: .init(isAnySheetShown: true, hasUnsavedWork: true),
                                age: Policy.maxAge + 1) == .expire)
        }
        #expect(Policy.step(for: .deepLink, screen: .init(isAnySheetShown: false), age: Policy.maxAge) == .present)
    }
}
