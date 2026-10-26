// View-independent presentation of the *Next exam* widget (Stage B1): subject, title, date, time, room, the countdown
// text with its escalation level and icon, the exam-day live countdown, the empty and unavailable states, the
// VoiceOver sentence and the deep link. Pure, Linux-tested; `NextExamWidgetViews.swift` only lays it out.
//
// Countdown text (escalating as the exam nears; the exam's own wording, `exams.when.*`, and the Tasks tab's "Today, 8:00"):
//   9 days away  "in 9 days"   · calendar icon (later) / calendar.badge.clock (within a week)
//   tomorrow     "Tomorrow"    · exclamation icon
//   today        "Today, 10:00" + a live "Starts in" countdown (`Text(timerInterval:)`) · alarm icon
//   in progress  "In progress" + a live "Time left" countdown to the end · pencil icon
//   afterwards   "Finished" (or "Today, 10:00" when the exam has no known end) · check icon
// The VoiceOver sentence names the start time instead of the ticking countdown (a static value VoiceOver can read).
import Foundation
import TimetableCore

/// Everything a Next exam widget view needs for one entry.
public struct ExamDisplay: Equatable, Sendable {
    /// How close the exam is; drives the icon (and the view's emphasis).
    public enum Escalation: Equatable, Sendable {
        case later, soon, tomorrow, today, inProgress, finished
    }

    /// One exam, formatted.
    public struct Info: Equatable, Sendable {
        public var id: UUID
        public var subject: SubjectSummary?
        public var title: String
        /// "Tue, Oct 20".
        public var dateText: String
        /// "10:00" / "10:00 – 10:45", `nil` without a start.
        public var timeText: String?
        public var room: String?
        /// "in 9 days" / "Tomorrow" / "Today, 10:00" / "In progress" / "Finished".
        public let whenText: String
        /// Short form for the circular family: "9", "1", "10:00".
        public var circularValue: String
        public var escalation: Escalation
        /// SF Symbol of the escalation level.
        public var symbol: String
        /// Live countdown interval on the exam day (entry…start before it, start…end while it runs).
        public var timer: ClosedRange<Date>?
        /// "Starts in" / "Time left" for `timer`.
        public var timerCaption: String?
        /// "Tue, Oct 20 · 10:00 – 10:45 · Lab", joined with the localised separator.
        public var detailLine: String
        /// The Lock Screen rectangular line (one short line): "Thu 22 · 10:00 · Lab" (short date and start time only);
        /// the date is left out on the exam day.
        public var rectangularLine: String
        /// The small family's line: the date is left out on the exam day (the countdown says it).
        public var smallLine: String
        /// "Today, 10:00 · in 1 h 30 min" (static sentence; the live view shows the pieces separately).
        public var whenLine: String
        /// The countdown with its unit word, minutes only (never seconds); `nil` without a timer (U7, H2).
        public var countdown: WidgetCountdown?
    }

    public enum Kind: Equatable, Sendable {
        case exam(Info)
        /// No upcoming exam.
        case empty(title: String, detail: String)
        /// Nothing can be shown: open the app.
        case unavailable(title: String, detail: String)
    }

    /// The entry's date (the static "now" of the gallery).
    public var date: Date
    public var kind: Kind
    /// "Next Exam".
    public var title: String
    /// One VoiceOver sentence for the whole widget.
    public var accessibilityLabel: String
    /// Where a tap goes: the exam, else the Today tab.
    public var link: ItemLink
}

/// Builds `ExamDisplay` values.
public struct ExamPresenter: Sendable {
    public let renderer: LocalizedTextRenderer
    public let context: CalendarContext

    public init(renderer: LocalizedTextRenderer, context: CalendarContext) {
        self.renderer = renderer
        self.context = context
    }

    /// Texts of the Pro placeholder (Lock Screen families on the free tier).
    public func proTexts() -> (title: String, short: String) {
        (renderer.string(forKey: "widget.pro.title"), renderer.string(forKey: "widget.pro.short"))
    }

    /// The display of `entry`.
    public func display(_ entry: WidgetStateEntry<ExamState>) -> ExamDisplay {
        let title = renderer.string(forKey: "widget.exam.name")
        let separator = renderer.string(forKey: "a11y.separator")
        switch entry.state {
        case .unavailable(let reason):
            let (heading, detail) = WidgetUnavailableText.texts(for: reason, renderer: renderer)
            return ExamDisplay(date: entry.date, kind: .unavailable(title: heading, detail: detail), title: title,
                               accessibilityLabel: [heading, detail].joined(separator: separator), link: .today)
        case .none:
            let heading = renderer.string(forKey: "exams.empty.upcoming.title")
            let detail = renderer.string(forKey: "widget.exam.empty.detail")
            return ExamDisplay(date: entry.date, kind: .empty(title: heading, detail: detail), title: title,
                               accessibilityLabel: [title, heading, detail].joined(separator: separator), link: .today)
        case let .upcoming(exam, days):
            return examDisplay(entry.date, exam: exam, days: days, phase: nil, title: title)
        case let .today(exam, phase):
            return examDisplay(entry.date, exam: exam, days: 0, phase: phase, title: title)
        }
    }

