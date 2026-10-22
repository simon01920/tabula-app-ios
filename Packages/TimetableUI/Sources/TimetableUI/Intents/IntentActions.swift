// App Intents, the pure part (Phase 4 B3). Linux-tested; the `AppIntent` types themselves live in the app and widget
// targets (App/Sources/Intents, WidgetExtension/Sources/Intents) and only forward to what is here.
//
// WRITE PATH (decided in B3, ENVIRONMENT §32): every data-changing intent is a `LiveActivityIntent`, which Apple
// documents as performed "in the app's process" even when the button sits in a widget or a Live Activity
// (WidgetKit article "Adding interactivity to widgets and Live Activities"; AlarmKit passes such intents as
// `stopIntent` / `secondaryIntent`). The intent's `perform()` asks `IntentHost` for the app's services; only the app
// registers them (`AppServices`), so:
//   - in the app process the mutation runs through `AppModel.apply` (stamping, validation, save, reminder re-plan,
//     widget snapshot) exactly like the notification action;
//   - if the system ever ran the intent in the widget extension, no services are registered there and the intent does
//     nothing (`IntentActionOutcome.unavailable`): the extension NEVER writes the store (which may live in Application
//     Support on a free team, out of the extension's reach).
//
// Mark done = the notification action's rule: `ReminderResponseInterpreter.mutation(for:now:)` →
// `DatabaseMutation.completeTask` / `.completeExam` (sets `completedAt`; a repeating task gets its successor per the
// DOMAIN_MODEL §3.9 caller rule, tombstone-safe). Idempotent: a completed or deleted/unknown item is a no-op, decided
// here BEFORE anything is applied, so a second tap (stale widget, alarm and widget both used) changes nothing and can
// never create a second successor.
import Foundation
import TimetableCore

/// What a data-changing intent asks for.
public enum IntentAction: Hashable, Sendable {
    /// Mark a task done (widget checkbox, loud alarm "Done").
    case completeTask(TaskItem.ID)
    /// Mark an exam done (loud alarm "Done" of an exam reminder).
    case completeExam(Exam.ID)

    /// From an intent's string parameter (`TaskItem.ID.uuidString`); `nil` when it is not a UUID.
    public init?(taskID: String) {
        guard let id = TaskItem.ID(uuidString: taskID) else { return nil }
        self = .completeTask(id)
    }

    /// From an intent's string parameter (`Exam.ID.uuidString`); `nil` when it is not a UUID.
    public init?(examID: String) {
        guard let id = Exam.ID(uuidString: examID) else { return nil }
        self = .completeExam(id)
    }

    /// The reminder source of the item (the notification action's vocabulary).
    public var source: ReminderSource {
        switch self {
        case .completeTask(let id): return .task(id)
        case .completeExam(let id): return .exam(id)
        }
    }
}

/// What happened (logged on the debug screen; intents never show errors for these).
public enum IntentActionOutcome: String, Hashable, Sendable {
    /// The item is completed now (and a repeating task has its successor).
    case completed
    /// It was already completed: nothing changed.
    case alreadyDone
    /// Unknown or deleted (tombstoned) item, or a malformed id: nothing changed.
    case notFound
    /// No app services in this process (widget extension), or the store is not loaded / read-only: nothing changed.
    case unavailable
    /// `AppModel.apply` refused or failed: nothing changed.
    case failed
}

/// The decision for one action against the current database.
public enum IntentActionDecision: Sendable {
    /// Apply this mutation (the same value the notification "Mark done" action applies).
    case apply(DatabaseMutation)
    /// Do nothing and report this outcome.
    case skip(IntentActionOutcome)

    /// The outcome when skipped, else `nil`.
    public var skippedOutcome: IntentActionOutcome? {
        if case .skip(let outcome) = self { return outcome }
        return nil
    }
}

public enum IntentActionPlanner {
    /// What to do for `action` on `database` at `now` (`nil` database = not loaded / nothing stored → `.unavailable`).
    public static func decide(_ action: IntentAction, database: TabulaDatabase?, now: Date) -> IntentActionDecision {
        guard let database else { return .skip(.unavailable) }
        switch action {
        case .completeTask(let id):
            guard let task = database.tasks.first(where: { $0.id == id && !$0.isDeleted }) else { return .skip(.notFound) }
            if task.isCompleted { return .skip(.alreadyDone) }
        case .completeExam(let id):
            guard let exam = database.exams.first(where: { $0.id == id && !$0.isDeleted }) else { return .skip(.notFound) }
            if exam.isCompleted { return .skip(.alreadyDone) }
        }
        guard let mutation = ReminderResponseInterpreter.mutation(for: action.source, now: now) else {
            return .skip(.notFound)
        }
        return .apply(mutation)
    }
}

// MARK: - Host registry (the app's services for intents)

