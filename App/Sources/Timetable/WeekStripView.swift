// The week strip: a navigation bar (previous/next week, the week's date range, the cycle label "Week A") and, for
// day-based views, the row of day pills (selected-day pill, today marker, change dot). Week-based views (grid,
// time blocks) draw the same day data as their column headers (`DayColumnHeader`) so the columns line up.
// The dot never carries meaning alone: each day's VoiceOver label says "2 changes" (`WeekStripModel`).
// APIs: Button, Image(systemName:), Capsule, Circle, accessibilityLabel(_:), accessibilityAddTraits(.isSelected /
//       .isHeader), accessibilityHint(_:), @ScaledMetric, Environment(\.dynamicTypeSize).
import SwiftUI
import TimetableCore
import TimetableUI

/// Previous / range + cycle label / next.
struct WeekNavigationBar: View {
    let strip: WeekStripModel
    let onPrevious: () -> Void
    let onNext: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.backward")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("timetable.week.previous"))
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Text(verbatim: rangeText)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let cycle = strip.cycleWeek {
                    Text(verbatim: cycle.text(renderer: model.renderer))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.tint.opacity(0.15)))
                        .overlay(Capsule().strokeBorder(.tint, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(action: onNext) {
                Image(systemName: "chevron.forward")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text("timetable.week.next"))
        }
        .font(.body.weight(.semibold))
    }

    private var rangeText: String {
        let first = strip.days.first?.date ?? strip.weekStart
        let last = strip.days.last?.date ?? strip.weekStart.adding(days: 6)
        return model.renderer.format(key: "timetable.week.range", arguments: [
            .text(model.formatter.date(first, style: .dayMonth)), .text(model.formatter.date(last, style: .dayMonth)),
        ])
    }
}

/// The row of day pills for day-based views.
struct WeekDayStrip: View {
    let strip: WeekStripModel
    let onSelect: (LocalDate) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(strip.days) { day in
                Button {
                    onSelect(day.date)
                } label: {
                    DayColumnHeader(day: day, showsSelection: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One day's header: short weekday, day number (filled circle = today, pill = selected), change dot, day-cycle label.
struct DayColumnHeader: View {
    let day: WeekStripDay
    var showsSelection = false
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 30

    var body: some View {
        let selected = showsSelection && day.isSelected
        VStack(spacing: 3) {
            Text(verbatim: model.formatter.weekdayName(day.date.weekday, width: .abbreviated))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: day.date.day.formatted())
                .font(.callout.weight(day.isToday || selected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? Color.white : Color.primary)
                .frame(minWidth: circle, minHeight: circle)
                .background {
                    if day.isToday {
                        Circle().fill(Color.red)   // white on system red ≥ 4.5:1 (same as Calendar's today marker)
                    } else if selected {
                        Circle().strokeBorder(Color.primary, lineWidth: 1.5)
                    }
                }
            // Change dot (meaning also in the VoiceOver label); a fixed-height slot keeps the rows aligned.
            Circle()
                .fill(day.hasChanges ? Color.orange : Color.clear)
                .frame(width: 6, height: 6)
            if let cycle = day.cycleDay {
                Text(verbatim: cycle.text(renderer: model.renderer))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.vertical, 4)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: WeekStripModel.accessibilityLabel(day, renderer: model.renderer)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
