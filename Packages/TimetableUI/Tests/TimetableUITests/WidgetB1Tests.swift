// Phase 4 B1: the Today / Homework / Next exam widgets' pure logic — snapshot extension (overdue list), the Homework and
// Exam state planners, the three presenters, the Pro gate of their families and the gallery scenes. Hand-made snapshots
// for exact boundaries; the seeded secondary profile for "the widget shows what the app shows".
import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let zone = SampleScenarios.timeZone
private let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func instant(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> Date { context.date(day, time(h, m)) }
private let today = SampleScenarios.today   // Tue 2026-10-13

private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: zone),
    lookup: EnglishCatalog.lookup)

private let math = SubjectSummary(id: Subject.ID(UUID()), name: "Mathematics", shortName: "MAT",
                                  color: ColorValue(red: 30, green: 90, blue: 200))
private let bio = SubjectSummary(id: Subject.ID(UUID()), name: "Biology", color: ColorValue(red: 240, green: 220, blue: 60),
                                 symbol: .emoji("🧬"))

private func task(_ title: String, _ due: LocalDate, _ at: LocalTime? = nil, priority: TaskPriority = .normal,
                  subject: SubjectSummary? = math) -> WidgetSnapshot.DueTask {
    WidgetSnapshot.DueTask(id: UUID(), title: title, subject: subject, dueDate: due, dueTime: at, priority: priority)
}

private func exam(on day: LocalDate, start: LocalTime? = time(10), end: LocalTime? = time(10, 45),
                  room: String? = "Lab") -> WidgetSnapshot.UpcomingExam {
    WidgetSnapshot.UpcomingExam(id: UUID(), title: "Organic chemistry", subject: bio, date: day, start: start, end: end,
                                room: room)
}

private func lesson(_ name: String, _ day: LocalDate, _ start: LocalTime, _ end: LocalTime, subject: SubjectSummary = math,
                    room: String? = "214", status: ResolvedLesson.Status = .scheduled,
                    reasons: [ModificationReason]? = nil) -> WidgetSnapshot.Lesson {
    WidgetSnapshot.Lesson(id: "lesson:\(name):\(day.isoString)", subject: subject, date: day, startTime: start,
                          endTime: end, room: room, status: status, reasons: reasons)
}

private func school(_ day: LocalDate, _ lessons: [WidgetSnapshot.Lesson] = []) -> WidgetSnapshot.Day {
    WidgetSnapshot.Day(date: day, kind: .school, lessons: lessons)
}

/// Covers today … today + 2 unless `days` is given; written at 08:00 today.
private func snapshot(days: [WidgetSnapshot.Day]? = nil, tasks: [WidgetSnapshot.DueTask] = [],
                      overdue: [WidgetSnapshot.DueTask]? = nil, overdueCount: Int = 0,
                      exam: WidgetSnapshot.UpcomingExam? = nil, exams: [WidgetSnapshot.UpcomingExam]? = nil,
                      openTaskCount: Int? = nil, tier: Tier = .pro) -> WidgetSnapshot {
    WidgetSnapshot(generatedAt: instant(today, 8), timeZoneID: zone.identifier, followsDeviceTimeZone: false,
                   localeID: "en_GB", languageCode: "en", hourCycle: .h24, tier: tier, hasTimetable: true,
                   days: days ?? [school(today), school(today.adding(days: 1)), school(today.adding(days: 2))],
                   followingLesson: nil, tasks: tasks, overdueTaskCount: overdueCount, nextExam: exam,
                   overdueItems: overdue, exams: exams, openTaskCount: openTaskCount)
}

private func homeworkRows(_ snap: WidgetSnapshot, at now: Date) -> HomeworkList? {
    if case .list(let list) = HomeworkPlanner.state(snapshot: snap, at: now, context: context) { return list }
    return nil
}

private let homework = HomeworkPresenter(renderer: renderer, context: context)
private let examPresenter = ExamPresenter(renderer: renderer, context: context)
private let todayPresenter = TodayPresenter(renderer: renderer, context: context)

private func homeworkDisplay(_ snap: WidgetSnapshot, at now: Date) -> HomeworkDisplay {
    homework.display(HomeworkPlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone).entries[0])
}

private func examDisplay(_ snap: WidgetSnapshot, at now: Date) -> ExamDisplay {
    examPresenter.display(ExamPlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone).entries[0])
}

private func todayDisplay(_ snap: WidgetSnapshot, at now: Date) -> TodayDisplay {
    let entry = WidgetTimelinePlanner.entry(snapshot: snap, at: now, context: context)
    return todayPresenter.display(snapshot: snap, entry: entry)
}

// MARK: - Snapshot extension

@Suite("Widget snapshot: overdue list (B1)")
struct WidgetOverdueSnapshotTests {
    @Test func builderListsTheOverdueTasksOldestFirst() throws {
        let snap = WidgetSnapshotBuilder.make(database: SampleScenarios.secondary().database, now: SampleScenarios.referenceNow,
                                              context: context, tier: .pro, locale: Locale(identifier: "sk_SK"),
                                              languageCode: "sk")
        #expect(snap.overdueTaskCount == 1)
        let listed = snap.overdueTasks
        #expect(listed.count == 1 && listed[0].dueDate == date(2026, 10, 12))
        #expect(listed[0].title.hasPrefix("Laboratórny protokol"))
        // The Tasks tab's overdue segment and the widget list agree.
        #expect(snap.tasks.allSatisfy { $0.dueDate >= today })
    }

    @Test func listIsCappedWhileTheCountIsComplete() throws {
        var database = SampleScenarios.secondary().database
        let template = try #require(database.tasks.first { $0.title.hasPrefix("Laboratórny") })
        for index in 0..<12 {
            var copy = template
            copy.id = TaskItem.ID(UUID())
            copy.title = "Overdue \(index)"
            copy.due = .date(date(2026, 10, 1).adding(days: index % 10))
            database.tasks.append(copy)
        }
        let snap = WidgetSnapshotBuilder.make(database: database, now: SampleScenarios.referenceNow, context: context,
                                              tier: .pro, locale: Locale(identifier: "en_GB"), languageCode: "en")
        #expect(snap.overdueTaskCount == 13)
        #expect(snap.overdueTasks.count == WidgetSnapshotBuilder.maxOverdueTasks)
        let dates = snap.overdueTasks.map(\.dueDate)
        #expect(dates == dates.sorted())
        let data = try WidgetSnapshotStore.encode(snap)
        #expect(data.count < 20_000, "\(data.count) bytes")
    }

