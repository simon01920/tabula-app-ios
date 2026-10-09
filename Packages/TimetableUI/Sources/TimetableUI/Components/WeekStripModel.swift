// The week strip above every timetable view: one entry per shown day with the selected-day pill, the today marker
// and a dot for days with changes (cancellations, substitutions, extra lessons, a cancelled day), plus the week's
// cycle label. The VoiceOver sentence of a day is built here too, so the dot is never the only carrier of meaning.
// Pure, Linux-tested.
import Foundation
import TimetableCore

/// One day of the week strip.
public struct WeekStripDay: Equatable, Sendable, Identifiable {
    public var date: LocalDate
    public var id: LocalDate { date }
    public var isToday: Bool
    public var isSelected: Bool
    /// Lessons can take place.
    public var isSchoolDay: Bool
    /// Lessons that take place (not cancelled).
    public var lessonCount: Int
    /// Occurrences that differ from the regular timetable (modified, added or cancelled).
    public var changeCount: Int
    /// The whole day is cancelled by a "cancel day" change.
    public var isDayCancelled: Bool
    /// A holiday/break covers the day.
    public var isInBreak: Bool
    /// The day's cycle position for day cycles ("Day 3"); `nil` otherwise.
    public var cycleDay: CycleLabel?

    /// Show the change dot.
    public var hasChanges: Bool { changeCount > 0 || isDayCancelled }
}

/// The week strip of one week.
public struct WeekStripModel: Equatable, Sendable {
    public var weekStart: LocalDate
    public var days: [WeekStripDay]
    /// The week's cycle label for week cycles ("Week A"); `nil` otherwise.
    public var cycleWeek: CycleLabel?
    /// `true` when the week contains today.
    public var containsToday: Bool

    /// Builds the strip for `selection` (shown days = the timetable's enabled days) with actual schedules.
    public static func make(selection: TimetableSelection, today: LocalDate, resolver: ScheduleResolver) -> WeekStripModel {
        let dates = TimetableSelection.shownDays(weekStart: selection.weekStart, resolver: resolver)
        let scheme = resolver.timetable.rotation
        let days = dates.map { date -> WeekStripDay in
            let schedule = resolver.day(date)
            return WeekStripDay(
                date: date, isToday: date == today, isSelected: date == selection.selectedDate,
                isSchoolDay: schedule.isSchoolDay,
                lessonCount: schedule.entries.filter { $0.status != .cancelled }.count,
                changeCount: schedule.entries.filter { $0.status != .scheduled }.count,
                isDayCancelled: schedule.cancellingOverrideID != nil, isInBreak: schedule.activeBreakID != nil,
                cycleDay: { if case .dayCycle = scheme { return CycleLabel.of(schedule, scheme: scheme) } else { return nil } }())
        }
        let middle = selection.weekStart.adding(days: 3)
        let cycleWeekNumber = resolver.rotation.cycleWeek(on: middle)
        let cycleWeek = CycleLabel.week(cycleWeekNumber, scheme: scheme,
                                        userLabel: cycleWeekNumber.flatMap(resolver.rotation.label(forCycleWeek:)))
        let weekEnd = selection.weekStart.adding(days: 6)
        return WeekStripModel(weekStart: selection.weekStart, days: days, cycleWeek: cycleWeek,
                              containsToday: selection.weekStart <= today && today <= weekEnd)
    }

    /// The VoiceOver sentence of a day: "Tuesday, 13 October, today, 7 lessons, 2 changes" (only true facts; parts
    /// joined with the catalog separator, each part one catalog phrase).
    public static func accessibilityLabel(_ day: WeekStripDay, renderer: LocalizedTextRenderer) -> String {
        var parts = [renderer.formatter.date(day.date, style: .full)]
        if day.isToday { parts.append(renderer.string(forKey: "timetable.strip.today")) }
        if let cycle = day.cycleDay { parts.append(cycle.text(renderer: renderer)) }
        if day.isInBreak {
            parts.append(renderer.string(forKey: "timetable.strip.holiday"))
        } else if day.isDayCancelled {
            parts.append(renderer.string(forKey: "timetable.strip.dayCancelled"))
        } else if day.lessonCount == 0 {
            parts.append(renderer.string(forKey: "timetable.strip.noLessons"))
        } else {
            parts.append(renderer.format(key: "timetable.strip.lessons", arguments: [.integer(Int64(day.lessonCount))]))
        }
        if day.changeCount > 0 {
            parts.append(renderer.format(key: "timetable.strip.changes", arguments: [.integer(Int64(day.changeCount))]))
        }
        return parts.joined(separator: renderer.string(forKey: "a11y.separator"))
    }
}
