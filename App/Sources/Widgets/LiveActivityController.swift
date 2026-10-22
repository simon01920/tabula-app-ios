// Runs the lesson and exam-day Live Activities (Phase 4 Stage B2, PHASE4_PLAN §0.5). The decisions are the pure
// `LiveActivityPlanner` (TimetableUI, Linux-tested); this class only gathers the input, executes the steps with
// ActivityKit and decides WHEN to run.
//
// Triggers (coalesced, debounced like the widget writer; installed by chaining onto `AppModel.onChange`):
//   .loaded       launch (also a background launch: adopts the activities that survived a relaunch via
//                 `Activity<…>.activities`, so nothing is duplicated)
//   .data         every accepted change (lessons, overrides, exams, settings)
//   .environment  scene active (foreground), day change, time-zone / locale / significant time change
//   timer         while the app runs: at the plan's next lesson boundary / window opening / exam start or end
//   enablement    `ActivityAuthorizationInfo().activityEnablementUpdates` (the user switched them off / on in Settings)
//   preferences   the Settings toggles
//   background    `backgroundRefresh()` from the BGAppRefreshTask (TabulaApp): updates / ends only (starting needs the
//                 foreground); `backgroundRefreshHint` lets the reminder coordinator ask for a refresh near the next
//                 boundary while an activity runs.
// Starting / scheduling only happens while the scene is active (`UIApplication.applicationState == .active`); the
// planner records each start in a ledger (UserDefaults) so an activity the user swiped away is not started again the
// same day. A failed request is taken out of the ledger again (the next foreground retries).
//
// Seed / screenshot runs (`AppEnvironment.liveActivities.isLive == false`) never touch ActivityKit: seed data must not
// reach the real Lock Screen.
//
// APIs (Apple docs JSON, checked 2026-10-16, ENVIRONMENT §29): Activity.request(attributes:content:pushType:) (iOS 16.2,
//   foreground only, throws ActivityAuthorizationError e.g. .visibility in the background),
//   Activity.request(attributes:content:pushType:style:alertConfiguration:start:) (iOS 26: "Requests and schedules a
//   Live Activity for a specific date"; the system starts it even if the app is in the background; must alert),
//   ActivityStyle.standard, AlertConfiguration(title:body:sound:) + AlertSound.default, Activity.activities,
//   Activity.id / .attributes / .activityState / .content, ActivityState (.pending iOS 26, .active, .stale, .ended,
//   .dismissed), ActivityContent(state:staleDate:relevanceScore:) (iOS 16.2), Activity.update(_:) and
//   end(_:dismissalPolicy:) (iOS 16.2, foreground or background), ActivityUIDismissalPolicy (.immediate, .after(_:)),
//   ActivityAuthorizationInfo().areActivitiesEnabled / .activityEnablementUpdates (iOS 16.1).
import ActivityKit
import Foundation
import Observation
import TimetableCore
import TimetableUI
import UIKit

/// The Live Activity dependencies of the environment.
struct LiveActivityDependencies: Sendable {
    let store: any LiveActivityPreferenceStore
    /// `false` for seed / screenshot runs: plan nothing, touch no ActivityKit API.
    let isLive: Bool

    static func live(defaults: UserDefaults) -> LiveActivityDependencies {
        LiveActivityDependencies(store: UserDefaultsLiveActivityPreferenceStore(defaults: defaults), isLive: true)
    }

    static func inMemory() -> LiveActivityDependencies {
        LiveActivityDependencies(store: InMemoryLiveActivityPreferenceStore(), isLive: false)
    }
}

@MainActor
@Observable
final class LiveActivityController {
    /// `ActivityAuthorizationInfo().areActivitiesEnabled` (Settings shows an explanation when `false`).
    private(set) var systemEnabled: Bool
    /// The user's choices (Settings → Live Activities).
    private(set) var preferences: LiveActivityPreferences
    /// Developer diagnostics: the last run.
    private(set) var lastRun = "not run yet"
    /// The plan's next evaluation instant.
    private(set) var nextEvaluation: Date?
    /// At least one lesson / exam activity is pending, active or stale after the last run.
    private(set) var hasRunningActivity = false

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let store: any LiveActivityPreferenceStore
    @ObservationIgnored private let isLive: Bool
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var enablementTask: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(model: AppModel, dependencies: LiveActivityDependencies, debounce: Duration = .milliseconds(600)) {
        self.model = model
        store = dependencies.store
        isLive = dependencies.isLive
        self.debounce = debounce
        preferences = dependencies.store.loadPreferences()
        systemEnabled = dependencies.isLive ? ActivityAuthorizationInfo().areActivitiesEnabled : true
    }

