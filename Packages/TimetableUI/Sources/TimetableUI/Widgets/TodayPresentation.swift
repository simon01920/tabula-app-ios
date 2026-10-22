// View-independent presentation of the *Today* widget (Stage B1): the day's lessons (times, subject badge, room,
// cancelled ones struck through, changed ones badged, the current one highlighted), the tasks due that day and the
// status / unavailable states. Pure, Linux-tested; `TodayWidgetViews.swift` only lays it out.
//
// Which day: the Now & Next state decides (`WidgetTimelinePlanner.state`, so the widget never disagrees with the Today
// tab): a lesson in progress or still to come today → today's list; lessons over and tomorrow has lessons that take place
// → tomorrow's list under a "Tomorrow" header; otherwise the Stage A status (no more lessons / no lessons / holidays /
// cancelled day) with the next lesson, or the "Open Tabula" state. Entries come from `WidgetTimelinePlanner.plan(…,
// includeCancelledBoundaries: true)`: lesson boundaries and midnights.
//
// Families: medium lists the lessons from now on (ended ones dropped), 4 rows, or 3 when a shown row has a change line;
// large lists the whole day (ended lessons dimmed; the earliest ended ones are dropped when the day is longer than the
// room) plus up to 3 tasks due that day. Each row has a spoken sentence; the widget label joins the visible ones.
import Foundation
import TimetableCore

/// Everything a Today widget view needs for one entry.
public struct TodayDisplay: Equatable, Sendable {
    /// One lesson of the listed day.
    public struct Row: Equatable, Sendable, Identifiable {
        public var line: NowNextDisplay.LessonLine
        /// Cancelled (struck through, "Cancelled" badge).
        public var isCancelled: Bool
        /// The lesson in progress at the entry's instant.
        public var isCurrent: Bool
        /// Over at the entry's instant.
        public var isPast: Bool
        /// SF Symbol of the change badge, if the lesson differs from the timetable.
        public var badgeSymbol: String?
        /// "Mathematics, 8:55 to 9:40, room 12, room changed".
        public var spoken: String
        public var id: String { line.id }
    }

    /// A day's lesson list.
    public struct Day: Equatable, Sendable {
        /// "Today" / "Tomorrow".
        public var header: String
        /// "Tue 13 Oct".
        public var dateText: String
        public var isTomorrow: Bool
        public var rows: [Row]
        /// "Due today" / "Due tomorrow".
        public var dueTitle: String
        /// Tasks due that day (at most `maxDueTasks`).
        public var dueTasks: [HomeworkDisplay.TaskLine]
        /// Due tasks left out.
        public var hiddenDue: Int
    }

    public enum Kind: Equatable, Sendable {
        case lessons(Day)
        /// No lessons to list: why (SF Symbol + title + optional detail) and the next lesson.
        case status(symbol: String, title: String, detail: String?, next: NowNextDisplay.LessonLine?,
                    nextCaption: String?, nothingAhead: String?)
        /// Nothing can be shown: open the app.
        case unavailable(title: String, detail: String)
    }

    /// Tasks listed under "Due today" in the large family.
    public static let maxDueTasks = 3
    /// Large family: lessons shown with / without a due list.
    public static let largeRowsWithTasks = 7
    public static let largeRowsWithoutTasks = 9
    /// Medium family: rows, and rows when a shown row carries a change line.
    public static let mediumRows = 4
    public static let mediumRowsWithChange = 3

    /// The entry's date.
    public var date: Date
    public var kind: Kind
    /// "Open the app" etc. for the unavailable kind, else the day's one-sentence label.
    var spokenHeader: String
    var spokenSeparator: String
    var moreFormat: @Sendable (Int) -> String
    /// Where a tap goes.
    public var link: ItemLink { .today }

