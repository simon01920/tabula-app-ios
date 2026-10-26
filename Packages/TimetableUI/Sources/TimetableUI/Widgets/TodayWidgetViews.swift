// SwiftUI views of the Today widget (Stage B1), medium and large; compiled into the widget extension and the app's DEBUG
// gallery (see NowNextWidgetViews.swift for why, and for the rendering-mode rules). They only lay out a `TodayDisplay`
// (TodayPresentation.swift, Linux-tested). The extension sets one `widgetURL` (the Today tab).
//
// Row: start time · subject badge · name (struck through when cancelled) · change icon · room; a change / "Cancelled"
// text line under the name; the lesson in progress sits on a tinted plate with a leading bar (shape + weight, not colour
// alone); lessons that are over are dimmed. One VoiceOver sentence per widget (`TodayDisplay.accessibilityLabel(for:)`).
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

/// The Today widget for one family (medium or large).
public struct TodayWidgetView: View {
    private let display: TodayDisplay
    private let family: WidgetFamilyKind

    public init(display: TodayDisplay, family: WidgetFamilyKind) {
        self.display = display
        self.family = family
    }

    public var body: some View {
        Group {
            switch display.kind {
            case .lessons(let day):
                TodayLessonsColumn(display: display, day: day, family: family)
            case let .status(symbol, title, detail, next, nextCaption, nothingAhead):
                TodayStatusColumn(symbol: symbol, title: title, detail: detail, next: next, nextCaption: nextCaption,
                                  nothingAhead: nothingAhead)
            case let .unavailable(title, detail):
                TodayUnavailableColumn(title: title, detail: detail)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: display.accessibilityLabel(for: family)))
    }
}

private struct TodayLessonsColumn: View {
    let display: TodayDisplay
    let day: TodayDisplay.Day
    let family: WidgetFamilyKind

    private var isLarge: Bool { family == .systemLarge || family == .systemExtraLarge }

    var body: some View {
        let shown = display.visibleRows(for: family)
        VStack(alignment: .leading, spacing: isLarge ? 4 : 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: day.header)
                    .font(.headline)
                    .widgetAccentable()
                Spacer(minLength: 4)
                Text(verbatim: day.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ForEach(shown.rows) { row in
                TodayLessonRow(row: row)
            }
            if shown.hidden > 0 {
                Text(verbatim: display.moreText(shown.hidden))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if isLarge, !day.dueTasks.isEmpty {
                Divider()
                Text(verbatim: day.dueTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                ForEach(day.dueTasks) { line in
                    HomeworkRowContent(line: line)
                }
                if day.hiddenDue > 0 {
                    Text(verbatim: display.moreText(day.hiddenDue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One lesson of the day.
struct TodayLessonRow: View {
    let row: TodayDisplay.Row
    /// Time column and badge scale with Dynamic Type instead of being fixed widths.
    @ScaledMetric(relativeTo: .caption) private var timeWidth: CGFloat = 42
    @ScaledMetric(relativeTo: .caption) private var markSize: CGFloat = 16

    var body: some View {
        let line = row.line
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text(verbatim: line.startText)
                    .font(.caption.weight(row.isCurrent ? .bold : .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: timeWidth, alignment: .leading)
                WidgetSubjectMark(subject: line.subject, size: markSize)
                Text(verbatim: line.name)
                    .font(.caption.weight(.semibold))
                    .strikethrough(row.isCancelled)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let symbol = row.badgeSymbol {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                }
                if let room = line.room {
                    Text(verbatim: room)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let badge = line.badgeText {
                Text(verbatim: badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, timeWidth + markSize + 12)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, row.isCurrent ? 4 : 0)
        .background {
            if row.isCurrent {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().frame(width: 3).padding(.vertical, 2).widgetAccentable()
                    }
            }
        }
        .opacity(row.isPast && !row.isCurrent ? 0.5 : 1)
    }
}

private struct TodayStatusColumn: View {
    let symbol: String
    let title: String
    let detail: String?
    let next: NowNextDisplay.LessonLine?
    let nextCaption: String?
    let nothingAhead: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
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
            if let next {
                if let nextCaption {
                    Text(verbatim: nextCaption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                NowNextLessonRow(line: next)
            } else if let nothingAhead {
                Text(verbatim: nothingAhead)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TodayUnavailableColumn: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(AppSymbol.date)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
