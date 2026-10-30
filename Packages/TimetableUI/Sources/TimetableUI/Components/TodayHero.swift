// The Today hero (Phase 4U U3; Opus review R1 "hero states", H2, Astra F02): which of the five moments the top card
// shows and every string it needs, in the order the card reads. Pure, Linux-tested; `TodayHeroView` only lays it out.
//
// The moment is a view of the shared `TodayState.Header` (the widget planner's state, tested against it), never a
// second state machine:
//   before school  `.upcoming(first, isFirstOfDay: true)`   first lesson, "in 40 min", the day's bring list
//   break          `.upcoming(next, isFirstOfDay: false)`   "Next" lesson, "in 2 min"
//   in a lesson    `.current(lesson, next)`                  NOW · until 10:45, "25 min left", the next lesson line
//   after school   `.dayOver(next)`                          "Done for today", the next lesson, its day's bring list
//   day off        `.free` / `.holiday` / `.dayCancelled`    why ("Autumn holidays until Fri, Oct 30"), next lesson
// Countdowns are whole minutes rounded up ("1 min left" with 20 s to go), never seconds and never "25:00" (H2); the
// app redraws them once a minute (`TimelineView(.everyMinute)`). Durations reuse the widgets' catalog units
// (`WidgetCountdownBuilder`), so Today, widgets and Live Activities say the same thing in all 12 languages.
import Foundation
import TimetableCore

/// The five moments of the Today hero.
public enum TodayMoment: Equatable, Sendable {
    case beforeSchool, breakTime, inLesson, afterSchool, dayOff
}

extension TodayState.Header {
    /// The hero moment of this header.
    public var moment: TodayMoment {
        switch self {
        case .current: return .inLesson
        case let .upcoming(_, isFirst): return isFirst ? .beforeSchool : .breakTime
        case .dayOver: return .afterSchool
        case .free, .holiday, .dayCancelled: return .dayOff
        }
    }
}

/// The strings of the Today hero and its rows.
public struct TodayHeroText: Sendable {
    public let renderer: LocalizedTextRenderer
    public let visibility: FieldVisibility

    public init(renderer: LocalizedTextRenderer, visibility: FieldVisibility) {
        self.renderer = renderer
        self.visibility = visibility
    }

    /// Catalog keys this type formats at runtime (for `DynamicL10nKeys`).
    public static let catalogKeys = [
        "today.hero.until", "today.hero.untilDate", "today.hero.lesson", "today.hero.lessonPlace", "today.hero.bring",
        "today.subtitle.withCycle", "today.exam.when", "today.tasks.overdueRow",
    ]

    /// The bring list the hero shows: today's before school, the next school day's after school (pack your bag);
    /// none during the day or on days off (R1).
    public static func bringItems(_ state: TodayState, visibility: FieldVisibility) -> [String] {
        switch state.header.moment {
        case .beforeSchool: return TodayState.bringList(state.items, visibility: visibility)
        case .afterSchool: return TodayState.bringList(state.upcomingItems, visibility: visibility)
        case .breakTime, .inLesson, .dayOff: return []
        }
    }

    /// Whole minutes from `now` to `end`, rounded up (a lesson with 20 s left has 1 min left); 0 once it is over.
    public static func minutesLeft(until end: Date, now: Date) -> Int {
        max(0, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }

    // MARK: Countdowns

    /// "25 min left" / "1 h 5 min left".
    public func left(until end: Date, now: Date) -> String {
        renderer.format(key: "widget.countdown.leftPhrase", arguments: [.text(duration(until: end, now: now))])
    }

    /// "in 2 min" / "in 1 h 30 min".
    public func startsIn(_ start: Date, now: Date) -> String {
        renderer.format(key: "widget.countdown.inPhrase", arguments: [.text(duration(until: start, now: now))])
    }

    /// "until 10:45" (the end of the current lesson).
    public func until(_ time: LocalTime) -> String {
        renderer.format(key: "today.hero.until", arguments: [.text(renderer.formatter.time(time))])
    }

    /// "until Fri, Oct 30" (the last day of a holiday; the year only when it is not this year).
    public func until(_ date: LocalDate, today: LocalDate) -> String {
        renderer.format(key: "today.hero.untilDate", arguments: [
            .text(renderer.formatter.contextualDate(date, today: today, style: .abbreviated)),
        ])
    }

    // MARK: Lessons

    /// The lesson's place: its visible room and building ("214", "214, Building A"); `nil` when both are absent.
    public func place(_ lesson: ResolvedLesson) -> String? {
        let fields = VisibleLessonFields(lesson: lesson, visibility: visibility)
        let parts = [fields.room, fields.building].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: renderer.string(forKey: "a11y.separator"))
    }

    /// When a lesson starts: "10:55" today, "Tomorrow, 8:00", "Mon, Oct 19, 8:00" later.
    public func start(_ lesson: ResolvedLesson, today: LocalDate) -> String {
        let time = renderer.formatter.time(lesson.startTime)
        guard lesson.date != today else { return time }
        let day = lesson.date == today.adding(days: 1)
            ? renderer.string(forKey: "today.header.tomorrow")
            : renderer.formatter.date(lesson.date, style: .weekdayDayMonth)
        return renderer.format(key: "today.header.dayAndTime", arguments: [.text(day), .text(time)])
    }

