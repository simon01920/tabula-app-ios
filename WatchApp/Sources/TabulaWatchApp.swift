// Tabula for Apple Watch (Phase 5 W1, PHASE5_PLAN). XcodeGen/CI path ONLY — xtool cannot build or sign watchOS apps
// (RISKS #1). Embedded in the iOS app (TabulaApp.app/Watch/TabulaWatch.app) by project.yml; local type-check:
// scripts/watch-typecheck.sh. Series 7 = arm64_32 (32-bit Int, RISKS #39): no Int time math here, the shared planners
// use Int64. No macros (plain ObservableObject).
//
// Read-only v1: the iPhone sends its widget snapshot as the WatchConnectivity application context (App/Sources/Widgets/
// WatchSnapshotSender.swift); `WatchSessionReceiver` validates it, stores it in the App Group (`WatchCache`, the offline
// cache) and reloads the complications. The screen renders only from the cache, re-evaluated every minute
// (`TimelineView(.everyMinute)`); the live remaining time is `Text(timerInterval:)` inside the shared widget views.
//
// APIs (watchOS 27 SDK headers / swiftinterface, 2026-10-30): WCSession.isSupported(), .default, .activate(),
//   .receivedApplicationContext, .hasContentPending (watchOS 3); WCSessionDelegate
//   session(_:activationDidCompleteWith:error:) (watchOS 2.2, the only required method on watchOS),
//   session(_:didReceiveApplicationContext:); Scene.backgroundTask(_:action:) with BackgroundTask.watchConnectivity
//   (the documented replacement of WKWatchConnectivityRefreshBackgroundTask: "defer … until after you've activated
//   your session and received all the pending data. Use the hasContentPending property",
//   https://developer.apple.com/documentation/watchkit/wkwatchconnectivityrefreshbackgroundtask);
//   WidgetCenter.shared.reloadAllTimelines() (watchOS 9; a plain class, not main-actor isolated in the SDK);
//   TimelineView(.everyMinute) (watchOS 8); Synchronization.Mutex (watchOS 11).
import Combine
import SwiftUI
import Synchronization
import TimetableCore
import TimetableUI
import WatchConnectivity
import WidgetKit

@main
struct TabulaWatchApp: App {
    private let model: WatchModel
    private let receiver: WatchSessionReceiver

    init() {
        let model = WatchModel()
        self.model = model
        receiver = WatchSessionReceiver(model: model)
        receiver.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
        .backgroundTask(.watchConnectivity) { [receiver] in
            await receiver.waitForPendingContent()
        }
    }
}

/// The cached snapshot the screen shows.
@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var snapshot: WidgetSnapshot? = WatchCache.read()

    func reload() {
        snapshot = WatchCache.read()
    }
}

struct WatchRootView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            WatchHomeView(display: WatchPresenter.display(
                snapshot: model.snapshot, now: timeline.date, deviceTimeZone: .autoupdatingCurrent,
                lookup: WatchCache.lookup(language: model.snapshot?.languageCode)))
        }
    }
}

/// Receives the iPhone's snapshot. Delegate calls arrive on a WatchConnectivity queue, not the main thread.
final class WatchSessionReceiver: NSObject, WCSessionDelegate, Sendable {
    private let model: WatchModel
    /// Deliveries being stored right now.
    private let receiving = Mutex(0)

    init(model: WatchModel) {
        self.model = model
    }

    @MainActor
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        // The last context also lands here when it arrived while the app was not running.
        receive(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    /// Stores and reloads synchronously on the delegate queue, so a background launch never ends between the write and
    /// the complication reload; `receiving` tells `waitForPendingContent` that a delivery is still being handled.
    private func receive(_ context: [String: Any]) {
        receiving.withLock { $0 += 1 }
        defer { receiving.withLock { $0 -= 1 } }
        guard let data = WatchSnapshotTransfer.snapshotData(in: context), (try? WatchCache.store(data)) == true else { return }
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor [model] in model.reload() }   // the screen only; the cache is already written
    }

    /// Keeps a background launch alive until the session is active, nothing is pending and the last delivery is stored.
    func waitForPendingContent() async {
        // shortcut: polls for at most 10 s; a delivery still running after that is lost until the next launch (RISKS #89).
        let session = WCSession.default
        var polls = 0
        while polls < 20, session.activationState != .activated || session.hasContentPending
                || receiving.withLock({ $0 }) > 0 {
            polls += 1
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
