// The real `AlarmClient` (Phase 3 Stage A): fixed-time AlarmKit alarms for the planner's loud-alarm reminders.
// APIs (developer.apple.com DocC JSON; docs/spikes/ALARMKIT.md §2, re-checked 2026-10-10):
//   Alarm (.id, .state: Alarm.State .scheduled/.alerting/.countdown/.paused),
//   AlarmManager.shared, .authorizationState, .requestAuthorization() async throws, .authorizationUpdates,
//   .alarms { get throws }, .schedule(id:configuration:) async throws, .cancel(id:) throws,
//   AlarmManager.AlarmError.maximumLimitReached, AlarmManager.AlarmConfiguration<M>.alarm(schedule:attributes:) /
//   init(countdownDuration:schedule:attributes:), Alarm.Schedule.fixed(Date), Alarm.CountdownDuration(preAlert:postAlert:),
//   AlarmAttributes(presentation:metadata:tintColor:), AlarmPresentation(alert:countdown:paused:),
//   AlarmPresentation.Countdown(title:pauseButton:), AlarmButton(text:textColor:systemImageName:),
//   AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)            -- iOS 26.1+
//   AlarmPresentation.Alert(title:stopButton:secondaryButton:secondaryButtonBehavior:) -- iOS 26.0, deprecated 26.1
//
// Rules from the Phase 0 spike:
//   - never prompt implicitly: `schedule` checks `authorizationState == .authorized` first (the first `schedule` call
//     would otherwise show the system prompt, F12); the prompt comes only from `requestAuthorization()` (explicit UI);
//   - `.fixed(Date)` is absolute and does not follow time-zone changes (F15): the coordinator re-plans on zone changes;
//   - snooze uses `secondaryButtonBehavior: .countdown` + `postAlert`, which needs the TabulaWidgets Live Activity
//     (`AlarmLiveActivity`, F13);
//   - stop/snooze App Intents are not used (App Intents metadata under xtool unproven; Mark done is notification-only).
// Titles: the planner text is rendered by the app (`ReminderRequestBuilder`) and passed as an interpolated
// `LocalizedStringResource` (catalog key "%@" is absent, so the system shows the rendered value); the Snooze/Stop
// button titles are catalog keys.
import AlarmKit
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI

struct LiveAlarmClient: AlarmClient {
    func authorization() async -> AlarmAuthorization {
        Self.map(AlarmManager.shared.authorizationState)
    }

    func requestAuthorization() async -> AlarmAuthorization {
        do {
            return Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            return Self.map(AlarmManager.shared.authorizationState)
        }
    }

    func scheduledAlarms() async -> [ScheduledAlarmInfo]? {
        do {
            return try AlarmManager.shared.alarms.map { ScheduledAlarmInfo(id: $0.id, state: Self.map($0.state)) }
        } catch {
            return nil
        }
    }

    func schedule(_ spec: AlarmSpec) async -> AlarmScheduleOutcome {
        guard AlarmManager.shared.authorizationState == .authorized else { return .notAuthorized }
        let title = LocalizedStringResource("\(spec.title)")
        let metadata = TabulaAlarmMetadata(kind: spec.reminderID.hasPrefix(ReminderRequestID.testPrefix) ? .test : .reminder,
                                           reminderID: spec.reminderID, source: spec.sourceRawValue, subtitle: spec.subtitle)
        do {
            if let snooze = spec.snoozeSeconds {
                let presentation = AlarmPresentation(
                    alert: Self.alert(title: title,
                                      secondaryButton: AlarmButton(text: "alarm.button.snooze", textColor: .white,
                                                                   systemImageName: "zzz"),
                                      secondaryButtonBehavior: .countdown),
                    countdown: AlarmPresentation.Countdown(title: LocalizedStringResource("\(spec.snoozedTitle)"),
                                                           pauseButton: nil),
                    paused: nil)
                let attributes = AlarmAttributes<TabulaAlarmMetadata>(presentation: presentation, metadata: metadata,
                                                                      tintColor: Color.orange)
                let configuration = AlarmManager.AlarmConfiguration<TabulaAlarmMetadata>(
                    countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snooze),
                    schedule: .fixed(spec.fireDate),
                    attributes: attributes)
                _ = try await AlarmManager.shared.schedule(id: spec.id, configuration: configuration)
            } else {
                let attributes = AlarmAttributes<TabulaAlarmMetadata>(
                    presentation: AlarmPresentation(alert: Self.alert(title: title)), metadata: metadata,
                    tintColor: Color.orange)
                let configuration = AlarmManager.AlarmConfiguration<TabulaAlarmMetadata>.alarm(
                    schedule: .fixed(spec.fireDate), attributes: attributes)
                _ = try await AlarmManager.shared.schedule(id: spec.id, configuration: configuration)
            }
            return .scheduled
        } catch AlarmManager.AlarmError.maximumLimitReached {
            return .limitReached
        } catch {
            return .failed(String(describing: error))
        }
    }

    func cancel(id: UUID) async {
        try? AlarmManager.shared.cancel(id: id)
    }

    func authorizationUpdates() -> AsyncStream<AlarmAuthorization> {
        AsyncStream { continuation in
            let task = Task {
                for await state in AlarmManager.shared.authorizationUpdates {
                    continuation.yield(Self.map(state))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// iOS 26.1 removed the app-provided stop button (the system provides it); iOS 26.0 still needs one.
    static func alert(title: LocalizedStringResource, secondaryButton: AlarmButton? = nil,
                      secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? = nil) -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: title, secondaryButton: secondaryButton,
                                           secondaryButtonBehavior: secondaryButtonBehavior)
        } else {
            return AlarmPresentation.Alert(title: title,
                                           stopButton: AlarmButton(text: "alarm.button.stop", textColor: .white,
                                                                   systemImageName: "stop.circle"),
                                           secondaryButton: secondaryButton, secondaryButtonBehavior: secondaryButtonBehavior)
        }
    }

    /// `Alarm.State` (alerting, countdown, paused, scheduled; ALARMKIT.md §2.3).
    static func map(_ state: Alarm.State) -> ScheduledAlarmInfo.State {
        switch state {
        case .scheduled: return .scheduled
        case .alerting: return .alerting
        case .countdown: return .countdown
        case .paused: return .paused
        @unknown default: return .unknown
        }
    }

    static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .authorized: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