    /// The one-line lesson: "10:55 · Biology · 214" (without a place: "10:55 · Biology").
    public func line(_ lesson: ResolvedLesson, today: LocalDate) -> String {
        let when = start(lesson, today: today)
        guard let place = place(lesson) else {
            return renderer.format(key: "today.hero.lesson", arguments: [.text(when), .text(lesson.subject.name)])
        }
        return renderer.format(key: "today.hero.lessonPlace",
                               arguments: [.text(when), .text(lesson.subject.name), .text(place)])
    }

    /// "What to bring: atlas, ruler"; `nil` for an empty list.
    public func bring(_ items: [String]) -> String? {
        items.isEmpty ? nil : renderer.format(key: "today.hero.bring", arguments: [.text(renderer.formatter.list(items))])
    }

    // MARK: Day off

    /// SF Symbol, title and detail of a day without lessons left: the holiday's name (or "Holidays") with "until Fri, Oct 30", "No
    /// lessons today", or "Lessons are cancelled today" with the user's note.
    public func dayOff(_ header: TodayState.Header, holidayEnd: LocalDate?, today: LocalDate) -> (symbol: String, title: String, detail: String?) {
        switch header {
        case let .holiday(name, _):
            return (AppSymbol.holiday.name, name ?? renderer.string(forKey: "today.header.holiday"),
                    holidayEnd.map { until($0, today: today) })
        case let .dayCancelled(note, _):
            return (AppSymbol.cancelledDay.name, renderer.string(forKey: "today.header.dayCancelled"), note)
        case .dayOver:
            return (AppSymbol.completed.name, renderer.string(forKey: "widget.dayOver"), nil)
        default:
            // The Timetable's "no lessons" symbol (DayEmptyView), not the Today tab's sun (one meaning per symbol).
            return ("moon.zzz", renderer.string(forKey: "today.header.free"), nil)
        }
    }

    // MARK: VoiceOver

    /// The hero as one VoiceOver sentence, in the reading order of the card (H13 / F02: subject, room, time left,
    /// next lesson; the teacher last). `bring` is the list the card shows.
    public func accessibilityLabel(_ state: TodayState, now: Date, bring: [String]) -> String {
        var parts: [String] = []
        let today = state.date
        func lessonParts(_ lesson: ResolvedLesson) {
            parts.append(lesson.subject.name)
            if let place = place(lesson) { parts.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(place)])) }
            let reasons = state.reasonsByOccurrence[lesson.id] ?? []
            if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                parts.append(renderer.string(forKey: badge.titleKey))
            }
        }
        func nextParts(_ lesson: ResolvedLesson?, captionKey: String) {
            if let lesson {
                parts.append(renderer.string(forKey: captionKey))
                parts.append(line(lesson, today: today))
            } else {
                parts.append(renderer.string(forKey: "today.header.nothingAhead"))
            }
        }
        switch state.header {
        case let .current(lesson, next):
            parts.append(renderer.string(forKey: "now.marker"))
            lessonParts(lesson)
            parts.append(left(until: lesson.end, now: now))
            parts.append(renderer.format(key: "widget.nowNext.a11y.endsAt",
                                         arguments: [.text(renderer.formatter.time(lesson.endTime))]))
            if let next { nextParts(next, captionKey: "today.header.next") }
            if let teacher = VisibleLessonFields(lesson: lesson, visibility: visibility).teacher {
                parts.append(renderer.format(key: "a11y.lesson.teacher", arguments: [.text(teacher)]))
            }
        case let .upcoming(lesson, isFirst):
            parts.append(renderer.string(forKey: isFirst ? "today.header.first" : "today.header.next"))
            lessonParts(lesson)
            parts.append(startsIn(lesson.start, now: now))
            parts.append(renderer.format(key: "widget.nowNext.a11y.startsAt",
                                         arguments: [.text(renderer.formatter.time(lesson.startTime))]))
        case .dayOver, .free, .holiday, .dayCancelled:
            let status = dayOff(state.header, holidayEnd: state.holidayEnd, today: today)
            parts.append(status.title)
            if let detail = status.detail { parts.append(detail) }
            nextParts(state.header.next, captionKey: "today.header.nextLesson")
        }
        if let bring = self.bring(bring) { parts.append(bring) }
        return parts.joined(separator: renderer.string(forKey: "a11y.separator"))
    }

    // MARK: Screen texts

    /// The navigation subtitle: "Tue, Oct 13 · Week B" (no year; the rotation phrase from `CycleLabel`, never
    /// "Week " + label).
    public func subtitle(_ state: TodayState) -> String {
        let date = renderer.formatter.contextualDate(state.date, today: state.date, style: .abbreviated)
        guard let cycle = state.cycle else { return date }
        return renderer.format(key: "today.subtitle.withCycle", arguments: [.text(date), .text(cycle.text(renderer: renderer))])
    }

    /// The exam row's second line: "Thu, Oct 22 · in 9 days".
    public func examWhen(_ row: ExamRow) -> String {
        let texts = ExamTexts(renderer: renderer)
        return renderer.format(key: "today.exam.when", arguments: [.text(texts.date(row.exam.date)), .text(texts.when(row.when))])
    }

    /// "1 overdue task" / "3 overdue tasks".
    public func overdue(_ count: Int) -> String {
        renderer.format(key: "today.tasks.overdueRow", arguments: [.integer(Int64(count))])
    }

    private func duration(until target: Date, now: Date) -> String {
        WidgetCountdownBuilder(renderer: renderer).durationText(Double(Self.minutesLeft(until: target, now: now)) * 60)
    }
}
