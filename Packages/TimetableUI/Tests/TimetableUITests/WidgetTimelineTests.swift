import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let bratislava = SampleScenarios.timeZone
private let newYork = TimeZone(identifier: "America/New_York")!
private let context = CalendarContext(timeZone: bratislava, firstWeekday: .monday)
private func date(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func time(_ h: Int, _ m: Int = 0) -> LocalTime { LocalTime(hour: h, minute: m)! }
private func instant(_ day: LocalDate, _ h: Int, _ m: Int = 0, in ctx: CalendarContext = context) -> Date {
    ctx.date(day, time(h, m))
}
private let today = SampleScenarios.today   // Tue 2026-10-13

private func build(_ database: TabulaDatabase?, at now: Date) -> WidgetSnapshot {
    WidgetSnapshotBuilder.make(database: database, now: now, context: context, tier: .pro,
                               locale: Locale(identifier: "en_GB"), languageCode: "en")
}

// MARK: Hand-made snapshots

private let math = SubjectSummary(id: Subject.ID(UUID()), name: "Mathematics", shortName: "MAT",
                                  color: ColorValue(red: 30, green: 90, blue: 200))
private let bio = SubjectSummary(id: Subject.ID(UUID()), name: "Biology", color: ColorValue(red: 240, green: 220, blue: 60),
                                 symbol: .emoji("🧬"))

private func lesson(_ name: String, _ day: LocalDate, _ start: LocalTime, _ end: LocalTime,
                    subject: SubjectSummary = math, room: String? = "214", status: ResolvedLesson.Status = .scheduled,
                    reasons: [ModificationReason]? = nil) -> WidgetSnapshot.Lesson {
    WidgetSnapshot.Lesson(id: "lesson:\(name):\(day.isoString)", subject: subject, date: day, startTime: start,
                          endTime: end, room: room, status: status, reasons: reasons)
}

private func snapshot(_ days: [WidgetSnapshot.Day], following: WidgetSnapshot.Lesson? = nil,
                      zone: String = "Europe/Bratislava", follows: Bool = true) -> WidgetSnapshot {
    WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 0), timeZoneID: zone, followsDeviceTimeZone: follows,
                   localeID: "en_GB", languageCode: "en", hourCycle: .h24, tier: .pro, hasTimetable: true, days: days,
                   followingLesson: following, tasks: [], overdueTaskCount: 0, nextExam: nil)
}

private func school(_ day: LocalDate, _ lessons: [WidgetSnapshot.Lesson]) -> WidgetSnapshot.Day {
    WidgetSnapshot.Day(date: day, kind: .school, lessons: lessons)
}

/// The same state, compared by occurrence ID (the snapshot drops fields the widget does not need).
private func matches(_ state: NowNextState, _ header: TodayState.Header) -> Bool {
    func same(_ a: WidgetSnapshot.Lesson?, _ b: ResolvedLesson?) -> Bool { a?.id == b?.id.rawValue }
    switch (state, header) {
    case let (.current(a, an), .current(b, bn)): return same(a, b) && same(an, bn)
    case let (.upcoming(a, af), .upcoming(b, bf)): return same(a, b) && af == bf
    case let (.dayOver(a), .dayOver(b)), let (.free(a), .free(b)): return same(a, b)
    case let (.holiday(n, a), .holiday(m, b)): return n == m && same(a, b)
    case let (.dayCancelled(n, a), .dayCancelled(m, b)): return n == m && same(a, b)
    default: return false
    }
}

