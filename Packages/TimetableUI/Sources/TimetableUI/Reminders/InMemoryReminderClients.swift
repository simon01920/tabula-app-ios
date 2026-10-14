// In-memory notification centre and AlarmKit (Phase 3 Stage A). Used by the Linux tests and by the app in
// `-TabulaSeed` screenshot mode, so screenshots never schedule anything on the real device / simulator
// (PHASE3_PLAN Stage A, item 1). They mimic the documented system behaviour the adapter relies on: adding a request
// with an existing id replaces it; removing unknown ids is a no-op; AlarmKit refuses alarms past a (configurable)
// limit with `maximumLimitReached` and refuses everything unless authorised (the adapter never triggers the implicit
// prompt).
import Foundation
import TimetableCore

/// Fake `UNUserNotificationCenter`.
public actor InMemoryNotificationCenterClient: NotificationCenterClient {
    public private(set) var requests: [String: NotificationRequestSpec] = [:]
    /// Pending requests added by "someone else" (other features, the debug probe): only ids and userInfo.
    public private(set) var foreign: [String: PendingNotificationInfo] = [:]
    public private(set) var categories: [NotificationCategorySpec] = []
    public private(set) var removedDelivered: [String] = []
    /// Delivered notifications still shown in Notification Center.
    public private(set) var delivered: [String: PendingNotificationInfo] = [:]
    public private(set) var addCount = 0
    public private(set) var removeCount = 0
    public var snapshot: NotificationSettingsSnapshot
    /// Ids whose `add` fails (to test retry).
    public var failingIDs: Set<String> = []
    /// What `requestAuthorization()` grants.
    public var grantOnRequest: NotificationAuthorization

    public init(authorization: NotificationAuthorization = .authorized, timeSensitive: NotificationSettingState = .enabled,
                grantOnRequest: NotificationAuthorization = .authorized) {
        snapshot = NotificationSettingsSnapshot(authorization: authorization, timeSensitive: timeSensitive,
                                                alert: .enabled, sound: .enabled)
        self.grantOnRequest = grantOnRequest
    }

    public func pendingRequests() -> [PendingNotificationInfo] {
        let own = requests.values.map { PendingNotificationInfo(id: $0.id, nextTriggerDate: $0.fireDate, userInfo: $0.userInfo) }
        return (own + foreign.values).sorted { $0.id < $1.id }
    }

    public func add(_ request: NotificationRequestSpec) -> NotificationAddOutcome {
        if failingIDs.contains(request.id) { return .failed("simulated failure") }
        foreign[request.id] = nil
        requests[request.id] = request
        addCount += 1
        return .added
    }

    public func removePending(ids: [String]) {
        for id in ids {
            requests[id] = nil
            foreign[id] = nil
        }
        removeCount += ids.count
    }

    public func deliveredNotifications() -> [PendingNotificationInfo] { delivered.values.sorted { $0.id < $1.id } }

    public func removeDelivered(ids: [String]) {
        removedDelivered += ids
        for id in ids { delivered[id] = nil }
    }
    public func settings() -> NotificationSettingsSnapshot { snapshot }

    public func requestAuthorization() -> NotificationAuthorization {
        if snapshot.authorization == .notDetermined { snapshot.authorization = grantOnRequest }
        return snapshot.authorization
    }

    public func registerCategories(_ categories: [NotificationCategorySpec]) { self.categories = categories }

    // Test helpers.
    public func seedForeign(_ info: PendingNotificationInfo) { foreign[info.id] = info }
    public func setFailing(_ ids: Set<String>) { failingIDs = ids }
    public func setAuthorization(_ value: NotificationAuthorization) { snapshot.authorization = value }
    /// Simulates delivery: the request leaves the pending list and is shown in Notification Center.
    public func deliver(_ id: String) {
        if let request = requests[id] {
            delivered[id] = PendingNotificationInfo(id: id, userInfo: request.userInfo)
        }
        requests[id] = nil
    }
}

/// Fake AlarmKit.
public actor InMemoryAlarmClient: AlarmClient {
    public private(set) var alarms: [UUID: AlarmSpec] = [:]
    /// Daemon state per alarm (absent = `.scheduled`).
    public private(set) var states: [UUID: ScheduledAlarmInfo.State] = [:]
    /// Alarms scheduled by "someone else" (the debug probe).
    public private(set) var foreign: Set<UUID> = []
    public private(set) var cancelled: [UUID] = []
    public private(set) var scheduleCount = 0
    public var state: AlarmAuthorization
    /// Total alarms (own + foreign) after which `schedule` answers `.limitReached`; `nil` = unlimited.
    public var limit: Int?
    public var grantOnRequest: AlarmAuthorization
    private var continuations: [UUID: AsyncStream<AlarmAuthorization>.Continuation] = [:]

    public init(authorization: AlarmAuthorization = .authorized, limit: Int? = nil,
                grantOnRequest: AlarmAuthorization = .authorized) {
        state = authorization
        self.limit = limit
        self.grantOnRequest = grantOnRequest
    }

    public func authorization() -> AlarmAuthorization { state }

    public func requestAuthorization() -> AlarmAuthorization {
        if state == .notDetermined { setAuthorization(grantOnRequest) }
        return state
    }

    public func scheduledAlarms() -> [ScheduledAlarmInfo]? {
        (Array(alarms.keys) + Array(foreign)).map { ScheduledAlarmInfo(id: $0, state: states[$0] ?? .scheduled) }
    }

    public func schedule(_ alarm: AlarmSpec) -> AlarmScheduleOutcome {
        guard state == .authorized else { return .notAuthorized }
        let isReplacement = alarms[alarm.id] != nil
        if let limit, !isReplacement, alarms.count + foreign.count >= limit { return .limitReached }
        alarms[alarm.id] = alarm
        states[alarm.id] = nil
        scheduleCount += 1
        return .scheduled
    }

    public func cancel(id: UUID) {
        alarms[id] = nil
        states[id] = nil
        foreign.remove(id)
        cancelled.append(id)
    }

    public nonisolated func authorizationUpdates() -> AsyncStream<AlarmAuthorization> {
        AsyncStream { continuation in
            let key = UUID()
            Task { await self.register(key, continuation) }
            continuation.onTermination = { _ in Task { await self.unregister(key) } }
        }
    }

    private func register(_ key: UUID, _ continuation: AsyncStream<AlarmAuthorization>.Continuation) {
        continuations[key] = continuation
        continuation.yield(state)
    }

    private func unregister(_ key: UUID) { continuations[key] = nil }

    // Test helpers.
    public func setAuthorization(_ value: AlarmAuthorization) {
        state = value
        for continuation in continuations.values { continuation.yield(value) }
    }

    public func setLimit(_ value: Int?) { limit = value }
    public func seedForeign(_ id: UUID) { foreign.insert(id) }
    /// Simulates the alarm firing and being stopped (one-shot alarms leave the daemon, ALARMKIT.md F16).
    public func fire(_ id: UUID) {
        alarms[id] = nil
        states[id] = nil
    }

    /// Simulates a daemon state change: `.alerting` (ringing), `.countdown` (snoozed), `.paused`.
    public func setState(_ id: UUID, _ state: ScheduledAlarmInfo.State) { states[id] = state }
}