    @Test func oldFilesWithoutTheKeyStillDecodeAndNewKeysAreOptional() throws {
        let plain = snapshot()
        let data = try WidgetSnapshotStore.encode(plain)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"od\""))   // nil is omitted: v1 files look the same
        #expect(WidgetSnapshotStore.decode(data)?.overdueTasks.isEmpty == true)
        let withList = snapshot(overdue: [task("Late", date(2026, 10, 1))], overdueCount: 1)
        let encoded = try WidgetSnapshotStore.encode(withList)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"od\""))
        #expect(WidgetSnapshotStore.decode(encoded) == withList)
        #expect(WidgetSnapshot.currentVersion == 1)   // additive optional key: no version bump
    }
}

// MARK: - Homework

@Suite("Homework widget: planner")
struct HomeworkPlannerTests {
    private func fixture() -> WidgetSnapshot {
        let late3 = task("late3", date(2026, 10, 10)), late1 = task("late1", date(2026, 10, 12))
        let noon = task("noon", today, time(12)), evening = task("evening", today, time(16))
        let anyTime = task("anyTime", today), tomorrow = task("tomorrow", today.adding(days: 1))
        return snapshot(tasks: [noon, evening, anyTime, tomorrow], overdue: [late3, late1], overdueCount: 2)
    }

    @Test func overdueFirstOldestFirstThenDueSoonest() throws {
        let snap = fixture()
        let list = try #require(homeworkRows(snap, at: instant(today, 14)))
        #expect(list.rows.map(\.task.title) == ["late3", "late1", "noon", "evening", "anyTime", "tomorrow"])
        #expect(list.rows.map(\.isOverdue) == [true, true, true, false, false, false])
        #expect(list.overdueTotal == 3 && list.unlistedOverdue == 0 && list.knownTotal == 6)
    }

    @Test func aTaskTurnsOverdueOneMinuteAfterItsDueTime() throws {
        let snap = fixture()
        let at = try #require(homeworkRows(snap, at: instant(today, 16)))
        #expect(at.rows.first { $0.task.title == "evening" }?.isOverdue == false)   // the Tasks tab: `time < now`
        let after = try #require(homeworkRows(snap, at: instant(today, 16, 1)))
        #expect(after.rows.map(\.task.title) == ["late3", "late1", "noon", "evening", "anyTime", "tomorrow"])
        #expect(after.rows.first { $0.task.title == "evening" }?.isOverdue == true)
        #expect(after.rows.first { $0.task.title == "anyTime" }?.isOverdue == false)   // no time: due all day
        #expect(after.overdueTotal == 4)
    }

    @Test func midnightMakesYesterdaysTasksOverdue() throws {
        let snap = fixture()
        let next = try #require(homeworkRows(snap, at: instant(today.adding(days: 1), 0, 1)))
        #expect(next.rows.map(\.isOverdue) == [true, true, true, true, true, false])
        #expect(next.rows.last?.task.title == "tomorrow")
    }

    @Test func unlistedOverdueTasksAreCounted() throws {
        let snap = snapshot(tasks: [task("open", today)], overdue: [task("late", date(2026, 10, 1))], overdueCount: 5)
        let list = try #require(homeworkRows(snap, at: instant(today, 9)))
        #expect(list.unlistedOverdue == 4 && list.overdueTotal == 5 && list.knownTotal == 6)
        let old = snapshot(tasks: [], overdue: nil, overdueCount: 2)   // a file written before B1
        let oldList = try #require(homeworkRows(old, at: instant(today, 9)))
        #expect(oldList.rows.isEmpty && oldList.unlistedOverdue == 2 && oldList.knownTotal == 2)
    }

    @Test func entriesFollowMidnightsAndDueTimesWithinTheBudget() {
        let snap = fixture()
        let now = instant(today, 14)
        let plan = HomeworkPlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone)
        let dates = plan.entries.map(\.date)
        #expect(dates.first == now && dates == dates.sorted())
        #expect(dates.contains(instant(today, 16, 1)))                              // "evening" becomes overdue
        #expect(!dates.contains(instant(today, 12, 1)))                             // already past
        #expect(dates.contains(context.startOfDay(today.adding(days: 1))))
        #expect(plan.entries.count <= WidgetTimelinePlanner.maxEntries)
        #expect(plan.reloadDate <= now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval))
        #expect(plan.reloadDate > now)
    }

    @Test func unavailableWithoutASnapshotOrWhenOutdated() {
        let none = HomeworkPlanner.plan(snapshot: nil, now: instant(today, 9), deviceTimeZone: zone)
        #expect(none.entries.count == 1 && none.entries[0].state == .unavailable(.noSnapshot))
        let stale = HomeworkPlanner.plan(snapshot: snapshot(), now: instant(today.adding(days: 3), 9), deviceTimeZone: zone)
        #expect(stale.entries.count == 1 && stale.entries[0].state == .unavailable(.outdated))
        #expect(stale.reloadDate == instant(today.adding(days: 3), 9).addingTimeInterval(WidgetTimelinePlanner.unavailableRetry))
    }
}