@Suite("Widget timeline planner")
struct WidgetTimelinePlannerTests {
    /// The widget never disagrees with the Today tab: every 5 minutes across the covered days, on school days, a
    /// weekend, a holiday and a cancelled day, for three scenarios.
    @Test(arguments: [
        (SeedKind.secondary, date(2026, 10, 13)), (.secondary, date(2026, 10, 16)), (.secondary, date(2026, 10, 29)),
        (.secondary, date(2026, 10, 23)),   // Fri → Mon over the DST end (Sun 25 Oct, a 25-hour day)
        (.university, date(2026, 10, 13)), (.elementary, date(2026, 10, 13)),
    ])
    func stateMatchesTheTodayTab(_ seed: SeedKind, _ day: LocalDate) throws {
        var database = try #require(SampleScenarios.make(seed).database)
        if seed == .elementary {
            database.overrides.append(ScheduleOverride(id: ScheduleOverride.ID(UUID()), meta: .created(at: .zero),
                                                       timetableID: database.timetables[0].id, date: date(2026, 10, 14),
                                                       change: .cancelDay(note: "Výlet")))
        }
        let timetable = try #require(ActiveTimetable.resolve(database))
        let resolver = try #require(ScheduleResolver(database: database, timetableID: timetable.id, context: context))
        let start = instant(day, 0, 0)
        let snapshot = build(database, at: start)
        let end = context.startOfDay(try #require(snapshot.lastDay).adding(days: 1))
        var probe = start
        var checked = 0
        while probe < end {
            let state = WidgetTimelinePlanner.state(snapshot: snapshot, at: probe, context: context)
            let header = TodayState.make(now: probe, resolver: resolver, database: database).header
            #expect(matches(state, header), "\(seed) at \(probe): widget \(state) vs Today \(header)")
            probe = probe.addingTimeInterval(300)
            checked += 1
        }
        #expect(checked >= 2 * 288)
    }

    @Test func entriesStartNowFollowBoundariesAndStayUnder30() throws {
        let now = SampleScenarios.referenceNow
        let snapshot = build(SampleScenarios.secondary().database, at: now)
        let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, now: now, deviceTimeZone: bratislava)
        #expect(plan.entries.count <= WidgetTimelinePlanner.maxEntries && plan.entries.count < 30)
        #expect(plan.entries.first?.date == now)
        #expect(zip(plan.entries, plan.entries.dropFirst()).allSatisfy { $0.date < $1.date })
        var boundaries: Set<Date> = []
        for day in snapshot.days {
            boundaries.insert(context.startOfDay(day.date.adding(days: 1)))
            for lesson in day.lessons where lesson.takesPlace {
                boundaries.insert(lesson.start(in: context))
                boundaries.insert(lesson.end(in: context))
            }
        }
        let future = boundaries.filter { $0 > now }.sorted()
        #expect(plan.entries.dropFirst().map(\.date) == Array(future.prefix(plan.entries.count - 1)))
        for entry in plan.entries {
            #expect(entry.state == WidgetTimelinePlanner.state(snapshot: snapshot, at: entry.date, context: context))
        }
        // Three school days have more boundaries than one timeline holds: cut at the last midnight inside the cap,
        // reload there (or within 6 h, whichever is earlier).
        #expect(future.count > plan.entries.count - 1)
        let last = try #require(plan.entries.last?.date)
        #expect(snapshot.days.map { context.startOfDay($0.date.adding(days: 1)) }.contains(last))
        #expect(plan.reloadDate == min(last, now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval)))
        #expect(plan.entries.dropFirst().map(\.date).contains(context.startOfDay(today.adding(days: 1))))
    }

