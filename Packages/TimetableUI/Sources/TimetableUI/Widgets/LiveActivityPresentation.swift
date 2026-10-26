// View-independent presentation of the two Live Activities (Stage B2): every string, the live-timer intervals, the
// VoiceOver sentences and the deep link, for one content state at one instant. Pure, Linux-tested; the SwiftUI views
// (LiveActivityViews.swift) only lay it out, so the widget extension and the app's DEBUG gallery render the same thing.
//
// "Now" is the render time: the extension passes `Date()` when the system asks for the views (start, every update,
// and when the activity becomes stale at its stale date — the planner sets that to the next lesson boundary / the exam
// start and end), the gallery a fixed instant. The live remaining time is never a string: views show `timer` with
// `Text(timerInterval:)`, which the system keeps counting without updates. VoiceOver gets static sentences naming
// the end / start time instead (`accessibilityLabel`, `timerAccessibilityLabel`).
//
// Strings reuse the Today header's catalog keys (`today.header.*`, `a11y.lesson.*`, `widget.nowNext.*`) so the
// activity, the widgets and the Today tab use the same words; only the exam phases and the alert format are new
// (`liveActivity.*`, registered in DynamicL10nKeys).
import Foundation
import TimetableCore

/// Everything a Live Activity view needs at one instant.
public struct LiveActivityDisplay: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Before the lesson / exam (counting down to the start).
        case upcoming
        /// A lesson / the exam is in progress.
        case running
        /// The day's lessons / the exam are over (final content).
        case finished
    }

    public var phase: Phase
    /// `true` for the exam-day activity.
    public var isExam: Bool
    /// "Now", "Next", "First Lesson", "Exam today", "In progress", "Exam finished"; `nil` for "No more lessons today".
    public var caption: String?
    /// Subject name, exam title, or the finished state's text.
    public var title: String
    /// The subject badge (colour, emoji / symbol / short name); `nil` → `symbol`.
    public var subject: SubjectSummary?
    /// SF Symbol when there is no subject badge.
    public var symbol: String
    /// "12 · 8:55–9:40" (room and time).
    public var detail: String?
    /// "Time left" / "Starts in".
    public var timerCaption: String?
    /// Live countdown interval (to the end while running, to the start before).
    public var timer: ClosedRange<Date>?
    /// Live progress interval (running lessons and exams with an end).
    public var progress: ClosedRange<Date>?
    /// "Next: Biology, 9:50" (running lessons).
    public var next: String?
    /// Short static text for the compact trailing area when there is no timer (start time, "✓").
    public var compactText: String
    /// One VoiceOver sentence for the whole activity.
    public var accessibilityLabel: String
    /// Spoken text of a timer shown alone (compact / minimal Dynamic Island): "Mathematics, ends at 9:40".
    public var timerAccessibilityLabel: String
    /// Where a tap goes.
    public var link: ItemLink
    /// The countdown with its unit word ("left" / "until start"); `nil` without a timer (U7, H2). Exams are always
    /// minutes only.
    public var countdown: WidgetCountdown?
    /// `true` while a lesson runs: the views draw the highlighter "NOW" marker in place of the caption (U7).
    public var showsNowMarker = false

    /// Fraction of `progress` elapsed at `instant` (0…1), for static (paused) progress views.
    public func progressValue(at instant: Date) -> Double {
        guard let progress else { return 0 }
        let total = progress.upperBound.timeIntervalSince(progress.lowerBound)
        guard total > 0 else { return 1 }
        return min(1, max(0, instant.timeIntervalSince(progress.lowerBound) / total))
    }
}

/// Builds `LiveActivityDisplay` values.
public struct LiveActivityPresenter: Sendable {
    public let renderer: LocalizedTextRenderer
    /// The calendar context of the style's zone (wall-clock times of the instants).
    public let context: CalendarContext

    public init(renderer: LocalizedTextRenderer, context: CalendarContext) {
        self.renderer = renderer
        self.context = context
    }

