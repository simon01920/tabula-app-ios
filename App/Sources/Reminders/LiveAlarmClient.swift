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
//   - Phase 4 B3: on builds with App Intents metadata (`TABULA_APP_INTENTS`, Xcode / TestFlight) a task or exam alarm's
//     secondary button is "Done" (`secondaryButtonBehavior: .custom` + `secondaryIntent` = MarkTaskDoneIntent /
//     MarkExamDoneIntent, a `LiveActivityIntent` run in the app process; `AlarmSecondaryAction` decides); every other
//     alarm, and every alarm on the xtool path, keeps Snooze. `stopIntent` stays nil (Stop only stops).
//     APIs (iOS 27 SDK AlarmKit.swiftinterface): AlarmConfiguration.alarm(schedule:attributes:stopIntent:secondaryIntent:
//     sound:) with `(any LiveActivityIntent)?`; AlarmPresentation.Alert.SecondaryButtonBehavior.custom (iOS 26).
// Titles: the planner text is rendered by the app (`ReminderRequestBuilder`) and passed as an interpolated
// `LocalizedStringResource` (catalog key "%@" is absent, so the system shows the rendered value); the Snooze/Stop
// button titles are catalog keys.
import AlarmKit
import AppIntents
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
        let secondary = AlarmSecondaryAction.make(sourceRawValue: spec.sourceRawValue,
                                                  snoozeAvailable: spec.snoozeSeconds != nil,
                                                  intentsAvailable: Self.intentsAvailable)
        do {
            if case .markDone(let action) = secondary {
                // Phase 4 B3 (RISKS #51 resolved on builds with App Intents metadata): Stop (system) + "Done", which
                // runs the Mark done intent in the app's process (`LiveActivityIntent`); no countdown, so no Snooze.
                let presentation = AlarmPresentation(
                    alert: Self.alert(title: title,
                                      secondaryButton: AlarmButton(text: "alarm.button.done", textColor: .white,
                                                                   systemImageName: "checkmark.circle"),
                                      secondaryButtonBehavior: .custom))
                let attributes = AlarmAttributes<TabulaAlarmMetadata>(presentation: presentation, metadata: metadata,
                                                                      tintColor: Color.orange)
                let configuration = AlarmManager.AlarmConfiguration<TabulaAlarmMetadata>.alarm(
                    schedule: .fixed(spec.fireDate), attributes: attributes, stopIntent: nil,
                    secondaryIntent: Self.doneIntent(for: action, alarmID: spec.id))
                _ = try await AlarmManager.shared.schedule(id: spec.id, configuration: configuration)
            } else if secondary == .snooze, let snooze = spec.snoozeSeconds {
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

    /// `true` on builds that ship App Intents metadata (`TABULA_APP_INTENTS`, project.yml = Xcode / TestFlight). On the
    /// xtool path an intent button would have no metadata to run (RISKS #19), so alarms keep Snooze (Phase 3).
    #if TABULA_APP_INTENTS
    static let intentsAvailable = true
    #else
    static let intentsAvailable = false
    #endif

    /// The Mark done intent of a task / exam alarm (CompletionIntents.swift); it stops `alarmID` whatever the outcome.
    static func doneIntent(for action: IntentAction, alarmID: UUID) -> any LiveActivityIntent {
        switch action {
        case .completeTask(let id): return MarkTaskDoneIntent(taskID: id.uuidString, alarmID: alarmID.uuidString)
        case .completeExam(let id): return MarkExamDoneIntent(examID: id.uuidString, alarmID: alarmID.uuidString)
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
