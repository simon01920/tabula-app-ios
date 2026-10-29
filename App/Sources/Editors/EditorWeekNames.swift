// Names of rotation weeks in the editors (UX overhaul D11): one localised full phrase per case, never "Week " + label.
// "A" -> "Week A" (`editor.lesson.weeks.named`), "Odd" / "Párny" -> as typed, no label -> "Week 2"
// (`editor.cycleWeek.name`). The rule itself is `CycleWeekSelection.name(of:labels:)` (TimetableUI, Linux-tested).
import TimetableCore
import TimetableUI

@MainActor
enum EditorWeekNames {
    /// The name of cycle week `week` of `timetable` (plain "Week 2" outside a week rotation).
    static func name(_ week: Int, in timetable: Timetable, renderer: LocalizedTextRenderer) -> String {
        var labels: [String]?
        if case .weekCycle(let cycle) = timetable.rotation { labels = cycle.labels }
        switch CycleWeekSelection.name(of: week, labels: labels) {
        case .numbered(let index):
            return renderer.format(key: "editor.cycleWeek.name", arguments: [.integer(Int64(index))])
        case .named(let label):
            return renderer.format(key: "editor.lesson.weeks.named", arguments: [.text(label)])
        case .verbatim(let label):
            return label
        }
    }
}
