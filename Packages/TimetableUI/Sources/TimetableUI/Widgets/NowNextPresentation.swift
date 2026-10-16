// View-independent presentation of one Now & Next timeline entry: every string the widget shows (rendered through
// `LocalizedTextRenderer` in the app's language, times through `TimetableFormatter` with the app's 12/24 h setting),
// the live-timer interval, the VoiceOver sentence and the deep link. Pure, Linux-tested; the SwiftUI views in
// NowNextWidgetViews.swift only lay it out, so the widget extension and the app's DEBUG gallery render the same thing.
//
// Strings reuse the Today header's catalog keys (`today.header.*`, `a11y.lesson.*`), so the widget and the Today tab
// use the same words in all 12 languages. The live remaining time is never a string: views show `timer` with
// `Text(timerInterval:)`; the VoiceOver sentence names the end / start time instead (a static value VoiceOver can read).
import Foundation
import TimetableCore

/// Everything a Now & Next widget view needs for one entry.
public struct NowNextDisplay: Equatable, Sendable {
    /// One lesson, formatted.
    public struct LessonLine: Equatable, Sendable, Identifiable {
        /// Occurrence ID.
        public var id: String
        /// Subject (badge colour / symbol).
        public var subject: SubjectSummary
        /// "8:55 – 9:40".
        public var timeRange: String
        /// "8:55".
        public var startText: String
        /// "8:55" today, "Tomorrow, 8:55", "Mon 19 Oct, 8:55" later.
        public var whenText: String
        /// Room (field rule applied), if any.
        public var room: String?
        /// Status badge text ("Room changed", "Extra lesson"), if the lesson differs from the regular timetable.
        public var badgeText: String?
        /// Start instant.
        public var start: Date
        /// End instant (≥ start).
        public var end: Date

        /// Subject name.
        public var name: String { subject.name }
    }

    /// The main content.
    public enum Kind: Equatable, Sendable {
        /// A lesson in progress.
        case current(LessonLine)
        /// The next lesson today.
        case upcoming(LessonLine)
        /// No lesson now or later today: why (SF Symbol + title + optional detail).
        case status(symbol: String, title: String, detail: String?)
        /// Nothing can be shown: open the app.
        case unavailable(title: String, detail: String)
    }

    /// The entry's date (the static "now" of the gallery).
    public var date: Date
    /// Main content.
    public var kind: Kind
    /// "Now" / "Next" / "First Lesson" (lesson kinds only).
    public var caption: String?
    /// "Time left" / "Starts in" (lesson kinds only).
    public var timerCaption: String?
    /// Live countdown interval: lesson start…end (current), entry date…lesson start (upcoming).
    public var timer: ClosedRange<Date>?
    /// The next lesson after the main content (current → following lesson; status → next lesson).
    public var next: LessonLine?
    /// "Next" (after a current lesson) / "Next Lesson" (after a status).
    public var nextCaption: String?
    /// "Next: Biology 9:50" — one line for small and accessory families.
    public var nextShort: String?
    /// "No lessons in the next few weeks." (status without a next lesson).
    public var nothingAhead: String?
    /// Further lessons on the next lesson's day (medium family).
    public var later: [LessonLine]
    /// The accessoryInline text when no live timer is shown; for a current lesson the subject name shown before the timer.
    public var inlineText: String
    /// One VoiceOver sentence for the whole widget.
    public var accessibilityLabel: String
    /// Where a tap goes.
    public var link: ItemLink
    /// Caption of the medium family's list: "Next" after a current lesson, else "Later".
    public var laterCaption: String = ""

    /// Fraction of the current lesson elapsed at `instant` (0…1), for static (paused) progress views.
    public func progress(at instant: Date) -> Double {
        guard case .current(let lesson) = kind else { return 0 }
        let total = lesson.end.timeIntervalSince(lesson.start)
        guard total > 0 else { return 1 }
        return min(1, max(0, instant.timeIntervalSince(lesson.start) / total))
    }
}

/// Builds `NowNextDisplay` values.
public struct NowNextPresenter: Sendable {
    /// Renderer (catalog lookup in the app's language + formatter with the app's locale and 12/24 h).
    public let renderer: LocalizedTextRenderer
    /// The context the instants were planned in.
    public let context: CalendarContext

    public init(renderer: LocalizedTextRenderer, context: CalendarContext) {
        self.renderer = renderer
        self.context = context
    }

