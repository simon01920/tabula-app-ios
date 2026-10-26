// Week rotation in the lesson editor (UX overhaul D9 / Opus H8): "Every week" is an explicit, default choice instead of
// "no week switched on". Pure UI mapping onto the existing model, no schema change. Linux-tested.
//
// Storage (unchanged): `LessonOccurrenceRule.cycleWeeks` is `nil` for every week, else the chosen 1-based cycle weeks.
// `LessonDraft.cycleWeeks` holds the same set, with `[]` (or all weeks) meaning every week; `LessonDraft.makeLesson`
// stores both as `nil`. This type converts between that set and what the form shows:
// - a two-week cycle: a segmented control "Every week | Week A | Week B" (`Segment`);
// - a longer cycle: a multi-select list whose first row "Every week" is checked by default (`toggling`).
import Foundation
import TimetableCore

/// How the lesson editor offers the weeks of a week rotation.
public enum CycleWeekSelection {
    /// The control for a cycle of `length` weeks; `nil` when there is nothing to choose (fewer than two weeks).
    public enum Style: Equatable, Sendable { case segmented, list }

    /// One segment of the two-week control.
    public enum Segment: Hashable, Sendable {
        case everyWeek
        case week(Int)
    }

    /// How a week is named in the control.
    public enum WeekName: Equatable, Sendable {
        /// No name: "Week 2" (catalog `editor.cycleWeek.name`).
        case numbered(Int)
        /// A short user name such as "A": "Week A" (catalog `editor.lesson.weeks.named`, one full-phrase format).
        case named(String)
        /// A longer user name such as "Odd" / "Párny": shown as it is (no "Week " + label concatenation, D11).
        case verbatim(String)
    }

    /// The control for a cycle of `length` weeks.
    public static func style(length: Int) -> Style? {
        if length == 2 { return .segmented }
        return length > 2 ? .list : nil
    }

    /// The weeks a cycle of `length` has.
    public static func allWeeks(length: Int) -> Set<Int> { Set(1...max(1, length)) }

    /// `true` when `weeks` means every week (nothing chosen, or every week of the cycle chosen).
    public static func isEveryWeek(_ weeks: Set<Int>, length: Int) -> Bool {
        let chosen = weeks.intersection(allWeeks(length: length))
        return chosen.isEmpty || chosen == allWeeks(length: length)
    }

    /// The segments of a two-week control, "Every week" first.
    public static func segments(length: Int) -> [Segment] {
        [.everyWeek] + (1...max(1, length)).map { Segment.week($0) }
    }

    /// The segment that shows `weeks` (draft or stored value).
    public static func segment(of weeks: Set<Int>, length: Int) -> Segment {
        if isEveryWeek(weeks, length: length) { return .everyWeek }
        let chosen = weeks.intersection(allWeeks(length: length))
        return chosen.count == 1 ? .week(chosen.min() ?? 1) : .everyWeek
    }

    /// The draft value for `segment`.
    public static func weeks(for segment: Segment) -> Set<Int> {
        switch segment {
        case .everyWeek: return []
        case .week(let week): return [week]
        }
    }

    /// The list's "Every week" row: always resets to every week.
    public static func selectingEveryWeek() -> Set<Int> { [] }

    /// The draft value after tapping week `week` in the list. From "every week", tapping a week chooses only that week;
    /// unchecking the last week or checking every week returns to "every week" (one meaning, one state).
    public static func toggling(_ week: Int, in weeks: Set<Int>, length: Int) -> Set<Int> {
        let all = allWeeks(length: length)
        guard all.contains(week) else { return weeks }
        if isEveryWeek(weeks, length: length) { return [week] }
        var chosen = weeks.intersection(all)
        if chosen.contains(week) { chosen.remove(week) } else { chosen.insert(week) }
        return (chosen.isEmpty || chosen == all) ? [] : chosen
    }

    /// `true` when the list row of `week` shows a checkmark.
    public static func isChecked(_ week: Int, in weeks: Set<Int>, length: Int) -> Bool {
        !isEveryWeek(weeks, length: length) && weeks.contains(week)
    }

    /// The name of week `index` with the rotation's optional labels: one or two characters ("A") read as a name
    /// ("Week A"), longer labels ("Odd", "Párny") stand alone, no label gives "Week 2".
    public static func name(of index: Int, labels: [String]?) -> WeekName {
        guard let label = DayChoices.label(at: index, in: labels) else { return .numbered(index) }
        return label.count <= 2 ? .named(label) : .verbatim(label)
    }
}
