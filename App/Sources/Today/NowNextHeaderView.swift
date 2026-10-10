// The Now & Next header of Today:
// - in a lesson: subject, time, room, a live "time left" countdown and progress bar, then the next lesson;
// - before/between lessons: the next lesson with a live "starts in" countdown;
// - day over / free day / holiday / cancelled day: why, plus the next lesson with its day and time.
// Countdowns are `Text(timerInterval:pauseTime:countsDown:showsHours:)` and `ProgressView(timerInterval:)` (the
// system updates them; no per-second timers). With a fixed clock (screenshot mode) both are paused at `model.now`.
// APIs: Text(timerInterval:pauseTime:countsDown:showsHours:) (iOS 16),
//       ProgressView(timerInterval:countsDown:label:currentValueLabel:) (iOS 16), ProgressView(value:total:),
//       accessibilityElement(children:), accessibilityAddTraits(.isHeader), @ScaledMetric.
import SwiftUI
import TimetableCore
import TimetableUI

struct NowNextHeaderView: View {
    let header: TodayState.Header
    let today: LocalDate
    let visibility: FieldVisibility
    /// Modification reasons of today's / the next day's occurrences (for badges and VoiceOver).
    let reasons: [OccurrenceID: [ModificationReason]]
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch header {
            case let .current(lesson, next):
                currentSection(lesson)
                if let next {
                    Divider()
                    nextRow(next, captionKey: "today.header.next")
                }
            case let .upcoming(lesson, isFirst):
                upcomingSection(lesson, captionKey: isFirst ? "today.header.first" : "today.header.next")
            case let .dayOver(next):
                statusSection(symbol: "checkmark.circle", title: model.renderer.string(forKey: "today.header.dayOver"),
                              detail: nil)
                followUp(next)
            case let .free(next):
                statusSection(symbol: "sun.max", title: model.renderer.string(forKey: "today.header.free"), detail: nil)
                followUp(next)
            case let .holiday(name, next):
                statusSection(symbol: "beach.umbrella", title: name ?? model.renderer.string(forKey: "today.header.holiday"),
                              detail: name == nil ? nil : model.renderer.string(forKey: "today.header.holiday"))
                followUp(next)
            case let .dayCancelled(note, next):
                statusSection(symbol: "xmark.circle", title: model.renderer.string(forKey: "today.header.dayCancelled"),
                              detail: note)
                followUp(next)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.secondary.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }

    private var pauseTime: Date? { model.isClockFixed ? model.now : nil }

    // MARK: Sections

    private func currentSection(_ lesson: ResolvedLesson) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NowPill()
            lessonSummary(lesson, large: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("today.header.timeLeft")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(timerInterval: interval(lesson.start, lesson.end), pauseTime: pauseTime, countsDown: true,
                     showsHours: true)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                progress(lesson)
                    .tint(Color(LessonTileStyle(color: lesson.subject.color).background))
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func progress(_ lesson: ResolvedLesson) -> some View {
        if let pauseTime {
            let total = max(1, lesson.end.timeIntervalSince(lesson.start))
            ProgressView(value: min(max(0, pauseTime.timeIntervalSince(lesson.start)), total), total: total)
        } else {
            ProgressView(timerInterval: interval(lesson.start, lesson.end), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
        }
    }

    private func upcomingSection(_ lesson: ResolvedLesson, captionKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(captionKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            lessonSummary(lesson, large: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("today.header.startsIn")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(timerInterval: interval(model.now, lesson.start), pauseTime: pauseTime, countsDown: true,
                     showsHours: true)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statusSection(symbol: String, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func followUp(_ next: ResolvedLesson?) -> some View {
        if let next {
            Divider()
            nextRow(next, captionKey: "today.header.nextLesson")
        } else {
            Text("today.header.nothingAhead")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Next · Matematika · 9:50 – 10:35 · room 214" (with the day when it is not today).
    private func nextRow(_ lesson: ResolvedLesson, captionKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(captionKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 12) {
                SubjectBadge(subject: lesson.subject, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: lesson.subject.name)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: whenText(lesson))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    LessonFieldLinesView(lines: LessonFieldLines.make(lesson: lesson, visibility: visibility,
                                                                      only: [.room, .building]),
                                         font: .subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: nextAccessibilityLabel(lesson, captionKey: captionKey)))
    }

    /// "Next, tomorrow, Matematika, period 1, …": caption, day (when not today), lesson sentence.
    private func nextAccessibilityLabel(_ lesson: ResolvedLesson, captionKey: String) -> String {
        var parts = [model.renderer.string(forKey: captionKey)]
        if let day = whenDay(lesson) { parts.append(day) }
        parts.append(LessonAccessibilityLabel.make(lesson: lesson, visibility: visibility,
                                                   reasons: reasons[lesson.id] ?? [], renderer: model.renderer))
        return parts.joined(separator: model.renderer.string(forKey: "a11y.separator"))
    }

    private func lessonSummary(_ lesson: ResolvedLesson, large: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            SubjectBadge(subject: lesson.subject, size: large ? 52 : 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: lesson.subject.name)
                    .font(large ? .title2.weight(.bold) : .headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: model.formatter.timeRange(lesson.startTime, lesson.endTime))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                LessonFieldLinesView(lines: LessonFieldLines.make(lesson: lesson, visibility: visibility,
                                                                  only: [.room, .building, .teacher]),
                                     font: .subheadline)
                    .foregroundStyle(.secondary)
                if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons[lesson.id] ?? []) {
                    LessonStatusBadge(badge)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(lesson: lesson, visibility: visibility,
                                                                         reasons: reasons[lesson.id] ?? [],
                                                                         renderer: model.renderer)))
    }

    // MARK: Text

    /// The day of a lesson when it is not today: "Tomorrow" / "Wed 14 Oct"; `nil` for today.
    private func whenDay(_ lesson: ResolvedLesson) -> String? {
        if lesson.date == today { return nil }
        if lesson.date == today.adding(days: 1) { return model.renderer.string(forKey: "today.header.tomorrow") }
        return model.formatter.date(lesson.date, style: .weekdayDayMonth)
    }

    private func whenText(_ lesson: ResolvedLesson) -> String {
        let range = model.formatter.timeRange(lesson.startTime, lesson.endTime)
        guard let day = whenDay(lesson) else { return range }
        return model.renderer.format(key: "today.header.dayAndTime", arguments: [.text(day), .text(range)])
    }

    private func interval(_ start: Date, _ end: Date) -> ClosedRange<Date> {
        min(start, end)...max(start, end)
    }
}

/// "● Now" capsule.
private struct NowPill: View {
    var body: some View {
        Label {
            Text("today.header.now")
        } icon: {
            Circle().fill(Color.red).frame(width: 8, height: 8)
        }
        .font(.subheadline.weight(.bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().strokeBorder(Color.red, lineWidth: 1.5))
        .accessibilityAddTraits(.isHeader)
    }
}