@Suite("Homework widget: presentation")
struct HomeworkPresentationTests {
    @Test func dueTextsAndTheOverdueMark() throws {
        let late = task("late", date(2026, 10, 11))
        let noon = task("noon", today, time(12))
        let evening = task("evening", today, time(16))
        let tomorrow = task("tomorrow", today.adding(days: 1), time(8))
        let friday = task("friday", date(2026, 10, 16))
        let fridayAt = task("fridayAt", date(2026, 10, 16), time(8))
        let far = task("far", date(2026, 10, 20))
        let snap = snapshot(tasks: [noon, evening, tomorrow, friday, fridayAt, far], overdue: [late], overdueCount: 1)
        let shown = homeworkDisplay(snap, at: instant(today, 14))
        let byTitle = Dictionary(uniqueKeysWithValues: shown.lines.map { ($0.title, $0) })
        let formatter = renderer.formatter
        #expect(byTitle["late"]?.dueText == "2 days overdue" && byTitle["late"]?.isOverdue == true)
        #expect(byTitle["noon"]?.dueText == "Overdue" && byTitle["noon"]?.isOverdue == true)
        #expect(byTitle["evening"]?.dueText == "Today, \(formatter.time(time(16)))")
        #expect(byTitle["tomorrow"]?.dueText == "Tomorrow, \(formatter.time(time(8)))")
        #expect(byTitle["friday"]?.dueText == "Fri")
        #expect(byTitle["fridayAt"]?.dueText == "Fri, \(formatter.time(time(8)))")
        #expect(byTitle["far"]?.dueText == formatter.date(date(2026, 10, 20), style: .dayMonth))
        // Overdue is a sentence part too (not colour alone).
        #expect(byTitle["late"]?.accessibilityLabel.contains("2 days overdue") == true)
        #expect(byTitle["noon"]?.accessibilityLabel.contains("overdue") == true)
        #expect(byTitle["friday"]?.accessibilityLabel.contains("due Friday") == true)
        #expect(byTitle["friday"]?.accessibilityLabel.contains("Mathematics") == true)
    }

    @Test func countTopTaskAndLinks() throws {
        let urgent = task("urgent", today.adding(days: 1), priority: .urgent)
        let snap = snapshot(tasks: [urgent, task("later", today.adding(days: 2))], overdue: nil, overdueCount: 0)
        let shown = homeworkDisplay(snap, at: instant(today, 9))
        #expect(shown.kind == .tasks && shown.countText == "2 tasks to do" && shown.title == "Homework")
        #expect(shown.lines[0].isHighPriority && shown.lines[0].accessibilityLabel.contains("urgent priority"))
        #expect(shown.link == .task(TaskItem.ID(urgent.id)))
        #expect(ItemLinkURL.url(for: shown.lines[0].link).absoluteString == "tabula://open/task/\(urgent.id.uuidString)")
        #expect(shown.accessibilityLabel.contains("2 tasks to do") && shown.accessibilityLabel.contains("urgent"))
    }

    @Test func capacitiesAndTheMoreCount() {
        let many = (1...12).map { task("t\($0)", today.adding(days: min($0, 6))) }
        let snap = snapshot(tasks: many, overdue: [task("late", date(2026, 10, 1))], overdueCount: 3)
        let shown = homeworkDisplay(snap, at: instant(today, 9))
        #expect(shown.lines.count == 13)
        let small = shown.visible(for: .systemSmall), medium = shown.visible(for: .systemMedium)
        let large = shown.visible(for: .systemLarge)
        #expect(small.lines.count == 1 && small.hidden == 12 + 2)    // 12 more lines + 2 unlisted overdue tasks
        #expect(medium.lines.count == 3 && medium.hidden == 10 + 2)
        #expect(large.lines.count == 9 && large.hidden == 4 + 2)
        #expect(shown.moreText(6) == "+6 more")
        #expect(shown.lines.first?.isOverdue == true)
    }

    @Test func emptyAndUnavailableStates() {
        let done = homeworkDisplay(snapshot(), at: instant(today, 9))
        #expect(done.kind == .allDone(title: "All done", detail: "Nothing is due this week."))
        #expect(done.link == .today && done.lines.isEmpty && done.accessibilityLabel.contains("All done"))
        let none = homework.display(HomeworkPlanner.plan(snapshot: nil, now: instant(today, 9), deviceTimeZone: zone).entries[0])
        #expect(none.kind == .unavailable(title: "Open Tabula", detail: "Open the app once to show your timetable here."))
    }

    @Test func seededSecondaryShowsTheOverdueTaskFirst() throws {
        let scene = try #require(WidgetGallerySamples.scenes(locale: Locale(identifier: "en_GB"), languageCode: "en")
            .first { $0.id == "lesson" })
        let shown = homeworkDisplay(scene.snapshot, at: scene.date)
        #expect(shown.lines.first?.isOverdue == true)
        #expect(shown.lines.first?.title.hasPrefix("Laboratórny protokol") == true)
        #expect(shown.lines.dropFirst().allSatisfy { !$0.isOverdue })
        #expect(shown.lines.count == 5)
    }
}

// MARK: - Next exam

@Suite("Next exam widget: planner")
struct ExamPlannerTests {
    private let examDay = date(2026, 10, 22)

    @Test func statesAcrossTheExamDay() {
        let snap = snapshot(exam: exam(on: examDay))
        func state(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> ExamState {
            ExamPlanner.state(snapshot: snap, at: instant(day, h, m), context: context)
        }
        guard case .upcoming(_, let days) = state(date(2026, 10, 13), 9) else { Issue.record("upcoming"); return }
        #expect(days == 9)
        guard case .upcoming(_, 1) = state(date(2026, 10, 21), 23, 59) else { Issue.record("tomorrow"); return }
        guard case .today(_, .beforeStart(let start)) = state(examDay, 0) else { Issue.record("before"); return }
        #expect(start == instant(examDay, 10))
        guard case .today(_, .inProgress(let from, let to)) = state(examDay, 10) else { Issue.record("progress"); return }
        #expect(from == instant(examDay, 10) && to == instant(examDay, 10, 45))
        guard case .today(_, .finished) = state(examDay, 10, 45) else { Issue.record("finished"); return }
        #expect(state(examDay.adding(days: 1), 0) == .unavailable(.outdated))   // the next exam is unknown until the app writes
    }

    @Test func examsWithoutAnEndOrAStart() {
        let noEnd = snapshot(exam: exam(on: examDay, end: nil))
        guard case .today(_, .started(let start)) = ExamPlanner.state(snapshot: noEnd, at: instant(examDay, 12), context: context)
        else { Issue.record("started"); return }
        #expect(start == instant(examDay, 10))
        let allDay = snapshot(exam: exam(on: examDay, start: nil, end: nil))
        guard case .today(_, .allDay) = ExamPlanner.state(snapshot: allDay, at: instant(examDay, 12), context: context)
        else { Issue.record("allDay"); return }
        let backwards = snapshot(exam: exam(on: examDay, start: time(10), end: time(9)))   // end before start: ignored
        guard case .today(_, .started) = ExamPlanner.state(snapshot: backwards, at: instant(examDay, 12), context: context)
        else { Issue.record("backwards"); return }
    }

    @Test func noExamIsEmptyUntilTheSnapshotIsOutdated() {
        let snap = snapshot()
        #expect(ExamPlanner.state(snapshot: snap, at: instant(today, 9), context: context) == .none)
        #expect(ExamPlanner.state(snapshot: snap, at: instant(today.adding(days: 3), 9), context: context) == .unavailable(.outdated))
    }

    @Test func entriesIncludeTheStartAndEndOnTheExamDay() {
        let snap = snapshot(exam: exam(on: examDay))
        let now = instant(examDay, 8, 30)
        let plan = ExamPlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone)
        let dates = plan.entries.map(\.date)
        #expect(dates == [now, instant(examDay, 10), instant(examDay, 10, 45), context.startOfDay(examDay.adding(days: 1))])
        #expect(plan.reloadDate <= now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval))
    }