    /// Chains the controller onto `model.onChange` and observes the system permission. Call once.
    static func install(on model: AppModel) -> LiveActivityController {
        let controller = LiveActivityController(model: model, dependencies: model.environment.liveActivities)
        let previous = model.onChange
        model.onChange = { change in
            previous?(change)
            controller.requestRefresh()
        }
        controller.observeEnablement()
        return controller
    }

    /// The Live Activity is a Pro feature (MONETIZATION.md; all-access for now).
    var isEntitled: Bool { model?.entitlements.isAllowed(.liveActivity) ?? false }

    /// A background refresh should come no later than this while an activity runs (lesson boundary, exam start / end).
    var backgroundRefreshHint: Date? { hasRunningActivity ? nextEvaluation : nil }

    // MARK: Preferences

    /// Saves the user's choices and re-plans at once. Switching an activity on again clears "already started today",
    /// so it can start right away.
    func setPreferences(_ new: LiveActivityPreferences) {
        guard new != preferences else { return }
        var ledger = store.loadLedger()
        if new.lessonEnabled, !preferences.lessonEnabled, let today = model?.today { ledger.forgetLessons(from: today) }
        if new.examEnabled, !preferences.examEnabled { ledger.forgetExams() }
        store.saveLedger(ledger)
        store.savePreferences(new)
        preferences = new
        requestRefresh(debounce: .zero)
    }

    // MARK: Triggers

