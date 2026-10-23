// DEBUG-only Live Activity gallery (Phase 4 B2): the simulator cannot screenshot the Lock Screen or the Dynamic Island,
// so these routes render the real Live Activity views (TimetableUI `LiveActivity*`, the same code the extension runs)
// statically at the HIG sizes of a 430×932 pt iPhone (Lock Screen / expanded 408 × 84…160 pt, compact 62.33 × 36.67 pt
// each side, minimal 36.67 × 36.67 pt) from the planner's content for the seeded secondary timetable at fixed instants
// (`LiveActivityGallerySamples`).
//
//   widgets.gallery-live       lesson in progress (Lock Screen, expanded, compact + minimal) + in a break
//   widgets.gallery-live-exam  exam countdown (all presentations) + exam in progress + the final lesson state
// The Dynamic Island is drawn as a black shape with dark-scheme content (the system's island is always black); the
// Lock Screen frame uses the system's material over a grey backdrop. Timers are paused at the scene's instant.
// The expanded layout only approximates the system's region placement (leading / trailing beside the camera, center,
// bottom); the real placement is a device check (B2.9). Strings are verbatim developer labels (DEBUG only).
#if DEBUG
import SwiftUI
import TimetableCore
import TimetableUI

struct LiveActivityGalleryScreen: View {
    enum Page: Sendable { case lessons, exams }

    let page: Page
    @Environment(AppModel.self) private var model

    private static let width: CGFloat = 408
    private static let islandHeight: CGFloat = 160
    private static let compactSide = CGSize(width: 62.33, height: 36.67)
    private static let cameraGap: CGFloat = 126

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch page {
                case .lessons:
                    if let scene = scene("lesson") { full(scene) }
                    if let scene = scene("break") { lockAndCompact(scene) }
                case .exams:
                    if let scene = scene("examCountdown") { full(scene) }
                    if let scene = scene("examRunning") { lockAndCompact(scene) }
                    if let scene = scene("finished") { lockOnly(scene) }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
        .background(Color.gray.opacity(0.25))
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Scenes

    private var scenes: [LiveActivityGalleryScene] {
        LiveActivityGallerySamples.scenes(locale: model.formatter.locale,
                                          languageCode: Bundle.main.preferredLocalizations.first)
    }

    private func scene(_ id: String) -> LiveActivityGalleryScene? { scenes.first { $0.id == id } }

    private func display(_ scene: LiveActivityGalleryScene) -> LiveActivityDisplay {
        switch scene.content {
        case .lesson(let state):
            return LiveActivityPresenter(style: state.style, lookup: model.environment.catalogLookup)
                .lesson(state, now: scene.date)
        case let .exam(id, state):
            return LiveActivityPresenter(style: state.style, lookup: model.environment.catalogLookup)
                .exam(state, examID: id, now: scene.date)
        }
    }

    private func label(_ scene: LiveActivityGalleryScene) -> some View {
        Text(verbatim: scene.caption(locale: model.formatter.locale))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func full(_ scene: LiveActivityGalleryScene) -> some View {
        let shown = display(scene)
        return VStack(alignment: .leading, spacing: 6) {
            label(scene)
            lockScreen(shown, scene.date)
            expanded(shown, scene.date)
            compactRow(shown, scene.date)
        }
    }

    private func lockAndCompact(_ scene: LiveActivityGalleryScene) -> some View {
        let shown = display(scene)
        return VStack(alignment: .leading, spacing: 6) {
            label(scene)
            lockScreen(shown, scene.date)
            compactRow(shown, scene.date)
        }
    }

    private func lockOnly(_ scene: LiveActivityGalleryScene) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(scene)
            lockScreen(display(scene), scene.date)
        }
    }

    // MARK: Presentations

    /// Lock Screen: 408 pt wide, the system material (light / dark follows the scheme).
    private func lockScreen(_ shown: LiveActivityDisplay, _ date: Date) -> some View {
        LiveActivityLockScreenView(display: shown, pauseTime: date)
            .frame(width: Self.width, alignment: .leading)
            .frame(minHeight: 84, maxHeight: 160)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial))
    }

    /// Expanded Dynamic Island: 408 × 160 pt, black, regions placed around the camera.
    private func expanded(_ shown: LiveActivityDisplay, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                LiveActivityExpandedLeading(display: shown).frame(width: 130, alignment: .leading)
                Spacer(minLength: 0)
                LiveActivityExpandedTrailing(display: shown, pauseTime: date).frame(width: 110, alignment: .trailing)
            }
            LiveActivityExpandedCenter(display: shown)
                .frame(maxWidth: .infinity)
            LiveActivityExpandedBottom(display: shown, pauseTime: date)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: Self.width, height: Self.islandHeight, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background(RoundedRectangle(cornerRadius: 46, style: .continuous).fill(Color.black))
    }

    /// Compact (leading · camera · trailing) and minimal, as in the Dynamic Island.
    private func compactRow(_ shown: LiveActivityDisplay, _ date: Date) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                LiveActivityCompactLeading(display: shown)
                    .frame(width: Self.compactSide.width, height: Self.compactSide.height)
                Color.clear.frame(width: Self.cameraGap, height: Self.compactSide.height)
                LiveActivityCompactTrailing(display: shown, pauseTime: date)
                    .frame(width: Self.compactSide.width, height: Self.compactSide.height, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            .background(Capsule().fill(Color.black))
            LiveActivityMinimal(display: shown)
                .frame(width: Self.compactSide.height, height: Self.compactSide.height)
                .background(Circle().fill(Color.black))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
#endif // DEBUG
