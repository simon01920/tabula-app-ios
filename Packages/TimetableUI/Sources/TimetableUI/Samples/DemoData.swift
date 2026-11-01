// Demo data for the Developer screen (DEBUG UI): a `-TabulaSeed` scenario moved to the current week, so its
// "today", overdue task and upcoming exams read naturally on a real device. Applied with
// `DatabaseMutation.restore(_:mode: .replace)`, which re-stamps everything with the device's own clock.
//
// The shift is a whole number of weeks (weekdays and A/B lessons stay on their days), rounded so the scenario's
// reference Tuesday lands within three days of the real today.
import Foundation
import TimetableCore

/// A sample scenario dated around a given day.
public enum DemoData {
    /// The scenario's database moved to the week of `today`, with onboarding finished at `now` and its first timetable
    /// active. `nil` for kinds without a database (`.empty`).
    public static func database(_ kind: SeedKind, today: LocalDate, now: Date) -> TabulaDatabase? {
        guard var database = SampleScenarios.make(kind).database else { return nil }
        database = shifted(database, days: 7 * weeks(from: SampleScenarios.today, to: today))
        database.settings.onboardingCompletedAt = now
        database.settings.activeTimetableID = ActiveTimetable.resolve(database)?.id
        return database
    }

    /// Whole weeks from `reference` to the nearest same weekday around `today`.
    static func weeks(from reference: LocalDate, to today: LocalDate) -> Int {
        Int((Double(reference.days(to: today)) / 7).rounded())
    }

    /// Every stored date of `database` moved by `days` (wall-clock dates; instants keep their local time).
    static func shifted(_ database: TabulaDatabase, days: Int) -> TabulaDatabase {
        guard days != 0 else { return database }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SampleScenarios.timeZone
        func date(_ value: LocalDate) -> LocalDate { value.adding(days: days) }
        func range(_ value: LocalDateRange) -> LocalDateRange {
            LocalDateRange(start: date(value.start), end: date(value.end))
        }
        func instant(_ value: Date?) -> Date? { value.flatMap { calendar.date(byAdding: .day, value: days, to: $0) } }

        var db = database
        for index in db.timetables.indices {
            switch db.timetables[index].rotation {
            case .weekCycle(var cycle):
                if case let .referenceWeek(anchor, week) = cycle.anchor {
                    cycle.anchor = .referenceWeek(date: date(anchor), cycleWeek: week)
                }
                db.timetables[index].rotation = .weekCycle(cycle)
            case .dayCycle(var cycle):
                cycle.anchorDate = date(cycle.anchorDate)
                db.timetables[index].rotation = .dayCycle(cycle)
            case .none:
                break
            }
        }
        for index in db.lessons.indices {
            if case .range(let value) = db.lessons[index].validity { db.lessons[index].validity = .range(range(value)) }
        }
        for index in db.terms.indices { db.terms[index].range = range(db.terms[index].range) }
        for index in db.breaks.indices { db.breaks[index].range = range(db.breaks[index].range) }
        for index in db.overrides.indices { db.overrides[index].date = date(db.overrides[index].date) }
        for index in db.tasks.indices {
            var task = db.tasks[index]
            switch task.due {
            case .date(let day)?: task.due = .date(date(day))
            case .dateTime(let day, let time)?: task.due = .dateTime(date(day), time)
            default: break
            }
            if let link = task.linkedLesson { task.linkedLesson?.date = date(link.date) }
            if let until = task.repeatRule?.until { task.repeatRule?.until = date(until) }
            task.completedAt = instant(task.completedAt)
            for sub in task.subtasks.indices { task.subtasks[sub].completedAt = instant(task.subtasks[sub].completedAt) }
            db.tasks[index] = task
        }
        for index in db.exams.indices {
            db.exams[index].date = date(db.exams[index].date)
            db.exams[index].completedAt = instant(db.exams[index].completedAt)
        }
        return db
    }
}
