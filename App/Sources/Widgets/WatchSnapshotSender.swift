// Sends the widget snapshot to the Apple Watch (Phase 5 W1, PHASE5_PLAN decision 1). `WidgetSnapshotWriter` calls
// `send(_:)` after every successful snapshot write; the bytes go out as the WatchConnectivity application context
// (`WatchSnapshotTransfer`, ≤ 19 000 B; "replaces the previous dictionary", may be sent while the watch is unreachable:
// https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)).
//
// The session is activated once (the writer owns one sender). Nothing happens when WatchConnectivity is unsupported,
// no watch is paired or the watch app is not installed. `updateApplicationContext` may only be called once the session
// is `.activated` ("a programmer error" otherwise), so the latest bytes wait in `pending` until then. On activation and
// when the watch state changes (watch app installed later, another watch) the App Group file is re-sent if it differs
// from the last context, because the writer skips unchanged snapshots and would never send one to a new watch.
// APIs (iOS 27 SDK WCSession.h, 2026-10-30): WCSession.isSupported(), .default, .activate(), .activationState,
//   .isPaired / .isWatchAppInstalled (iOS only), .applicationContext, updateApplicationContext(_:) throws;
//   WCSessionDelegate session(_:activationDidCompleteWith:error:), sessionDidBecomeInactive(_:),
//   sessionDidDeactivate(_:) (required on iOS; re-activate for the newly selected watch), sessionWatchStateDidChange(_:).
import Foundation
import TimetableUI
import WatchConnectivity

@MainActor
final class WatchSnapshotSender: NSObject, WCSessionDelegate {
    private let container: URL
    private var pending: Data?

    /// `nil` where WatchConnectivity is unsupported (e.g. iPad).
    init?(container: URL) {
        guard WCSession.isSupported() else { return nil }
        self.container = container
        super.init()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends `data` now, or once the session is active.
    func send(_ data: Data) {
        pending = data
        flush()
    }

    private func flush() {
        let session = WCSession.default
        guard let data = pending, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }   // kept in `pending` until then
        guard (session.applicationContext[WatchSnapshotTransfer.key] as? Data) != data,
              let context = WatchSnapshotTransfer.context(for: data) else {
            pending = nil   // already sent, or over the cap (never sendable)
            return
        }
        do {
            try session.updateApplicationContext(context)
            pending = nil
        } catch {
            // Kept in `pending`: the next snapshot write, activation or watch-state change retries it.
        }
    }

    /// Re-sends the App Group snapshot (activation, watch state change).
    private func resend() {
        if pending == nil {
            pending = try? Data(contentsOf: WidgetSnapshotStore.fileURL(container: container))
        }
        flush()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in self.resend() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.resend() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: activate again for the new one (WCSession docs).
        Task { @MainActor in WCSession.default.activate() }
    }
}