/// What intents need from the app. Implemented by the app (`AppIntentHost`, App/Sources/Intents), registered once in
/// `AppServices.init` (the dependency container), never in the widget extension.
@MainActor
public protocol IntentHostServices: AnyObject {
    /// Applies a data-changing action (load → decide → `AppModel.apply` → save → re-plan → widget snapshot written).
    func perform(_ action: IntentAction) async -> IntentActionOutcome
    /// The "What's next?" sentence (the Today header's now/next logic, in the app's language).
    func whatsNextAnswer() async -> String
    /// Opens the Tasks tab with the new-task editor ("Add homework").
    func openNewTask() async
}

/// Where intents find the app's services. Part of the dependency container (`AppServices` registers itself); not a
/// general-purpose singleton: nothing but intents reads it.
@MainActor
public enum IntentHost {
    private static var registered: (any IntentHostServices)?

    /// Called once by the app (`AppServices.init`).
    public static func register(_ services: any IntentHostServices) {
        registered = services
    }

    /// Tests only.
    public static func unregister() {
        registered = nil
    }

    /// The registered services; waits up to `timeout` for the registration (an intent that launched the app in the
    /// background may be performed while the app delegate is still being created). `nil` in the widget extension.
    public static func services(waitingUpTo timeout: Duration = .seconds(3)) async -> (any IntentHostServices)? {
        if let registered { return registered }
        let step = Duration.milliseconds(50)
        var waited = Duration.zero
        while waited < timeout {
            try? await Task.sleep(for: step)
            waited += step
            if let registered { return registered }
        }
        return nil
    }

    /// Performs `action` through the app's services, or reports `.unavailable` (widget extension / no app).
    public static func perform(_ action: IntentAction?, waitingUpTo timeout: Duration = .seconds(3)) async -> IntentActionOutcome {
        guard let action else { return .notFound }
        guard let services = await services(waitingUpTo: timeout) else { return .unavailable }
        return await services.perform(action)
    }
}

// MARK: - Loud alarm secondary button

/// The loud alarm's secondary button (AlarmKit `AlarmPresentation.Alert.secondaryButton` + `secondaryButtonBehavior`).
/// The system always adds Stop. With App Intents metadata (Xcode / TestFlight builds), task and exam alarms offer
/// "Done" (`.custom` + `secondaryIntent` = the Mark done intent, resolving RISKS #51); everything else, and every alarm
/// on builds without metadata (xtool, RISKS #19), keeps Snooze (`.countdown` + `postAlert`), as in Phase 3.
/// DECISION FOR THE HUMAN (B3 report): AlarmKit has ONE secondary button, so a task/exam alarm offers Done *instead of*
/// Snooze; flip `doneReplacesSnooze` to keep Snooze everywhere.
public enum AlarmSecondaryAction: Hashable, Sendable {
    /// Stop only.
    case none
    /// Snooze (post-alert countdown).
    case snooze
    /// "Done": runs the Mark done intent for this item.
    case markDone(IntentAction)

    /// Done replaces Snooze on task / exam alarms when intents work (the B3 default).
    public static let doneReplacesSnooze = true

    /// The button for an alarm whose metadata `source` is `sourceRawValue` (`ReminderSource.rawValue`; empty for test
    /// alarms). `snoozeAvailable`: the alarm has a snooze length. `intentsAvailable`: this build ships App Intents
    /// metadata (compile-time `TABULA_APP_INTENTS`).
    public static func make(sourceRawValue: String, snoozeAvailable: Bool, intentsAvailable: Bool) -> AlarmSecondaryAction {
        if intentsAvailable, doneReplacesSnooze, let source = ReminderSource(rawValue: sourceRawValue) {
            switch source {
            case .task(let id): return .markDone(.completeTask(id))
            case .exam(let id): return .markDone(.completeExam(id))
            case .lesson, .packTonight: break
            }
        }
        return snoozeAvailable ? .snooze : .none
    }
}

// MARK: - "What's next?"

/// The answer of the "What's next?" App Shortcut: the same now/next state as the Today header and the Now & Next widget
/// (`WidgetTimelinePlanner` over the app's snapshot; `WidgetTimelinePlannerTests.stateMatchesTheTodayTab` proves the
/// state equals `TodayState.make`), rendered by `NowNextPresenter` in the app's language. The spoken / shown sentence is
/// the widget's VoiceOver sentence ("Now, Maths, 8:00 to 8:45, room 12, ends at 8:45, Next, …"), so no new strings.
public enum WhatsNextAnswer {
    /// The display at `now` (its `accessibilityLabel` is the answer).
    public static func display(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone,
                               lookup: @escaping LocalizedTextRenderer.Lookup) -> NowNextDisplay {
        let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, now: now, deviceTimeZone: deviceTimeZone)
        let context = plan.context ?? CalendarContext(timeZone: deviceTimeZone, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context, lookup: lookup)
        return NowNextPresenter(renderer: renderer, context: context).display(plan.entries[0])
    }

    /// The sentence.
    public static func sentence(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone,
                                lookup: @escaping LocalizedTextRenderer.Lookup) -> String {
        display(snapshot: snapshot, now: now, deviceTimeZone: deviceTimeZone, lookup: lookup).accessibilityLabel
    }
}