    @Test func aFarExamStaysWithinTheBudgetAndEndsAtAMidnight() {
        let far = snapshot(exam: exam(on: today.adding(days: 60)))
        let now = instant(today, 9)
        let plan = ExamPlanner.plan(snapshot: far, now: now, deviceTimeZone: zone)
        #expect(plan.entries.count <= WidgetTimelinePlanner.maxEntries)
        let last = plan.entries.last!.date
        #expect(last == context.startOfDay(context.localDate(of: last)))
        #expect(plan.reloadDate <= now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval))
        #expect(plan.entries.dropFirst().allSatisfy { if case .upcoming = $0.state { return true } else { return false } })
    }

    @Test func theCountdownCrossesTheAutumnDSTChangeInRealTime() throws {
        let dstDay = date(2026, 10, 25)   // 25-hour day in Europe/Bratislava
        let snap = snapshot(days: [school(date(2026, 10, 24)), school(dstDay)], exam: exam(on: dstDay, start: time(8), end: nil))
        let midnight = instant(dstDay, 0)
        let shown = examDisplay(snap, at: midnight)
        let timer = try #require({ () -> ClosedRange<Date>? in
            if case .exam(let info) = shown.kind { return info.timer }
            return nil
        }())
        #expect(timer.upperBound == instant(dstDay, 8) && timer.upperBound.timeIntervalSince(midnight) == 9 * 3600)
    }
}

@Suite("Next exam widget: presentation")
struct ExamPresentationTests {
    private func info(_ display: ExamDisplay) throws -> ExamDisplay.Info {
        guard case .exam(let info) = display.kind else {
            Issue.record("expected an exam, got \(display.kind)")
            throw CancellationError()
        }
        return info
    }

    @Test func countdownEscalatesWithTheDays() throws {
        let formatter = renderer.formatter
        let expectations: [(Int, String, ExamDisplay.Escalation, String)] = [
            (9, "in 9 days", .later, "calendar"), (7, "in 7 days", .soon, "calendar.badge.clock"),
            (2, "in 2 days", .soon, "calendar.badge.clock"), (1, "Tomorrow", .tomorrow, "exclamationmark.circle.fill"),
        ]
        for (days, text, level, symbol) in expectations {
            let day = today.adding(days: days)
            let shown = examDisplay(snapshot(exam: exam(on: day)), at: instant(today, 9))
            let details = try info(shown)
            #expect(details.whenText == text && details.escalation == level && details.symbol == symbol, "\(days) days")
            #expect(details.circularValue == String(days) && details.timer == nil)
        }
        let shown = examDisplay(snapshot(exam: exam(on: date(2026, 10, 22))), at: instant(today, 9))
        let details = try info(shown)
        #expect(details.title == "Organic chemistry" && details.subject?.name == "Biology" && details.room == "Lab")
        #expect(details.dateText == formatter.date(date(2026, 10, 22), style: .weekdayDayMonth))
        #expect(details.timeText == formatter.timeRange(time(10), time(10, 45)))
        #expect(shown.link == .exam(Exam.ID(details.id)) && shown.title == "Next Exam")
        for part in ["Next Exam", "Organic chemistry", "Biology", "in 9 days", "Room Lab"] {
            #expect(shown.accessibilityLabel.contains(part), "\(part) missing from \(shown.accessibilityLabel)")
        }
    }

    @Test func examDayHasALiveCountdownThenProgressThenFinished() throws {
        let day = date(2026, 10, 22)
        let snap = snapshot(exam: exam(on: day))
        let formatter = renderer.formatter
        let before = try info(examDisplay(snap, at: instant(day, 8, 30)))
        #expect(before.whenText == "Today, \(formatter.time(time(10)))" && before.escalation == .today && before.symbol == "alarm.fill")
        #expect(before.timer == instant(day, 8, 30)...instant(day, 10) && before.timerCaption == "Starts in")
        #expect(before.circularValue == formatter.time(time(10)))
        let during = try info(examDisplay(snap, at: instant(day, 10, 20)))
        #expect(during.whenText == "In progress" && during.escalation == .inProgress)
        #expect(during.timer == instant(day, 10)...instant(day, 10, 45) && during.timerCaption == "Time left")
        let after = try info(examDisplay(snap, at: instant(day, 11)))
        #expect(after.whenText == "Finished" && after.escalation == .finished && after.timer == nil)
        let allDay = try info(examDisplay(snapshot(exam: exam(on: day, start: nil, end: nil)), at: instant(day, 9)))
        #expect(allDay.whenText == "Today" && allDay.timer == nil && allDay.timeText == nil)
        #expect(allDay.circularValue == "Today")   // a word, never "0"
        let dot = try #require(EnglishCatalog.values["widget.separator"])
        #expect(dot == " · " && before.smallLine == "\(formatter.timeRange(time(10), time(10, 45)))\(dot)Lab")
        #expect(before.detailLine.hasPrefix(formatter.date(day, style: .weekdayDayMonth) + dot))
        // The spoken sentence names the start, never the ticking timer.
        #expect(examDisplay(snap, at: instant(day, 8, 30)).accessibilityLabel.contains("Today, \(formatter.time(time(10)))"))
    }

