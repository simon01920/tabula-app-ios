// Settings → Calendar & time: week start, 12/24 h with a live sample, time-zone mode (+ fixed zone picker).
// Writes only via `model.apply(.settings { … })`; AppModel rebuilds the calendar context and formatters.
// APIs: Picker (menu style in Form), LabeledContent, NavigationLink, List + View.searchable(text:),
//       TimeZone.knownTimeZoneIdentifiers, DismissAction (EnvironmentValues.dismiss).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsCalendarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            weekStartSection
            hourCycleSection
            timeZoneSection
        }
        .navigationTitle(Text("settings.calendar.title"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
    }

    // MARK: Week start

    private var weekStartSection: some View {
        Section {
            Picker(selection: weekStart) {
                ForEach(WeekStartChoice.options(including: model.settings.weekStartOverride), id: \.self) { choice in
                    switch choice {
                    case .system: Text("settings.calendar.weekstart.system").tag(choice)
                    case .weekday(let day): Text(model.formatter.weekdayName(day)).tag(choice)
                    }
                }
            } label: {
                Text("settings.calendar.weekstart.title")
            }
        }
    }

    private var weekStart: Binding<WeekStartChoice> {
        Binding(get: { WeekStartChoice(model.settings.weekStartOverride) }, set: { choice in
            let value = choice.override
            model.apply(.settings { $0.weekStartOverride = value })
        })
    }

    // MARK: 12/24 h

    private var hourCycleSection: some View {
        Section {
            Picker(selection: hourCycle) {
                Text("settings.calendar.hourcycle.system").tag(HourCycleChoice.system)
                Text("settings.calendar.hourcycle.h12").tag(HourCycleChoice.h12)
                Text("settings.calendar.hourcycle.h24").tag(HourCycleChoice.h24)
            } label: {
                Text("settings.calendar.hourcycle.title")
            }
            LabeledContent {
                Text(sampleTime)
            } label: {
                Text("settings.calendar.hourcycle.example")
            }
        }
    }

    private var hourCycle: Binding<HourCycleChoice> {
        Binding(get: { HourCycleChoice(model.settings.hourCycle) }, set: { choice in
            let value = choice.hourCycle
            model.apply(.settings { $0.hourCycle = value })
        })
    }

    /// The current time as the stored preference shows it (live: follows the picker immediately).
    private var sampleTime: String { model.formatter.time(model.now) }

    // MARK: Time zone

    private var timeZoneSection: some View {
        let mode = model.settings.timeZoneMode
        return Section {
            Picker(selection: timeZoneKind) {
                Text("settings.calendar.timezone.follow").tag(TimeZoneModeKind.followDevice)
                Text("settings.calendar.timezone.fixed").tag(TimeZoneModeKind.fixed)
            } label: {
                Text("settings.calendar.timezone.title")
            }
            switch mode {
            case .followDevice:
                LabeledContent {
                    Text(TimeZoneChoices.displayName(model.environment.deviceTimeZone().identifier))
                } label: {
                    Text("settings.calendar.timezone.device")
                }
            case .fixed(let identifier):
                NavigationLink {
                    TimeZonePickerView(selected: identifier)
                } label: {
                    LabeledContent {
                        Text(TimeZoneChoices.displayName(identifier))
                    } label: {
                        Text("settings.calendar.timezone.zone")
                    }
                }
            }
        } footer: {
            switch mode {
            case .followDevice: Text("settings.calendar.timezone.footer.follow")
            case .fixed: Text("settings.calendar.timezone.footer.fixed")
            }
        }
    }

    private var timeZoneKind: Binding<TimeZoneModeKind> {
        Binding(get: { TimeZoneModeKind(model.settings.timeZoneMode) }, set: { kind in
            let device = model.environment.deviceTimeZone()
            let next = TimeZoneChoices.mode(kind: kind, current: model.settings.timeZoneMode, deviceZone: device)
            model.apply(.settings { $0.timeZoneMode = next })
        })
    }
}

/// Searchable list of IANA time zones; choosing one stores `.fixed(identifier:)`.
struct TimeZonePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let selected: String
    @State private var query = ""

    var body: some View {
        let rows = TimeZoneChoices.identifiers(matching: query, current: selected)
        List(rows, id: \.self) { identifier in
            Button {
                model.apply(.settings { $0.timeZoneMode = .fixed(identifier: identifier) })
                dismiss()
            } label: {
                HStack {
                    Text(TimeZoneChoices.displayName(identifier)).foregroundStyle(.primary)
                    Spacer()
                    if identifier == selected {
                        Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(identifier == selected ? .isSelected : [])
        }
        .searchable(text: $query, prompt: Text("settings.calendar.timezone.search"))
        .navigationTitle(Text("settings.calendar.timezone.zone"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
    }
}