    /// The presenter for `style` with `lookup` (the catalog in the style's language).
    public init(style: LiveActivityStyle, lookup: @escaping LocalizedTextRenderer.Lookup) {
        let zone = style.timeZone
        let formatter = TimetableFormatter(locale: Locale(identifier: style.localeID), hourCycle: style.hourCycle,
                                           timeZone: zone)
        self.init(renderer: LocalizedTextRenderer(formatter: formatter, lookup: lookup),
                  context: CalendarContext(timeZone: zone, firstWeekday: .monday))
    }

    // MARK: (a) Lessons

    /// The lesson activity at `now`.
    public func lesson(_ state: LessonActivityAttributes.ContentState, now: Date) -> LiveActivityDisplay {
        var shown = lessonBase(state, now: now)
        shown.showsNowMarker = shown.phase == .running
        return withCountdown(shown, now: now, allowsSeconds: true)
    }

    /// `display` with its countdown (unit word, minutes-only above an hour, never seconds for exams; U7 H2).
    func withCountdown(_ display: LiveActivityDisplay, now: Date, allowsSeconds: Bool) -> LiveActivityDisplay {
        var shown = display
        if let timer = display.timer {
            shown.countdown = WidgetCountdownBuilder(renderer: renderer).make(
                interval: timer, now: now, kind: display.phase == .running ? .left : .untilStart,
                allowsSeconds: allowsSeconds)
        }
        return shown
    }