    /// The renderer for `snapshot`: its locale + 12/24 h, the planning zone, and `lookup` (catalog in its language).
    public static func renderer(for snapshot: WidgetSnapshot?, context: CalendarContext,
                                lookup: @escaping LocalizedTextRenderer.Lookup) -> LocalizedTextRenderer {
        let locale = snapshot.map { Locale(identifier: $0.localeID) } ?? Locale(identifier: "en_US_POSIX")
        let formatter = TimetableFormatter(locale: locale, hourCycle: snapshot?.hourCycle ?? .auto,
                                           timeZone: context.timeZone)
        return LocalizedTextRenderer(formatter: formatter, lookup: lookup)
    }

    /// The display of `entry`.
    public func display(_ entry: NowNextTimelineEntry) -> NowNextDisplay {
        var result = content(entry)
        switch result.kind {
        case .current: result.laterCaption = renderer.string(forKey: "today.header.next")
        case .upcoming, .status: result.laterCaption = renderer.string(forKey: "widget.nowNext.later")
        case .unavailable: break
        }
        return result
    }

    /// Texts of the Pro placeholder: "Available in Tabula Pro" and the short "Pro" (accessoryCircular).
    public func proTexts() -> (title: String, short: String) {
        (renderer.string(forKey: "widget.pro.title"), renderer.string(forKey: "widget.pro.short"))
    }

    func content(_ entry: NowNextTimelineEntry) -> NowNextDisplay {
        let today = context.localDate(of: entry.date)
        let later = entry.laterLessons.map { line($0, today: today) }
        let separator = renderer.string(forKey: "a11y.separator")
        switch entry.state {
        case let .current(lesson, next):
            let main = line(lesson, today: today)
            let nextLine = next.map { line($0, today: today) }
            let caption = renderer.string(forKey: "today.header.now")
            var spoken = [caption] + lessonParts(main, lesson)
            spoken.append(renderer.format(key: "widget.nowNext.a11y.endsAt", arguments: [.text(renderer.formatter.time(lesson.endTime))]))
            if let nextLine { spoken.append(nextSentence(nextLine, captionKey: "today.header.next")) }
            return NowNextDisplay(
                date: entry.date, kind: .current(main), caption: caption,
                timerCaption: renderer.string(forKey: "today.header.timeLeft"), timer: main.start...main.end,
                next: nextLine, nextCaption: nextLine == nil ? nil : renderer.string(forKey: "today.header.next"),
                nextShort: nextLine.map(nextShort), nothingAhead: nil, later: later,
                inlineText: main.name, accessibilityLabel: spoken.joined(separator: separator), link: .today)
        case let .upcoming(lesson, isFirst):
            let main = line(lesson, today: today)
            let captionKey = isFirst ? "today.header.first" : "today.header.next"
            let caption = renderer.string(forKey: captionKey)
            var spoken = [caption] + lessonParts(main, lesson)
            spoken.append(renderer.format(key: "widget.nowNext.a11y.startsAt", arguments: [.text(main.startText)]))
            let start = max(entry.date, main.start)
            return NowNextDisplay(
                date: entry.date, kind: .upcoming(main), caption: caption,
                timerCaption: renderer.string(forKey: "today.header.startsIn"), timer: min(entry.date, start)...start,
                next: nil, nextCaption: nil, nextShort: nil, nothingAhead: nil, later: later,
                inlineText: nextShort(main), accessibilityLabel: spoken.joined(separator: separator), link: .today)
        case .dayOver, .free, .holiday, .dayCancelled:
            let (symbol, title, detail) = status(entry.state)
            let nextLine = entry.state.next.map { line($0, today: today) }
            var spoken = [title] + (detail.map { [$0] } ?? [])
            let nothing = nextLine == nil ? renderer.string(forKey: "today.header.nothingAhead") : nil
            if let nextLine { spoken.append(nextSentence(nextLine, captionKey: "today.header.nextLesson")) }
            if let nothing { spoken.append(nothing) }
            return NowNextDisplay(
                date: entry.date, kind: .status(symbol: symbol, title: title, detail: detail), caption: nil,
                timerCaption: nil, timer: nil, next: nextLine,
                nextCaption: nextLine == nil ? nil : renderer.string(forKey: "today.header.nextLesson"),
                nextShort: nextLine.map(nextShort), nothingAhead: nothing, later: later,
                inlineText: nextLine.map(nextShort) ?? title, accessibilityLabel: spoken.joined(separator: separator),
                link: .today)
        case .unavailable(let reason):
            let title = renderer.string(forKey: "widget.open.title")
            let detail: String
            switch reason {
            case .noTimetable: detail = renderer.string(forKey: "widget.open.noTimetable")
            case .noSnapshot: detail = renderer.string(forKey: "widget.open.noSnapshot")
            case .outdated: detail = renderer.string(forKey: "widget.open.outdated")
            }
            return NowNextDisplay(
                date: entry.date, kind: .unavailable(title: title, detail: detail), caption: nil, timerCaption: nil,
                timer: nil, next: nil, nextCaption: nil, nextShort: nil, nothingAhead: nil, later: [],
                inlineText: title, accessibilityLabel: [title, detail].joined(separator: separator), link: .today)
        }
    }