    @Test func shortTimelineEndsWithTheCoveredRangeAndReloadsWithinSixHours() {
        let day = date(2026, 10, 13)
        let snap = snapshot([school(day, [lesson("a", day, time(8), time(8, 45))]),
                             WidgetSnapshot.Day(date: day.adding(days: 1), kind: .free)])
        let now = instant(day, 7)
        let plan = WidgetTimelinePlanner.plan(snapshot: snap, now: now, deviceTimeZone: bratislava)
        #expect(plan.entries.map(\.date) == [now, instant(day, 8), instant(day, 8, 45), context.startOfDay(day.adding(days: 1)),
                                             context.startOfDay(day.adding(days: 2))])
        #expect(plan.entries.last?.state == .unavailable(.outdated))
        // The range ends in 41 h: the reload is capped at 6 h (a zone change needs a re-plan, RISKS #67).
        #expect(plan.reloadDate == now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval))
        #expect(WidgetTimelinePlanner.maxReloadInterval == 6 * 3600)
        // The range ends in 2 h: reload at its end.
        let late = instant(day.adding(days: 1), 22)
        #expect(WidgetTimelinePlanner.plan(snapshot: snap, now: late, deviceTimeZone: bratislava).reloadDate
            == context.startOfDay(day.adding(days: 2)))
    }

    @Test func everyPlanReloadsWithinSixHours() throws {
        let database = SampleScenarios.secondary().database
        for day in [today, date(2026, 10, 16), date(2026, 10, 29)] {
            for hour in [0, 7, 10, 15, 21] {
                let now = instant(day, hour)
                let plan = WidgetTimelinePlanner.plan(snapshot: build(database, at: instant(day, 0)), now: now,
                                                      deviceTimeZone: bratislava)
                #expect(plan.reloadDate > now && plan.reloadDate <= now.addingTimeInterval(6 * 3600), "\(day) \(hour):00")
            }
        }
    }

    @Test func manyLessonsAreCutAtTheLastMidnightBeforeTheCap() {
        let first = date(2026, 10, 12)
        let days = (0..<5).map { offset -> WidgetSnapshot.Day in
            let day = first.adding(days: offset)
            return school(day, (0..<8).map { lesson("l\($0)", day, time(8 + $0), time(8 + $0, 45)) })
        }
        let now = instant(first, 6)
        let plan = WidgetTimelinePlanner.plan(snapshot: snapshot(days), now: now, deviceTimeZone: bratislava)
        // 17 boundaries a day (16 lesson boundaries + midnight): 28 slots reach into day 2, so the timeline ends at the
        // first midnight (now + 16 boundaries + midnight = 18 entries) and its last state stays valid overnight.
        #expect(plan.entries.count == 18)
        #expect(plan.entries.last?.date == context.startOfDay(first.adding(days: 1)))
        #expect(plan.entries.last?.state == .upcoming(days[1].lessons[0], isFirstOfDay: true))
        #expect(plan.reloadDate == now.addingTimeInterval(WidgetTimelinePlanner.maxReloadInterval))
    }

    @Test func gapBetweenLessonsAndAfterTheLastLesson() throws {
        let day = date(2026, 10, 13)
        let tomorrow = day.adding(days: 1)
        let snap = snapshot([
            school(day, [lesson("a", day, time(8), time(8, 45)), lesson("c", day, time(10), time(10, 45))]),
            school(tomorrow, [lesson("t", tomorrow, time(8, 55), time(9, 40), subject: bio)]),
        ])
        func state(_ h: Int, _ m: Int = 0, on d: LocalDate = day) -> NowNextState {
            WidgetTimelinePlanner.state(snapshot: snap, at: instant(d, h, m), context: context)
        }
        #expect(state(7) == .upcoming(snap.days[0].lessons[0], isFirstOfDay: true))
        #expect(state(8) == .current(snap.days[0].lessons[0], next: snap.days[0].lessons[1]))
        #expect(state(8, 45) == .upcoming(snap.days[0].lessons[1], isFirstOfDay: false))   // half-open: ended
        #expect(state(9, 15) == .upcoming(snap.days[0].lessons[1], isFirstOfDay: false))
        #expect(state(10, 30) == .current(snap.days[0].lessons[1], next: snap.days[1].lessons[0]))
        #expect(state(10, 45) == .dayOver(next: snap.days[1].lessons[0]))   // tomorrow's first lesson
        #expect(state(23, 59) == .dayOver(next: snap.days[1].lessons[0]))
        // Midnight rollover: tomorrow's lesson becomes today's first lesson.
        #expect(state(0, 0, on: tomorrow) == .upcoming(snap.days[1].lessons[0], isFirstOfDay: true))
        let plan = WidgetTimelinePlanner.plan(snapshot: snap, now: instant(day, 9, 15), deviceTimeZone: bratislava)
        #expect(plan.entries.map(\.date).contains(context.startOfDay(tomorrow)))
        #expect(plan.entries.map(\.date).contains(instant(day, 10)))
    }

    @Test func cancelledLessonsAreSkipped() {
        let day = date(2026, 10, 13)
        let a = lesson("a", day, time(8), time(9))
        let b = lesson("b", day, time(9), time(10), status: .cancelled)
        let c = lesson("c", day, time(10), time(11))
        let snap = snapshot([school(day, [a, b, c])])
        #expect(WidgetTimelinePlanner.state(snapshot: snap, at: instant(day, 8, 30), context: context) == .current(a, next: c))
        #expect(WidgetTimelinePlanner.state(snapshot: snap, at: instant(day, 9, 30), context: context)
            == .upcoming(c, isFirstOfDay: false))
        let plan = WidgetTimelinePlanner.plan(snapshot: snap, now: instant(day, 7), deviceTimeZone: bratislava)
        // 9:00 is a's end anyway; b's own end (10:00) is c's start: no extra boundary from the cancelled lesson.
        #expect(plan.entries.map(\.date) == [instant(day, 7), instant(day, 8), instant(day, 9), instant(day, 10),
                                             instant(day, 11), context.startOfDay(day.adding(days: 1))])
        // Only cancelled lessons: a free day.
        let allCancelled = snapshot([school(day, [b])], following: c)
        #expect(WidgetTimelinePlanner.state(snapshot: allCancelled, at: instant(day, 8), context: context) == .free(next: c))
    }

    @Test func emptyDayHolidayAndCancelledDay() {
        let day = date(2026, 10, 13)
        let next = lesson("n", day.adding(days: 3), time(8), time(8, 45))
        let empty = snapshot([school(day, []), WidgetSnapshot.Day(date: day.adding(days: 1), kind: .free),
                              WidgetSnapshot.Day(date: day.adding(days: 2), kind: .free),
                              school(day.adding(days: 3), [next])])
        #expect(WidgetTimelinePlanner.state(snapshot: empty, at: instant(day, 10), context: context) == .free(next: next))
        let holiday = snapshot([WidgetSnapshot.Day(date: day, kind: .holiday, note: "Autumn break")], following: next)
        #expect(WidgetTimelinePlanner.state(snapshot: holiday, at: instant(day, 10), context: context)
            == .holiday(name: "Autumn break", next: next))
        let cancelled = snapshot([WidgetSnapshot.Day(date: day, kind: .cancelled, note: nil,
                                                     lessons: [lesson("x", day, time(8), time(9), status: .cancelled)])])
        #expect(WidgetTimelinePlanner.state(snapshot: cancelled, at: instant(day, 10), context: context)
            == .dayCancelled(note: nil, next: nil))
        // Holiday with the following lesson beyond the covered range.
        #expect(WidgetTimelinePlanner.state(snapshot: holiday, at: instant(day, 23, 59), context: context).next == next)
    }

    @Test func overlappingLessonsPickTheOneThatStartedLast() {
        let day = date(2026, 10, 13)
        let long = lesson("long", day, time(8), time(9, 30))
        let short = lesson("short", day, time(9), time(9, 45))
        let snap = snapshot([school(day, [long, short])])
        #expect(WidgetTimelinePlanner.state(snapshot: snap, at: instant(day, 9, 10), context: context) == .current(short, next: nil))
        #expect(WidgetTimelinePlanner.state(snapshot: snap, at: instant(day, 8, 10), context: context) == .current(long, next: short))
    }

    @Test func autumnDSTEndKeepsWallClockTimes() throws {
        // Sun 2026-10-25: 03:00 CEST → 02:00 CET (a 25-hour day).
        let friday = date(2026, 10, 23)
        let now = instant(friday, 12)
        let snap = build(SampleScenarios.secondary().database, at: now)
        #expect(snap.days.map(\.date) == [friday, date(2026, 10, 24), date(2026, 10, 25), date(2026, 10, 26)])
        let sunday = context.startOfDay(date(2026, 10, 25))
        let monday = context.startOfDay(date(2026, 10, 26))
        #expect(monday.timeIntervalSince(sunday) == 25 * 3600)
        let first = try #require(snap.days.last?.lessons.first { $0.takesPlace })
        #expect(first.start(in: context).timeIntervalSince(monday) == TimeInterval(first.startTime.minuteOfDay * 60))
        // 02:30 happens twice on Sunday; both are a free day with Monday's first lesson next.
        let ambiguous = context.resolve(date(2026, 10, 25), time(2, 30))
        guard case let .repeated(earlier, later) = ambiguous else {
            Issue.record("expected a repeated local time, got \(ambiguous)")
            return
        }
        for probe in [earlier, later] {
            #expect(WidgetTimelinePlanner.state(snapshot: snap, at: probe, context: context) == .free(next: first))
        }
        let plan = WidgetTimelinePlanner.plan(snapshot: snap, now: now, deviceTimeZone: bratislava)
        let dates = plan.entries.map(\.date)
        #expect(dates.contains(sunday) && dates.contains(monday))
    }

    @Test func springDSTGapShiftsTheNonexistentEnd() {
        // Sun 2027-03-28: 02:00 CET → 03:00 CEST. A lesson 01:30–02:30 ends at 03:30 CEST (DST policy: gap → forward).
        let day = date(2027, 3, 28)
        let early = lesson("early", day, time(1, 30), time(2, 30))
        let later = lesson("later", day, time(9), time(9, 45))
        let snap = snapshot([school(day, [early, later])])
        let start = early.start(in: context)
        let end = early.end(in: context)
        #expect(end.timeIntervalSince(start) == 3600)
        #expect(WidgetTimelinePlanner.state(snapshot: snap, at: end.addingTimeInterval(-60), context: context)
            == .current(early, next: later))
        #expect(WidgetTimelinePlanner.state(snapshot: snap, at: end, context: context) == .upcoming(later, isFirstOfDay: false))
        // Midnight of the next day is 23 hours after this day's midnight.
        #expect(context.startOfDay(day.adding(days: 1)).timeIntervalSince(context.startOfDay(day)) == 23 * 3600)
    }

    @Test func timeZoneChangeKeepsWallClockForFollowDeviceAndHomeZoneForFixed() throws {
        let day = date(2026, 10, 13)
        let first = lesson("a", day, time(8), time(8, 45))
        let follow = snapshot([school(day, [first])])
        let nyContext = CalendarContext(timeZone: newYork, firstWeekday: .monday)
        // The snapshot was written in Bratislava; the phone is now in New York.
        let now = instant(day, 7, in: nyContext)
        let plan = WidgetTimelinePlanner.plan(snapshot: follow, now: now, deviceTimeZone: newYork)
        #expect(plan.context?.timeZone == newYork)
        #expect(plan.entries[0].state == .upcoming(first, isFirstOfDay: true))
        #expect(plan.entries.map(\.date).contains(instant(day, 8, in: nyContext)))   // 08:00 New York time
        // The evening before in New York is not covered: outdated, never guessed.
        let before = WidgetTimelinePlanner.plan(snapshot: follow, now: instant(day.adding(days: -1), 20, in: nyContext),
                                                deviceTimeZone: newYork)
        #expect(before.entries.map(\.state) == [.unavailable(.outdated)])
        #expect(before.reloadDate == instant(day.adding(days: -1), 20, in: nyContext).addingTimeInterval(WidgetTimelinePlanner.unavailableRetry))
        // A fixed-zone timetable keeps Bratislava's clock wherever the phone is.
        let fixed = snapshot([school(day, [first])], follows: false)
        let fixedPlan = WidgetTimelinePlanner.plan(snapshot: fixed, now: instant(day, 7), deviceTimeZone: newYork)
        #expect(fixedPlan.context?.timeZone == bratislava)
        #expect(fixedPlan.entries.map(\.date).contains(instant(day, 8)))
    }

    @Test func unavailableStates() {
        let now = SampleScenarios.referenceNow
        let none = WidgetTimelinePlanner.plan(snapshot: nil, now: now, deviceTimeZone: bratislava)
        #expect(none.entries.map(\.state) == [.unavailable(.noSnapshot)] && none.context == nil)
        #expect(none.reloadDate == now.addingTimeInterval(WidgetTimelinePlanner.unavailableRetry))
        let onboarding = WidgetTimelinePlanner.plan(snapshot: build(nil, at: now), now: now, deviceTimeZone: bratislava)
        #expect(onboarding.entries.map(\.state) == [.unavailable(.noTimetable)])
        // Days after the covered range: outdated.
        let snap = build(SampleScenarios.secondary().database, at: now)
        let late = WidgetTimelinePlanner.plan(snapshot: snap, now: instant(date(2026, 10, 20), 9), deviceTimeZone: bratislava)
        #expect(late.entries.map(\.state) == [.unavailable(.outdated)])
    }

    @Test func laterLessonsListTheNextLessonsDay() throws {
        let now = SampleScenarios.referenceNow
        let snap = build(SampleScenarios.secondary().database, at: now)
        let entry = WidgetTimelinePlanner.entry(snapshot: snap, at: now, context: context)
        let next = try #require(entry.state.next)
        #expect(entry.laterLessons.count <= WidgetTimelinePlanner.maxLaterLessons)
        #expect(entry.laterLessons.allSatisfy { $0.date == next.date && $0.takesPlace && $0.id != next.id })
        #expect(entry.laterLessons.allSatisfy { $0.start(in: context) >= next.start(in: context) })
        #expect(!entry.laterLessons.isEmpty)
    }
}

