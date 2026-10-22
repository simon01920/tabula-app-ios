// The re-plan coordinator (Phase 3 Stage A, PHASE3_PLAN §0.2): decides WHEN to re-plan, gathers the snapshot from
// `AppModel`, runs `ReminderEngine` (TimetableUI: planner → diff → clients) and asks for the next background refresh.
// It never decides reminder timing itself.
//
// Triggers (all coalesced; data changes debounced by 1 s):
//   launch (store loaded) · scene active / time zone / locale / significant time change (AppModel.onChange(.environment))
//   · any accepted data change (AppModel.onChange(.data)) · a notification action · AlarmKit authorization changes
//   · BGAppRefreshTask (`backgroundRefresh()`) · an in-app timer at the plan's `nextReplanDate` while running.
// Editors need to do nothing: `model.apply(...)` re-plans automatically.
//
// Safety: never plans while the store is loading or failed to load (an unreadable store must not wipe every pending
// reminder); with no database yet (onboarding) it applies an empty plan, which removes only our own `rem.` requests.
// Screenshot / seed mode uses in-memory clients (AppEnvironment), so nothing reaches the real notification centre.
//
// Permission service (for B4's UI): `requestNotificationAuthorization()` / `requestAlarmAuthorization()` only from
// explicit UI (never at launch; the pre-explainer is B4's), `refreshHealth()` → `healthItems`, test notification/alarm.
// In-context offer (final QA fix Q1, PHASE3_PLAN §0.5): a user save of a task or exam (`AppModel.apply(_:origin:
// .userSave)`) arms the offer; the re-plan that covers it asks `ReminderPermissionOffer.shouldOffer` (permission not
// determined, ≥ 1 planned request, not declined before) and, if so, publishes `permissionOffer`. The shell
// (MainTabView) presents the pre-explainer from the root when the screen allows it (RootPresentationPolicy) and calls
// `permissionOfferShown()`; every explainer (root offer or an explicit entry point) reports its close through
// `permissionExplainerClosed()` (Phase 3 polish). Launch, foreground, background refresh, timer and other data-change
// re-plans never offer it.
// APIs: Observation.Observable (app code), NotificationCenter.addObserver(forName:object:queue:using:),
//       ProcessInfo / UIApplication notifications (see ReminderSystemServices.swift), Task.sleep(for:).
import Foundation
import Observation
import TimetableCore
import TimetableUI
import UIKit

/// Why a re-plan was requested (debug screen).
enum ReplanReason: String, Sendable, CaseIterable {
    case launch, environment, dataChange, notificationAction, alarmAuthorization, backgroundRefresh, timer, manual,
         permission
    /// An App Intent completed an item (Phase 4 B3: widget checkbox, loud-alarm "Done").
    case intentAction
}

@MainActor
@Observable
final class ReminderCoordinator {
    // MARK: Observable state (debug screen, health check UI)

    /// The last run's result (`nil` before the first run).
    private(set) var lastResult: ReminderRunResult?
    private(set) var lastReasons: [ReplanReason] = []
    private(set) var lastRunAt: Date?
    /// The last background refresh request (earliest begin date) or the error it produced.
    private(set) var lastBackgroundRequest: String?
    /// The health check snapshot and rows (`refreshHealth()`).
    private(set) var health: ReminderHealthInput?
    private(set) var healthItems: [ReminderHealthItem] = []
    private(set) var isRunning = false
    /// A pending in-context offer of the notification pre-explainer (presented by MainTabView), else `nil`.
    private(set) var permissionOffer: PermissionOfferRequest?

    /// One in-context offer; `requestedAt` (wall clock) lets the shell drop it when it could not be shown for long.
    struct PermissionOfferRequest: Equatable {
        let id = UUID()
        let requestedAt: Date
    }

    // MARK: Dependencies

    @ObservationIgnored let engine: ReminderEngine
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let navigation: AppNavigation
    @ObservationIgnored private let backgroundScheduler: any BackgroundRefreshScheduling
    @ObservationIgnored private let deviceState: @MainActor () -> DeviceReminderState
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var pendingReasons = Set<ReplanReason>()
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let offerStore: any ReminderPermissionOfferStore
    /// A user save happened since the last run started (consumed by the next run).
    @ObservationIgnored private var offerArmed = false
    /// Another feature's wish for an earlier background refresh (Phase 4 B2: the next lesson boundary / exam start
    /// while a Live Activity runs); merged into the request by `BackgroundRefreshPolicy`.
    @ObservationIgnored var additionalRefreshDate: (@MainActor () -> Date?)?

    init(engine: ReminderEngine, model: AppModel, navigation: AppNavigation,
         backgroundScheduler: any BackgroundRefreshScheduling, deviceState: @escaping @MainActor () -> DeviceReminderState,
         offerStore: any ReminderPermissionOfferStore, debounce: Duration = .seconds(1)) {
        self.engine = engine
        self.model = model
        self.navigation = navigation
        self.backgroundScheduler = backgroundScheduler
        self.deviceState = deviceState
        self.offerStore = offerStore
        self.debounce = debounce
    }

