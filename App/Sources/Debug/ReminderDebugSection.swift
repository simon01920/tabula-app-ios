// Reminders on the developer screen (DEBUG only, Phase 3 Stage A): what the re-plan coordinator did last, the health
// check rows, and buttons for the device checklist (re-plan, permission prompts, test notification / alarm).
// Developer-facing: verbatim strings on purpose (never shipped). Macro-free (property wrappers only, validate.sh).
// APIs: List sections (SwiftUI), ObservableObject/@Published for the local result line.
#if DEBUG
import Combine
import SwiftUI
import TimetableCore
import TimetableUI

@MainActor
final class ReminderDebugState: ObservableObject {
    @Published var message: String?
}

/// A group of `Section`s: place inside a `List`.
struct ReminderDebugSection: View {
    @Environment(ReminderCoordinator.self) private var reminders
    @Environment(AppModel.self) private var model
    @StateObject private var state = ReminderDebugState()

    var body: some View {
        Group {
            Section {
                ProbeRow("Clients", value: model.environment.reminders.isLive ? "live (UNUserNotificationCenter, AlarmKit)"
                                                                               : "in-memory fakes (seed mode)")
                ProbeRow("Last run", value: lastRun)
                if let result = reminders.lastResult {
                    let report = result.report
                    ProbeRow("Plan", value: "\(result.plan.notifications.count) notifications, \(result.plan.alarms.count) alarms, "
                        + "\(result.plan.dropped.count) dropped, saturated: \(result.plan.isSaturated)")
                    ProbeRow("Applied", value: "+\(report.notificationsAdded) −\(report.notificationsRemoved) "
                        + "=\(report.notificationsUnchanged) notifications; +\(report.alarmsScheduled) −\(report.alarmsCancelled) "
                        + "=\(report.alarmsUnchanged) alarms; stale snoozes −\(report.staleSnoozesRemoved)")
                    if !report.notificationFailures.isEmpty || !report.alarmFailures.isEmpty || report.alarmLimitReached {
                        ProbeRow("Failures", value: (report.notificationFailures + report.alarmFailures).joined(separator: "; ")
                            + (report.alarmLimitReached ? " · AlarmKit maximumLimitReached" : ""), status: .fail)
                    }
                    ProbeRow("Alarm authorization", value: result.alarmAuthorization.rawValue)
                    ProbeRow("Next re-plan", value: result.plan.nextReplanDate.formatted(date: .abbreviated, time: .shortened))
                    ForEach(result.notices, id: \.self) { notice in
                        ProbeRow("Notice", value: model.renderer.string(notice), status: .info)
                    }
                    if let next = result.plan.notifications.first {
                        ProbeRow("Next notification", value: "\(next.fireDate.formatted(date: .abbreviated, time: .shortened)) · "
                            + "\(next.effectiveTier.rawValue) · \(model.renderer.string(next.content.title))")
                    }
                }
                ProbeRow("Background refresh request", value: reminders.lastBackgroundRequest ?? "–")
                ProbeRow("Learned alarm limit", value: reminders.engine.state.learnedAlarmLimit.map {
                    "\($0.count) (since \($0.learnedAt.formatted(date: .omitted, time: .shortened)))" } ?? "none")
                Button { Task { await reminders.replanNow(.manual) } } label: { Text(verbatim: "Re-plan now") }
            } header: { Text(verbatim: "Reminders — coordinator") }

            Section {
                ForEach(reminders.healthItems) { item in
                    ProbeRow(model.renderer.string(forKey: item.titleKey), value: model.renderer.string(item.detail),
                             status: Self.status(item.status))
                }
                Button { Task { await reminders.refreshHealth() } } label: { Text(verbatim: "Refresh health check") }
                Button {
                    Task { state.message = "notifications: \(await reminders.requestNotificationAuthorization().rawValue)" }
                } label: { Text(verbatim: "Request notification permission") }
                Button {
                    Task { state.message = "alarms: \(await reminders.requestAlarmAuthorization().rawValue)" }
                } label: { Text(verbatim: "Request AlarmKit permission") }
                Button {
                    Task { state.message = "test notification (5 s): \(await reminders.sendTestNotification())" }
                } label: { Text(verbatim: "Send test notification (5 s, lock the phone)") }
                Button {
                    Task { state.message = "test alarm (60 s): \(await reminders.sendTestAlarm())" }
                } label: { Text(verbatim: "Schedule test alarm (60 s)") }
                if let message = state.message {
                    ProbeRow("Result", value: message)
                }
            } header: { Text(verbatim: "Reminders — health check (B4 builds the real screen)") }
        }
        .task { await reminders.refreshHealth() }
    }

    private var lastRun: String {
        guard let date = reminders.lastRunAt else { return reminders.isRunning ? "running…" : "not yet" }
        return date.formatted(date: .omitted, time: .standard) + " · " + reminders.lastReasons.map(\.rawValue).joined(separator: ", ")
    }

    private static func status(_ status: ReminderHealthStatus) -> ProbeStatus {
        switch status {
        case .ok: return .pass
        case .info: return .info
        case .warning: return .pending
        case .problem: return .fail
        }
    }
}
#endif // DEBUG
