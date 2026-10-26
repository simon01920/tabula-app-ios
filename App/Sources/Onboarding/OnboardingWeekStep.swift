// Onboarding step 3 · "Your week" (F07): school days as chips, "How does your timetable repeat?" with an explicit
// anchor per pattern, and optional term dates (a separate toggle, available with every pattern).
// The mapping onto the frozen rotation model lives in `OnboardingDraft.rotationScheme(firstWeekday:)` (TimetableUI,
// Linux-tested): alternating weeks = a 2-week cycle anchored on this week (or calendar odd/even weeks with the matching
// offset); alternating days = a 2-day cycle anchored on today / the next school day; custom = 3…6-week cycle.
// HIG: segmented-controls.md (two closely related choices, noun labels), toggles.md, layout.md › progressive disclosure.
// APIs: Picker + PickerStyle.segmented / .menu, Toggle(isOn:label:), DatePicker(selection:displayedComponents:label:),
//       View.environment(\.timeZone, _) / (\.calendar, _). Dates are edited as `Date` and converted with CalendarContext.
import SwiftUI
import TimetableCore
import TimetableUI

struct WeekStepView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(AppModel.self) private var model

    private var draft: OnboardingDraft { flow.draft }
    private var firstWeekday: Weekday { model.calendarContext.firstWeekday }

    var body: some View {
        StepScaffold(title: "onboarding.week.title", subtitle: "onboarding.week.subtitle",
                     actionTitle: "onboarding.action.continue", actionEnabled: draft.canAdvance(from: .week)) {
            flow.advance(from: .week)
        } content: {
            OnboardingSectionHeader(title: "onboarding.week.days.title")
            OnboardingCard {
                WeekdayChips(days: OnboardingDraft.orderedWeekdays(firstWeekday: firstWeekday),
                             isOn: { draft.enabledDays.contains($0) },
                             toggle: { day in flow.draft.set(day, enabled: !flow.draft.enabledDays.contains(day)) },
                             shortName: { model.formatter.weekdayName($0, width: .abbreviated) },
                             fullName: { model.formatter.weekdayName($0) })
                if draft.enabledDays.isEmpty {
                    OnboardingErrorLine(text: "onboarding.week.days.empty")
                }
            }
            OnboardingSectionHeader(title: "onboarding.week.repeat.title")
            VStack(spacing: 12) {
                ForEach(draft.availableRotations, id: \.self) { choice in
                    OnboardingChoiceRow(title: Self.title(of: choice), detail: Self.detail(of: choice),
                                        systemImage: Self.symbol(of: choice), isSelected: draft.rotation == choice) {
                        flow.draft.rotation = choice
                    }
                }
            }
            switch draft.rotation {
            case .alternatingWeeks: alternatingWeeksCard
            case .alternatingDays: alternatingDaysCard
            case .customCycle: customCycleCard
            case .none: EmptyView()
            }
            termCard
        }
    }

    // MARK: Anchors

    private var alternatingWeeksCard: some View {
        OnboardingCard {
            Text("onboarding.week.anchor.week").font(.headline).fixedSize(horizontal: false, vertical: true)
            Picker(selection: cycleWeek) {
                Text("onboarding.week.weekA").tag(1)
                Text("onboarding.week.weekB").tag(2)
            } label: {
                Text("onboarding.week.anchor.week")
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            Toggle(isOn: $flow.draft.followsCalendarParity) {
                Text("onboarding.week.parity.toggle").fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            Text(verbatim: weeksFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shows the mapping explicitly: with calendar parity, which parity Week A has and this week's number.
    private var weeksFooter: String {
        guard draft.followsCalendarParity else { return model.renderer.string(forKey: "onboarding.week.anchor.week.footer") }
        let week = Int64(draft.currentISOWeek(firstWeekday: firstWeekday).week)
        let key = draft.weekAIsOdd(firstWeekday: firstWeekday) ? "onboarding.week.parity.oddA" : "onboarding.week.parity.evenA"
        return model.renderer.format(key: key, arguments: [.integer(week)])
    }

    private var alternatingDaysCard: some View {
        let anchor = draft.dayCycleAnchorDate
        let question = anchor == draft.today
            ? model.renderer.string(forKey: "onboarding.week.anchor.day.today")
            : model.renderer.format(key: "onboarding.week.anchor.day.date",
                                    arguments: [.text(model.formatter.date(anchor, style: .weekdayDayMonth))])
        return OnboardingCard {
            Text(verbatim: question).font(.headline).fixedSize(horizontal: false, vertical: true)
            Picker(selection: $flow.draft.currentCycleDay) {
                Text("onboarding.week.dayA").tag(1)
                Text("onboarding.week.dayB").tag(2)
            } label: {
                Text(verbatim: question)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            Text("onboarding.week.anchor.day.footer")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var customCycleCard: some View {
        OnboardingCard {
            OnboardingStepper(titleKey: "onboarding.rotation.cycleLength", value: $flow.draft.customCycleLength,
                              range: OnboardingDraft.customCycleLengths) { weeks in
                model.renderer.format(key: "onboarding.rotation.cycleLength.value", arguments: [.integer(Int64(weeks))])
            }
            Picker(selection: cycleWeek) {
                ForEach(1...draft.cycleWeekCount, id: \.self) { week in
                    Text(verbatim: model.renderer.format(key: "timetable.cycle.numberedWeek",
                                                         arguments: [.integer(Int64(week))])).tag(week)
                }
            } label: {
                Text("onboarding.week.anchor.week").fixedSize(horizontal: false, vertical: true)
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
        }
    }

    /// The chosen week, kept within the (possibly shortened) cycle.
    private var cycleWeek: Binding<Int> {
        Binding(get: { flow.draft.effectiveCycleWeek }, set: { flow.draft.currentCycleWeek = $0 })
    }

    // MARK: Term dates

    private var termCard: some View {
        OnboardingCard {
            Toggle(isOn: $flow.draft.termEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("onboarding.term.title").fixedSize(horizontal: false, vertical: true)
                    Text("onboarding.term.footer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 44)
            if draft.termEnabled {
                DatePicker(selection: dateBinding(\.termStart), displayedComponents: .date) {
                    Text("onboarding.term.start")
                }
                .frame(minHeight: 44)
                DatePicker(selection: dateBinding(\.termEnd), displayedComponents: .date) {
                    Text("onboarding.term.end")
                }
                .frame(minHeight: 44)
                switch draft.termIssue {
                case .endBeforeStart?: OnboardingErrorLine(text: "onboarding.term.error.endBeforeStart")
                case .tooLong?: OnboardingErrorLine(text: "onboarding.term.error.tooLong")
                case nil: EmptyView()
                }
            }
        }
        .environment(\.timeZone, model.calendarContext.timeZone)
        .environment(\.calendar, model.calendarContext.calendar)
    }

    private func dateBinding(_ keyPath: WritableKeyPath<OnboardingDraft, LocalDate>) -> Binding<Date> {
        let context = model.calendarContext
        return Binding(get: { context.startOfDay(flow.draft[keyPath: keyPath]) },
                       set: { flow.draft[keyPath: keyPath] = context.localDate(of: $0) })
    }

    // MARK: Labels

    private static func title(of choice: RotationChoice) -> LocalizedStringKey {
        switch choice {
        case .none: return "onboarding.week.repeat.none"
        case .alternatingWeeks: return "onboarding.week.repeat.alternatingWeeks"
        case .alternatingDays: return "onboarding.week.repeat.alternatingDays"
        case .customCycle: return "onboarding.week.repeat.customCycle"
        }
    }

    private static func detail(of choice: RotationChoice) -> LocalizedStringKey? {
        switch choice {
        case .none: return nil
        case .alternatingWeeks: return "onboarding.week.repeat.alternatingWeeks.detail"
        case .alternatingDays: return "onboarding.week.repeat.alternatingDays.detail"
        case .customCycle: return "onboarding.week.repeat.customCycle.detail"
        }
    }

    private static func symbol(of choice: RotationChoice) -> String {
        switch choice {
        case .none: return "calendar"
        case .alternatingWeeks: return "arrow.left.arrow.right"
        case .alternatingDays: return "arrow.triangle.2.circlepath"
        case .customCycle: return "repeat"
        }
    }
}
