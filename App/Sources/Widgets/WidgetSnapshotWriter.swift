// Writes the widget snapshot (PHASE4_PLAN §0.1, Stage A) and asks WidgetKit to reload. Installed once in
// `AppServices.init` by chaining onto `AppModel.onChange` (the previous handler always runs first and unchanged).
//
// Triggers (all arrive through `AppModel.onChange` or the scene):
//   .loaded       launch (also a background-refresh launch: the reminder coordinator loads the store)
//   .data         every accepted `model.apply` (settings changes included: they are data)
//   .environment  scene active (foreground), day change / DST / clock change (significantTimeChangeNotification),
//                 time-zone change, locale change (AppModel.refreshEnvironment)
//   flushNow()    the scene leaves `active` (TabulaApp), so a change made just before going home is not lost
// Debounced (`debounce`), built on the main actor from the model's current state (pure `WidgetSnapshotBuilder`),
// written atomically off the main actor (`WidgetSnapshotStore.write`), then `WidgetCenter.shared.reloadAllTimelines()`.
// Unchanged content (ignoring `generatedAt`) is neither written nor reloaded, so foregrounding does not spend the
// widgets' reload budget (reloads while the app is in the foreground do not count anyway: WidgetKit docs).
//
// No App Group (free team, RISKS #47/#56; `AppEnvironment.widgetContainer == nil`) or seed mode → nothing is written:
// the widgets keep showing "Open Tabula". Never writes while the store is loading or failed to load.
// APIs: WidgetCenter.shared.reloadAllTimelines() (iOS 14), Task.sleep(for:), Task.detached(priority:operation:),
//       Bundle.preferredLocalizations (docs checked 2026-10-16).
import Foundation
import TimetableCore
import TimetableUI
import WidgetKit

@MainActor
final class WidgetSnapshotWriter {
    private weak var model: AppModel?
    private let container: URL?
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var lastWritten: WidgetSnapshot?
    private var writeChain: Task<Void, Never>?
    /// Developer diagnostics: the last write (time, size) or failure.
    private(set) var lastResult: String = "not written yet"

    init(model: AppModel, container: URL?, debounce: Duration = .milliseconds(800)) {
        self.model = model
        self.container = container
        self.debounce = debounce
    }

    /// Chains the writer onto `model.onChange`. Call once, after every other `onChange` owner attached.
    static func install(on model: AppModel) -> WidgetSnapshotWriter {
        let writer = WidgetSnapshotWriter(model: model, container: model.environment.widgetContainer)
        let previous = model.onChange
        model.onChange = { change in
            previous?(change)
            writer.handle(change)
        }
        return writer
    }

    func handle(_ change: AppModelChange) {
        guard container != nil else { return }
        pending?.cancel()
        let delay = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.writeIfChanged()
        }
    }

    /// Writes now (the scene is leaving the foreground).
    func flushNow() {
        guard pending != nil else { return }
        pending?.cancel()
        pending = nil
        writeIfChanged()
    }

    private func writeIfChanged() {
        pending = nil
        guard let model, let container, !model.isLoading, model.problem == nil else { return }
        let snapshot = WidgetSnapshotBuilder.make(
            database: model.database, now: model.now, context: model.calendarContext, tier: model.entitlements.tier,
            locale: model.environment.locale(), languageCode: Bundle.main.preferredLocalizations.first)
        guard snapshot.contentOnly != lastWritten?.contentOnly else { return }
        let data: Data
        do {
            data = try WidgetSnapshotStore.encode(snapshot)
        } catch {
            lastResult = "encode failed: \(error)"
            return
        }
        lastWritten = snapshot
        let previous = writeChain
        writeChain = Task { [weak self] in
            await previous?.value
            let outcome = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try WidgetSnapshotStore.write(data, container: container)
                    return nil
                } catch {
                    return "\(error)"
                }
            }.value
            guard let self else { return }
            if let outcome {
                self.lastResult = "write failed: \(outcome)"
                self.lastWritten = nil   // retry on the next trigger
            } else {
                self.lastResult = "wrote \(data.count) bytes at \(Date().ISO8601Format())"
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
