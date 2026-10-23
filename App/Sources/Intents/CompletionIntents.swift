// Mark done App Intents (Phase 4 B3). THIS FILE EXISTS TWICE, byte for byte: App/Sources/Intents/CompletionIntents.swift
// and WidgetExtension/Sources/Intents/CompletionIntents.swift (scripts/validate_config.py fails if they differ). That is
// Apple's documented "add the intent to your widget extension target and your app target" setup, expressed for two
// build systems: the widget needs the type for `Button(intent:)`, the app needs it because a `LiveActivityIntent` is
// performed in the app's process, and each bundle then carries the intent in its own App Intents metadata.
//
// Why `LiveActivityIntent`: "If you adopt the LiveActivityIntent or AudioPlaybackIntent protocol, the system runs the
// app intent in the app's process" (WidgetKit, "Adding interactivity to widgets and Live Activities"), and AlarmKit
// takes exactly this type for `stopIntent` / `secondaryIntent`. The deprecated alternatives (`openAppWhenRun`,
// `ForegroundContinuableIntent`, both deprecated in iOS 26 in favour of `supportedModes`) would bring the app to the
// foreground; Mark done must not.
//
// `perform()` only forwards to `IntentHost` (TimetableUI/Intents/IntentActions.swift): in the app process the app's
// services complete the item through `AppModel.apply` with the notification action's mutation; in the widget extension
// nothing is registered and nothing is written. Unknown, deleted or already completed items are a no-op.
// Builds without App Intents metadata (xtool, RISKS #19) compile these types but never show an intent-driven control
// (`TABULA_APP_INTENTS` is defined only in project.yml): the widget row's `Link` and the alarm's Snooze stay.
// Final QA m1: the alarm "Done" passes its alarm id; the alarm is stopped (`AlarmManager.stop(id:)`) whatever the
// outcome, so a failed or impossible completion never leaves it ringing (the next re-plan re-creates nothing for a
// completed item; for an item that could not be completed the reminder stays in the plan).
// APIs (iOS 26/27 SDK interface + docs, checked 2026-10-23): AppIntent (title, description, isDiscoverable iOS 17,
//   perform()), LiveActivityIntent (iOS 17), IntentParameter / @Parameter(title:), IntentDescription, IntentResult,
//   AlarmKit AlarmManager.shared.stop(id:) throws (AlarmKit.swiftinterface: "public func stop(id: Alarm.ID) throws").
import AlarmKit
import AppIntents
import Foundation
import TimetableUI

/// Marks one task done (Homework widget checkbox, loud alarm "Done" of a task reminder).
struct MarkTaskDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "intent.markTaskDone.title" }
    static var description: IntentDescription? { IntentDescription("intent.markTaskDone.description") }
    /// Not offered as a Shortcuts action: it needs a task id a person cannot pick there.
    static var isDiscoverable: Bool { false }

    /// `TaskItem.ID.uuidString`.
    @Parameter(title: "intent.param.task")
    var taskID: String

    /// The ringing alarm's `Alarm.ID.uuidString` (alarm "Done" only; `nil` from the widget).
    @Parameter(title: "intent.param.alarm")
    var alarmID: String?

    init() {}

    init(taskID: String, alarmID: String? = nil) {
        self.taskID = taskID
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        RingingAlarm.stop(alarmID)
        _ = await IntentHost.perform(IntentAction(taskID: taskID))
        return .result()
    }
}

/// Marks one exam done (loud alarm "Done" of an exam reminder).
struct MarkExamDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "intent.markExamDone.title" }
    static var description: IntentDescription? { IntentDescription("intent.markExamDone.description") }
    static var isDiscoverable: Bool { false }

    /// `Exam.ID.uuidString`.
    @Parameter(title: "intent.param.exam")
    var examID: String

    /// The ringing alarm's `Alarm.ID.uuidString`.
    @Parameter(title: "intent.param.alarm")
    var alarmID: String?

    init() {}

    init(examID: String, alarmID: String? = nil) {
        self.examID = examID
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        RingingAlarm.stop(alarmID)
        _ = await IntentHost.perform(IntentAction(examID: examID))
        return .result()
    }
}

/// Stops the alarm whose "Done" ran the intent, first and regardless of the completion's outcome.
private enum RingingAlarm {
    static func stop(_ alarmID: String?) {
        guard let alarmID, let id = UUID(uuidString: alarmID) else { return }
        try? AlarmManager.shared.stop(id: id)   // throws when it no longer rings: nothing to do then
    }
}
