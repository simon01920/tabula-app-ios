// SwiftUI views of the Now & Next widget, one per family, compiled into BOTH the widget extension (the real widget)
// and the app (the DEBUG `widgets.gallery` route renders them at their exact point sizes for CI screenshots, because a
// simulator cannot screenshot Home Screen widgets). They live in TimetableUI because both targets already link it on
// both build paths (no extra target to keep in sync) and Phase 5 can reuse them for watch complications; that is why
// they avoid iOS-only API (scripts/watch-typecheck.sh compiles TimetableUI for watchOS).
//
// The views only lay out a `NowNextDisplay` (NowNextPresentation.swift, Linux-tested). They add no container
// background: the extension applies `containerBackground(_:for: .widget)` (removable, so StandBy works), the gallery
// draws its own frame.
//
// Phase 4U U7: countdowns come from `NowNextDisplay.countdown` (WidgetCountdown.swift) and always carry a unit word
// ("left" / "until start"); from an hour on they are minutes only. Lock Screen families put the time first and use
// short subject names (M29); the current lesson wears U1's highlighter `NowMarker`.
// Live time: `Text(timerInterval:countsDown:showsHours:)` and `ProgressView(timerInterval:countsDown:)` — the system
// updates them without timeline reloads. With `pauseTime` (the gallery's fixed clock) static values are shown instead
// (`Text(timerInterval:pauseTime:)` showed the full interval when paused, see NowNextHeaderView).
// Rendering modes: in `.accented` / `.vibrant` (tinted Home Screen, Lock Screen, StandBy at night) subject colours carry
// no meaning, so the coloured badge becomes an outlined mark and the timer is the accent group (`widgetAccentable`).
// Text uses `.primary` / `.secondary` (legible in every mode); text on a subject colour uses LessonTileStyle's
// WCAG black/white (SubjectBadge). One VoiceOver sentence per widget (`accessibilityLabel`).
//
// APIs (Apple docs JSON, checked 2026-10-16; ENVIRONMENT.md §27): Text(timerInterval:pauseTime:countsDown:showsHours:)
//   iOS 16 / watchOS 9 (in widgets "horizontally flexible", so it gets a frame); ProgressView(timerInterval:countsDown:
//   label:currentValueLabel:) iOS 16 / watchOS 9 ("date-relative progress views … don't support custom styles";
//   `.circular` is a built-in style); EnvironmentValues.widgetRenderingMode + WidgetRenderingMode (.fullColor,
//   .accented, .vibrant) iOS 16 / watchOS 9; View.widgetAccentable(_:) iOS 16 / watchOS 9;
//   EnvironmentValues.showsWidgetContainerBackground iOS 15 / watchOS 8; AccessoryWidgetBackground iOS 16 / watchOS 9.
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

/// The Now & Next widget for one family.
public struct NowNextWidgetView: View {
    private let display: NowNextDisplay
    private let family: WidgetFamilyKind
    private let pauseTime: Date?

    /// `pauseTime` freezes live timers at that instant (gallery screenshots); `nil` in the real widget.
    public init(display: NowNextDisplay, family: WidgetFamilyKind, pauseTime: Date? = nil) {
        self.display = display
        self.family = family
        self.pauseTime = pauseTime
    }

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: display.accessibilityLabel))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall, .systemLarge, .systemExtraLarge:
            NowNextMainColumn(display: display, pauseTime: pauseTime, compact: false)
        case .systemMedium:
            NowNextMediumView(display: display, pauseTime: pauseTime)
        case .accessoryRectangular:
            NowNextRectangularView(display: display, pauseTime: pauseTime)
        case .accessoryCircular:
            NowNextCircularView(display: display, pauseTime: pauseTime)
        case .accessoryInline:
            NowNextInlineView(display: display, pauseTime: pauseTime)
        }
    }
}

/// "Available in Tabula Pro" in place of a gated family's content (never an empty or removed widget).
public struct WidgetProPlaceholderView: View {
    private let family: WidgetFamilyKind
    private let title: String
    private let short: String

    /// `title` / `short` come from `NowNextPresenter.proTexts()` (the app's language).
    public init(family: WidgetFamilyKind, title: String, short: String) {
        self.family = family
        self.title = title
        self.short = short
    }

    public var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label {
                    Text(verbatim: title)
                } icon: {
                    Image(AppSymbol.proLocked)
                }
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(AppSymbol.proLocked).font(.caption)
                        Text(verbatim: short).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .widgetAccentable()
                }
            default:
                HStack(alignment: .center, spacing: 8) {
                    Image(AppSymbol.proLocked).font(.title3).widgetAccentable()
                    Text(verbatim: title)
                        .font(.headline)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
    }
}

// MARK: - Shared pieces

/// The countdown of `display` with its unit word (H2): "24:59 left" under an hour, "1 h 30 min until start" from an hour on
/// (minutes only, never seconds). Nothing when the display has no countdown.
struct NowNextCountdown: View {
    let display: NowNextDisplay
    let pauseTime: Date?
    var layout: WidgetCountdownText.Layout = .stacked