    @Test func emptyAndUnavailableStates() {
        let none = examDisplay(snapshot(), at: instant(today, 9))
        #expect(none.kind == .empty(title: "No Upcoming Exams", detail: "Add an exam in the app to see its countdown here."))
        #expect(none.link == .today)
        let stale = examDisplay(snapshot(exam: exam(on: date(2026, 10, 10))), at: instant(today.adding(days: 3), 9))
        #expect(stale.kind == .unavailable(title: "Open Tabula", detail: "Open the app to update your timetable."))
    }

    @Test func galleryScenesShowTheirStates() throws {
        let locale = Locale(identifier: "en_GB")
        let extra = WidgetGallerySamples.extraScenes(locale: locale, languageCode: "en")
        #expect(extra.map(\.id) == ["exam-day", "empty"])
        let day = try #require(extra.first { $0.id == "exam-day" })
        guard case .today(let found, .beforeStart(let start)) = ExamPlanner.state(snapshot: day.snapshot, at: day.date, context: context)
        else { Issue.record("exam-day scene"); return }
        #expect(found.title.hasPrefix("Písomka") && start == instant(date(2026, 10, 22), 10))
        let empty = try #require(extra.first { $0.id == "empty" })
        #expect(ExamPlanner.state(snapshot: empty.snapshot, at: empty.date, context: context) == .none)
        #expect(homeworkRows(empty.snapshot, at: empty.date)?.rows.isEmpty == true)
        let upcoming = try #require(WidgetGallerySamples.scenes(locale: locale, languageCode: "en").first { $0.id == "lesson" })
        guard case .upcoming(_, 9) = ExamPlanner.state(snapshot: upcoming.snapshot, at: upcoming.date, context: context)
        else { Issue.record("lesson scene exam"); return }
    }

    @Test func previewSnapshotCarriesSampleTasksAndAnExam() throws {
        let now = instant(today, 10, 20)
        let snap = WidgetGallerySamples.previewSnapshot(now: now, timeZone: zone, localeID: "en_GB", languageCode: "en",
                                                        name: EnglishCatalog.lookup)
        #expect(snap.tasks.count == 2 && snap.tasks[0].title == "Exercises on page 42")
        #expect(snap.nextExam?.title == "Unit test" && snap.nextExam?.date == today.adding(days: 5))
        #expect(try WidgetSnapshotStore.encode(snap).count < 2_500)
    }
}

// MARK: - Today

@Suite("Today widget: presentation")
struct TodayPresentationTests {
    private func morning() -> WidgetSnapshot {
        let a = lesson("a", today, time(8), time(8, 45))
        let b = lesson("b", today, time(8, 55), time(9, 40), subject: bio, status: .cancelled)
        let c = lesson("c", today, time(9, 50), time(10, 35), room: "105", status: .modified, reasons: [.roomChanged])
        let d = lesson("d", today, time(10, 45), time(11, 30), subject: bio, room: nil)
        let tomorrow = [lesson("e", today.adding(days: 1), time(8), time(8, 45)),
                        lesson("f", today.adding(days: 1), time(8, 55), time(9, 40), subject: bio)]
        return snapshot(days: [school(today, [a, b, c, d]), school(today.adding(days: 1), tomorrow), school(today.adding(days: 2))],
                        tasks: [task("Essay", today, time(18)), task("Worksheet", today.adding(days: 1))])
    }

    private func day(_ display: TodayDisplay) throws -> TodayDisplay.Day {
        guard case .lessons(let day) = display.kind else {
            Issue.record("expected lessons, got \(display.kind)")
            throw CancellationError()
        }
        return day
    }

    @Test func duringALessonTheCurrentRowIsHighlightedAndCancelledOnesAreMarked() throws {
        let shown = todayDisplay(morning(), at: instant(today, 10))
        let content = try day(shown)
        #expect(content.header == "Today" && !content.isTomorrow)
        #expect(content.rows.map(\.line.id) == ["lesson:a:2026-10-13", "lesson:b:2026-10-13", "lesson:c:2026-10-13", "lesson:d:2026-10-13"])
        #expect(content.rows.map(\.isCurrent) == [false, false, true, false])
        #expect(content.rows.map(\.isPast) == [true, true, false, false])
        #expect(content.rows.map(\.isCancelled) == [false, true, false, false])
        #expect(content.rows[1].line.badgeText == EnglishCatalog.values["lesson.status.cancelled"])
        #expect(content.rows[1].badgeSymbol == "xmark.circle")
        #expect(content.rows[2].line.badgeText == EnglishCatalog.values[ModificationReason.roomChanged.l10nKey])
        #expect(content.rows[2].line.room == "105")
        #expect(content.rows[3].line.room == nil && content.rows[3].badgeSymbol == nil)
        #expect(shown.link == .today)
    }

    @Test func mediumListsTheLessonsFromNowOnLargeTheWholeDay() throws {
        let shown = todayDisplay(morning(), at: instant(today, 10))
        let medium = shown.visibleRows(for: .systemMedium)
        #expect(medium.rows.map(\.line.name) == ["Mathematics", "Biology"] && medium.hidden == 0)   // c (now), d
        let large = shown.visibleRows(for: .systemLarge)
        #expect(large.rows.count == 4 && large.hidden == 0)
        let medSentence = shown.accessibilityLabel(for: .systemMedium)
        let cancelledWord = try #require(EnglishCatalog.values["a11y.lesson.cancelled"])
        #expect(medSentence.contains("Today") && medSentence.contains("Now"))
        #expect(!medSentence.contains(cancelledWord))                     // ended lessons are not listed
        let largeSentence = shown.accessibilityLabel(for: .systemLarge)
        #expect(largeSentence.contains(cancelledWord) && largeSentence.contains("Due today") && largeSentence.contains("Essay"))
    }