@Suite("Now & Next presentation")
struct NowNextPresentationTests {
    private let renderer = LocalizedTextRenderer(
        formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: bratislava),
        lookup: EnglishCatalog.lookup)
    private var presenter: NowNextPresenter { NowNextPresenter(renderer: renderer, context: context) }

    private func display(_ snap: WidgetSnapshot, at now: Date) -> NowNextDisplay {
        presenter.display(WidgetTimelinePlanner.entry(snapshot: snap, at: now, context: context))
    }

    @Test func currentLessonShowsTimerNextAndASpokenSentence() throws {
        let day = date(2026, 10, 13)
        let a = lesson("a", day, time(8), time(8, 45))
        let b = lesson("b", day, time(8, 55), time(9, 40), subject: bio, room: nil)
        let shown = display(snapshot([school(day, [a, b])]), at: instant(day, 8, 15))
        guard case .current(let line) = shown.kind else {
            Issue.record("expected current, got \(shown.kind)")
            return
        }
        #expect(line.name == "Mathematics" && line.room == "214" && line.timeRange.contains("8:00"))
        #expect(shown.caption == "Now" && shown.timerCaption == "Time left")
        #expect(shown.timer == instant(day, 8)...instant(day, 8, 45))
        #expect(shown.nextShort == "Next: Biology, 8:55")
        #expect(shown.inlineText == "Mathematics")
        #expect(shown.laterCaption == "Next")
        #expect(shown.link == .today)
        #expect(abs(shown.progress(at: instant(day, 8, 15)) - 1.0 / 3.0) < 0.0001)
        let spoken = shown.accessibilityLabel
        for part in ["Now", "Mathematics", "8:00 to 8:45", "room 214", "ends at 8:45", "Next", "Biology"] {
            #expect(spoken.contains(part), "\(part) missing from \(spoken)")
        }
    }

    @Test func upcomingCountsDownToTheStartAndShowsChanges() {
        let day = date(2026, 10, 13)
        let a = lesson("a", day, time(8), time(8, 45), room: "105", status: .modified, reasons: [.roomChanged])
        let shown = display(snapshot([school(day, [a])]), at: instant(day, 7, 30))
        #expect(shown.caption == "First Lesson" && shown.timerCaption == "Starts in")
        #expect(shown.timer == instant(day, 7, 30)...instant(day, 8))
        #expect(shown.inlineText == "Next: Mathematics, 8:00")
        #expect(shown.laterCaption == "Later")
        guard case .upcoming(let line) = shown.kind else {
            Issue.record("expected upcoming, got \(shown.kind)")
            return
        }
        #expect(line.badgeText == EnglishCatalog.values[ModificationReason.roomChanged.l10nKey])
        #expect(shown.accessibilityLabel.contains("starts at 8:00"))
        #expect(shown.accessibilityLabel.contains("changed"))
    }

    @Test func afterSchoolNamesTomorrowAndMidnightDropsIt() throws {
        let now = instant(today, 18)
        let snap = build(SampleScenarios.secondary().database, at: now)
        let evening = display(snap, at: now)
        guard case let .status(_, title, _) = evening.kind else {
            Issue.record("expected status, got \(evening.kind)")
            return
        }
        #expect(title == "No more lessons today")
        let next = try #require(evening.next)
        #expect(next.whenText.hasPrefix("Tomorrow, "))
        #expect(evening.nextCaption == "Next Lesson")
        #expect(evening.inlineText.hasPrefix("Next: "))
        let midnight = display(snap, at: context.startOfDay(today.adding(days: 1)))
        guard case .upcoming(let line) = midnight.kind else {
            Issue.record("expected upcoming at midnight, got \(midnight.kind)")
            return
        }
        #expect(line.id == next.id && line.whenText == line.startText)
        #expect(midnight.caption == "First Lesson")
    }

    @Test func holidayUnavailableAndNothingAhead() {
        let holiday = display(build(SampleScenarios.secondary().database, at: instant(date(2026, 10, 29), 9)),
                              at: instant(date(2026, 10, 29), 9))
        #expect(holiday.kind == .status(symbol: "beach.umbrella", title: "Jesenné prázdniny", detail: "Holidays"))
        #expect(holiday.next?.whenText.contains("2") == true)   // "Mon 2 Nov, 08:00"
        #expect(holiday.nothingAhead == nil)

        let day = date(2026, 10, 13)
        let nothing = display(snapshot([WidgetSnapshot.Day(date: day, kind: .free)]), at: instant(day, 10))
        #expect(nothing.next == nil && nothing.nothingAhead == "No lessons in the next few weeks.")
        #expect(nothing.inlineText == "No lessons today")

        let outdated = presenter.display(NowNextTimelineEntry(date: instant(day, 10), state: .unavailable(.outdated)))
        #expect(outdated.kind == .unavailable(title: "Open Tabula", detail: "Open the app to update your timetable."))
        #expect(outdated.timer == nil && outdated.accessibilityLabel.contains("Open Tabula"))
        let texts = presenter.proTexts()
        #expect(texts.title == "Available in Tabula Pro" && texts.short == "Pro")
    }

    @Test func rendererUsesTheSnapshotLocaleAndHourCycle() {
        var snap = snapshot([])
        snap.localeID = "en_US"
        snap.hourCycle = .h12
        let renderer = NowNextPresenter.renderer(for: snap, context: context, lookup: EnglishCatalog.lookup)
        #expect(renderer.formatter.time(time(13, 5)).contains("PM"))
        snap.hourCycle = .h24
        #expect(NowNextPresenter.renderer(for: snap, context: context, lookup: EnglishCatalog.lookup)
            .formatter.time(time(13, 5)) == "13:05")
    }
}

