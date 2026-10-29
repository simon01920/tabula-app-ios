// Day headers of the Timetable tab (Phase 4U U4). The week's date range and rotation phrase moved to the navigation
// subtitle and previous / next week to the toolbar (TimetableRootView); what stays here:
// - `WeekDayStrip`: the row of day pills for day-based views (selected day = tinted pill, today = filled ink circle;
//   the two never look alike, Astra F20);
// - `DayColumnHeader`: one day's header, shared with the grid and week columns (today's column header is tinted,
//   Opus H5); a day with changes shows a small `exclamationmark.circle` instead of the unexplained orange dot, and its
//   VoiceOver sentence says "2 changes" (`WeekStripModel`);
// - `DayPagerHeader`: the compact header of day views at accessibility text sizes (Astra F03): previous day, a date
//   picker and next day instead of five weekday columns.
// APIs: Button, Image(systemName:), Circle, RoundedRectangle, DatePicker(.compact) bridged with `LocalDateBridge`,
//       ViewThatFits, accessibilityLabel(_:), accessibilityAddTraits(.isSelected / .isHeader), @ScaledMetric.
import SwiftUI
import TimetableCore
import TimetableUI

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

/// One day's header: short weekday, day number (filled ink circle = today; tinted pill = selected), the change symbol,
/// the day-cycle label. In week columns (`showsSelection == false`) today's whole header is tinted.
struct DayColumnHeader: View {
    let day: WeekStripDay
    var showsSelection = false
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 30
    @ScaledMetric(relativeTo: .caption2) private var markerHeight: CGFloat = 11

    var body: some View {
        let selected = showsSelection && day.isSelected
        VStack(spacing: 3) {
            Text(verbatim: model.formatter.weekdayName(day.date.weekday, width: .abbreviated))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(selected || day.isToday ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: day.date.day.formatted())
                .font(.callout.weight(day.isToday || selected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(day.isToday ? Color.onInk : Color.primary)
                .frame(minWidth: circle, minHeight: circle)
                .background {
                    // Ink, not red: red means "cancelled / overdue" only (UX plan D1). White on #2541B2 8.5:1;
                    // black on the dark-mode ink #8EA2FF 8.8:1.
                    if day.isToday { Circle().fill(Color.ink) }
                }
            // A fixed-height slot keeps the rows aligned; the meaning is also in the VoiceOver sentence.
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: markerHeight, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .opacity(day.hasChanges ? 1 : 0)
                .frame(height: markerHeight)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.16))
            } else if !showsSelection && day.isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(0.12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: WeekStripModel.accessibilityLabel(day, renderer: model.renderer)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Day views at accessibility text sizes: ‹ previous day · date picker · next day › (stacks when it does not fit).
struct DayPagerHeader: View {
    let date: LocalDate
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPick: (LocalDate) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                previous
                Spacer(minLength: 0)
                picker
                Spacer(minLength: 0)
                next
            }
            VStack(spacing: 4) {
                picker
                HStack {
                    previous
                    Spacer(minLength: 0)
                    next
                }
            }
        }
        .font(.body.weight(.semibold))
    }

    private var previous: some View {
        Button(action: onPrevious) {
            Image(systemName: "chevron.backward").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("timetable.day.previous"))
    }

    private var next: some View {
        Button(action: onNext) {
            Image(systemName: "chevron.forward").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text("timetable.day.next"))
    }

    private var picker: some View {
        DatePicker(selection: Binding(
            get: { LocalDateBridge.instant(date) },
            set: { onPick(LocalDateBridge.date($0, fallback: date)) }
        ), displayedComponents: .date) {
            Text("timetable.day.pick")
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .environment(\.timeZone, LocalDateBridge.timeZone)
        .environment(\.calendar, LocalDateBridge.calendar(locale: model.environment.locale()))
    }
}
