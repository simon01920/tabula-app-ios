// A day's timeline as tiles with break / lunch / free-period separators (`TodayState.timeline`), shared by Today
// and the big-tiles view, plus the empty state of a day (holiday, cancelled day, no lessons).
// Durations use Foundation's locale-aware `Duration.UnitsFormatStyle` ("10 min", "1 hr, 35 min").
// APIs: LazyVStack, Button(.plain), Duration.formatted(.units(allowed:width:)) (iOS 16), ContentUnavailableView.
import SwiftUI
import TimetableCore
import TimetableUI

struct TimelineItemsView: View {
    let items: [TodayItem]
    let visibility: FieldVisibility
    var size: LessonTileSize = .regular
    var density: Density = .comfortable
    let onOpen: (ResolvedLesson) -> Void

    var body: some View {
        ForEach(items) { item in
            switch item {
            case let .lesson(lesson, reasons, timing):
                Button {
                    onOpen(lesson)
                } label: {
                    LessonTileView(lesson: lesson, reasons: reasons, visibility: visibility, timing: timing, size: size,
                                   density: density)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("timetable.a11y.openHint"))
            case let .gap(start, end, kind):
                GapSeparatorView(start: start, end: end, kind: kind)
            }
        }
    }
}

/// "Break · 10 min" between two tiles.
struct GapSeparatorView: View {
    let start: LocalTime
    let end: LocalTime
    let kind: TodayItem.GapKind
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            line
            Label {
                Text(verbatim: model.renderer.format(key: key, arguments: [.text(duration)]))
            } icon: {
                Image(systemName: symbol)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .layoutPriority(1)
            line
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1).accessibilityHidden(true)
    }

    private var duration: String {
        Duration.seconds(start.minutes(to: end) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(model.formatter.locale))
    }

    private var key: String {
        switch kind {
        case .lunch: return "today.gap.lunch"
        case .freePeriod: return "today.gap.free"
        case .breakTime: return "today.gap.break"
        }
    }

    private var symbol: String {
        switch kind {
        case .lunch: return "fork.knife"
        case .freePeriod: return "cup.and.heat.waves"
        case .breakTime: return "figure.walk"
        }
    }
}

/// Why a day has no lessons, as a content-unavailable view.
struct DayEmptyView: View {
    let schedule: DaySchedule
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
        } description: {
            Text(verbatim: model.formatter.date(schedule.date, style: .full))
        } actions: {
            EmptyView()
        }
    }

    private var title: String {
        if let id = schedule.activeBreakID {
            let name = model.database?.breaks.first { $0.id == id }?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty { return name }
            return model.renderer.string(forKey: "timetable.day.holiday")
        }
        if schedule.cancellingOverrideID != nil { return model.renderer.string(forKey: "timetable.day.cancelled") }
        return model.renderer.string(forKey: "timetable.day.noLessons")
    }

    private var symbol: String {
        if schedule.activeBreakID != nil { return "beach.umbrella" }
        if schedule.cancellingOverrideID != nil { return "xmark.circle" }
        return "moon.zzz"
    }
}
