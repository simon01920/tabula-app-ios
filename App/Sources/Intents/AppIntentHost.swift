// The app's side of every App Intent (Phase 4 B3): registered in `AppServices.init` as `IntentHost`'s services, so it
// exists before an intent that launched the app in the background is performed (and `IntentHost.services` waits up to
// 3 s for it otherwise). Never compiled into the widget extension: the extension has no services and cannot write.
//
// Mark done (widget checkbox, alarm "Done"): the same sequence as the notification action
// (`ReminderCoordinator.handle(.markDone)`):
//   load the store (the intent may have launched the app) → `IntentActionPlanner.decide` (no-op for completed / deleted
//   / unknown items: idempotent, never a second successor) → `AppModel.apply` with the notification action's mutation
//   (stamping, validation, debounced save, `onChange` → re-plan + widget snapshot + Live Activities) → remove the item's
//   delivered notifications → flush the save → re-plan now (cancels the item's remaining reminders and its alarm) →
//   write the widget snapshot and wait for it, because WidgetKit reloads the widget's timeline as soon as `perform()`
//   returns ("Make sure any code that's necessary for the timeline update runs before you return").
// "What's next?": `WhatsNextAnswer` over the snapshot the widgets would get now (Today header logic).
// "Add homework": `AppNavigation.open(.newTask)` → Tasks tab + `tasks.editor-new` (the shell shows it when it can).
import Foundation
import TimetableCore
import TimetableUI

@MainActor
final class AppIntentHost: IntentHostServices {
    private let model: AppModel
    private let reminders: ReminderCoordinator
    private let navigation: AppNavigation
    private let widgets: WidgetSnapshotWriter
    /// Developer diagnostics: the last intent action and its outcome.
    private(set) var lastAction: String = "none yet"

    init(model: AppModel, reminders: ReminderCoordinator, navigation: AppNavigation, widgets: WidgetSnapshotWriter) {
        self.model = model
        self.reminders = reminders
        self.navigation = navigation
        self.widgets = widgets
    }

    func perform(_ action: IntentAction) async -> IntentActionOutcome {
        await model.load()
        let outcome: IntentActionOutcome
        switch IntentActionPlanner.decide(action, database: model.database, now: model.now) {
        case .skip(let skipped):
            outcome = skipped
        case .apply(let mutation):
            switch model.apply(mutation) {
            case .applied:
                outcome = .completed
                await reminders.engine.removeDelivered(for: action.source)
            case .readOnly:
                outcome = .unavailable
            case .rejected, .failed:
                outcome = .failed
            }
        }
        if outcome == .completed {
            await model.flush()                         // persist first: the system may suspend us any moment
            await reminders.replanNow(.intentAction)
        }
        await widgets.flushAndWait()                    // the timeline reload after perform() must see the change
        lastAction = "\(action.source.rawValue): \(outcome.rawValue) at \(Date().ISO8601Format())"
        return outcome
    }

    func whatsNextAnswer() async -> String {
        await model.load()
        let environment = model.environment
        let snapshot = WidgetSnapshotBuilder.make(
            database: model.database, now: model.now, context: model.calendarContext, tier: model.entitlements.tier,
            locale: environment.locale(), languageCode: Bundle.main.preferredLocalizations.first)
        return WhatsNextAnswer.sentence(snapshot: snapshot, now: model.now, deviceTimeZone: environment.deviceTimeZone(),
                                        lookup: environment.catalogLookup)
    }

    func openNewTask() async {
        navigation.open(.newTask)
    }
}