    private func lessonBase(_ state: LessonActivityAttributes.ContentState, now: Date) -> LiveActivityDisplay {
        let lessons = state.lessons
        let lowerBound = min(max(0, state.index), lessons.count)
        guard !state.isFinal, let index = LiveActivityTimeline.currentIndex(in: lessons, at: now, from: lowerBound) else {
            let title = renderer.string(forKey: "widget.dayOver")
            return LiveActivityDisplay(phase: .finished, isExam: false, caption: nil, title: title, subject: nil,
                                       symbol: "checkmark.circle.fill", detail: nil, timerCaption: nil, timer: nil,
                                       progress: nil, next: nil, compactText: "✓", accessibilityLabel: title,
                                       timerAccessibilityLabel: title, link: .today)
        }
        let lesson = lessons[index]
        let separator = renderer.string(forKey: "a11y.separator")
        let detail = [lesson.room, timeRange(lesson.start, lesson.end)].compactMap { $0 }.joined(separator: " · ")
        let name = lesson.subject.name
        var spokenParts = [name, renderer.format(key: "a11y.lesson.time", arguments: [
            .text(time(lesson.start)), .text(time(lesson.end)),
        ])]
        if let room = lesson.room { spokenParts.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(room)])) }

        if lesson.start <= now {
            let caption = renderer.string(forKey: "today.header.now")
            let following = lessons.indices.first { $0 > index && lessons[$0].start >= now }.map { lessons[$0] }
            let endsAt = renderer.format(key: "widget.nowNext.a11y.endsAt", arguments: [.text(time(lesson.end))])
            var spoken = [caption] + spokenParts + [endsAt]
            if let following {
                spoken.append([renderer.string(forKey: "today.header.next"), time(following.start), following.subject.name]
                    .joined(separator: separator))
            }
            return LiveActivityDisplay(
                phase: .running, isExam: false, caption: caption, title: name, subject: lesson.subject.summary,
                symbol: "book.closed.fill", detail: detail, timerCaption: renderer.string(forKey: "today.header.timeLeft"),
                timer: lesson.start...lesson.end, progress: lesson.start...lesson.end,
                next: following.map { nextShort($0) }, compactText: time(lesson.end),
                accessibilityLabel: spoken.joined(separator: separator),
                timerAccessibilityLabel: [name, endsAt].joined(separator: separator), link: .today)
        }
        let isFirst = index == 0
        let caption = renderer.string(forKey: isFirst ? "today.header.first" : "today.header.next")
        let startsAt = renderer.format(key: "widget.nowNext.a11y.startsAt", arguments: [.text(time(lesson.start))])
        let spoken = [caption] + spokenParts + [startsAt]
        return LiveActivityDisplay(
            phase: .upcoming, isExam: false, caption: caption, title: name, subject: lesson.subject.summary,
            symbol: "book.closed.fill", detail: detail, timerCaption: renderer.string(forKey: "today.header.startsIn"),
            timer: min(now, lesson.start)...lesson.start, progress: nil, next: nil, compactText: time(lesson.start),
            accessibilityLabel: spoken.joined(separator: separator),
            timerAccessibilityLabel: [name, startsAt].joined(separator: separator), link: .today)
    }

    // MARK: (b) Exams

    /// The exam activity of `examID` at `now`.
    public func exam(_ state: ExamActivityAttributes.ContentState, examID: UUID, now: Date) -> LiveActivityDisplay {
        withCountdown(examBase(state, examID: examID, now: now), now: now, allowsSeconds: false)
    }

    private func examBase(_ state: ExamActivityAttributes.ContentState, examID: UUID, now: Date) -> LiveActivityDisplay {
        let separator = renderer.string(forKey: "a11y.separator")
        let when = state.end.map { timeRange(state.start, $0) } ?? time(state.start)
        let detail = [state.room, when].compactMap { $0 }.joined(separator: " · ")
        var parts = [state.title]
        if let subject = state.subject, subject.name != state.title { parts.append(subject.name) }
        parts.append(state.end.map {
            renderer.format(key: "a11y.lesson.time", arguments: [.text(time(state.start)), .text(time($0))])
        } ?? time(state.start))
        if let room = state.room { parts.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(room)])) }
        let link = ItemLink.exam(Exam.ID(examID))
        let subject = state.subject?.summary
        let symbol = "graduationcap.fill"

        if state.isFinal || now >= state.close {
            let caption = renderer.string(forKey: "liveActivity.exam.finished")
            return LiveActivityDisplay(
                phase: .finished, isExam: true, caption: caption, title: state.title, subject: subject, symbol: symbol,
                detail: detail, timerCaption: nil, timer: nil, progress: nil, next: nil, compactText: "✓",
                accessibilityLabel: ([caption] + parts).joined(separator: separator),
                timerAccessibilityLabel: [state.title, caption].joined(separator: separator), link: link)
        }
        if now >= state.start {
            let caption = renderer.string(forKey: "liveActivity.exam.inProgress")
            if let end = state.end {
                let endsAt = renderer.format(key: "widget.nowNext.a11y.endsAt", arguments: [.text(time(end))])
                return LiveActivityDisplay(
                    phase: .running, isExam: true, caption: caption, title: state.title, subject: subject, symbol: symbol,
                    detail: detail, timerCaption: renderer.string(forKey: "today.header.timeLeft"), timer: state.start...end,
                    progress: state.start...end, next: nil, compactText: time(end),
                    accessibilityLabel: ([caption] + parts + [endsAt]).joined(separator: separator),
                    timerAccessibilityLabel: [state.title, endsAt].joined(separator: separator), link: link)
            }
            return LiveActivityDisplay(
                phase: .running, isExam: true, caption: caption, title: state.title, subject: subject, symbol: symbol,
                detail: detail, timerCaption: nil, timer: nil, progress: nil, next: nil, compactText: time(state.start),
                accessibilityLabel: ([caption] + parts).joined(separator: separator),
                timerAccessibilityLabel: [state.title, caption].joined(separator: separator), link: link)
        }
        let caption = renderer.string(forKey: "liveActivity.exam.today")
        let startsAt = renderer.format(key: "widget.nowNext.a11y.startsAt", arguments: [.text(time(state.start))])
        return LiveActivityDisplay(
            phase: .upcoming, isExam: true, caption: caption, title: state.title, subject: subject, symbol: symbol,
            detail: detail, timerCaption: renderer.string(forKey: "today.header.startsIn"),
            timer: min(now, state.start)...state.start, progress: nil, next: nil, compactText: time(state.start),
            accessibilityLabel: ([caption] + parts + [startsAt]).joined(separator: separator),
            timerAccessibilityLabel: [state.title, startsAt].joined(separator: separator), link: link)
    }

    // MARK: Internals

    func time(_ instant: Date) -> String { renderer.formatter.time(instant) }

    func timeRange(_ start: Date, _ end: Date) -> String {
        renderer.formatter.timeRange(context.local(from: start).time, context.local(from: end).time)
    }

    /// "Next: Biology, 9:50".
    func nextShort(_ lesson: LiveActivityLesson) -> String {
        renderer.format(key: "widget.nowNext.nextShort", arguments: [.text(lesson.subject.name), .text(time(lesson.start))])
    }
}
