// Writes the widget snapshot (PHASE4_PLAN §0.1, Stage A) and asks WidgetKit to reload. Installed once in
// `AppServices.init` by chaining onto `AppModel.onChange` (the previous handler always runs first and unchanged).
//
// Triggers (all arrive through `AppModel.onChange` or the scene):
//   .loaded       launch (also a background-refresh launch: the reminder coordinator loads the store)
//   .data         every accepted `model.apply` (settings changes included: they are data)
//   .environment  scene active (foreground), day change / DST / clock change (significantTimeChangeNotification),
//                 time-zone change, locale change (AppModel.refreshEnvironment)
//   flushNow()    the scene leaves `active` (TabulaApp), so a change made just before going home is not lost
// Debounced (`debounce`), built on the main actor from the model's current state (pure `WidgetSnapshotBuilder`; since
// Phase 10 WP2 one build per change, shared with the Live Activity controller and carrying its encoded bytes:
// `WidgetSnapshotSource`), written atomically off the main actor (`WidgetSnapshotStore.write`), then
// `WidgetCenter.shared.reloadAllTimelines()` and, since Phase 5 W1, sent to the Apple Watch (`WatchSnapshotSender`, WatchConnectivity application context).
// Unchanged content (ignoring `generatedAt`) is neither written nor reloaded, so foregrounding does not spend the
// widgets' reload budget (reloads while the app is in the foreground do not count anyway: WidgetKit docs). The
// comparison starts from the file already in the App Group, so a cold or background launch with unchanged data writes
// nothing either. Each write runs inside a UIKit background-task assertion (it can start as the scene leaves `active`).
//
// No App Group (free team, RISKS #47/#56; `AppEnvironment.widgetContainer == nil`) or seed mode → nothing is written:
// the widgets keep showing "Open Tabula". Never writes while the store is loading or failed to load.
// APIs: WidgetCenter.shared.reloadAllTimelines() (iOS 14), Task.sleep(for:), Task.detached(priority:operation:),
//       Bundle.preferredLocalizations (docs checked 2026-10-16).
import Foundation
import TimetableCore
import TimetableUI
import UIKit
import WidgetKit

/// A UIKit background-task assertion (`beginBackgroundTask(withName:expirationHandler:)`: returns `.invalid` when no
/// background time is granted; every begin needs exactly one `endBackgroundTask(_:)`, also from the expiration handler).
@MainActor
final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// The snapshot already in the App Group, read once off the main actor at launch (Phase 10 WP2, P18: it used to be
/// read and decoded synchronously in `AppServices.init`). `take()` returns it; if the background read has not finished
/// yet (a write in the first moments after launch), it reads the file itself. Nothing is written before the first
/// `take()`, so both reads see the same file.
final class PreviousSnapshotRead: @unchecked Sendable {   // @unchecked: `value` is only touched under `lock`
    private let lock = NSLock()
    private let container: URL
    private var value: WidgetSnapshot??   // .none = not read yet

    init(container: URL) {
        self.container = container
        Task.detached(priority: .utility) { [self] in
            let read = WidgetSnapshotStore.read(container: container)
            lock.withLock { if value == nil { value = .some(read) } }
        }
    }

    func take() -> WidgetSnapshot? {
        if let read = lock.withLock({ value }) { return read }
        let read = WidgetSnapshotStore.read(container: container)
        lock.withLock { if value == nil { value = .some(read) } }
        return read
    }
}

@MainActor
final class WidgetSnapshotWriter {
    private let container: URL?
    private let debounce: Duration
    private var pending: Task<Void, Never>?
    private var lastWritten: WidgetSnapshot?
    /// What the widgets already have, until the first write consumes it (`lastWritten` from then on).
    private var previous: PreviousSnapshotRead?
    private var writeChain: Task<Void, Never>?
    /// The snapshot build shared with the Live Activity controller (Phase 10 WP2).
    let source: WidgetSnapshotSource
    /// Phase 5 W1: every written snapshot also goes to the Apple Watch.
    let watch: WatchSnapshotSender?
    /// Developer diagnostics: the last write (time, size) or failure.
    private(set) var lastResult: String = "not written yet"

    init(model: AppModel, container: URL?, debounce: Duration = .milliseconds(800)) {
        self.container = container
        self.debounce = debounce
        source = WidgetSnapshotSource(model: model)
        watch = container.flatMap { WatchSnapshotSender(container: $0) }
        // What the widgets already have (a cold or background launch with unchanged data then writes and reloads
        // nothing). A small file (< 20 KB), read once off the main actor (the first write reads it itself if that
        // read has not finished yet).
        previous = container.map { PreviousSnapshotRead(container: $0) }
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

    /// Writes now if anything changed and waits until the file is on disk (Phase 4 B3: an App Intent's `perform()`
    /// returns only after this, because WidgetKit reloads the widget timeline right after it).
    func flushAndWait() async {
        pending?.cancel()
        pending = nil
        writeIfChanged()
        await writeChain?.value
    }

    private func writeIfChanged() {
        pending = nil
        // The build (and its encoded bytes) the Live Activity controller may already have made for this change.
        guard let container, let build = source.current() else { return }
        if let previous {
            lastWritten = previous.take()
            self.previous = nil
        }
        let snapshot = build.snapshot
        guard snapshot.contentOnly != lastWritten?.contentOnly else { return }
        let data: Data
        if let built = build.data {
            data = built
        } else {
            do {
                data = try WidgetSnapshotStore.encode(snapshot)
            } catch {
                lastResult = "encode failed: \(error)"
                return
            }
        }
        lastWritten = snapshot
        let previous = writeChain
        // The write may start just as the scene leaves the foreground (`flushNow`): ask for background time so iOS
        // does not suspend the app mid-write (the atomic rename means a cut write leaves the old file, never half a
        // file, but the widgets would miss the change). Balanced by exactly one `end()`, also from the expiration.
        let assertion = BackgroundAssertion(name: "tabula.widget-snapshot")
        writeChain = Task { [weak self] in
            defer { assertion.end() }
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
                self.watch?.send(data)
            }
        }
    }
}
