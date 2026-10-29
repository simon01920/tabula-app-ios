// Weekday chips (UX overhaul M16): one button-style toggle per weekday, in the user's week order (`Weekday.week(
// startingAt:)` with `calendarContext.firstWeekday`, so Monday first for Slovak), instead of seven switch rows.
// Used by timetable settings (school days) and the bell schedule editor ("Used on").
//
// HIG toggles.md › "Outside of a list, use a button that behaves like a toggle" and "Make sure the visual differences in a
// toggle's state are obvious": on = filled, off = outlined (shape, not colour alone). VoiceOver gets a real switch
// (`accessibilityRepresentation`) named with the full weekday. Seven equal columns at standard sizes; at accessibility
// sizes the chips wrap into a grid with full names (no word-internal breaks: one line per chip).
// Colours: U1 tokens, on = `ink` fill with an `onInk` label (8.5:1 light, 8.8:1 dark), off = outline.
import SwiftUI
import TimetableCore
import TimetableUI

struct WeekdayChips: View {
    let days: [Weekday]
    let isOn: (Weekday) -> Bool
    let setOn: (Weekday, Bool) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.adaptive(minimum: 140), spacing: 8)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 6), count: max(1, days.count))
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(days, id: \.self) { day in
                Toggle(isOn: Binding(get: { isOn(day) }, set: { setOn(day, $0) })) {
                    Text(verbatim: model.formatter.weekdayName(day, width: typeSize.isAccessibilitySize ? .wide : .abbreviated))
                }
                .toggleStyle(WeekdayChipStyle())
                .accessibilityLabel(Text(verbatim: model.formatter.weekdayName(day)))
            }
        }
        .padding(.vertical, 4)
    }
}

/// On = filled with the tint, off = outlined. A plain button inside, so several chips in one form row stay separate
/// tap targets (a form row otherwise forwards a tap to every button in it).
private struct WeekdayChipStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(configuration.isOn ? Color.onInk : Color.primary)
                .background {
                    Capsule().fill(configuration.isOn ? Color.ink : Color.clear)
                }
                .overlay {
                    Capsule().strokeBorder(configuration.isOn ? Color.ink : Color.secondary, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