    var body: some View {
        if let countdown = display.countdown {
            WidgetCountdownText(countdown: countdown, pauseTime: pauseTime, layout: layout)
        }
    }
}

/// Linear progress of the current lesson (live or paused).
struct NowNextProgressBar: View {
    let display: NowNextDisplay
    let pauseTime: Date?
    let tint: Color?

    var body: some View {
        Group {
            if let pauseTime {
                ProgressView(value: display.progress(at: pauseTime))
            } else if let interval = display.timer {
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
}

/// The subject badge in full colour; an outlined mark (accent group) when the system tints or desaturates the widget.
struct WidgetSubjectMark: View {
    let subject: SubjectSummary
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            SubjectBadge(subject: subject, size: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(lineWidth: 1.5)
                Text(verbatim: WidgetSubjectMark.label(for: subject))
                    .font(.system(size: size * 0.42, weight: .bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(2)
            }
            .frame(width: size, height: size)
            .widgetAccentable()
            .accessibilityHidden(true)
        }
    }

    /// Emoji, else short name, else initial (user data).
    static func label(for subject: SubjectSummary) -> String {
        if case .emoji(let emoji)? = subject.symbol { return emoji }
        return SubjectBadge.fallbackLabel(for: subject)
    }
}

/// The subject colour as a tint, only in full-colour rendering (elsewhere colours carry no meaning), made contrast-safe
/// against the widget background (`LessonTileStyle.contrastSafeAccent`, ≥ 3:1 for non-text UI).
private struct SubjectTint {
    static func color(_ subject: SubjectSummary, mode: WidgetRenderingMode, scheme: ColorScheme) -> Color? {
        guard mode == .fullColor else { return nil }
        return Color(LessonTileStyle.contrastSafeAccent(subject.color, isDark: scheme == .dark))
    }
}

/// One compact lesson row: badge, name, "when · room".
struct NowNextLessonRow: View {
    let line: NowNextDisplay.LessonLine

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            WidgetSubjectMark(subject: line.subject, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: line.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(verbatim: [line.whenText, line.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - systemSmall (and the left column of systemMedium)

struct NowNextMainColumn: View {
    let display: NowNextDisplay
    let pauseTime: Date?
    /// `true` in the medium family's left column (slightly smaller timer).
    let compact: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch display.kind {
            case .current(let lesson):
                HStack(alignment: .center, spacing: 6) {
                    WidgetSubjectMark(subject: lesson.subject, size: 24)
                    NowMarker(size: .small, label: display.caption ?? "").accessibilityHidden(true)
                }
                Text(verbatim: lesson.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(verbatim: lesson.room ?? lesson.timeRange)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                timer
                NowNextProgressBar(display: display, pauseTime: pauseTime,
                                   tint: SubjectTint.color(lesson.subject, mode: renderingMode, scheme: colorScheme))
                if let next = display.nextShort {
                    Text(verbatim: next)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .upcoming(let lesson):
                Text(verbatim: display.caption ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                HStack(alignment: .center, spacing: 6) {
                    WidgetSubjectMark(subject: lesson.subject, size: 24)
                    Text(verbatim: lesson.name)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Text(verbatim: [lesson.timeRange, lesson.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let badge = lesson.badgeText {
                    Label {
                        Text(verbatim: badge)
                    } icon: {
                        Image(AppSymbol.changed)
                    }
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                timer   // value + "until start" (H2)
            case let .status(symbol, title, detail):
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.ink)
                    .widgetAccentable()
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if let next = display.next {
                    Text(verbatim: display.nextCaption ?? "")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    NowNextLessonRow(line: next)
                } else if let nothing = display.nothingAhead {
                    Text(verbatim: nothing)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            case let .unavailable(title, detail):
                Image(AppSymbol.date)
                    .font(.title3)
                    .foregroundStyle(Color.ink)
                    .widgetAccentable()
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The value (live, rounded monospaced digits) with the unit word under it.
    private var timer: some View {
        NowNextCountdown(display: display, pauseTime: pauseTime)
            .font(.system(compact ? .title2 : .title, design: .rounded).weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetAccentable()
    }
}

// MARK: - systemMedium

struct NowNextMediumView: View {
    let display: NowNextDisplay
    let pauseTime: Date?

    /// Lessons for the right-hand column: after a current lesson its next lesson (same day) + the later ones;
    /// otherwise the later lessons of the next lesson's day.
    private var list: [NowNextDisplay.LessonLine] {
        if case .current = display.kind, let next = display.next {
            return Array(([next] + display.later).prefix(WidgetTimelinePlanner.maxLaterLessons))
        }
        return display.later
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NowNextMainColumn(display: display, pauseTime: pauseTime, compact: true)
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: display.laterCaption)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(list) { line in
                        NowNextLessonRow(line: line)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - accessoryRectangular

/// Lock Screen rectangle (U7, M29): time first, then a short name; nothing the eye needs is at the truncated end.
///   in a lesson   "24:59 left" / "SJL · 214" / "Next: BIO, 10:55"
///   before one    "Next 8:00 ANJ" / full name · room
///   after school  "Done for today" / "Next: BIO, Tomorrow, 8:00"
struct NowNextRectangularView: View {
    let display: NowNextDisplay
    let pauseTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch display.kind {
            case .current(let lesson):
                NowNextCountdown(display: display, pauseTime: pauseTime, layout: .inline)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .widgetAccentable()
                Text(verbatim: [lesson.shortName, lesson.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let next = display.nextCompact {
                    Text(verbatim: next).font(.caption).lineLimit(1)
                }
            case .upcoming(let lesson):
                Text(verbatim: display.inlineText)
                    .font(.system(.headline, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .widgetAccentable()
                Text(verbatim: [lesson.name, lesson.room].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(2)
            case let .status(_, title, _):
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(2)
                    .widgetAccentable()
                Text(verbatim: display.nextCompact ?? display.nothingAhead ?? "")
                    .font(.caption)
                    .lineLimit(2)
            case let .unavailable(title, detail):
                Text(verbatim: title).font(.headline).lineLimit(1).widgetAccentable()
                Text(verbatim: detail).font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - accessoryCircular

/// Lock Screen circle (U7, M29, L9).
///   in a lesson   a ring of the lesson's remaining time with the short name and the time left in the centre
///   before one    short name over the start time
///   after school  tomorrow's first start time (L9) under the next lesson's short name, a check mark only without one
///
/// Ring: HIG gauges.md › Anatomy: "accessory ... works well in iOS Lock Screen widgets" (`Gauge` +
/// `.gaugeStyle(.accessoryCircular)`, Apple docs checked 2026-10-23: `Gauge.init(value:in:label:currentValueLabel:)`;
/// `Gauge` has no timer-interval initialiser). A `Gauge`'s value is static between timeline entries, and entries exist
/// only at lesson boundaries, so the real widget keeps the system's live date-relative ring (`ProgressView(timerInterval:)`,
/// which the Lock Screen draws as the same ring) and the paused gallery uses the `Gauge`.
struct NowNextCircularView: View {
    let display: NowNextDisplay
    let pauseTime: Date?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch display.kind {
            case .current(let lesson):
                ring(label: lesson.shortName)
            case .upcoming(let lesson):
                labelOverTime(lesson.shortName, lesson.startText)
            case let .status(symbol, _, _):
                if let next = display.next, let time = display.nextStartText {
                    labelOverTime(next.shortName, time)
                } else {
                    Image(systemName: symbol).font(.title2).widgetAccentable()
                }
            case .unavailable:
                Image(AppSymbol.date).font(.title2).widgetAccentable()
            }
        }
    }

    private func labelOverTime(_ label: String, _ time: String) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: time)
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
        }
        .padding(6)
    }

    /// The short name and the time left, inside the ring.
    private func centre(label: String) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let countdown = display.countdown {
                WidgetCountdownText(countdown: countdown, pauseTime: pauseTime, layout: .valueOnly)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 44)
            }
        }
    }

    @ViewBuilder
    private func ring(label: String) -> some View {
        if let pauseTime {
            Gauge(value: 1 - display.progress(at: pauseTime)) {
                EmptyView()
            } currentValueLabel: {
                centre(label: label)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else if let interval = display.timer {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                centre(label: label)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        }
    }
}

// MARK: - accessoryInline

/// Lock Screen line above the clock (U7, M29): time first, then the short name.
///   in a lesson   "25 min · SJL"   (live, minutes only, so it always carries a unit)
///   before one    "Next 8:00 ANJ"
///   after school  "Done for today"
struct NowNextInlineView: View {
    let display: NowNextDisplay
    let pauseTime: Date?

    var body: some View {
        if case .current = display.kind, let countdown = display.countdown {
            // One catalog format ("%1$@ · %2$@", same in every language, so the extension's own lookup is fine) with the
            // live minutes as a `Text` argument (`Text + Text` is deprecated in iOS 26; LocalizedStringKey interpolation
            // of a Text is the documented replacement). The value is minutes only (`Text(date, style: .relative)` or the
            // static duration), never mm:ss, because the inline family has no room for a separate unit word.
            let name = Text(verbatim: display.inlineText)
            if pauseTime != nil {
                let remaining = Text(verbatim: countdown.durationText)
                Text("widget.nowNext.inline.current \(remaining) \(name)")
            } else {
                let remaining = Text(countdown.interval.upperBound, style: .relative)
                Text("widget.nowNext.inline.current \(remaining) \(name)")
            }
        } else {
            Text(verbatim: display.inlineText)
        }
    }
}
#endif