    // MARK: Internals

    func line(_ lesson: WidgetSnapshot.Lesson, today: LocalDate) -> NowNextDisplay.LessonLine {
        let formatter = renderer.formatter
        let start = formatter.time(lesson.startTime)
        let when: String
        if lesson.date == today {
            when = start
        } else {
            let day = lesson.date == today.adding(days: 1)
                ? renderer.string(forKey: "today.header.tomorrow")
                : formatter.date(lesson.date, style: .weekdayDayMonth)
            when = renderer.format(key: "today.header.dayAndTime", arguments: [.text(day), .text(start)])
        }
        let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: lesson.reasons ?? [])
        return NowNextDisplay.LessonLine(
            id: lesson.id, subject: lesson.subject, timeRange: formatter.timeRange(lesson.startTime, lesson.endTime),
            startText: start, whenText: when, room: lesson.room, badgeText: badge.map { renderer.string(forKey: $0.titleKey) },
            start: lesson.start(in: context), end: lesson.end(in: context))
    }

    /// "Next: Biology 9:50".
    func nextShort(_ line: NowNextDisplay.LessonLine) -> String {
        renderer.format(key: "widget.nowNext.nextShort", arguments: [.text(line.name), .text(line.whenText)])
    }

    /// Subject, time, room and change, as in the Today header's VoiceOver sentence.
    func lessonParts(_ line: NowNextDisplay.LessonLine, _ lesson: WidgetSnapshot.Lesson) -> [String] {
        var parts = [line.name, renderer.format(key: "a11y.lesson.time", arguments: [
            .text(renderer.formatter.time(lesson.startTime)), .text(renderer.formatter.time(lesson.endTime)),
        ])]
        if let room = line.room { parts.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(room)])) }
        switch lesson.status {
        case .scheduled: break
        case .cancelled: parts.append(renderer.string(forKey: "a11y.lesson.cancelled"))
        case .added: parts.append(renderer.string(forKey: "a11y.lesson.added"))
        case .modified:
            let reasons = lesson.reasons ?? []
            if reasons.isEmpty {
                parts.append(renderer.string(forKey: "a11y.lesson.modified"))
            } else {
                let what = renderer.formatter.list(reasons.map { renderer.string(forKey: $0.l10nKey) })
                parts.append(renderer.format(key: "a11y.lesson.modifiedReasons", arguments: [.text(what)]))
            }
        }
        return parts
    }

    /// "Next, Tomorrow, 8:00, Biology, room 12".
    func nextSentence(_ line: NowNextDisplay.LessonLine, captionKey: String) -> String {
        var parts = [renderer.string(forKey: captionKey), line.whenText, line.name]
        if let room = line.room { parts.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(room)])) }
        return parts.joined(separator: renderer.string(forKey: "a11y.separator"))
    }

    func status(_ state: NowNextState) -> (symbol: String, title: String, detail: String?) {
        switch state {
        case .dayOver:
            return ("checkmark.circle", renderer.string(forKey: "today.header.dayOver"), nil)
        case let .holiday(name, _):
            let holiday = renderer.string(forKey: "today.header.holiday")
            return ("beach.umbrella", name ?? holiday, name == nil ? nil : holiday)
        case let .dayCancelled(note, _):
            return ("xmark.circle", renderer.string(forKey: "today.header.dayCancelled"), note)
        default:
            return ("sun.max", renderer.string(forKey: "today.header.free"), nil)
        }
    }
}