    /// The rows `family` shows and how many it leaves out after them.
    public func visibleRows(for family: WidgetFamilyKind) -> (rows: [Row], hidden: Int) {
        guard case .lessons(let day) = kind else { return ([], 0) }
        switch family {
        case .systemLarge, .systemExtraLarge:
            let limit = day.dueTasks.isEmpty ? Self.largeRowsWithoutTasks : Self.largeRowsWithTasks
            var rows = day.rows
            // Drop the earliest ended lessons first; they matter least.
            while rows.count > limit, let first = rows.first, first.isPast { rows.removeFirst() }
            let shown = Array(rows.prefix(limit))
            return (shown, rows.count - shown.count)
        default:
            let upcoming = day.rows.filter { !$0.isPast }
            let four = Array(upcoming.prefix(Self.mediumRows))
            let shown = four.contains { $0.line.badgeText != nil } ? Array(four.prefix(Self.mediumRowsWithChange)) : four
            return (shown, upcoming.count - shown.count)
        }
    }

    /// "+2 more".
    public func moreText(_ hidden: Int) -> String { moreFormat(hidden) }

    /// One VoiceOver sentence for the widget in `family`: the day, the visible lessons and (large) the due tasks.
    public func accessibilityLabel(for family: WidgetFamilyKind) -> String {
        guard case .lessons(let day) = kind else { return spokenHeader }
        let isLarge = family == .systemLarge || family == .systemExtraLarge
        var parts = [spokenHeader] + visibleRows(for: family).rows.map(\.spoken)
        if isLarge, !day.dueTasks.isEmpty { parts += [day.dueTitle] + day.dueTasks.map(\.accessibilityLabel) }
        return parts.joined(separator: spokenSeparator)
    }

    public static func == (lhs: TodayDisplay, rhs: TodayDisplay) -> Bool {
        lhs.date == rhs.date && lhs.kind == rhs.kind && lhs.spokenHeader == rhs.spokenHeader
    }
}

/// Builds `TodayDisplay` values.
public struct TodayPresenter: Sendable {
    public let renderer: LocalizedTextRenderer
    public let context: CalendarContext

    public init(renderer: LocalizedTextRenderer, context: CalendarContext) {
        self.renderer = renderer
        self.context = context
    }

    private var nowNext: NowNextPresenter { NowNextPresenter(renderer: renderer, context: context) }

    /// Texts of the Pro placeholder (large family on the free tier).
    public func proTexts() -> (title: String, short: String) { nowNext.proTexts() }

    /// The display of `entry` (planned from `snapshot`).
    public func display(snapshot: WidgetSnapshot?, entry: NowNextTimelineEntry) -> TodayDisplay {
        let separator = renderer.string(forKey: "a11y.separator")
        let more: @Sendable (Int) -> String = { [renderer] hidden in
            renderer.format(key: "widget.more", arguments: [.integer(Int64(hidden))])
        }
        func make(_ kind: TodayDisplay.Kind, spoken: String) -> TodayDisplay {
            TodayDisplay(date: entry.date, kind: kind, spokenHeader: spoken, spokenSeparator: separator, moreFormat: more)
        }
        let today = context.localDate(of: entry.date)
        switch entry.state {
        case .unavailable(let reason):
            let (title, detail) = WidgetUnavailableText.texts(for: reason, renderer: renderer)
            return make(.unavailable(title: title, detail: detail), spoken: [title, detail].joined(separator: separator))
        case .current, .upcoming:
            return list(snapshot: snapshot, date: today, isTomorrow: false, entry: entry, make: make)
                ?? statusDisplay(entry, make: make)
        case .dayOver:
            let tomorrow = today.adding(days: 1)
            if let snapshot, let day = snapshot.day(tomorrow), !WidgetTimelinePlanner.active(day, context).isEmpty {
                return list(snapshot: snapshot, date: tomorrow, isTomorrow: true, entry: entry, make: make)
                    ?? statusDisplay(entry, make: make)
            }
            return statusDisplay(entry, make: make)
        case .free, .holiday, .dayCancelled:
            return statusDisplay(entry, make: make)
        }
    }

