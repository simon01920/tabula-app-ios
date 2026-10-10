// Small system seams of the reminder coordinator (Phase 3 Stage A): background app refresh requests and the device
// state the health check shows. Real implementations + fakes for `-TabulaSeed` screenshot mode.
// APIs (developer.apple.com DocC JSON, checked 2026-10-10; docs/ENVIRONMENT.md §21):
//   BackgroundTasks: BGTaskScheduler.shared, BGAppRefreshTaskRequest(identifier:), BGTaskRequest.earliestBeginDate,
//     submit(_:) throws (iOS 13–26; deprecated in iOS 27) / submitTaskRequest(_:) async throws (iOS 27+, "do not call
//     from the main thread"); one pending refresh request per app, a new submit replaces it.
//     The launch handler is SwiftUI's `Scene.backgroundTask(.appRefresh(_:))` (TabulaApp.swift), which registers the
//     identifier itself — never also call `BGTaskScheduler.register` for it (double registration kills the app).
//     Info.plist: `BGTaskSchedulerPermittedIdentifiers` = [BackgroundRefreshPolicy.taskIdentifier] and
//     `UIBackgroundModes` = [fetch] ("Executing app refresh tasks requires setting the fetch UIBackgroundModes").
//   UIKit: UIApplication.backgroundRefreshStatus (+ backgroundRefreshStatusDidChangeNotification); Foundation:
//     ProcessInfo.isLowPowerModeEnabled (+ NSProcessInfoPowerStateDidChange). "Background App Refresh is disabled
//     automatically when a device is operating in low-power mode."
import BackgroundTasks
import Foundation
import TimetableCore
import TimetableUI
import UIKit

/// Submits the next background refresh request.
protocol BackgroundRefreshScheduling: Sendable {
    /// Returns an error description, or `nil` when submitted.
    func submit(earliestBeginDate: Date) async -> String?
}

struct LiveBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    /// `@concurrent`: always off the main actor (`submitTaskRequest` must not be called from the main thread).
    @concurrent func submit(earliestBeginDate: Date) async -> String? {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundRefreshPolicy.taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            if #available(iOS 27.0, *) {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } else {
                try BGTaskScheduler.shared.submit(request)
            }
            return nil
        } catch {
            return String(describing: error)
        }
    }
}

/// Records requests instead of submitting them (seed / screenshot mode).
actor RecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private(set) var requests: [Date] = []

    func submit(earliestBeginDate: Date) async -> String? {
        requests.append(earliestBeginDate)
        return nil
    }
}

/// Reads the device state for the health check.
enum DeviceStateReader {
    @MainActor
    static func live() -> DeviceReminderState {
        let refresh: BackgroundRefreshState
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: refresh = .available
        case .denied: refresh = .denied
        case .restricted: refresh = .restricted
        @unknown default: refresh = .unknown
        }
        return DeviceReminderState(isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                   backgroundRefresh: refresh)
    }
}