    private func examDisplay(_ instant: Date, exam: WidgetSnapshot.UpcomingExam, days: Int,
                             phase: ExamState.Phase?, title: String) -> ExamDisplay {
        let formatter = renderer.formatter
        let startText = exam.start.map { formatter.time($0) }
        let timeText: String? = exam.start.map { start in
            if let end = exam.end, end > start { return formatter.timeRange(start, end) }
            return formatter.time(start)
        }
        let dateText = formatter.date(exam.date, style: .weekdayDayMonth)
        var timer: ClosedRange<Date>?
        var timerCaption: String?
        let whenText: String
        var circular = String(days)
        let escalation: ExamDisplay.Escalation
        let symbol: String
        func today(_ time: String?) -> String {
            time.map { renderer.format(key: "tasks.due.todayAt", arguments: [.text($0)]) } ?? renderer.string(forKey: "exams.when.today")
        }
        switch phase {
        case nil:
            whenText = ExamTexts(renderer: renderer).when(ExamWhen(daysUntil: days))
            escalation = days == 1 ? .tomorrow : (days <= 7 ? .soon : .later)
            symbol = days == 1 ? "exclamationmark.circle.fill" : (days <= 7 ? "calendar.badge.clock" : "calendar")
        case .beforeStart(let start)?:
            whenText = today(startText)
            timer = min(instant, start)...start
            timerCaption = renderer.string(forKey: "today.header.startsIn")
            circular = startText ?? renderer.string(forKey: "exams.when.today")
            escalation = .today
            symbol = "alarm.fill"
        case .allDay?:
            whenText = today(nil)
            circular = renderer.string(forKey: "exams.when.today")
            escalation = .today
            symbol = "alarm.fill"
        case let .inProgress(start, end)?:
            whenText = renderer.string(forKey: "widget.exam.inProgress")
            timer = start...max(start, end)
            timerCaption = renderer.string(forKey: "today.header.timeLeft")
            circular = startText ?? renderer.string(forKey: "exams.when.today")
            escalation = .inProgress
            symbol = "pencil"
        case .started?:
            whenText = today(startText)
            circular = startText ?? renderer.string(forKey: "exams.when.today")
            escalation = .inProgress
            symbol = "pencil"
        case .finished?:
            whenText = renderer.string(forKey: "widget.exam.finished")
            circular = startText ?? renderer.string(forKey: "exams.when.today")
            escalation = .finished
            symbol = "checkmark.circle"
        }
        let dot = renderer.string(forKey: "widget.separator")
        let detailLine = [dateText, timeText, exam.room].compactMap { $0 }.joined(separator: dot)
        let smallLine = [timer == nil ? dateText : nil, timeText, exam.room].compactMap { $0 }.joined(separator: dot)
        let rectangularLine = [timer == nil ? formatter.date(exam.date, style: .weekdayDay) : nil, startText, exam.room]
            .compactMap { $0 }.joined(separator: dot)
        // U7 (H2): never seconds before an exam. The countdown is minutes only with its unit word; `whenLine` is the static
        // sentence "Today, 10:00 · in 1 h 30 min" (VoiceOver, paused gallery); the live view shows `whenText` and the
        // countdown separately (`Text(date, style: .relative)` keeps the minutes current without timeline entries).
        var countdown: WidgetCountdown?
        if let timer {
            let running: Bool
            if case .inProgress? = phase { running = true } else { running = false }
            countdown = WidgetCountdownBuilder(renderer: renderer)
                .make(interval: timer, now: instant, kind: running ? .left : .untilStart, allowsSeconds: false)
        }
        let whenLine = [whenText, countdown?.phrase].compactMap { $0 }.joined(separator: dot)
        let subjectName = exam.subject?.name
        // Spoken: exam, subject, when, full date, start time, room.
        var spoken = [renderer.string(forKey: "widget.exam.name"), exam.title]
        if let subjectName { spoken.append(subjectName) }
        spoken.append(whenText)
        if let countdown { spoken.append(countdown.phrase) }
        spoken.append(formatter.date(exam.date, style: .full))
        if let timeText { spoken.append(timeText) }
        if let room = exam.room { spoken.append(renderer.format(key: "exams.a11y.room", arguments: [.text(room)])) }
        var info = ExamDisplay.Info(id: exam.id, subject: exam.subject, title: exam.title, dateText: dateText,
                                    timeText: timeText, room: exam.room, whenText: whenText, circularValue: circular,
                                    escalation: escalation, symbol: symbol, timer: timer, timerCaption: timerCaption,
                                    detailLine: detailLine, rectangularLine: rectangularLine, smallLine: smallLine,
                                    whenLine: whenLine)
        info.countdown = countdown
        return ExamDisplay(date: instant, kind: .exam(info), title: title,
                           accessibilityLabel: formatter.list(spoken), link: .exam(Exam.ID(exam.id)))
    }
}
