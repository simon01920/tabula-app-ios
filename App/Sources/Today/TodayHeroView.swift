// The Today hero (Phase 4U U3; Opus review R1 / H2 / H13, Astra F02): the first row of Today, in one of five moments
// (`TodayMoment`, pure in TimetableUI/Components/TodayHero.swift):
//   in a lesson    NOW · until 10:45 / subject / room · teacher / ink progress / "25 min left" / Next 10:55 · Biology · 214
//   before school  First lesson · in 40 min / subject / room / 8:00 – 8:45 / What to bring: …
//   break          Next · in 2 min / subject / room / 10:55 – 11:40
//   after school   Done for today / Next lesson: Tomorrow, 8:00 · English · JAZ-2 / What to bring: …
//   day off        Autumn holidays · until Fri, Oct 30 (or no lessons / cancelled) / Next lesson: …
// Minutes only, rounded up, redrawn once a minute by the parent's TimelineView (no seconds, no "25:00"). The progress bar
// is ink, never the subject colour (a red subject must not read as an alarm). Reading order at every size: subject,
// room, time left, next lesson; at accessibility sizes the teacher (in the lesson detail and the VoiceOver sentence)
// leaves the card so the next lesson follows the essentials. VoiceOver reads the card as one sentence.
// Static content (no tap target): Now is status, not an action (Astra F17); the lesson rows below open the detail.
// APIs: ProgressView(value:total:), Divider, Label, accessibilityElement(children: .ignore), accessibilityLabel(_:),
//       Environment(\.dynamicTypeSize).
import SwiftUI
import TimetableCore
import TimetableUI

struct TodayHeroView: View {
    let state: TodayState
    let now: Date
    let visibility: FieldVisibility
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var text: TodayHeroText { TodayHeroText(renderer: model.renderer, visibility: visibility) }

    var body: some View {
        let bring = TodayHeroText.bringItems(state, visibility: visibility)
        VStack(alignment: .leading, spacing: 10) {
            switch state.header {
            case let .current(lesson, next):
                lessonHero(lesson, next: next)
            case let .upcoming(lesson, isFirst):
                upcomingHero(lesson, captionKey: isFirst ? "today.header.first" : "today.header.next")
            case .dayOver, .free, .holiday, .dayCancelled:
                dayOffHero()
            }
            if let line = text.bring(bring) {
                Label { Text(verbatim: line) } icon: { Image(AppSymbol.bringList) }
                    .font(TypeScale.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text.accessibilityLabel(state, now: now, bring: bring)))
    }

    // MARK: Moments

    @ViewBuilder
    private func lessonHero(_ lesson: ResolvedLesson, next: ResolvedLesson?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            NowMarker()
            Text(verbatim: text.until(lesson.endTime))
                .font(.subheadline)
                .timeStyle()
        }
        title(lesson)
        places(lesson, includesTeacher: !dynamicTypeSize.isAccessibilitySize)
        statusBadge(lesson)
        let total = max(1, lesson.end.timeIntervalSince(lesson.start))
        ProgressView(value: min(max(0, now.timeIntervalSince(lesson.start)), total), total: total)
            .tint(Color.ink)
        Text(verbatim: text.left(until: lesson.end, now: now))
            .font(TypeScale.detail)
            .countdownStyle()
        if let next {
            Divider()
            nextLine(next, captionKey: "today.header.next")
        }
    }

    @ViewBuilder
    private func upcomingHero(_ lesson: ResolvedLesson, captionKey: String) -> some View {
        AdaptiveStack(horizontalAlignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(captionKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: text.startsIn(lesson.start, now: now))
                .font(.subheadline)
                .countdownStyle()
        }
        title(lesson)
        places(lesson, includesTeacher: false)
        Text(verbatim: model.formatter.timeRange(lesson.startTime, lesson.endTime))
            .font(TypeScale.detail)
            .timeStyle()
        statusBadge(lesson)
    }

    @ViewBuilder
    private func dayOffHero() -> some View {
        let status = text.dayOff(state.header, holidayEnd: state.holidayEnd, today: state.date)
        AdaptiveStack(horizontalAlignment: .top, spacing: 12) {
            ScaledIcon(systemName: status.symbol, base: 26, maximum: 40)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: status.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = status.detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        Divider()
        if let next = state.header.next {
            nextLine(next, captionKey: "today.header.nextLesson")
        } else {
            Text("today.header.nothingAhead")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Parts

    private func title(_ lesson: ResolvedLesson) -> some View {
        Text(verbatim: lesson.subject.name)
            .font(TypeScale.currentLesson)
            .strikethrough(lesson.status == .cancelled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Room and building (and the teacher at ordinary sizes) in the primary colour (M9).
    private func places(_ lesson: ResolvedLesson, includesTeacher: Bool) -> some View {
        let fields: Set<LessonField> = includesTeacher ? [.room, .building, .teacher] : [.room, .building]
        return LessonFieldLinesView(lines: LessonFieldLines.make(lesson: lesson, visibility: visibility, only: fields),
                                    font: TypeScale.detail)
    }

    @ViewBuilder
    private func statusBadge(_ lesson: ResolvedLesson) -> some View {
        if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: state.reasonsByOccurrence[lesson.id] ?? []) {
            LessonStatusBadge(badge)
        }
    }

    /// "Next   10:55 · Biology · 214" (caption + one line; stacked at accessibility sizes).
    private func nextLine(_ lesson: ResolvedLesson, captionKey: String) -> some View {
        AdaptiveStack(horizontalAlignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(captionKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: text.line(lesson, today: state.date))
                .font(.subheadline)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