    /// Coalesced, debounced run.
    func requestRefresh(debounce: Duration? = nil) {
        guard isLive else { return }
        pending?.cancel()
        let delay = debounce ?? self.debounce
        pending = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.runCoalesced()
        }
    }

    /// Runs now and returns when the run (and any requested follow-up) finished.
    func refreshNow() async {
        guard isLive else { return }
        pending?.cancel()
        await runCoalesced()
    }

    /// The BGAppRefreshTask part: load the store if the app was launched for it, then update / end.
    func backgroundRefresh() async {
        await model?.load()
        await refreshNow()
    }

    private func observeEnablement() {
        guard isLive else { return }
        let updates = ActivityAuthorizationInfo().activityEnablementUpdates
        enablementTask = Task { [weak self] in
            for await enabled in updates {
                guard let self else { return }
                self.applySystemEnabled(enabled)
                self.requestRefresh(debounce: .zero)
            }
        }
    }

    /// Records the system permission. Turned on again in the Settings app: the activities the system ended may start
    /// again today (they were not swiped away by the user).
    private func applySystemEnabled(_ enabled: Bool) {
        if enabled, !systemEnabled {
            var ledger = store.loadLedger()
            if let today = model?.today { ledger.forgetLessons(from: today) }
            ledger.forgetExams()
            store.saveLedger(ledger)
        }
        systemEnabled = enabled
    }

    private func runCoalesced() async {
        if isRunning {
            rerunRequested = true
            await withCheckedContinuation { idleWaiters.append($0) }
            return
        }
        isRunning = true
        repeat {
            rerunRequested = false
            await runOnce()
        } while rerunRequested
        isRunning = false
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    // MARK: One run

    private func runOnce() async {
        guard isLive, let model, !model.isLoading, model.problem == nil else { return }
        applySystemEnabled(ActivityAuthorizationInfo().areActivitiesEnabled)
        let now = model.now
        let sources = LiveActivitySourceBuilder.make(database: model.database, now: now, context: model.calendarContext,
                                                     locale: model.environment.locale(),
                                                     languageCode: Bundle.main.preferredLocalizations.first)
        let input = LiveActivityPlanInput(
            sources: sources, now: now, canStart: UIApplication.shared.applicationState == .active,
            systemEnabled: systemEnabled, entitled: isEntitled, preferences: preferences, ledger: store.loadLedger(),
            lessons: Self.existing(LessonActivityAttributes.self), exams: Self.existing(ExamActivityAttributes.self))
        let plan = LiveActivityPlanner(renderer: model.renderer).plan(input)
        var ledger = plan.ledger
        var failures: [String] = []
        for step in plan.lessonSteps {
            if let failure = await Self.execute(step) {
                failures.append(failure)
                if case .start(let attributes, _) = step { ledger.lessonDays.removeAll { $0 == attributes.day } }
                if case .schedule(let attributes, _, _, _) = step { ledger.lessonDays.removeAll { $0 == attributes.day } }
            }
        }
        for step in plan.examSteps {
            if let failure = await Self.execute(step) {
                failures.append(failure)
                if case .start(let attributes, _) = step { ledger.examIDs.removeAll { $0 == attributes.examID } }
                if case .schedule(let attributes, _, _, _) = step { ledger.examIDs.removeAll { $0 == attributes.examID } }
            }
        }
        store.saveLedger(ledger)
        nextEvaluation = plan.nextEvaluation
        hasRunningActivity = Self.existing(LessonActivityAttributes.self).contains { $0.status.isRunning }
            || Self.existing(ExamActivityAttributes.self).contains { $0.status.isRunning }
        let summary = "\(plan.lessonSteps.count) lesson + \(plan.examSteps.count) exam steps"
        lastRun = "\(Date().ISO8601Format()): \(summary)" + (failures.isEmpty ? "" : "; failed: \(failures.joined(separator: "; "))")
        scheduleTimer(at: plan.nextEvaluation, now: now)
    }

    /// While the app runs, run again just after the plan's next boundary (live clock only).
    private func scheduleTimer(at date: Date?, now: Date) {
        timer?.cancel()
        guard let model, !model.isClockFixed, let date else { return }
        let delay = date.timeIntervalSince(now) + 1
        guard delay > 0, delay < 24 * 3600 else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.requestRefresh(debounce: .zero)
        }
    }

    // MARK: ActivityKit

    /// The app's current activities of one type, for the planner.
    private static func existing<Attributes: ActivityAttributes & Hashable & Sendable>(
        _ type: Attributes.Type
    ) -> [LiveActivityExisting<Attributes, Attributes.ContentState>] where Attributes.ContentState: Sendable {
        Activity<Attributes>.activities.map { activity in
            LiveActivityExisting(id: activity.id, attributes: activity.attributes, status: status(activity.activityState),
                                 content: LiveActivityContent(state: activity.content.state,
                                                              staleDate: activity.content.staleDate,
                                                              relevanceScore: activity.content.relevanceScore))
        }
    }

    private static func status(_ state: ActivityState) -> LiveActivityStatus {
        switch state {
        case .pending: return .pending
        case .active: return .active
        case .stale: return .stale
        case .ended: return .ended
        case .dismissed: return .dismissed
        @unknown default: return .ended
        }
    }

    /// Executes one step; returns a failure description, or `nil`. Nonisolated: the `Activity` it looks up stays in this
    /// task (Swift 6 region isolation: handing a main-actor `Activity` to its nonisolated async `update` / `end` would
    /// "send" it).
    private nonisolated static func execute<Attributes: ActivityAttributes & Hashable & Sendable>(
        _ step: LiveActivityStep<Attributes, Attributes.ContentState>
    ) async -> String? where Attributes.ContentState: Sendable {
        switch step {
        case let .start(attributes, content):
            do {
                _ = try Activity<Attributes>.request(attributes: attributes, content: activityContent(content), pushType: nil)
                return nil
            } catch {
                return "start: \(error)"
            }
        case let .schedule(attributes, content, date, alert):
            // The rendered texts are passed as interpolated resources (no catalog key "%@" exists, so the system shows
            // the value, as for the AlarmKit titles).
            let configuration = AlertConfiguration(title: LocalizedStringResource("\(alert.title)"),
                                                   body: LocalizedStringResource("\(alert.body)"), sound: .default)
            do {
                _ = try Activity<Attributes>.request(attributes: attributes, content: activityContent(content), pushType: nil,
                                                     style: .standard, alertConfiguration: configuration, start: date)
                return nil
            } catch {
                return "schedule: \(error)"
            }
        case let .update(id, content):
            guard let activity = Activity<Attributes>.activities.first(where: { $0.id == id }) else { return "update: gone" }
            await activity.update(activityContent(content))
            return nil
        case let .end(id, content, dismissal):
            guard let activity = Activity<Attributes>.activities.first(where: { $0.id == id }) else { return nil }
            let policy: ActivityUIDismissalPolicy
            switch dismissal {
            case .immediate: policy = .immediate
            case .after(let date): policy = .after(date)
            }
            await activity.end(content.map(activityContent), dismissalPolicy: policy)
            return nil
        }
    }

    private nonisolated static func activityContent<State: Hashable & Sendable & Codable>(
        _ content: LiveActivityContent<State>
    ) -> ActivityContent<State> {
        ActivityContent(state: content.state, staleDate: content.staleDate, relevanceScore: content.relevanceScore)
    }
}
