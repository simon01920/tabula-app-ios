// SwiftUI views of the Next exam widget (Stage B1): systemSmall and the Lock Screen families accessoryRectangular /
// accessoryCircular; compiled into the widget extension and the app's DEBUG gallery (see NowNextWidgetViews.swift for why,
// and for the rendering-mode rules). They only lay out an `ExamDisplay` (NextExamPresentation.swift, Linux-tested). The
// extension sets one `widgetURL` (`tabula://open/exam/<id>`).
//
// The escalation level is an SF Symbol (calendar → calendar.badge.clock → exclamation → alarm → pencil → check) next to
// the countdown text, so the urgency is never colour alone. On the exam day the countdown to the start is a live
// `Text(timerInterval:)` (no reloads); with `pauseTime` (the gallery's fixed clock) a static value is shown instead.
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

/// The Next exam widget for one family.
public struct NextExamWidgetView: View {
    private let display: ExamDisplay
    private let family: WidgetFamilyKind
    private let pauseTime: Date?

    /// `pauseTime` freezes the live countdown at that instant (gallery screenshots); `nil` in the real widget.
    public init(display: ExamDisplay, family: WidgetFamilyKind, pauseTime: Date? = nil) {
        self.display = display
        self.family = family
        self.pauseTime = pauseTime
    }

    public var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: ExamRectangularView(display: display, pauseTime: pauseTime)
            case .accessoryCircular: ExamCircularView(display: display)
            default: ExamSmallView(display: display, pauseTime: pauseTime)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: display.accessibilityLabel))
    }
}

/// Live or paused remaining time of an exam's `timer`.
struct ExamTimerText: View {
    let timer: ClosedRange<Date>
    let pauseTime: Date?

    var body: some View {
        if let pauseTime {
            Text(verbatim: CountdownFormat.string(remaining: timer.upperBound.timeIntervalSince(max(pauseTime, timer.lowerBound))))
        } else {
            Text(timerInterval: timer, countsDown: true, showsHours: true)
        }
    }
}

// MARK: - systemSmall

struct ExamSmallView: View {
    let display: ExamDisplay
    let pauseTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch display.kind {
            case .exam(let info):
                HStack(alignment: .center, spacing: 6) {
                    if let subject = info.subject {
                        WidgetSubjectMark(subject: subject, size: 22)
                    } else {
                        Image(systemName: "pencil.and.list.clipboard").font(.title3).widgetAccentable()
                    }
                    Text(verbatim: info.subject?.name ?? display.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .widgetAccentable()
                }
                Text(verbatim: info.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(verbatim: info.smallLine)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let timer = info.timer {
                    Text(verbatim: info.whenLine)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ExamTimerText(timer: timer, pauseTime: pauseTime)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .widgetAccentable()
                } else {
                    Label {
                        Text(verbatim: info.whenText)
                    } icon: {
                        Image(systemName: info.symbol)
                    }
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                }
            case let .empty(title, detail):
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.title2)
                    .foregroundStyle(.tint)
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
            case let .unavailable(title, detail):
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.tint)
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
}

// MARK: - accessoryRectangular

struct ExamRectangularView: View {
    let display: ExamDisplay
    let pauseTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch display.kind {
            case .exam(let info):
                Text(verbatim: info.subject?.name ?? info.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: info.symbol)
                    if let timer = info.timer {
                        ExamTimerText(timer: timer, pauseTime: pauseTime)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(verbatim: info.whenText).lineLimit(1)
                    }
                }
                .font(.body.weight(.semibold))
                .widgetAccentable()
                Text(verbatim: info.rectangularLine)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            case let .empty(title, detail), let .unavailable(title, detail):
                Text(verbatim: title).font(.headline).lineLimit(1).widgetAccentable()
                Text(verbatim: detail).font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - accessoryCircular

struct ExamCircularView: View {
    let display: ExamDisplay

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch display.kind {
            case .exam(let info):
                VStack(spacing: 0) {
                    Image(systemName: info.symbol).font(.caption)
                    Text(verbatim: info.circularValue)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(4)
                .widgetAccentable()
            case .empty:
                Image(systemName: "pencil.and.list.clipboard").font(.title2).widgetAccentable()
            case .unavailable:
                Image(systemName: "calendar").font(.title2).widgetAccentable()
            }
        }
    }
}
#endif
