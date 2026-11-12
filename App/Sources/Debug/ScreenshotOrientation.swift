#if DEBUG
// Screenshot helper (adaptive layout, 2026-11-11): `-TabulaOrientation landscape|portrait` asks every window scene to
// rotate, because `simctl` has no rotate command (.github/workflows/ui-screenshots.yml `orientation` input).
// DEBUG only, like every file in Debug/ (validate_config.py); Release never reads the argument.
// APIs (Apple docs JSON, checked 2026-11-11): UIWindowScene.requestGeometryUpdate(_:errorHandler:) (iOS 16),
//   UIWindowScene.GeometryPreferences.iOS(interfaceOrientations:) (iOS 16), UIInterfaceOrientationMask.
import UIKit

@MainActor
enum ScreenshotOrientation {
    static func apply() {
        guard let raw = UserDefaults.standard.string(forKey: "TabulaOrientation") else { return }
        let mask: UIInterfaceOrientationMask = raw == "landscape" ? .landscapeRight : .portrait
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                NSLog("TabulaOrientation %@: %@", raw, error.localizedDescription)   // in the simulator's unified log
            }
        }
    }
}
#endif
