// View-independent presentation of the *Homework* widget (Stage B1): the task lines (title, subject, due text, overdue
// mark), the count, the empty ("All done") and unavailable states, the per-row VoiceOver sentence and the deep link.
// Pure, Linux-tested; `HomeworkWidgetViews.swift` only lays it out.
//
// Due text: "Today" / "Today, 16:00" / "Tomorrow" / weekday ("Fri", "Fri, 8:00") for 2–6 days ahead / "20 Oct" later
// (the Tasks tab's phrases, `tasks.due.*`, with the weekday instead of "In 3 days" as the widget has little room);
// overdue by days → "2 days overdue" (`tasks.due.overdueDays`), overdue today (the time has passed) → "Overdue". An
// overdue row also carries a warning icon and a spoken "overdue", so the mark is never colour alone.
// Count: only tasks the snapshot knows (overdue + due within a week) are counted ("3 tasks to do"); undated tasks and
// tasks due later are not in the snapshot.
import Foundation
import TimetableCore

/// Everything a Homework widget view needs for one entry.
public struct HomeworkDisplay: Equatable, Sendable {
    /// One open task, formatted.
    public struct TaskLine: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var subject: SubjectSummary?
        /// "Today", "Fri", "2 days overdue".
        public var dueText: String
        public var isOverdue: Bool
        /// High or urgent priority (shown as an icon).
        public var isHighPriority: Bool
        /// One VoiceOver sentence: title, subject, overdue, due, priority.
        public var accessibilityLabel: String

        /// Where a tap goes (`tabula://open/task/<id>`).
        public var link: ItemLink { .task(TaskItem.ID(id)) }
    }

    public enum Kind: Equatable, Sendable {
        /// Open tasks (`lines`).
        case tasks
        /// Nothing to do.
        case allDone(title: String, detail: String)
        /// Nothing can be shown: open the app.
        case unavailable(title: String, detail: String)
    }

    /// The entry's date.
    public var date: Date
    public var kind: Kind
    /// "Homework".
    public var title: String
    /// "3 tasks to do" (empty for the non-task kinds).
    public var countText: String
    /// Overdue first, then due soonest.
    public var lines: [TaskLine]
    /// Overdue tasks the snapshot did not list.
    public var unlistedOverdue: Int
    /// Overdue tasks (listed or not).
    public var overdueCount: Int
    /// One VoiceOver sentence for the whole widget in the small family (rows have their own in larger ones).
    public var accessibilityLabel: String
    /// "+3 more" for `hidden` items (plural variations).
    var moreFormat: @Sendable (Int) -> String

    /// Rows per family: the small widget shows the top task only.
    public static func capacity(for family: WidgetFamilyKind) -> Int {
        switch family {
        case .systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline: return 1
        case .systemMedium: return 3
        case .systemLarge, .systemExtraLarge: return 9
        }
    }

    /// The lines `family` shows and how many tasks it leaves out (including the unlisted overdue ones).
    public func visible(for family: WidgetFamilyKind) -> (lines: [TaskLine], hidden: Int) {
        let shown = Array(lines.prefix(Self.capacity(for: family)))
        return (shown, lines.count - shown.count + unlistedOverdue)
    }

    /// "+3 more".
    public func moreText(_ hidden: Int) -> String { moreFormat(hidden) }

    /// Where a tap on the widget goes: the top task (small family), else the Today tab.
    public var link: ItemLink { lines.first.map { .task(TaskItem.ID($0.id)) } ?? .today }

    public static func == (lhs: HomeworkDisplay, rhs: HomeworkDisplay) -> Bool {
        lhs.date == rhs.date && lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.countText == rhs.countText
            && lhs.lines == rhs.lines && lhs.unlistedOverdue == rhs.unlistedOverdue
            && lhs.overdueCount == rhs.overdueCount && lhs.accessibilityLabel == rhs.accessibilityLabel
    }
}

/// Builds `HomeworkDisplay` values.
public struct HomeworkPresenter: Sendable {
    public let renderer: LocalizedTextRenderer
    public let context: CalendarContext

    public init(renderer: LocalizedTextRenderer, context: CalendarContext) {
        self.renderer = renderer
        self.context = context
    }

    /// Texts of the Pro placeholder (the widget's families are all free today; kept for the gate's symmetry).
    public func proTexts() -> (title: String, short: String) {
        (renderer.string(forKey: "widget.pro.title"), renderer.string(forKey: "widget.pro.short"))
    }

