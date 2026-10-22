// Fixed scenes for the DEBUG Live Activity gallery (`widgets.gallery-live`, `widgets.gallery-live-exam`; Stage B2):
// content states built by the real planner from the seeded secondary timetable at fixed instants, so CI screenshots
// always show the same states. Pure, Linux-tested (each scene's phase is asserted).
//
//   lesson        Tue 2026-10-13 10:20 (a lesson in progress, the next one after it)
//   break         Tue 2026-10-13, two minutes before the end of the first gap between lessons
//   finished      Tue 2026-10-13 17:00 (final content: "No more lessons today")
//   examCountdown Thu 2026-10-22 08:30 (chemistry test at 10:00, counting down)
//   examRunning   Thu 2026-10-22 10:20 (in progress until 10:45)
import Foundation
import TimetableCore

/// One gallery scene: a lesson or an exam content state at a fixed instant.
public struct LiveActivityGalleryScene: Sendable, Identifiable {
    public enum Content: Sendable {
        case lesson(LessonActivityAttributes.ContentState)
        case exam(UUID, ExamActivityAttributes.ContentState)
    }

    /// Stable id ("lesson", "break", "finished", "examCountdown", "examRunning").
    public let id: String
    /// Developer label (DEBUG gallery only, not localised).
    public let title: String
    /// The fixed "now".
    public let date: Date
    public let content: Content
}

public enum LiveActivityGallerySamples {
    /// The scenes for `locale` / `languageCode` (the app's).
    public static func scenes(locale: Locale, languageCode: String?) -> [LiveActivityGalleryScene] {
        let database = SampleScenarios.secondary().database
        let context = WidgetGallerySamples.context
        func sources(at date: Date) -> LiveActivitySources {
            LiveActivitySourceBuilder.make(database: database, now: date, context: context, locale: locale,
                                           languageCode: languageCode)
        }
        var scenes: [LiveActivityGalleryScene] = []
        let today = SampleScenarios.today
        func lessonScene(_ id: String, _ title: String, _ date: Date) {
            let source = sources(at: date)
            guard let day = source.lessonDay(today) else { return }
            let content = date >= day.lastEnd
                ? LiveActivityPlanner.finalLessonContent(source.style)
                : LiveActivityPlanner.runningLessonContent(day, source.style, now: date)
            scenes.append(LiveActivityGalleryScene(id: id, title: title, date: date, content: .lesson(content.state)))
        }
        lessonScene("lesson", "Lesson in progress", SampleScenarios.referenceNow)
        let reference = WidgetSnapshotBuilder.make(database: database, now: SampleScenarios.referenceNow, context: context,
                                                   tier: .pro, locale: locale, languageCode: languageCode)
        let breakTime = WidgetGallerySamples.firstGapEnd(in: reference, on: today, context: context)
            .map { $0.addingTimeInterval(-120) } ?? context.date(today, LocalTime(hour: 9, minute: 43)!)
        lessonScene("break", "In a break", breakTime)
        lessonScene("finished", "After the last lesson", context.date(today, LocalTime(hour: 17, minute: 0)!))

        let examDay = LocalDate(year: 2026, month: 10, day: 22)!
        func examScene(_ id: String, _ title: String, _ date: Date) {
            guard let exam = sources(at: date).exams.first(where: { $0.day == examDay }) else { return }
            let content = LiveActivityPlanner.runningExamContent(exam, sources(at: date).style, now: date)
            scenes.append(LiveActivityGalleryScene(id: id, title: title, date: date, content: .exam(exam.id, content.state)))
        }
        examScene("examCountdown", "Exam day, before the exam", context.date(examDay, LocalTime(hour: 8, minute: 30)!))
        examScene("examRunning", "Exam in progress", context.date(examDay, LocalTime(hour: 10, minute: 20)!))
        return scenes
    }
}