    @Test func mediumShowsFourRowsOrThreeWhenAChangeLineIsShown() throws {
        let day = date(2026, 10, 13)
        let plain = (0..<6).map { lesson("p\($0)", day, time(8 + $0), time(8 + $0, 45)) }
        let plainShown = todayDisplay(snapshot(days: [school(day, plain), school(day.adding(days: 1)), school(day.adding(days: 2))]),
                                      at: instant(day, 7)).visibleRows(for: .systemMedium)
        #expect(plainShown.rows.count == 4 && plainShown.hidden == 2)
        var withChange = plain
        withChange[1] = lesson("p1", day, time(9), time(9, 45), status: .added)
        let changed = todayDisplay(snapshot(days: [school(day, withChange), school(day.adding(days: 1)), school(day.adding(days: 2))]),
                                   at: instant(day, 7)).visibleRows(for: .systemMedium)
        #expect(changed.rows.count == 3 && changed.hidden == 3)
    }

    @Test func largeDropsEndedLessonsFirstWhenTheDayIsTooLong() throws {
        let day = date(2026, 10, 13)
        let lessons = (0..<12).map { lesson("l\($0)", day, time(7 + $0), time(7 + $0, 45)) }
        let snap = snapshot(days: [school(day, lessons), school(day.adding(days: 1)), school(day.adding(days: 2))])
        let early = todayDisplay(snap, at: instant(day, 6)).visibleRows(for: .systemLarge)
        #expect(early.rows.count == TodayDisplay.largeRowsWithoutTasks && early.hidden == 3)
        let late = todayDisplay(snap, at: instant(day, 14, 30))
        let shown = late.visibleRows(for: .systemLarge)
        #expect(shown.rows.count == 9 && shown.hidden == 0)
        #expect(shown.rows.contains { $0.isCurrent })
        #expect(shown.rows.first?.line.id == "lesson:l3:2026-10-13")   // the three earliest ended lessons are gone
    }

    @Test func largeListsAtMostThreeDueTasksAndTrimsRowsForThem() throws {
        let tasks = (1...5).map { task("t\($0)", today, time(15 + $0 % 3)) }
        let a = lesson("a", today, time(8), time(8, 45))
        let snap = snapshot(days: [school(today, [a]), school(today.adding(days: 1)), school(today.adding(days: 2))], tasks: tasks)
        let shown = todayDisplay(snap, at: instant(today, 8, 10))
        let content = try day(shown)
        #expect(content.dueTasks.count == 3 && content.hiddenDue == 2 && content.dueTitle == "Due today")
        #expect(content.dueTasks.allSatisfy { !$0.isOverdue })
    }

    @Test func afterSchoolShowsTomorrowUnderATomorrowHeader() throws {
        let shown = todayDisplay(morning(), at: instant(today, 17))
        let content = try day(shown)
        #expect(content.header == "Tomorrow" && content.isTomorrow)
        #expect(content.rows.map(\.line.name) == ["Mathematics", "Biology"])
        #expect(content.rows.allSatisfy { !$0.isPast && !$0.isCurrent })
        #expect(content.dueTitle == "Due tomorrow" && content.dueTasks.map(\.title) == ["Worksheet"])
        #expect(content.dateText == renderer.formatter.date(today.adding(days: 1), style: .weekdayDayMonth))
        // Midnight switches to today's list under "Today".
        let midnight = try day(todayDisplay(morning(), at: context.startOfDay(today.adding(days: 1))))
        #expect(midnight.header == "Today" && midnight.rows.count == 2)
    }

    @Test func statusStatesReuseTheNowNextSemantics() throws {
        let holiday = WidgetSnapshot.Day(date: today, kind: .holiday, note: "Autumn break")
        let following = lesson("m", date(2026, 10, 19), time(8), time(8, 45))
        var snap = snapshot(days: [holiday, school(today.adding(days: 1)), school(today.adding(days: 2))])
        snap.followingLesson = following
        let shown = todayDisplay(snap, at: instant(today, 9))
        guard case let .status(symbol, title, detail, next, caption, _) = shown.kind else {
            Issue.record("expected status, got \(shown.kind)")
            return
        }
        #expect(symbol == "beach.umbrella" && title == "Autumn break" && detail == "Holidays")
        #expect(next?.name == "Mathematics" && caption == "Next Lesson")
        #expect(shown.visibleRows(for: .systemMedium).rows.isEmpty)
        // Lessons over and nothing tomorrow → "No more lessons today" with the next lesson.
        let evening = todayDisplay(snapshot(days: [school(today, [lesson("a", today, time(8), time(8, 45))]),
                                                   school(today.adding(days: 1)), school(today.adding(days: 2))]),
                                   at: instant(today, 17))
        guard case let .status(_, overTitle, _, _, _, _) = evening.kind else { Issue.record("expected status"); return }
        #expect(overTitle == "No more lessons today")
    }

    @Test func unavailableWithoutASnapshotAndThePlannerKeepsCancelledBoundariesOnRequest() throws {
        let none = WidgetTimelinePlanner.plan(snapshot: nil, now: instant(today, 9), deviceTimeZone: zone)
        let shown = todayPresenter.display(snapshot: nil, entry: none.entries[0])
        #expect(shown.kind == .unavailable(title: "Open Tabula", detail: "Open the app once to show your timetable here."))
        #expect(shown.accessibilityLabel(for: .systemMedium).contains("Open Tabula"))

        let cancelled = lesson("x", today, time(11), time(11, 45), status: .cancelled)
        let snap = snapshot(days: [school(today, [lesson("a", today, time(8), time(8, 45)), cancelled]),
                                   school(today.adding(days: 1)), school(today.adding(days: 2))])
        let now = instant(today, 7)
        let base = WidgetTimelinePlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone).entries.map(\.date)
        let withCancelled = WidgetTimelinePlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone,
                                                       includeCancelledBoundaries: true).entries.map(\.date)
        #expect(!base.contains(instant(today, 11, 45)) && withCancelled.contains(instant(today, 11, 45)))
        #expect(withCancelled.count <= WidgetTimelinePlanner.maxEntries)
    }

    @Test func seededSecondaryDuringALessonListsTheWholeDay() throws {
        let scene = try #require(WidgetGallerySamples.scenes(locale: Locale(identifier: "en_GB"), languageCode: "en")
            .first { $0.id == "lesson" })
        let content = try day(todayDisplay(scene.snapshot, at: scene.date))
        #expect(content.rows.count >= 5)
        #expect(content.rows.filter(\.isCurrent).count == 1)
        let after = try #require(WidgetGallerySamples.scenes(locale: Locale(identifier: "en_GB"), languageCode: "en")
            .first { $0.id == "after" })
        #expect(try day(todayDisplay(after.snapshot, at: after.date)).header == "Tomorrow")
    }
}

