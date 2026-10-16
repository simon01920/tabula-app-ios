// Fixed scenes for the DEBUG `widgets.gallery` route (PHASE4_PLAN §0.10): widget snapshots of the seeded secondary
// timetable at fixed instants, so CI screenshots always show the same states. Pure, Linux-tested (each scene's
// state is asserted), shared by the app's gallery and the tests.
//
//   lesson   Tue 2026-10-13 10:20 (the scenarios' reference instant: a lesson in progress)
//   break    Tue 2026-10-13, two minutes before the end of the day's first gap between lessons
//   after    Tue 2026-10-13 17:00 (lessons over, tomorrow's first lesson next)
//   holiday  Thu 2026-10-29 09:00 (autumn holidays, next lesson after the break)
import Foundation
import TimetableCore

/// One gallery scene.
public struct WidgetGalleryScene: Sendable, Identifiable {
    /// Stable id ("lesson", "break", "after", "holiday").
    public let id: String
    /// Developer label (DEBUG gallery only, not localised).
    public let title: String
    /// The snapshot as the app would have written it at `date`.
    public let snapshot: WidgetSnapshot
    /// The fixed "now".
    public let date: Date
}

public enum WidgetGallerySamples {
    /// The calendar context of the seeded scenarios.
    public static var context: CalendarContext {
        CalendarContext(timeZone: SampleScenarios.timeZone, firstWeekday: .monday)
    }

    /// The scenes, built for `locale` / `languageCode` (the app's) with the Pro tier.
    public static func scenes(locale: Locale, languageCode: String?, tier: Tier = .pro) -> [WidgetGalleryScene] {
        let database = SampleScenarios.secondary().database
        let context = context
        func snapshot(at date: Date) -> WidgetSnapshot {
            WidgetSnapshotBuilder.make(database: database, now: date, context: context, tier: tier, locale: locale,
                                       languageCode: languageCode)
        }
        let today = SampleScenarios.today
        let lessonTime = SampleScenarios.referenceNow
        let reference = snapshot(at: lessonTime)
        let breakTime = firstGapEnd(in: reference, on: today, context: context).map { $0.addingTimeInterval(-120) }
            ?? context.date(today, LocalTime(hour: 9, minute: 43)!)
        let after = context.date(today, LocalTime(hour: 17, minute: 0)!)
        let holiday = context.date(LocalDate(year: 2026, month: 10, day: 29)!, LocalTime(hour: 9, minute: 0)!)
        return [
            WidgetGalleryScene(id: "lesson", title: "During a lesson", snapshot: reference, date: lessonTime),
            WidgetGalleryScene(id: "break", title: "In a break", snapshot: snapshot(at: breakTime), date: breakTime),
            WidgetGalleryScene(id: "after", title: "After school", snapshot: snapshot(at: after), date: after),
            WidgetGalleryScene(id: "holiday", title: "Holiday", snapshot: snapshot(at: holiday), date: holiday),
        ]
    }

    /// End of the first gap between two lessons that take place on `date` (start of the lesson after it).
    static func firstGapEnd(in snapshot: WidgetSnapshot, on date: LocalDate, context: CalendarContext) -> Date? {
        guard let day = snapshot.day(date) else { return nil }
        let lessons = WidgetTimelinePlanner.active(day, context)
        var latestEnd: Date?
        for lesson in lessons {
            let start = lesson.start(in: context)
            if let end = latestEnd, end < start { return start }
            latestEnd = max(latestEnd ?? lesson.end(in: context), lesson.end(in: context))
        }
        return nil
    }
}
