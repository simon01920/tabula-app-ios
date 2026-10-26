// Navigation state of the Timetable tab, without SwiftUI: which week and day are shown, how the week moves, how
// "show week A/B" jumps, which view kind is used and how a cycle position is labelled. Pure, Linux-tested.
//
// Week arithmetic uses the *display* week start (`CalendarContext.firstWeekday`, user/locale setting); rotation
// arithmetic stays with `RotationResolver` (the timetable's own `rotationWeekStart`), as GridLayout does.
import Foundation
import TimetableCore

/// How a rotation position is shown ("Week A", "Odd week", "Week 2", "Day B", "Day 3"). Every label is one complete
/// catalog phrase (`catalogKey` + optional `argument`); a user label is never glued after "Week " unless it is a
/// short token such as "A", "2" or "II" (D11 / Opus M3: "Week " + "Párny" produced "Week Párny").
public enum CycleLabel: Equatable, Sendable {
    /// A cycle week named by a short token: the user's "A"/"B"/"2", or a derived letter for A/B weeks ("Week %@").
    case namedWeek(String)
    /// A numbered cycle week (cycles of 3+ weeks without labels).
    case numberedWeek(Int)
    /// A two-week cycle counted by the printed ISO week number: "Odd week" / "Even week" (own catalog phrases).
    case parityWeek(isOdd: Bool)
    /// A user label that is a word or phrase ("Párny", "Blue week"): shown as written, never prefixed.
    case customWeek(String)
    /// A cycle day named by a short token ("Day %@").
    case namedDay(String)
    /// A numbered cycle day.
    case numberedDay(Int)
    /// A user day label that is a word or phrase: shown as written.
    case customDay(String)

    /// Longest non-numeric user label that is still treated as a token after "Week"/"Day" ("A", "B", "A1", "II").
    public static let maximumTokenLength = 2

    /// `true` for labels such as "A", "II" or "12" that read as a name after "Week"/"Day"; `false` for words such as
    /// "Odd" or "Párny" (shown as written instead).
    public static func isToken(_ label: String) -> Bool {
        guard !label.isEmpty, !label.contains(where: \.isWhitespace) else { return false }
        return label.count <= maximumTokenLength || label.allSatisfy(\.isNumber)
    }

    /// The label of a week-cycle week, or `nil` without a week cycle.
    ///
    /// Order: the user's label (a short token → "Week A", a word → the word itself); else, for a two-week cycle
    /// anchored to the printed (strict) ISO week number, "Odd week" / "Even week"; else "Week A"/"Week B" for two
    /// weeks and "Week n" for longer cycles. A continuous parity count alternates strictly and can disagree with the
    /// printed number after a 53-week year, so it keeps A/B.
    public static func week(_ cycleWeek: Int?, scheme: RotationScheme, userLabel: String?) -> CycleLabel? {
        guard case .weekCycle(let cycle) = scheme, let cycleWeek else { return nil }
        if let label = userLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return isToken(label) ? .namedWeek(label) : .customWeek(label)
        }
        if cycle.length == 2, (1...2).contains(cycleWeek) {
            if case let .isoWeekParity(policy, offset) = cycle.anchor, policy.effective == .strict {
                // WeekParity.cycleWeek: cycle week = (isoWeek - 1 + offset) mod 2 + 1, so the ISO week is odd
                // exactly when (cycleWeek - 1 - offset) is even. `offset` is persisted data: reduce it first
                // (no overflow for hostile values).
                let shift = (offset % 2 + 2) % 2
                return .parityWeek(isOdd: (cycleWeek - 1 - shift + 2) % 2 == 0)
            }
            return .namedWeek(cycleWeek == 1 ? "A" : "B")
        }
        return .numberedWeek(cycleWeek)
    }

    /// The label of a day-cycle day, or `nil` unless `dayKey` is a cycle day.
    public static func day(_ dayKey: DayKey?, userLabel: String?) -> CycleLabel? {
        guard case .cycleDay(let index)? = dayKey else { return nil }
        if let label = userLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return isToken(label) ? .namedDay(label) : .customDay(label)
        }
        return .numberedDay(index)
    }

    /// The label of a resolved day: its cycle day for day cycles, else its cycle week.
    public static func of(_ day: DaySchedule, scheme: RotationScheme) -> CycleLabel? {
        switch scheme {
        case .none: return nil
        case .weekCycle: return week(day.cycleWeek, scheme: scheme, userLabel: day.cycleLabel)
        case .dayCycle: return CycleLabel.day(day.dayKey, userLabel: day.cycleLabel)
        }
    }

    /// Catalog keys of every rotation phrase (for `DynamicL10nKeys`).
    public static let allCatalogKeys = [
        "timetable.cycle.namedWeek", "timetable.cycle.numberedWeek", "timetable.cycle.oddWeek",
        "timetable.cycle.evenWeek", "timetable.cycle.namedDay", "timetable.cycle.numberedDay",
    ]

    /// Catalog key of the phrase; `nil` for user labels shown as written.
    public var catalogKey: String? {
        switch self {
        case .namedWeek: return "timetable.cycle.namedWeek"
        case .numberedWeek: return "timetable.cycle.numberedWeek"
        case .parityWeek(let isOdd): return isOdd ? "timetable.cycle.oddWeek" : "timetable.cycle.evenWeek"
        case .namedDay: return "timetable.cycle.namedDay"
        case .numberedDay: return "timetable.cycle.numberedDay"
        case .customWeek, .customDay: return nil
        }
    }

    /// The format argument, if the phrase has one.
    public var argument: CatalogArgument? {
        switch self {
        case .namedWeek(let text), .namedDay(let text), .customWeek(let text), .customDay(let text): return .text(text)
        case .numberedWeek(let number), .numberedDay(let number): return .integer(Int64(number))
        case .parityWeek: return nil
        }
    }

    /// The rendered text ("Week A", "Odd week", or the user's own label).
    public func text(renderer: LocalizedTextRenderer) -> String {
        switch self {
        case .customWeek(let label), .customDay(let label):
            return label
        default:
            guard let key = catalogKey else { return "" }
            return renderer.format(key: key, arguments: argument.map { [$0] } ?? [])
        }
    }
}

