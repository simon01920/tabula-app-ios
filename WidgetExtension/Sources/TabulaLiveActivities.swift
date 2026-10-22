// The lesson and exam-day Live Activities (Phase 4 Stage B2, PHASE4_PLAN §0.5, decision P3-6). The app starts,
// schedules, updates and ends them (App/Sources/Widgets/LiveActivityController.swift); this extension only renders
// them. Registered in `TabulaWidgetBundle` next to the AlarmKit activity (`AlarmLiveActivity`, unchanged).
//
// Rendering: `LiveActivityPresenter` (TimetableUI, Linux-tested) turns the content state into strings in the app's
// language (`style.languageCode` → the appex's `<lang>.lproj`, like the widgets, RISKS #69) at render time — `Date()`
// is "now", so a re-render when the activity becomes stale (the stale date is the next lesson boundary / the exam start
// and end) moves to the next lesson without an app update. Live time is `Text(timerInterval:)` /
// `ProgressView(timerInterval:)` inside the shared views (TimetableUI/Widgets/LiveActivityViews.swift).
// Taps: `widgetURL(ItemLinkURL.url(for:))` → the app's `onOpenURL` → Today (lesson) or the exam's detail.
// The Lock Screen keeps the system background (no `activityBackgroundTint`): it follows light / dark and Always-On,
// and the text colours are the system's (contrast-safe); the subject colour shows in the badge and progress only.
//
// APIs (Apple docs JSON, checked 2026-10-16, ENVIRONMENT §31): ActivityConfiguration(for:content:dynamicIsland:)
//   (iOS 16.1), ActivityViewContext (.attributes, .state, .isStale iOS 16.2), DynamicIsland(expanded:compactLeading:
//   compactTrailing:minimal:), DynamicIslandExpandedRegion(_:priority:content:) with .leading / .trailing / .center /
//   .bottom, DynamicIsland.keylineTint(_:), DynamicIsland.widgetURL(_:), View.widgetURL(_:).
import ActivityKit
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

/// (a) The current lesson.
struct LessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LessonActivityAttributes.self) { context in
            let display = LiveActivityRendering.lesson(context.state)
            LiveActivityLockScreenView(display: display)
                .widgetURL(ItemLinkURL.url(for: display.link))
        } dynamicIsland: { context in
            let display = LiveActivityRendering.lesson(context.state)
            return LiveActivityRendering.island(display)
        }
    }
}

/// (b) Exam day.
struct ExamLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExamActivityAttributes.self) { context in
            let display = LiveActivityRendering.exam(context.state, examID: context.attributes.examID)
            LiveActivityLockScreenView(display: display)
                .widgetURL(ItemLinkURL.url(for: display.link))
        } dynamicIsland: { context in
            let display = LiveActivityRendering.exam(context.state, examID: context.attributes.examID)
            return LiveActivityRendering.island(display)
        }
    }
}

/// Main actor: the shared views are SwiftUI views (main-actor initialisers); the configuration closures run there too.
@MainActor
enum LiveActivityRendering {
    static func lesson(_ state: LessonActivityAttributes.ContentState) -> LiveActivityDisplay {
        presenter(state.style).lesson(state, now: Date())
    }

    static func exam(_ state: ExamActivityAttributes.ContentState, examID: UUID) -> LiveActivityDisplay {
        presenter(state.style).exam(state, examID: examID, now: Date())
    }

    static func presenter(_ style: LiveActivityStyle) -> LiveActivityPresenter {
        LiveActivityPresenter(style: style, lookup: WidgetSnapshotReader.lookup(language: style.languageCode))
    }

    /// The Dynamic Island layouts (shared by both activities).
    static func island(_ display: LiveActivityDisplay) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                LiveActivityExpandedLeading(display: display)
            }
            DynamicIslandExpandedRegion(.trailing) {
                LiveActivityExpandedTrailing(display: display)
            }
            DynamicIslandExpandedRegion(.center) {
                LiveActivityExpandedCenter(display: display)
            }
            DynamicIslandExpandedRegion(.bottom) {
                LiveActivityExpandedBottom(display: display)
            }
        } compactLeading: {
            LiveActivityCompactLeading(display: display)
        } compactTrailing: {
            LiveActivityCompactTrailing(display: display)
        } minimal: {
            LiveActivityMinimal(display: display)
        }
        .keylineTint(keyline(display))
        .widgetURL(ItemLinkURL.url(for: display.link))
    }

    /// The subject colour, contrast-safe against the black Dynamic Island.
    static func keyline(_ display: LiveActivityDisplay) -> Color? {
        display.subject.map { Color(LessonTileStyle.contrastSafeAccent($0.color, isDark: true)) }
    }
}
