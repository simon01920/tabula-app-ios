// SwiftUI views of the two Live Activities (Stage B2), compiled into BOTH the widget extension (the real
// `ActivityConfiguration`s, WidgetExtension/Sources/*LiveActivity.swift) and the app (the DEBUG `widgets.gallery-live*`
// routes render them statically at the HIG sizes for CI screenshots: a simulator cannot screenshot the Lock Screen or
// the Dynamic Island). Like the widget views they live in TimetableUI behind `canImport(WidgetKit)` and avoid iOS-only
// API (scripts/watch-typecheck.sh compiles TimetableUI for watchOS): the ActivityKit-only modifiers
// (`activityBackgroundTint`, `keylineTint`, `widgetURL` on the island) are applied in the extension.
//
// The views only lay out a `LiveActivityDisplay` (LiveActivityPresentation.swift, Linux-tested). Pieces:
//   LiveActivityLockScreenView        Lock Screen / banner / StandBy (scaled by the system)
//   LiveActivityExpandedLeading       expanded Dynamic Island, `.leading` region: badge + caption
//   LiveActivityExpandedTrailing      `.trailing`: timer caption + live timer
//   LiveActivityExpandedCenter        `.center`: title
//   LiveActivityExpandedBottom        `.bottom`: detail, next lesson, live progress
//   LiveActivityCompactLeading / LiveActivityCompactTrailing / LiveActivityMinimal
// Live time: `Text(timerInterval:countsDown:showsHours:)` and `ProgressView(timerInterval:countsDown:)` (the system
// keeps them counting without updates); `pauseTime` freezes them for the gallery (static strings instead).
// Colours: text is `.primary` / `.secondary` (legible on the system Lock Screen material in light and dark, and white
// on the always-black Dynamic Island); the subject colour appears only in the badge (WCAG black/white text,
// SubjectBadge) and as the progress tint made contrast-safe (≥ 3:1, `LessonTileStyle.contrastSafeAccent`); with
// reduced luminance (Always-On) the tint falls back to `.secondary`.
// VoiceOver: the Lock Screen view and the expanded presentation are one element each with the presenter's sentence;
// the compact / minimal timers speak `timerAccessibilityLabel` ("Mathematics, ends at 9:40").
//
// APIs (Apple docs JSON, checked 2026-10-16, ENVIRONMENT §31): Text(timerInterval:pauseTime:countsDown:showsHours:)
//   iOS 16 / watchOS 9; ProgressView(timerInterval:countsDown:label:currentValueLabel:) iOS 16 / watchOS 9;
//   EnvironmentValues.isLuminanceReduced iOS 16 / watchOS 8; HIG Live Activities: Lock Screen margin 14 pt,
//   408 × 84…160 pt (430 × 932 screen), compact 62.33 × 36.67, minimal 36.67…45 × 36.67, limited width 28 pt circle.
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

// MARK: - Lock Screen

/// The Lock Screen (and banner / StandBy) presentation.
public struct LiveActivityLockScreenView: View {
    private let display: LiveActivityDisplay
    private let pauseTime: Date?

    /// `pauseTime` freezes live timers at that instant (gallery screenshots); `nil` in the real activity.
    public init(display: LiveActivityDisplay, pauseTime: Date? = nil) {
        self.display = display
        self.pauseTime = pauseTime
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                LiveActivityMark(display: display, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    LiveActivityCaption(display: display, font: .caption)
                    Text(verbatim: display.title)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.8)
                    if let detail = display.detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let countdown = display.countdown {
                    // Value with its unit word under it ("24:59 / left", "1 h 30 min / until start"; H2).
                    WidgetCountdownText(countdown: countdown, pauseTime: pauseTime, alignment: .trailing)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130, alignment: .trailing)
                }
            }
            if display.progress != nil || display.next != nil {
                VStack(alignment: .leading, spacing: 4) {
                    LiveActivityProgressBar(display: display, pauseTime: pauseTime)
                    if let next = display.next {
                        Text(verbatim: next)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: display.accessibilityLabel))
    }
}

// MARK: - Dynamic Island, expanded

/// Expanded `.leading` region: badge and caption.
public struct LiveActivityExpandedLeading: View {
    private let display: LiveActivityDisplay

    public init(display: LiveActivityDisplay) {
        self.display = display
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 6) {
            LiveActivityMark(display: display, size: 28)
            LiveActivityCaption(display: display, font: .caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)   // the center region carries the whole sentence
    }
}