@Suite("Widget accent contrast")
struct WidgetAccentContrastTests {
    @Test func progressTintReachesThreeToOneOnBothPages() {
        let palette = PalettePack.classic.colors.map(\.value) + [
            ColorValue(red: 255, green: 255, blue: 255), ColorValue(red: 0, green: 0, blue: 0),
            ColorValue(red: 240, green: 220, blue: 60), ColorValue(red: 20, green: 30, blue: 80),
            ColorValue(red: 200, green: 200, blue: 200, alpha: 80),
        ]
        for color in palette {
            for isDark in [false, true] {
                let page = isDark ? LessonTileStyle.darkPageBackground : LessonTileStyle.lightPageBackground
                let tint = LessonTileStyle.contrastSafeAccent(color, isDark: isDark)
                #expect(tint.contrastRatio(with: page) >= 3.0, "\(color) on \(isDark ? "dark" : "light"): \(tint)")
            }
        }
        // A colour that already contrasts is left as it is.
        let blue = ColorValue(red: 30, green: 90, blue: 200)
        #expect(LessonTileStyle.contrastSafeAccent(blue, isDark: false) == blue)
        // Pastel yellow on white is darkened, navy on black is lightened.
        let yellow = ColorValue(red: 240, green: 220, blue: 60)
        #expect(LessonTileStyle.contrastSafeAccent(yellow, isDark: false).relativeLuminance < yellow.relativeLuminance)
        let navy = ColorValue(red: 20, green: 30, blue: 80)
        #expect(LessonTileStyle.contrastSafeAccent(navy, isDark: true).relativeLuminance > navy.relativeLuminance)
    }
}