    // MARK: Lifecycle

    /// Hooks into the model; call once at launch (before the store loads).
    func attach() {
        model.onChange = { [weak self] change in
            switch change {
            case .loaded: self?.start()
            case .data(let origin):
                if origin == .userSave { self?.offerArmed = true }
                self?.requestReplan(.dataChange)
            case .environment: self?.requestReplan(.environment)
            }
        }
    }

    /// After the store loaded: categories, observers, first plan.
    private func start() {
        guard !started else { return }
        started = true
        let renderer = model.renderer
        let context = model.calendarContext
        Task { await engine.registerCategories(renderer: renderer, context: context) }
        for name in [NSNotification.Name.NSProcessInfoPowerStateDidChange,
                     UIApplication.backgroundRefreshStatusDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refreshHealthIfShown() }
                }
            })
        }
        let updates = engine.alarms.authorizationUpdates()
        let alarms = engine.alarms
        authorizationTask = Task { [weak self] in
            // Baseline first: whether the stream starts with the current value is not documented.
            var previous = await alarms.authorization()
            for await state in updates where state != previous {
                previous = state
                guard let self else { return }
                self.requestReplan(.alarmAuthorization, debounce: .zero)
                await self.refreshHealthIfShown()
            }
        }
        requestReplan(.launch, debounce: .zero)
    }

    // MARK: Triggers

    /// Coalesced, debounced re-plan.
    func requestReplan(_ reason: ReplanReason, debounce: Duration? = nil) {
        pendingReasons.insert(reason)
        debounceTask?.cancel()
        let delay = debounce ?? self.debounce
        debounceTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            // Also for zero-delay requests: a `replanNow` that already covered this reason cancels the task.
            guard !Task.isCancelled else { return }
            await self?.runCoalesced()
        }
    }

    /// Re-plans now and returns when this and any requested follow-up run finished (background refresh, actions).
    func replanNow(_ reason: ReplanReason) async {
        pendingReasons.insert(reason)
        debounceTask?.cancel()
        await runCoalesced()
    }

    /// The `BGAppRefreshTask` handler (SwiftUI `.backgroundTask(.appRefresh(_:))`): load if needed, re-plan, which
    /// also submits the next request.
    func backgroundRefresh() async {
        await model.load()
        await replanNow(.backgroundRefresh)
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

    private func runOnce() async {
        guard !model.isLoading, model.problem == nil else { return }
        let reasons = pendingReasons.sorted { $0.rawValue < $1.rawValue }
        pendingReasons = []
        let offerTrigger: ReminderPermissionOffer.Trigger = offerArmed ? .userSave : Self.offerTrigger(for: reasons)
        offerArmed = false
        let database = model.database ?? DatabaseMutation.emptyBase
        let resolvers = model.database == nil ? [] : model.resolvers.values.sorted { $0.timetable.id < $1.timetable.id }
        let signature = ReminderRenderSignature(language: Bundle.main.preferredLocalizations.first ?? "",
                                                localeIdentifier: model.formatter.locale.identifier,
                                                hourCycle: model.settings.hourCycle.rawValue,
                                                timeZoneIdentifier: model.calendarContext.timeZone.identifier)
        let input = ReminderRunInput(database: database, resolvers: resolvers, context: model.calendarContext,
                                     renderer: model.renderer, now: model.now,
                                     loudAlarmsEntitled: model.entitlements.isAllowed(.loudAlarms),
                                     renderSignature: signature)
        let result = await engine.run(input)
        lastResult = result
        lastReasons = reasons
        lastRunAt = model.now
        let earliest = BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: result.replanDate, now: model.now,
                                                                 additional: additionalRefreshDate?())
        if let error = await backgroundScheduler.submit(earliestBeginDate: earliest) {
            lastBackgroundRequest = "failed: \(error)"
        } else {
            lastBackgroundRequest = earliest.formatted(date: .abbreviated, time: .shortened)
        }
        scheduleTimer(at: result.replanDate)
        if offerTrigger == .userSave { await evaluatePermissionOffer(result) }
        await refreshHealthIfShown()
    }

    /// The offer trigger of a run without a user save (such runs never offer; spelled out for the debug trail).
    private static func offerTrigger(for reasons: [ReplanReason]) -> ReminderPermissionOffer.Trigger {
        if reasons.contains(.backgroundRefresh) { return .backgroundRefresh }
        if reasons.contains(.launch) { return .launch }
        if reasons.contains(.environment) { return .foreground }
        if reasons.contains(.notificationAction) { return .notificationAction }
        return .other
    }

    /// After a user save: publish the in-context offer when `ReminderPermissionOffer` says so.
    private func evaluatePermissionOffer(_ result: ReminderRunResult) async {
        guard permissionOffer == nil else { return }
        let authorization = await engine.notifications.settings().authorization
        guard ReminderPermissionOffer.shouldOffer(authorization: authorization, trigger: .userSave,
                                                  alreadyDeclined: offerStore.isDeclined,
                                                  plannedRequestCount: result.plannedRequestCount) else { return }
        permissionOffer = PermissionOfferRequest(requestedAt: Date())
    }

    /// The shell put the offer on screen (or dropped it because it could not be shown in time).
    func permissionOfferShown() {
        permissionOffer = nil
    }

    /// The shell's offer sheet was set but never appeared (RootPresentationPolicy `.clearStaleRootSheet`): queue it
    /// again with its original request time, unless a newer offer is pending or the user declined meanwhile.
    func restorePermissionOffer(requestedAt: Date) {
        guard permissionOffer == nil, !offerStore.isDeclined else { return }
        permissionOffer = PermissionOfferRequest(requestedAt: requestedAt)
    }

    /// Any pre-explainer closed (`ReminderPermissionSheet.onDisappear`: the root offer, the override section, the
    /// Settings toggles, the rule editor, the health check). Without an answer from the system (Not Now, swipe) it is
    /// remembered and a save never offers it again; an offer armed but not shown yet is dropped, so the same explainer
    /// cannot appear twice in a row (Phase 3 polish). The explicit entry points still show the explainer.
    func permissionExplainerClosed() async {
        let authorization = await engine.notifications.settings().authorization
        if ReminderPermissionOffer.recordClose(authorizationAfterClose: authorization, in: offerStore) {
            permissionOffer = nil
        }
        await refreshHealthIfShown()
    }

    /// Keeps the health rows current once a screen asked for them (`refreshHealth()` was called).
    private func refreshHealthIfShown() async {
        if health != nil { await refreshHealth() }
    }

    /// While the app runs, re-plan at the plan's `nextReplanDate` (live clock only).
    private func scheduleTimer(at date: Date) {
        timerTask?.cancel()
        guard !model.isClockFixed else { return }
        let delay = date.timeIntervalSince(model.now)
        guard delay > 0, delay < 2 * 24 * 3600 else { return }
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.requestReplan(.timer, debounce: .zero)
        }
    }

    // MARK: Notification responses

    /// Executes a notification response (delegate → here). Loads the store first (the action may have launched the app
    /// in the background), and for Mark done saves, then re-plans before returning, because the system may suspend the
    /// app right after the completion handler.
    func handle(_ action: NotificationResponseAction, _ delivered: DeliveredNotification) async {
        await model.load()
        switch ReminderResponseInterpreter.command(for: action, delivered: delivered) {
        case .markDone(let source):
            guard let mutation = ReminderResponseInterpreter.mutation(for: source, now: model.now) else { return }
            if case .applied = model.apply(mutation) {
                await engine.removeDelivered(for: source)   // the item's other reminders in Notification Center
            }
            await model.flush()                              // persist first: the system may suspend us any moment
            await replanNow(.notificationAction)
        case .snooze(let delivered, let reminderAction):
            _ = await engine.snooze(delivered, action: reminderAction, context: model.calendarContext,
                                    renderer: model.renderer, now: model.now)
        case .open(let link):
            navigation.open(link)
        case .none:
            break
        }
    }

    // MARK: Permission service + health check

    /// Re-reads permission and device state and rebuilds `healthItems`.
    func refreshHealth() async {
        let settings = await engine.notifications.settings()
        let alarms = await engine.alarms.authorization()
        let pending = await engine.notifications.pendingRequests().count
        let input = ReminderHealthInput(notifications: settings, alarmAuthorization: alarms, device: deviceState(),
                                        pendingCount: pending, lastPlan: engine.state.plan, database: model.database)
        health = input
        healthItems = ReminderHealthCheck.evaluate(input)
    }

    /// Shows the notification permission prompt (explicit UI only; B4 shows its pre-explainer first), then re-plans.
    @discardableResult
    func requestNotificationAuthorization() async -> NotificationAuthorization {
        let result = await engine.notifications.requestAuthorization()
        await refreshHealth()
        requestReplan(.permission, debounce: .zero)
        return result
    }

    /// Shows the AlarmKit prompt — only when the user enables a Loud-alarm rule (PHASE3_PLAN §0.5), then re-plans.
    @discardableResult
    func requestAlarmAuthorization() async -> AlarmAuthorization {
        let result = await engine.alarms.requestAuthorization()
        await refreshHealth()
        requestReplan(.permission, debounce: .zero)
        return result
    }

    /// Health check "send test notification" (5 s, Standard).
    func sendTestNotification() async -> NotificationAddOutcome {
        await engine.sendTestNotification(renderer: model.renderer, context: model.calendarContext, now: model.now)
    }

    /// Health check "test alarm" (60 s; only when authorised).
    func sendTestAlarm() async -> AlarmScheduleOutcome {
        await engine.sendTestAlarm(renderer: model.renderer, context: model.calendarContext, now: model.now)
    }
}