    /// The display of `entry`.
    public func display(_ entry: WidgetStateEntry<HomeworkState>) -> HomeworkDisplay {
        let title = renderer.string(forKey: "widget.homework.name")
        let separator = renderer.string(forKey: "a11y.separator")
        let more: @Sendable (Int) -> String = { [renderer] hidden in
            renderer.format(key: "widget.more", arguments: [.integer(Int64(hidden))])
        }
        switch entry.state {
        case .unavailable(let reason):
            let (heading, detail) = WidgetUnavailableText.texts(for: reason, renderer: renderer)
            return HomeworkDisplay(date: entry.date, kind: .unavailable(title: heading, detail: detail), title: title,
                                   countText: "", lines: [], unlistedOverdue: 0, overdueCount: 0,
                                   accessibilityLabel: [heading, detail].joined(separator: separator), moreFormat: more)
        case .list(let list):
            let today = context.localDate(of: entry.date)
            let lines = list.rows.map { taskLine($0.task, isOverdue: $0.isOverdue, today: today) }
            guard list.knownTotal > 0 else {
                let heading = renderer.string(forKey: "widget.homework.allDone.title")
                let detail = renderer.string(forKey: "widget.homework.allDone.detail")
                return HomeworkDisplay(date: entry.date, kind: .allDone(title: heading, detail: detail), title: title,
                                       countText: "", lines: [], unlistedOverdue: 0, overdueCount: 0,
                                       accessibilityLabel: [title, heading, detail].joined(separator: separator),
                                       moreFormat: more)
            }
            let count = renderer.format(key: "widget.homework.count", arguments: [.integer(Int64(list.knownTotal))])
            var spoken = [title, count]
            if let top = lines.first { spoken.append(top.accessibilityLabel) }
            return HomeworkDisplay(date: entry.date, kind: .tasks, title: title, countText: count, lines: lines,
                                   unlistedOverdue: list.unlistedOverdue, overdueCount: list.overdueTotal,
                                   accessibilityLabel: spoken.joined(separator: separator), moreFormat: more)
        }
    }

    /// One task line. `isOverdue` is evaluated by the caller at the entry's instant.
    func taskLine(_ task: WidgetSnapshot.DueTask, isOverdue: Bool, today: LocalDate) -> HomeworkDisplay.TaskLine {
        let separator = renderer.string(forKey: "a11y.separator")
        let visible = dueText(task, isOverdue: isOverdue, today: today, spoken: false)
        let spokenDue = dueText(task, isOverdue: isOverdue, today: today, spoken: true)
        var parts = [task.title]
        if let subject = task.subject { parts.append(subject.name) }
        if task.dueDate < today {
            parts.append(spokenDue)   // "2 days overdue"
        } else {
            if isOverdue { parts.append(renderer.string(forKey: "a11y.task.overdue")) }
            parts.append(renderer.format(key: "a11y.task.due", arguments: [.text(spokenDue)]))
        }
        if task.priority >= .high { parts.append(renderer.string(forKey: TaskL10nKeys.priorityAccessibility(task.priority))) }
        return HomeworkDisplay.TaskLine(id: task.id, title: task.title, subject: task.subject, dueText: visible,
                                        isOverdue: isOverdue, isHighPriority: task.priority >= .high,
                                        accessibilityLabel: parts.joined(separator: separator))
    }

    func dueText(_ task: WidgetSnapshot.DueTask, isOverdue: Bool, today: LocalDate, spoken: Bool) -> String {
        let formatter = renderer.formatter
        let delta = today.days(to: task.dueDate)
        let time = task.dueTime.map { [CatalogArgument.text(formatter.time($0))] }
        if delta < 0 {
            return renderer.format(key: "tasks.due.overdueDays", arguments: [.integer(Int64(-delta))])
        }
        if isOverdue { return renderer.string(forKey: "widget.homework.overdue") }
        switch delta {
        case 0: return renderer.format(key: time == nil ? "tasks.due.today" : "tasks.due.todayAt", arguments: time ?? [])
        case 1: return renderer.format(key: time == nil ? "tasks.due.tomorrow" : "tasks.due.tomorrowAt", arguments: time ?? [])
        case 2...6:
            let weekday = formatter.weekdayName(task.dueDate.weekday, width: spoken ? .wide : .abbreviated)
            guard let time else { return weekday }
            return renderer.format(key: "today.header.dayAndTime", arguments: [.text(weekday)] + time)
        default:
            let day = CatalogArgument.text(formatter.date(task.dueDate, style: .dayMonth))
            return renderer.format(key: time == nil ? "tasks.due.onDate" : "tasks.due.onDateAt", arguments: [day] + (time ?? []))
        }
    }
}

/// The "Open Tabula" texts shared by the B1 presenters (the same keys as `NowNextPresenter`).
enum WidgetUnavailableText {
    static func texts(for reason: NowNextState.Unavailable, renderer: LocalizedTextRenderer) -> (title: String, detail: String) {
        let title = renderer.string(forKey: "widget.open.title")
        switch reason {
        case .noTimetable: return (title, renderer.string(forKey: "widget.open.noTimetable"))
        case .noSnapshot: return (title, renderer.string(forKey: "widget.open.noSnapshot"))
        case .outdated: return (title, renderer.string(forKey: "widget.open.outdated"))
        }
    }
}