/// The views the Timetable tab offers (subset of `TimetableViewKind`).
public enum TimetableViewChoice {
    /// Offered views, in menu order.
    public static let offered: [TimetableViewKind] = [.grid, .timeBlocks, .day, .tiles]

    /// The view to show for a stored kind: known offered kinds as they are, `.agenda` (the Today tab covers it) → day,
    /// unknown kinds from newer versions → grid (the stored value is left untouched).
    public static func resolve(_ kind: TimetableViewKind) -> TimetableViewKind {
        if offered.contains(kind) { return kind }
        return kind == .agenda ? .day : .grid
    }

    /// SF Symbol of a view kind.
    public static func symbolName(_ kind: TimetableViewKind) -> String {
        switch resolve(kind) {
        case .grid: return "square.grid.3x3"
        case .timeBlocks: return "calendar.day.timeline.left"
        case .tiles: return "rectangle.grid.1x2"
        default: return "list.bullet.rectangle"
        }
    }

    /// Catalog key of a view kind's name.
    public static func nameKey(_ kind: TimetableViewKind) -> String {
        "timetable.view.\(resolve(kind).rawValue)"
    }

    /// `true` for views that show one day at a time (the week strip selects the day).
    public static func isDayBased(_ kind: TimetableViewKind) -> Bool {
        let resolved = resolve(kind)
        return resolved == .day || resolved == .tiles
    }
}

/// The shown week and selected day of the Timetable tab.
public struct TimetableSelection: Equatable, Sendable {
    /// First day of the shown week (display week start).
    public var weekStart: LocalDate
    /// Selected day (inside the shown week).
    public var selectedDate: LocalDate

    public init(weekStart: LocalDate, selectedDate: LocalDate) {
        self.weekStart = weekStart
        self.selectedDate = selectedDate
    }

    /// Where the tab opens: the week from `GridLayout.displayWeekStart` (next week once this week's school days are
    /// over) with today selected when it is an enabled day of that week, else the first enabled day on or after
    /// today in that week, else the week's first enabled day.
    public static func initial(today: LocalDate, resolver: ScheduleResolver) -> TimetableSelection {
        let start = GridLayout.displayWeekStart(today: today, resolver: resolver)
        return TimetableSelection(weekStart: start, selectedDate: preferredDay(in: start, near: today, resolver: resolver))
    }

    /// The week `weeks` weeks later (negative: earlier), keeping the selected weekday when it is enabled.
    public func shifted(byWeeks weeks: Int, resolver: ScheduleResolver) -> TimetableSelection {
        let start = weekStart.adding(days: 7 * weeks)
        let offset = weekStart.days(to: selectedDate)
        let candidate = start.adding(days: offset)
        return TimetableSelection(weekStart: start,
                                  selectedDate: Self.preferredDay(in: start, near: candidate, resolver: resolver))
    }

    /// Selects `date` (moving the week if `date` is outside it).
    public func selecting(_ date: LocalDate, resolver: ScheduleResolver) -> TimetableSelection {
        TimetableSelection(weekStart: resolver.context.startOfWeek(containing: date), selectedDate: date)
    }

    /// The first week on or after the week of `from` whose cycle week (as GridLayout labels it: the week's middle day)
    /// is `cycleWeek`; `nil` without a week cycle or for a cycle week outside the cycle.
    public static func week(withCycleWeek cycleWeek: Int, onOrAfter from: LocalDate, today: LocalDate,
                            resolver: ScheduleResolver) -> TimetableSelection? {
        guard case .weekCycle(let cycle) = resolver.timetable.rotation, (1...max(1, cycle.length)).contains(cycleWeek)
        else { return nil }
        let first = resolver.context.startOfWeek(containing: from)
        for index in 0...(2 * min(cycle.length, 1_000) + 2) {
            let start = first.adding(days: 7 * index)
            if resolver.rotation.cycleWeek(on: start.adding(days: 3)) == cycleWeek {
                return TimetableSelection(weekStart: start, selectedDate: preferredDay(in: start, near: today, resolver: resolver))
            }
        }
        return nil
    }

    /// The enabled days of the shown week, in display order (all seven when none is enabled).
    public static func shownDays(weekStart: LocalDate, resolver: ScheduleResolver) -> [LocalDate] {
        let all = (0..<7).map { weekStart.adding(days: $0) }
        let enabled = all.filter { resolver.timetable.enabledDays.contains($0.weekday) }
        return enabled.isEmpty ? all : enabled
    }

    /// `near` when it is a shown day of the week starting at `weekStart`, else the first shown day after it, else
    /// the last shown day before it.
    static func preferredDay(in weekStart: LocalDate, near: LocalDate, resolver: ScheduleResolver) -> LocalDate {
        let days = shownDays(weekStart: weekStart, resolver: resolver)
        if days.contains(near) { return near }
        if let later = days.first(where: { $0 > near }) { return later }
        return days.last { $0 < near } ?? days[0]
    }
}