/// Expanded `.trailing` region: the live timer (or the compact text).
public struct LiveActivityExpandedTrailing: View {
    private let display: LiveActivityDisplay
    private let pauseTime: Date?

    public init(display: LiveActivityDisplay, pauseTime: Date? = nil) {
        self.display = display
        self.pauseTime = pauseTime
    }

    public var body: some View {
        Group {
            if let countdown = display.countdown {
                WidgetCountdownText(countdown: countdown, pauseTime: pauseTime, alignment: .trailing)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(verbatim: display.compactText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }
}

/// Expanded `.center` region: the title (carries the VoiceOver sentence of the expanded presentation).
public struct LiveActivityExpandedCenter: View {
    private let display: LiveActivityDisplay

    public init(display: LiveActivityDisplay) {
        self.display = display
    }

    public var body: some View {
        Text(verbatim: display.title)
            .font(.headline)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(Text(verbatim: display.accessibilityLabel))
    }
}

/// Expanded `.bottom` region: detail, next lesson and the live progress.
public struct LiveActivityExpandedBottom: View {
    private let display: LiveActivityDisplay
    private let pauseTime: Date?

    public init(display: LiveActivityDisplay, pauseTime: Date? = nil) {
        self.display = display
        self.pauseTime = pauseTime
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let detail = display.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            LiveActivityProgressBar(display: display, pauseTime: pauseTime)
            if let next = display.next {
                Text(verbatim: next)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Dynamic Island, compact and minimal

/// Compact leading: the badge (fits the 28 pt limited-width circle).
public struct LiveActivityCompactLeading: View {
    private let display: LiveActivityDisplay

    public init(display: LiveActivityDisplay) {
        self.display = display
    }

    public var body: some View {
        LiveActivityMark(display: display, size: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: display.title))
    }
}

/// Compact trailing: the live timer ("12:34"), or the start / end time without one.
public struct LiveActivityCompactTrailing: View {
    private let display: LiveActivityDisplay
    private let pauseTime: Date?

    public init(display: LiveActivityDisplay, pauseTime: Date? = nil) {
        self.display = display
        self.pauseTime = pauseTime
    }

    public var body: some View {
        Group {
            if let countdown = display.countdown {
                // Minutes only ("25 min"): the compact area has no room for mm:ss plus a unit word.
                WidgetCountdownText(countdown: countdown, pauseTime: pauseTime, layout: .valueOnly, minutesOnly: true)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(verbatim: display.compactText)
            }
        }
        .font(.callout.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: 58, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: display.timerAccessibilityLabel))
    }
}

/// Minimal: the badge (recognisable among other apps' activities; the timer would not fit 36.67 pt).
public struct LiveActivityMinimal: View {
    private let display: LiveActivityDisplay

    public init(display: LiveActivityDisplay) {
        self.display = display
    }

    public var body: some View {
        LiveActivityMark(display: display, size: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: display.timerAccessibilityLabel))
    }
}

// MARK: - Shared pieces

/// The subject badge, or an SF Symbol in a circle (exam without subject, finished day).
struct LiveActivityMark: View {
    let display: LiveActivityDisplay
    let size: CGFloat

    var body: some View {
        Group {
            if let subject = display.subject, display.phase != .finished || display.isExam {
                SubjectBadge(subject: subject, size: size)
            } else {
                Image(systemName: display.symbol)
                    .font(.system(size: size * 0.6, weight: .semibold))
                    // Text colours (not the accent / green): legible on every Lock Screen material and Always-On.
                    .foregroundStyle(display.phase == .finished ? HierarchicalShapeStyle.secondary : .primary)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The caption above the title: the highlighter "NOW" marker while a lesson runs (U7, replaces plain "Now"), else the
/// caption text.
struct LiveActivityCaption: View {
    let display: LiveActivityDisplay
    let font: Font

    var body: some View {
        if let caption = display.caption {
            if display.showsNowMarker {
                NowMarker(size: .small, label: caption).accessibilityHidden(true)
            } else {
                Text(verbatim: caption)
                    .font(font.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// Linear progress (live or paused) in the contrast-safe subject colour.
struct LiveActivityProgressBar: View {
    let display: LiveActivityDisplay
    let pauseTime: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if let pauseTime, display.progress != nil {
                ProgressView(value: display.progressValue(at: pauseTime))
            } else if let interval = display.progress {
                ProgressView(timerInterval: interval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .tint(tint)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        guard !isLuminanceReduced, let color = display.subject?.color else { return .secondary }
        return Color(LessonTileStyle.contrastSafeAccent(color, isDark: colorScheme == .dark))
    }
}
#endif