@Suite("Widget gallery samples")
struct WidgetGallerySampleTests {
    @Test func previewSnapshotIsSmallAndRunsALiveLesson() throws {
        for (hour, minute) in [(10, 20), (0, 5), (23, 50)] {
            let now = instant(today, hour, minute)
            let snap = WidgetGallerySamples.previewSnapshot(now: now, timeZone: bratislava, localeID: "en_GB",
                                                            languageCode: "en", name: EnglishCatalog.lookup)
            let data = try WidgetSnapshotStore.encode(snap)
            #expect(data.count < 2_500)
            let state = WidgetTimelinePlanner.state(snapshot: snap, at: now, context: context)
            guard case let .current(lesson, next) = state else {
                Issue.record("expected a current lesson at \(hour):\(minute), got \(state)")
                continue
            }
            #expect(lesson.subject.name == "Mathematics")
            #expect(lesson.end(in: context) > now)   // the timer runs, never 0:00
            if hour == 10 { #expect(next?.subject.name == "Biology") }
        }
    }

    @Test func scenesShowTheirStates() throws {
        let scenes = WidgetGallerySamples.scenes(locale: Locale(identifier: "en_GB"), languageCode: "en")
        #expect(scenes.map(\.id) == ["lesson", "break", "after", "holiday"])
        func state(_ id: String) throws -> NowNextState {
            let scene = try #require(scenes.first { $0.id == id })
            return WidgetTimelinePlanner.plan(snapshot: scene.snapshot, now: scene.date, deviceTimeZone: bratislava)
                .entries[0].state
        }
        guard case .current = try state("lesson") else { Issue.record("lesson scene"); return }
        guard case .upcoming(_, false) = try state("break") else { Issue.record("break scene: \(try state("break"))"); return }
        guard case .dayOver(let next) = try state("after"), next?.date == date(2026, 10, 14) else {
            Issue.record("after scene: \(try state("after"))")
            return
        }
        guard case .holiday(let name, _) = try state("holiday"), name == "Jesenné prázdniny" else {
            Issue.record("holiday scene")
            return
        }
        #expect(WidgetGallerySamples.scenes(locale: Locale(identifier: "en_GB"), languageCode: "en", tier: .free)
            .allSatisfy { $0.snapshot.tier == .free })
    }
}
