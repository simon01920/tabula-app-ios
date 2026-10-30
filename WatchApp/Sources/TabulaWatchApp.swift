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
//   WidgetCenter.shared.reloadAllTimelines() (watchOS 9); TimelineView(.everyMinute) (watchOS 8).
import Combine
import SwiftUI
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

    private func receive(_ context: [String: Any]) {
        guard let data = WatchSnapshotTransfer.snapshotData(in: context), (try? WatchCache.store(data)) == true else { return }
        Task { @MainActor [model] in
            model.reload()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Keeps a background launch alive until WatchConnectivity has delivered what is pending.
    func waitForPendingContent() async {
        // shortcut: polls for at most 10 s; if a device shows late complications, wait for the delegate call instead.
        var polls = 0
        while WCSession.default.hasContentPending, polls < 20 {
            polls += 1
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