    // MARK: Internals

    private func statusDisplay(_ entry: NowNextTimelineEntry,
                               make: (TodayDisplay.Kind, String) -> TodayDisplay) -> TodayDisplay {
        let shown = nowNext.display(entry)
        switch shown.kind {
        case let .status(symbol, title, detail):
            return make(.status(symbol: symbol, title: title, detail: detail, next: shown.next,
                                nextCaption: shown.nextCaption, nothingAhead: shown.nothingAhead), shown.accessibilityLabel)
        case let .unavailable(title, detail):
            return make(.unavailable(title: title, detail: detail), shown.accessibilityLabel)
        case .current, .upcoming:
            // Only reached when a listed day is missing from the snapshot; ask for an update rather than guess.
            let (title, detail) = WidgetUnavailableText.texts(for: .outdated, renderer: renderer)
            return make(.unavailable(title: title, detail: detail),
                        [title, detail].joined(separator: renderer.string(forKey: "a11y.separator")))
        }
    }

    private func list(snapshot: WidgetSnapshot?, date: LocalDate, isTomorrow: Bool, entry: NowNextTimelineEntry,
                      make: (TodayDisplay.Kind, String) -> TodayDisplay) -> TodayDisplay? {
        guard let snapshot, let day = snapshot.day(date) else { return nil }
        let today = context.localDate(of: entry.date)
        let currentID = entry.state.current?.id
        let lessons = day.lessons.sorted { lhs, rhs in
            let (ls, rs) = (lhs.start(in: context), rhs.start(in: context))
            if ls != rs { return ls < rs }
            let (le, re) = (lhs.end(in: context), rhs.end(in: context))
            if le != re { return le < re }
            return lhs.id < rhs.id
        }
        let rows = lessons.map { lesson -> TodayDisplay.Row in
            let line = nowNext.line(lesson, today: today)
            let isCurrent = !isTomorrow && lesson.id == currentID
            var spoken = nowNext.lessonParts(line, lesson)
            if isCurrent { spoken.insert(renderer.string(forKey: "today.header.now"), at: 0) }
            let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: lesson.reasons ?? [])
            return TodayDisplay.Row(line: line, isCancelled: !lesson.takesPlace, isCurrent: isCurrent,
                                    isPast: !isTomorrow && line.end <= entry.date, badgeSymbol: badge?.symbolName,
                                    spoken: spoken.joined(separator: renderer.string(forKey: "a11y.separator")))
        }
        // Tasks due that day: the snapshot's list plus its overdue list (a task due today whose time has passed).
        let homework = HomeworkPresenter(renderer: renderer, context: context)
        let local = context.local(from: entry.date)
        let due = (snapshot.tasks + snapshot.overdueTasks).filter { $0.dueDate == date }
            .map { task -> HomeworkList.Row in
                let late = !isTomorrow && task.dueTime.map { $0 < local.time } == true
                return HomeworkList.Row(task: task, isOverdue: late)
            }
            .sorted(by: HomeworkPlanner.ordered)
        let lines = due.map { homework.taskLine($0.task, isOverdue: $0.isOverdue, today: today) }
        let shownDue = Array(lines.prefix(TodayDisplay.maxDueTasks))
        let header = renderer.string(forKey: isTomorrow ? "today.section.tomorrow" : "shell.tab.today")
        let dateText = renderer.formatter.date(date, style: .weekdayDayMonth)
        let content = TodayDisplay.Day(
            header: header, dateText: dateText, isTomorrow: isTomorrow, rows: rows,
            dueTitle: renderer.string(forKey: isTomorrow ? "widget.today.dueTomorrow" : "today.section.dueToday"),
            dueTasks: shownDue, hiddenDue: lines.count - shownDue.count)
        return make(.lessons(content), [header, dateText].joined(separator: renderer.string(forKey: "a11y.separator")))
    }
}
