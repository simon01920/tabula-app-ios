// Launch screen: shown only while the store loads (`AppModel.phase == .loading`), then AppRootView cross-fades to the
// app (a cut with Reduce Motion). Once on screen it stays for its 0.3 s swipe (no one-frame flash); with Reduce Motion
// there is no swipe and no hold, and a store already loaded at the first frame never shows it (`LaunchHold`, P6).
// The background is the system background, which is what the static iOS launch screen shows
// (Config/App-Info.plist `UILaunchScreen` is an empty dict on both build paths: no image, no colour asset).
// The mark is the app icon drawn in shapes (geometry from scripts/make-app-icon.py, 1024 px canvas scaled to 96 pt):
// the ink square keeps the light icon's ink in both appearances, like the Home Screen icon the user just tapped.
// Motion: the highlighter swipes in once (0.3 s), then the three lesson tiles light up top to bottom in a loop.
// Reduce Motion: the static mark. VoiceOver: one element, "Loading…". DEBUG route `launch` shows it permanently.
// APIs: PhaseAnimator.init(_:content:animation:) (iOS 17, Apple docs JSON checked 2026-11-01),
//       View.scaleEffect(x:y:anchor:), View.transformEffect(_:), View.rotationEffect(_:), View.position(x:y:),
//       RoundedRectangle(cornerRadius:style:), EnvironmentValues.accessibilityReduceMotion,
//       View.accessibilityElement(children:), Color(uiColor:) with UIColor.systemBackground.
import SwiftUI
import TimetableUI
import UIKit

struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swiped = false
    /// Called once the highlighter swipe (0.3 s) has played — at once with Reduce Motion (no swipe); `AppRootView`
    /// keeps the mark until then (no flash).
    var onSwipeFinished: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            LaunchMark(swiped: swiped || reduceMotion, animatesTiles: !reduceMotion)
            Text("launch.wordmark")
                .font(.title.weight(.bold))
                .foregroundStyle(.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("shell.loading"))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.3)) { swiped = true }
        }
        .task {
            let hold = LaunchHold.holdDuration(reduceMotion: reduceMotion)
            if hold > .zero { try? await Task.sleep(for: hold) }
            onSwipeFinished?()
        }
    }
}

/// The icon mark, 96 pt.
private struct LaunchMark: View {
    let swiped: Bool
    let animatesTiles: Bool

    private static let side: CGFloat = 96
    private static let scale = side / 1024
    /// Icon tile opacities, now → later.
    private static let fade: [Double] = [1, 0.66, 0.36]

    var body: some View {
        let s = Self.scale
        ZStack {
            RoundedRectangle(cornerRadius: 0.2237 * Self.side, style: .continuous)
                .fill(Color(DesignTokens.ink.light))
            if animatesTiles {
                PhaseAnimator([0, 1, 2]) { lit in
                    tiles((0..<3).map { $0 == lit ? 1 : Self.fade[2] })
                } animation: { _ in .easeInOut(duration: 0.35).delay(0.15) }
            } else {
                tiles(Self.fade)
            }
            // The chisel-cut highlighter: a rounded rect sheared like the icon's parallelogram (bottom 28 px left of the
            // top over 106 px), tilted -3°, swiping in from its leading edge.
            let height = 170 * s
            let shear = -28.0 / 106
            RoundedRectangle(cornerRadius: 32 * s, style: .continuous)
                .fill(Color.highlighter)
                .frame(width: 620 * s, height: height)
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: -shear * height / 2, ty: 0))
                .scaleEffect(x: swiped ? 1 : 0.01, y: 1, anchor: .leading)
                .rotationEffect(.degrees(-3))
                .position(x: 520 * s, y: 287 * s)
        }
        .frame(width: Self.side, height: Self.side)
    }

    private func tiles(_ opacity: [Double]) -> some View {
        let s = Self.scale
        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 32 * s, style: .continuous)
                    .fill(Color.white.opacity(opacity[index]))
                    .frame(width: 236 * s, height: 118 * s)
                    .position(x: 512 * s, y: CGFloat(461 + 148 * index) * s)
            }
        }
    }
}