// MARK: - Pro gate

@Suite("Today / Homework / Next exam: Pro gate")
struct WidgetB1GateTests {
    @Test func largeAndLockScreenFamiliesAreProTheRestFree() {
        // Today: medium free, large Pro. Homework: small + medium free, large Pro. Next exam: small free, accessory Pro.
        for family in [WidgetFamilyKind.systemSmall, .systemMedium] {
            #expect(WidgetProGate.decision(for: family, tier: .free) == .allowed)
        }
        #expect(WidgetProGate.decision(for: .systemLarge, tier: .free) == .requiresPro(.largeWidgets))
        #expect(WidgetProGate.decision(for: .accessoryRectangular, tier: .free) == .requiresPro(.lockScreenWidgets))
        #expect(WidgetProGate.decision(for: .accessoryCircular, tier: .free) == .requiresPro(.lockScreenWidgets))
        #expect(WidgetProGate.decision(for: .systemLarge, tier: .pro) == .allowed)
        #expect(WidgetProGate.decision(for: .accessoryRectangular, snapshot: snapshot(tier: .free)) == .requiresPro(.lockScreenWidgets))
        // The "Open Tabula" state carries no Pro content: never gated.
        #expect(WidgetProGate.decision(for: .systemLarge, snapshot: nil) == .allowed)
    }
}


// MARK: - QA fixes (B1)

private func database(withExtraExams extra: [(LocalDate, LocalTime?, LocalTime?)]) throws -> TabulaDatabase {
    var db = SampleScenarios.secondary().database
    let template = try #require(db.exams.first)
    for (day, start, end) in extra {
        var copy = template
        copy.id = Exam.ID(UUID())
        copy.date = day
        copy.start = start
        copy.end = end
        copy.title = "Extra \(day.isoString) \(start.map { "\($0.minuteOfDay)" } ?? "-")"
        db.exams.append(copy)
    }
    return db
}

private func build(_ db: TabulaDatabase, at now: Date) -> WidgetSnapshot {
    WidgetSnapshotBuilder.make(database: db, now: now, context: context, tier: .pro, locale: Locale(identifier: "en_GB"),
                               languageCode: "en")
}

@Suite("B1 QA: exams list, size budget, open count, planners")
struct WidgetB1QATests {
    @Test func builderSkipsEndedExamsAndListsTheNextFew() throws {
        let db = try database(withExtraExams: [(today, time(9), time(9, 45)), (today, time(11), nil)])
        let early = build(db, at: instant(today, 8))
        #expect(early.nextExam == early.exams?.first && early.exams?.first?.start == time(9))
        let later = build(db, at: instant(today, 10))   // the 09:00 exam has ended
        #expect(later.exams?.first?.start == time(11) && later.nextExam?.start == time(11))
        #expect((later.exams?.count ?? 0) <= WidgetSnapshotBuilder.maxExams && later.exams?.count ?? 0 >= 2)
        let tomorrow = build(db, at: instant(today.adding(days: 1), 8))
        #expect(tomorrow.exams?.allSatisfy { $0.date >= today.adding(days: 1) } == true)
    }

    @Test func twoExamsInADayHandOverAtTheEndAndOverMidnight() throws {
        let first = exam(on: today, start: time(9), end: time(9, 45))
        let second = exam(on: today, start: time(11), end: time(11, 45), room: nil)
        let next = exam(on: today.adding(days: 1), start: time(8), end: nil)
        let snap = snapshot(exam: first, exams: [first, second, next])
        func state(_ day: LocalDate, _ h: Int, _ m: Int = 0) -> ExamState {
            ExamPlanner.state(snapshot: snap, at: instant(day, h, m), context: context)
        }
        guard case .today(let a, .inProgress) = state(today, 9, 10), a.id == first.id else { Issue.record("first"); return }
        guard case .today(let b, .beforeStart(let start)) = state(today, 9, 50), b.id == second.id else { Issue.record("second"); return }
        #expect(start == instant(today, 11))
        guard case .upcoming(let c, 1) = state(today, 12), c.id == next.id else { Issue.record("after both"); return }
        guard case .today(let d, .beforeStart) = state(today.adding(days: 1), 0, 1), d.id == next.id else { Issue.record("midnight"); return }
        let plan = ExamPlanner.plan(snapshot: snap, now: instant(today, 8), deviceTimeZone: zone)
        let dates = plan.entries.map(\.date)
        for expected in [instant(today, 9), instant(today, 9, 45), instant(today, 11), instant(today, 11, 45), instant(today.adding(days: 1), 8)] {
            #expect(dates.contains(expected))
        }
    }

    @Test func aFullListThatIsOverIsOutdatedNotEmpty() {
        let list = (0..<WidgetSnapshotBuilder.maxExams).map { _ in exam(on: date(2026, 10, 10)) }
        let snap = snapshot(exam: list[0], exams: list)
        #expect(ExamPlanner.state(snapshot: snap, at: instant(today, 9), context: context) == .unavailable(.outdated))
        let short = snapshot(exam: list[0], exams: [list[0]])
        #expect(ExamPlanner.state(snapshot: short, at: instant(today, 9), context: context) == .none)
    }

    @Test func worstCaseSnapshotStaysUnderTheBudget() throws {
        var db = SampleScenarios.secondary().database
        let long = String(repeating: "Ř", count: 79)
        for index in db.subjects.indices { db.subjects[index].name = long }
        let template = try #require(db.tasks.first)
        for index in 0..<40 {
            var copy = template
            copy.id = TaskItem.ID(UUID())
            copy.title = String(repeating: "Úloha ", count: 20) + "\(index)"
            copy.due = .date(index < 20 ? today.adding(days: index % 7) : date(2026, 10, 1).adding(days: index % 10))
            copy.completedAt = nil
            db.tasks.append(copy)
        }
        let exams = try database(withExtraExams: (0..<6).map { (today.adding(days: $0 + 1), time(8), time(9)) })
        db.exams = exams.exams
        let snap = build(db, at: SampleScenarios.referenceNow)
        let data = try WidgetSnapshotStore.encode(snap)
        #expect(data.count < 20_000, "\(data.count) bytes")
        #expect(snap.exams?.isEmpty == false && snap.exams?.first?.date == today.adding(days: 1))   // the next exam always survives
        #expect(snap.tasks.allSatisfy { $0.title.count <= WidgetSnapshotBuilder.maxTextLength })
        #expect((snap.openTaskCount ?? 0) >= 40)   // the count stays true after trimming
    }

    @Test func overdueDueTodayIsAlwaysListed() throws {
        var db = SampleScenarios.secondary().database
        let template = try #require(db.tasks.first)
        for index in 0..<10 {
            var copy = template
            copy.id = TaskItem.ID(UUID())
            copy.title = "Old \(index)"
            copy.due = .date(date(2026, 9, 1).adding(days: index))
            copy.completedAt = nil
            db.tasks.append(copy)
        }
        var late = template
        late.id = TaskItem.ID(UUID())
        late.title = "Due this morning"
        late.due = .dateTime(today, time(8))
        late.completedAt = nil
        db.tasks.append(late)
        let snap = build(db, at: SampleScenarios.referenceNow)
        #expect(snap.overdueTasks.count == WidgetSnapshotBuilder.maxOverdueTasks)
        #expect(snap.overdueTasks.contains { $0.title == "Due this morning" })
        let dates = snap.overdueTasks.map(\.dueDate)
        #expect(dates == dates.sorted())
    }

    @Test func homeworkCountIsTheTrueOpenCount() throws {
        let snap = snapshot(tasks: [task("a", today.adding(days: 1)), task("b", today.adding(days: 2))], openTaskCount: 14)
        let shown = homeworkDisplay(snap, at: instant(today, 9))
        #expect(shown.countText == "14 tasks to do" && shown.totalCount == 14)
        #expect(shown.visible(for: .systemMedium).hidden == 12)
        // Only far-away tasks open: no rows, but not "All done".
        let far = homeworkDisplay(snapshot(openTaskCount: 3), at: instant(today, 9))
        #expect(far.kind == .tasks && far.lines.isEmpty && far.countText == "3 tasks to do")
        let db = SampleScenarios.secondary().database
        let built = build(db, at: SampleScenarios.referenceNow)
        let counts = TaskListModel.counts(of: db.tasks.filter { !$0.isDeleted }, now: context.local(from: SampleScenarios.referenceNow))
        #expect(built.openTaskCount == counts.today + counts.upcoming + counts.overdue)
    }

    @Test func plannersFollowTheDeviceZoneForFollowDeviceTimetables() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let nyContext = CalendarContext(timeZone: ny, firstWeekday: .monday)
        var snap = snapshot(tasks: [task("due", today, time(16))], exam: exam(on: today.adding(days: 1)))
        snap.followsDeviceTimeZone = true
        let now = nyContext.date(today, time(9))
        let homeworkDates = HomeworkPlanner.plan(snapshot: snap, now: now, deviceTimeZone: ny).entries.map(\.date)
        #expect(homeworkDates.contains(nyContext.date(today, time(16, 1))))
        guard case .upcoming(_, 1) = ExamPlanner.state(snapshot: snap, at: now, context: WidgetTimelinePlanner.context(for: snap, deviceTimeZone: ny))
        else { Issue.record("exam tomorrow in the device zone"); return }
        let examNow = nyContext.date(today.adding(days: 1), time(8))
        guard case .today(_, .beforeStart(let start)) = ExamPlanner.plan(snapshot: snap, now: examNow, deviceTimeZone: ny).entries[0].state
        else { Issue.record("exam day in the device zone"); return }
        #expect(start == nyContext.date(today.adding(days: 1), time(10)))
        // A fixed-zone timetable keeps its own zone.
        snap.followsDeviceTimeZone = false
        let fixedDates = HomeworkPlanner.plan(snapshot: snap, now: now, deviceTimeZone: ny).entries.map(\.date)
        #expect(fixedDates.contains(instant(today, 16, 1)) && !fixedDates.contains(nyContext.date(today, time(16, 1))))
    }

    @Test func dueTimeBoundaryAcrossTheAutumnDSTChange() throws {
        let dst = date(2026, 10, 25)   // 25-hour day in Europe/Bratislava
        let days = [school(date(2026, 10, 24)), school(dst), school(date(2026, 10, 26))]
        let snap = snapshot(days: days, tasks: [task("early", dst, time(8))])
        let midnight = instant(dst, 0)
        let plan = HomeworkPlanner.plan(snapshot: snap, now: midnight, deviceTimeZone: zone)
        let boundary = instant(dst, 8, 1)
        #expect(plan.entries.map(\.date).contains(boundary) && boundary.timeIntervalSince(midnight) == 9 * 3600 + 60)
        #expect(homeworkRows(snap, at: instant(dst, 8))?.rows.first?.isOverdue == false)
        #expect(homeworkRows(snap, at: boundary)?.rows.first?.isOverdue == true)
    }

    @Test func todayPlanAddsTaskDueEntriesOnlyOnRequest() {
        let snap = snapshot(tasks: [task("due", today, time(16))])
        let now = instant(today, 9)
        let plain = WidgetTimelinePlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone).entries.map(\.date)
        let withDue = WidgetTimelinePlanner.plan(snapshot: snap, now: now, deviceTimeZone: zone,
                                                 includeTaskDueBoundaries: true).entries.map(\.date)
        #expect(!plain.contains(instant(today, 16, 1)) && withDue.contains(instant(today, 16, 1)))
    }
}
