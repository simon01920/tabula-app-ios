import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 4 B2: Live Activity planner (start / schedule / update / end rules), presenter, 4 KB budget, sources, samples.

private let zone = SampleScenarios.timeZone
private let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d)! }
private func at(_ date: LocalDate, _ h: Int, _ m: Int = 0) -> Date { context.date(date, LocalTime(hour: h, minute: m)!) }
private let tue = day(2026, 10, 13)
private let wed = day(2026, 10, 14)
private let style = LiveActivityStyle(localeID: "en_GB", languageCode: "en", hourCycle: .h24, timeZoneID: zone.identifier)
private let renderer = LocalizedTextRenderer(
    formatter: TimetableFormatter(locale: Locale(identifier: "en_GB"), hourCycle: .h24, timeZone: zone),
    lookup: EnglishCatalog.lookup)
private let planner = LiveActivityPlanner(renderer: renderer)
private let presenter = LiveActivityPresenter(renderer: renderer, context: context)
/// A time as the app formats it (en_GB, 24 h).
private func t(_ date: LocalDate, _ h: Int, _ m: Int = 0) -> String { renderer.formatter.time(at(date, h, m)) }

private let math = LiveActivitySubject(name: "Mathematics", shortName: "MAT", color: ColorValue(red: 30, green: 90, blue: 200))
private let bio = LiveActivitySubject(name: "Biology", color: ColorValue(red: 240, green: 220, blue: 60), symbol: .emoji("🧬"))

/// 8:00–8:45 Mathematics (214), 8:55–9:40 Biology, 9:50–10:35 Mathematics.
private func lessonDay(_ date: LocalDate) -> LiveActivityLessonDay {
    LiveActivityLessonDay(day: date, lessons: [
        LiveActivityLesson(subject: math, room: "214", start: at(date, 8), end: at(date, 8, 45)),
        LiveActivityLesson(subject: bio, room: nil, start: at(date, 8, 55), end: at(date, 9, 40)),
        LiveActivityLesson(subject: math, room: "214", start: at(date, 9, 50), end: at(date, 10, 35)),
    ])
}

private let examID = UUID(uuidString: "E8A30000-0000-4000-8000-000000000001")!
private func exam(_ date: LocalDate, _ h: Int, _ m: Int = 0, end: (Int, Int)? = (11, 30), id: UUID = examID) -> LiveActivityExam {
    LiveActivityExam(id: id, day: date, title: "Chemistry test", subject: math, room: "Lab", start: at(date, h, m),
                     end: end.map { at(date, $0.0, $0.1) })
}

private func sources(days: [LiveActivityLessonDay] = [lessonDay(tue), lessonDay(wed)],
                     exams: [LiveActivityExam] = []) -> LiveActivitySources {
    LiveActivitySources(style: style, context: context, lessonDays: days, exams: exams)
}

private func input(_ src: LiveActivitySources, now: Date, canStart: Bool = true, systemEnabled: Bool = true,
                   entitled: Bool = true, preferences: LiveActivityPreferences = LiveActivityPreferences(),
                   ledger: LiveActivityLedger = LiveActivityLedger(), lessons: [LessonActivityExisting] = [],
                   exams: [ExamActivityExisting] = []) -> LiveActivityPlanInput {
    LiveActivityPlanInput(sources: src, now: now, canStart: canStart, systemEnabled: systemEnabled, entitled: entitled,
                          preferences: preferences, ledger: ledger, lessons: lessons, exams: exams)
}

private func running(_ date: LocalDate, now: Date, id: String = "L1",
                     status: LiveActivityStatus = .active) -> LessonActivityExisting {
    LessonActivityExisting(id: id, attributes: .init(day: date), status: status,
                           content: LiveActivityPlanner.runningLessonContent(lessonDay(date), style, now: now))
}

private let auto = LiveActivityPreferences(autoStart: true)

@Suite("Live Activity planner — lessons")
struct LessonActivityPlannerTests {
    @Test func startsFifteenMinutesBeforeTheFirstLessonNotEarlier() {
        let early = planner.plan(input(sources(), now: at(tue, 7, 44)))
        #expect(early.lessonSteps.isEmpty)
        #expect(early.nextEvaluation == at(tue, 7, 45))
        let plan = planner.plan(input(sources(), now: at(tue, 7, 45)))
        guard case let .start(attributes, content)? = plan.lessonSteps.first else {
            Issue.record("expected a start, got \(plan.lessonSteps)")
            return
        }
        #expect(attributes.day == tue)
        #expect(content.state.index == 0 && content.state.lessons.count == 3 && !content.state.isFinal)
        #expect(content.staleDate == at(tue, 8))
        #expect(content.relevanceScore == LiveActivityPolicy.lessonRelevance)
        #expect(plan.ledger.hasLesson(tue))
    }

    @Test func startsDuringALessonWithItsIndexAndTheNextBoundaryAsStaleDate() {
        let plan = planner.plan(input(sources(), now: at(tue, 9, 0)))
        guard case let .start(_, content)? = plan.lessonSteps.first else {
            Issue.record("expected a start")
            return
        }
        #expect(content.state.index == 1)
        #expect(content.staleDate == at(tue, 9, 40))
        #expect(plan.nextEvaluation == at(tue, 9, 40))
    }

    @Test func nothingStartsInTheBackgroundWithoutGateOrAfterTheUserDismissedIt() {
        let now = at(tue, 9)
        #expect(planner.plan(input(sources(), now: now, canStart: false)).lessonSteps.isEmpty)
        #expect(planner.plan(input(sources(), now: now, systemEnabled: false)).lessonSteps.isEmpty)
        #expect(planner.plan(input(sources(), now: now, entitled: false)).lessonSteps.isEmpty)
        #expect(planner.plan(input(sources(), now: now, preferences: .init(lessonEnabled: false))).lessonSteps.isEmpty)
        // Started earlier today and swiped away (no longer in Activity.activities): not started again.
        #expect(planner.plan(input(sources(), now: now, ledger: .init(lessonDays: [tue]))).lessonSteps.isEmpty)
    }

    @Test func adoptsARunningActivityAndUpdatesOnlyWhenTheContentChanged() {
        let started = running(tue, now: at(tue, 8, 10))
        // Same lesson, same boundary: nothing to do (adopted after a relaunch, no duplicate).
        let same = planner.plan(input(sources(), now: at(tue, 8, 30), ledger: .init(lessonDays: [tue]), lessons: [started]))
        #expect(same.lessonSteps.isEmpty)
        // After the boundary: one update with the new index.
        let later = planner.plan(input(sources(), now: at(tue, 8, 50), canStart: false, ledger: .init(lessonDays: [tue]),
                                       lessons: [started]))
        guard case let .update(id, content)? = later.lessonSteps.first, later.lessonSteps.count == 1 else {
            Issue.record("expected one update, got \(later.lessonSteps)")
            return
        }
        #expect(id == "L1" && content.state.index == 1 && content.staleDate == at(tue, 8, 55))
    }

    @Test func duplicatesAreEnded() {
        let a = running(tue, now: at(tue, 8, 10), id: "A")
        let b = running(tue, now: at(tue, 8, 10), id: "B")
        let plan = planner.plan(input(sources(), now: at(tue, 8, 10), lessons: [b, a]))
        #expect(plan.lessonSteps == [.end(id: "B", nil, .immediate)])
    }

    @Test func endsAfterTheLastLessonWithTheFinalStateForFifteenMinutes() {
        let started = running(tue, now: at(tue, 10))
        let plan = planner.plan(input(sources(), now: at(tue, 10, 40), lessons: [started]))
        #expect(plan.lessonSteps == [.end(id: "L1", LiveActivityPlanner.finalLessonContent(style), .after(at(tue, 10, 50)))])
        let late = planner.plan(input(sources(), now: at(tue, 18), lessons: [started]))
        #expect(late.lessonSteps == [.end(id: "L1", LiveActivityPlanner.finalLessonContent(style), .immediate)])
    }

    @Test func endsOnDayChangeHolidayAndWhenSwitchedOff() {
        let yesterday = running(tue, now: at(tue, 10))
        let plan = planner.plan(input(sources(), now: at(wed, 6), lessons: [yesterday]))
        #expect(plan.lessonSteps == [.end(id: "L1", LiveActivityPlanner.finalLessonContent(style), .immediate)])
        // Today became a holiday / cancelled day (no lessons today any more).
        let holiday = planner.plan(input(sources(days: [lessonDay(wed)]), now: at(tue, 9), lessons: [running(tue, now: at(tue, 9))]))
        #expect(holiday.lessonSteps == [.end(id: "L1", nil, .immediate)])
        let off = planner.plan(input(sources(), now: at(tue, 9), preferences: .init(lessonEnabled: false),
                                     lessons: [running(tue, now: at(tue, 9))]))
        #expect(off.lessonSteps == [.end(id: "L1", nil, .immediate)])
        let disabled = planner.plan(input(sources(), now: at(tue, 9), systemEnabled: false,
                                          lessons: [running(tue, now: at(tue, 9))]))
        #expect(disabled.lessonSteps == [.end(id: "L1", nil, .immediate)])
    }

    @Test func schedulesTodayWhenOpenedEarlyAndTomorrowAfterSchool() {
        let morning = planner.plan(input(sources(), now: at(tue, 6), preferences: auto))
        guard case let .schedule(attributes, content, date, alert)? = morning.lessonSteps.first else {
            Issue.record("expected a schedule, got \(morning.lessonSteps)")
            return
        }
        #expect(attributes.day == tue && date == at(tue, 7, 45))
        #expect(content == LiveActivityPlanner.scheduledLessonContent(lessonDay(tue), style))
        // A scheduled activity that starts needs no update: its content equals the running content before lesson 1.
        #expect(content == LiveActivityPlanner.runningLessonContent(lessonDay(tue), style, now: at(tue, 7, 50)))
        #expect(alert.title == "First Lesson" && alert.body == "Mathematics at \(t(tue, 8))")
        // Without "Start automatically" nothing is scheduled.
        #expect(planner.plan(input(sources(), now: at(tue, 6))).lessonSteps.isEmpty)
        // After school: tomorrow.
        let evening = planner.plan(input(sources(), now: at(tue, 19), preferences: auto))
        guard case let .schedule(next, _, nextDate, _)? = evening.lessonSteps.first else {
            Issue.record("expected tomorrow's schedule")
            return
        }
        #expect(next.day == wed && nextDate == at(wed, 7, 45))
        // During today's lessons tomorrow is not scheduled yet (at most one lesson activity at a time).
        let during = planner.plan(input(sources(), now: at(tue, 9), preferences: auto, ledger: .init(lessonDays: [tue]),
                                        lessons: [running(tue, now: at(tue, 9))]))
        #expect(during.lessonSteps.allSatisfy { if case .schedule = $0 { false } else { true } })
    }

    @Test func aChangedPendingActivityIsRescheduledAndAnUnchangedOneKept() {
        let pending = LessonActivityExisting(id: "P", attributes: .init(day: wed), status: .pending,
                                             content: LiveActivityPlanner.scheduledLessonContent(lessonDay(wed), style))
        let kept = planner.plan(input(sources(), now: at(tue, 19), preferences: auto, ledger: .init(lessonDays: [wed]),
                                      lessons: [pending]))
        #expect(kept.lessonSteps.isEmpty)
        var moved = lessonDay(wed)
        moved.lessons[0].start = at(wed, 7, 30)
        let changed = planner.plan(input(sources(days: [lessonDay(tue), moved]), now: at(tue, 19), preferences: auto,
                                         ledger: .init(lessonDays: [wed]), lessons: [pending]))
        #expect(changed.lessonSteps.count == 2)
        #expect(changed.lessonSteps.first == .end(id: "P", nil, .immediate))
        if case let .schedule(_, _, date, _)? = changed.lessonSteps.last {
            #expect(date == at(wed, 7, 15))
        } else {
            Issue.record("expected a new schedule")
        }
    }

    @Test func scheduleHorizonIsThreeDays() {
        let far = LiveActivityLessonDay(day: day(2026, 10, 19), lessons: lessonDay(day(2026, 10, 19)).lessons)
        let plan = planner.plan(input(sources(days: [far]), now: at(tue, 19), preferences: auto))
        #expect(plan.lessonSteps.isEmpty)
    }
}

@Suite("Live Activity planner — exams")
struct ExamActivityPlannerTests {
    @Test func windowOpensSixHoursBeforeButNotBeforeTheExamDay() {
        #expect(LiveActivityPlanner.window(exam(wed, 10), context).lowerBound == at(wed, 4))
        #expect(LiveActivityPlanner.window(exam(wed, 3, end: (4, 0)), context).lowerBound == context.startOfDay(wed))
        #expect(LiveActivityPlanner.window(exam(wed, 10), context).upperBound == at(wed, 11, 30))
        // Without an end: one hour of "in progress".
        #expect(LiveActivityPlanner.window(exam(wed, 10, end: nil), context).upperBound == at(wed, 11))
    }

    @Test func scheduledStartIsNotBeforeSixUnlessTheExamIsEarly() {
        #expect(LiveActivityPlanner.scheduledStart(exam(wed, 10), context) == at(wed, 6))
        #expect(LiveActivityPlanner.scheduledStart(exam(wed, 14), context) == at(wed, 8))
        #expect(LiveActivityPlanner.scheduledStart(exam(wed, 6, 10, end: nil), context) == at(wed, 5, 55))
        #expect(LiveActivityPlanner.scheduledStart(exam(wed, 0, 30, end: nil), context) == at(wed, 0, 15))
    }

    @Test func startsInTheWindowWithHigherRelevanceAndCountsDown() {
        let src = sources(exams: [exam(tue, 10)])
        #expect(planner.plan(input(src, now: at(tue, 3, 59))).examSteps.isEmpty)
        let plan = planner.plan(input(src, now: at(tue, 8)))
        guard case let .start(attributes, content)? = plan.examSteps.first else {
            Issue.record("expected an exam start, got \(plan.examSteps)")
            return
        }
        #expect(attributes.examID == examID)
        #expect(content.relevanceScore == LiveActivityPolicy.examRelevance)
        #expect(content.relevanceScore > LiveActivityPolicy.lessonRelevance)
        #expect(content.staleDate == at(tue, 10))
        #expect(plan.ledger.hasExam(examID, day: tue))
        let shown = presenter.exam(content.state, examID: examID, now: at(tue, 8))
        #expect(shown.phase == .upcoming && shown.caption == "Exam today" && shown.timerCaption == "Starts in")
        #expect(shown.timer == at(tue, 8)...at(tue, 10))
        #expect(shown.link == .exam(Exam.ID(examID)))
    }

    @Test func runningExamUpdatesOnEditAndEndsAfterwards() {
        let original = exam(tue, 10)
        let started = ExamActivityExisting(id: "X", attributes: .init(examID: examID), status: .active,
                                           content: LiveActivityPlanner.runningExamContent(original, style, now: at(tue, 8)))
        // The exam start passed: new stale date (the end) → update.
        let during = planner.plan(input(sources(exams: [original]), now: at(tue, 10, 5), ledger: .init(exams: [.init(id: examID, day: tue)]),
                                        exams: [started]))
        guard case let .update(_, content)? = during.examSteps.first else {
            Issue.record("expected an update")
            return
        }
        #expect(content.staleDate == at(tue, 11, 30))
        let shown = presenter.exam(content.state, examID: examID, now: at(tue, 10, 5))
        #expect(shown.phase == .running && shown.caption == "In progress" && shown.timer == at(tue, 10)...at(tue, 11, 30))
        // The room was edited: update.
        var edited = original
        edited.room = "B2"
        let edit = planner.plan(input(sources(exams: [edited]), now: at(tue, 8), ledger: .init(exams: [.init(id: examID, day: tue)]),
                                      exams: [started]))
        #expect(edit.examSteps.count == 1)
        // After the end: final content, kept 15 minutes.
        let after = planner.plan(input(sources(exams: [original]), now: at(tue, 11, 31), exams: [started]))
        #expect(after.examSteps == [.end(id: "X", LiveActivityPlanner.finalExamContent(original, style),
                                         .after(at(tue, 11, 45)))])
        // Deleted / completed (no longer a source): ended at once.
        let gone = planner.plan(input(sources(exams: []), now: at(tue, 9), exams: [started]))
        #expect(gone.examSteps == [.end(id: "X", nil, .immediate)])
    }

    @Test func examIsScheduledTheEveningBeforeAtSixWithAnAlert() {
        let plan = planner.plan(input(sources(exams: [exam(wed, 10)]), now: at(tue, 20), preferences: auto))
        guard case let .schedule(_, _, date, alert)? = plan.examSteps.first else {
            Issue.record("expected an exam schedule, got \(plan.examSteps)")
            return
        }
        #expect(date == at(wed, 6))
        #expect(alert.title == "Exam today" && alert.body == "Chemistry test at \(t(wed, 10))")
        #expect(planner.plan(input(sources(exams: [exam(wed, 10)]), now: at(tue, 20))).examSteps.isEmpty)
    }

    @Test func bothActivitiesRunTogetherWithTheExamOnTop() {
        let plan = planner.plan(input(sources(exams: [exam(tue, 10)]), now: at(tue, 9)))
        #expect(plan.lessonSteps.count == 1 && plan.examSteps.count == 1)
        if case let .start(_, lesson)? = plan.lessonSteps.first, case let .start(_, examContent)? = plan.examSteps.first {
            #expect(examContent.relevanceScore > lesson.relevanceScore)
        } else {
            Issue.record("expected two starts")
        }
    }
}

@Suite("Live Activity presentation")
struct LiveActivityPresentationTests {
    private func state(now: Date) -> LessonActivityAttributes.ContentState {
        LiveActivityPlanner.runningLessonContent(lessonDay(tue), style, now: now).state
    }

    @Test func currentLessonCountsDownAndNamesTheNextOne() {
        let shown = presenter.lesson(state(now: at(tue, 8, 10)), now: at(tue, 8, 10))
        #expect(shown.phase == .running && shown.caption == "Now" && shown.title == "Mathematics")
        #expect(shown.timer == at(tue, 8)...at(tue, 8, 45) && shown.progress == shown.timer)
        #expect(shown.timerCaption == "Time left" && shown.next == "Next: Biology, \(t(tue, 8, 55))")
        #expect(shown.detail?.hasPrefix("214 · ") == true && shown.detail?.contains(t(tue, 8, 45)) == true)
        for part in ["Now", "Mathematics", "room 214", "ends at \(t(tue, 8, 45))", "Next", "Biology"] {
            #expect(shown.accessibilityLabel.contains(part), "\(part) missing from \(shown.accessibilityLabel)")
        }
        #expect(shown.timerAccessibilityLabel == "Mathematics, ends at \(t(tue, 8, 45))")
        #expect(abs(shown.progressValue(at: at(tue, 8, 15)) - 1.0 / 3.0) < 0.0001)
    }

    @Test func rendersTheRightLessonWithoutAnUpdateAndNeverGoesBack() {
        // Content from 8:10, rendered at 9:00 (stale re-render): Biology is current.
        let shown = presenter.lesson(state(now: at(tue, 8, 10)), now: at(tue, 9))
        #expect(shown.title == "Biology" && shown.timer == at(tue, 8, 55)...at(tue, 9, 40))
        // In the break: the next lesson counts down from the render time.
        let gap = presenter.lesson(state(now: at(tue, 8, 10)), now: at(tue, 9, 45))
        #expect(gap.phase == .upcoming && gap.caption == "Next" && gap.timer == at(tue, 9, 45)...at(tue, 9, 50))
        #expect(gap.timerAccessibilityLabel == "Mathematics, starts at \(t(tue, 9, 50))")
        // Before the first lesson: "First Lesson".
        let first = presenter.lesson(state(now: at(tue, 7, 50)), now: at(tue, 7, 50))
        #expect(first.caption == "First Lesson" && first.phase == .upcoming)
        // A clock that went back never shows an earlier lesson than the update's index (lesson 3, not lesson 1).
        let back = presenter.lesson(state(now: at(tue, 10)), now: at(tue, 8, 10))
        #expect(back.title == "Mathematics" && back.phase == .upcoming && back.timer?.upperBound == at(tue, 9, 50))
    }

    @Test func afterTheLastLessonAndFinalContentShowTheDayIsOver() {
        let over = presenter.lesson(state(now: at(tue, 10)), now: at(tue, 10, 40))
        #expect(over.phase == .finished && over.title == "No more lessons today" && over.timer == nil)
        let final = presenter.lesson(LiveActivityPlanner.finalLessonContent(style).state, now: at(tue, 9))
        #expect(final.phase == .finished)
    }

    @Test func examWithoutEndAndFinished() {
        let noEnd = LiveActivityPlanner.runningExamContent(exam(tue, 10, end: nil), style, now: at(tue, 9)).state
        let running = presenter.exam(noEnd, examID: examID, now: at(tue, 10, 30))
        #expect(running.phase == .running && running.timer == nil && running.compactText == t(tue, 10))
        let done = presenter.exam(noEnd, examID: examID, now: at(tue, 11, 1))
        #expect(done.phase == .finished && done.caption == "Exam finished")
    }
}

@Suite("Live Activity data")
struct LiveActivityDataTests {
    /// Attributes + state, JSON, as ActivityKit would encode them (its encoder is not documented; JSON is the
    /// documented size reference "4 KB").
    private func encodedSize<A: Encodable, S: Encodable>(_ attributes: A, _ state: S) throws -> Int {
        try JSONEncoder().encode(attributes).count + JSONEncoder().encode(state).count
    }

    @Test func worstCaseLessonAndExamStayUnderTheBudget() throws {
        let long = String(repeating: "𝔐", count: 200)   // 4-byte characters, cut to the limits
        let subject = LiveActivitySubject(SubjectSummary(id: Subject.ID(UUID()), name: long, shortName: long,
                                                         color: ColorValue(red: 1, green: 2, blue: 3),
                                                         symbol: .systemImage(String(repeating: "a", count: LiveActivityLimits.maxSymbolLength))))
        #expect(subject.name.count <= LiveActivityLimits.maxTitleLength)
        #expect(subject.name.utf8.count <= LiveActivityLimits.maxTitleBytes)
        #expect(subject.name.hasSuffix("\u{2026}"))
        let lessons = (0..<LiveActivityLimits.maxLessons).map { index in
            LiveActivityLesson(subject: subject, room: LiveActivityLimits.cut(long, LiveActivityLimits.maxRoomLength),
                               start: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 3_123.456),
                               end: Date(timeIntervalSince1970: 1_800_002_700 + Double(index) * 3_123.456))
        }
        let longStyle = LiveActivityStyle(localeID: "sr-Latn_RS@calendar=gregorian", languageCode: "sr-Latn",
                                          hourCycle: .h24, timeZoneID: "America/Argentina/ComodRivadavia")
        let lesson = try encodedSize(LessonActivityAttributes(day: tue),
                                     LessonActivityAttributes.ContentState(lessons: lessons, index: 11, isFinal: false,
                                                                           style: longStyle))
        #expect(lesson < LiveActivityLimits.maxEncodedBytes, "lesson activity \(lesson) B")
        let examState = ExamActivityAttributes.ContentState(
            title: LiveActivityLimits.cut(long, LiveActivityLimits.maxTitleLength, maxBytes: LiveActivityLimits.maxTitleBytes)!, subject: subject,
            room: LiveActivityLimits.cut(long, LiveActivityLimits.maxRoomLength), start: Date(), end: Date(),
            isFinal: false, style: longStyle)
        let exam = try encodedSize(ExamActivityAttributes(examID: UUID()), examState)
        #expect(exam < LiveActivityLimits.maxEncodedBytes, "exam activity \(exam) B")
    }

    @Test func galleryCaptionsUseTheSceneTimeZoneNotUTC() throws {
        let locale = Locale(identifier: "en_GB")
        let lesson = try #require(LiveActivityGallerySamples.scenes(locale: locale, languageCode: "en").first { $0.id == "lesson" })
        #expect(lesson.timeZone.identifier == WidgetGallerySamples.context.timeZone.identifier)
        #expect(lesson.caption(locale: locale).contains("10:20"), "\(lesson.caption(locale: locale))")
        let widget = try #require(WidgetGallerySamples.scenes(locale: locale, languageCode: "en").first { $0.id == "lesson" })
        #expect(widget.caption(locale: locale).contains("10:20"), "\(widget.caption(locale: locale))")
    }

    @Test func normalSubjectNamesAreNotCutAndCutNamesEndWithAnEllipsis() {
        let slovak = "Slovensk\u{FD} jazyk a literat\u{FA}ra"
        #expect(LiveActivityLimits.cut(slovak, LiveActivityLimits.maxTitleLength, maxBytes: LiveActivityLimits.maxTitleBytes) == slovak)
        let cut = LiveActivityLimits.cut(String(repeating: "abcdefghi ", count: 10), LiveActivityLimits.maxTitleLength)!
        #expect(cut.count == LiveActivityLimits.maxTitleLength && cut.hasSuffix("\u{2026}"))
        #expect(LiveActivityLimits.cut("  ", 5) == nil)
        #expect(LiveActivityLimits.cut("12345", 5) == "12345")
    }

    @Test func contentStateRoundTripsAndPreferencesDecodeOldData() throws {
        let content = LiveActivityPlanner.runningLessonContent(lessonDay(tue), style, now: at(tue, 9))
        let data = try JSONEncoder().encode(content.state)
        #expect(try JSONDecoder().decode(LessonActivityAttributes.ContentState.self, from: data) == content.state)
        let prefs = try JSONDecoder().decode(LiveActivityPreferences.self, from: Data(#"{"lesson":false}"#.utf8))
        #expect(prefs == LiveActivityPreferences(lessonEnabled: false, examEnabled: true, autoStart: false))
    }

    @Test func ledgerPrunesAndForgets() {
        var ledger = LiveActivityLedger()
        for offset in 0..<20 { ledger.recordLesson(tue.adding(days: offset)) }
        #expect(ledger.lessonDays.count == LiveActivityLedger.keptDays && ledger.hasLesson(tue.adding(days: 19)))
        ledger.forgetLessons(from: tue.adding(days: 10))
        #expect(!ledger.hasLesson(tue.adding(days: 10)) && ledger.hasLesson(tue.adding(days: 9)))
        ledger.recordExam(examID, day: tue)
        #expect(ledger.hasExam(examID, day: tue) && !ledger.hasExam(examID, day: wed))
        ledger.forgetExams()
        #expect(!ledger.hasExam(examID, day: tue))
    }

    @Test func userDefaultsStoreRoundTrips() throws {
        let suite = "tabula.tests.liveActivities.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsLiveActivityPreferenceStore(defaults: defaults)
        #expect(store.loadPreferences() == LiveActivityPreferences())
        store.savePreferences(auto)
        store.saveLedger(LiveActivityLedger(lessonDays: [tue], exams: [.init(id: examID, day: tue)]))
        #expect(store.loadPreferences() == auto)
        #expect(store.loadLedger().hasLesson(tue) && store.loadLedger().hasExam(examID, day: tue))
    }

    @Test func sourcesFollowTheTodayTabAndTheExamsTab() throws {
        let scenario = SampleScenarios.secondary()
        let now = SampleScenarios.referenceNow
        let src = LiveActivitySourceBuilder.make(database: scenario.database, now: now, context: context,
                                                 locale: Locale(identifier: "en_GB"), languageCode: "en")
        let today = try #require(src.lessonDays.first)
        #expect(today.day == SampleScenarios.today)
        // Same lessons (taking place) as the widget snapshot of today.
        let snapshot = WidgetSnapshotBuilder.make(database: scenario.database, now: now, context: context, tier: .pro,
                                                  locale: Locale(identifier: "en_GB"), languageCode: "en")
        let widgetDay = try #require(snapshot.day(SampleScenarios.today))
        #expect(today.lessons.map(\.start) == WidgetTimelinePlanner.active(widgetDay, context).map { $0.start(in: context) })
        // Exams with a start time from today within three days: none on Tue 13th (chemistry is on the 22nd) …
        #expect(src.exams.isEmpty)
        // … but on the 20th the chemistry test (22nd) is in range; the biology test (27th) is not.
        let later = LiveActivitySourceBuilder.make(database: scenario.database, now: at(day(2026, 10, 20), 9),
                                                   context: context, locale: Locale(identifier: "en_GB"), languageCode: "en")
        #expect(later.exams.map(\.day) == [day(2026, 10, 22)])
        #expect(later.exams.first?.room == "Lab CHE" && later.exams.first?.end == at(day(2026, 10, 22), 10, 45))
    }

    @Test func gallerySamplesShowTheirPhases() {
        let scenes = LiveActivityGallerySamples.scenes(locale: Locale(identifier: "en_GB"), languageCode: "en")
        #expect(scenes.map(\.id) == ["lesson", "break", "finished", "examCountdown", "examRunning"])
        let phases: [LiveActivityDisplay.Phase] = scenes.map { scene in
            switch scene.content {
            case .lesson(let state): return presenter.lesson(state, now: scene.date).phase
            case let .exam(id, state): return presenter.exam(state, examID: id, now: scene.date).phase
            }
        }
        #expect(phases == [.running, .upcoming, .finished, .upcoming, .running])
    }

    @Test func backgroundRefreshMovesEarlierForALiveActivity() {
        let now = at(tue, 9)
        let base = BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: at(tue, 20), now: now)
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: at(tue, 20), now: now, additional: nil) == base)
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: at(tue, 20), now: now,
                                                          additional: at(tue, 9, 40)) == at(tue, 9, 40))
        // Never sooner than 15 minutes from now.
        #expect(BackgroundRefreshPolicy.earliestBeginDate(nextReplanDate: at(tue, 20), now: now,
                                                          additional: at(tue, 9, 5)) == at(tue, 9, 15))
    }
}

// MARK: - QA fixes (B1, M1–M3, m2–m5, m7)

private let thu = day(2026, 10, 15)
private let secondExamID = UUID(uuidString: "E8A30000-0000-4000-8000-000000000002")!

private func pendingLesson(_ date: LocalDate, _ lessons: LiveActivityLessonDay? = nil, id: String = "P") -> LessonActivityExisting {
    LessonActivityExisting(id: id, attributes: .init(day: date), status: .pending,
                           content: LiveActivityPlanner.scheduledLessonContent(lessons ?? lessonDay(date), style))
}

private func examActivity(_ exam: LiveActivityExam, id: String = "E", status: LiveActivityStatus,
                          now: Date) -> ExamActivityExisting {
    let content = status == .pending ? LiveActivityPlanner.scheduledExamContent(exam, style)
        : LiveActivityPlanner.runningExamContent(exam, style, now: now)
    return ExamActivityExisting(id: id, attributes: .init(examID: exam.id), status: status, content: content)
}

@Suite("Live Activity planner — QA fixes")
struct LiveActivityPlannerQAFixTests {
    // B1
    @Test func switchingStartAutomaticallyOffCancelsEveryPendingActivity() {
        let examWed = exam(wed, 10)
        let plan = planner.plan(input(sources(exams: [examWed]), now: at(tue, 19),
                                      ledger: .init(lessonDays: [wed], exams: [.init(id: examID, day: wed)]),
                                      lessons: [pendingLesson(wed)],
                                      exams: [examActivity(examWed, status: .pending, now: at(tue, 19))]))
        #expect(plan.lessonSteps == [.end(id: "P", nil, .immediate)])
        #expect(plan.examSteps == [.end(id: "E", nil, .immediate)])
        #expect(!plan.ledger.hasLesson(wed) && !plan.ledger.hasExam(examID, day: wed))
        #expect(plan.ledgerChanges.contains(.forgetLesson(wed)) && plan.ledgerChanges.contains(.forgetExam(examID)))
        #expect(!plan.keepsActivity)
        // Also in the background (cancelling needs no foreground).
        let background = planner.plan(input(sources(), now: at(tue, 19), canStart: false, ledger: .init(lessonDays: [wed]),
                                            lessons: [pendingLesson(wed)]))
        #expect(background.lessonSteps == [.end(id: "P", nil, .immediate)])
    }

    @Test func aCancelledPendingTodayStartsDirectlyWhenItsWindowIsOpen() {
        let plan = planner.plan(input(sources(), now: at(tue, 7, 50), ledger: .init(lessonDays: [tue]),
                                      lessons: [pendingLesson(tue)]))
        #expect(plan.lessonSteps.count == 2)
        #expect(plan.lessonSteps.first == .end(id: "P", nil, .immediate))
        if case .start(let attributes, _)? = plan.lessonSteps.last { #expect(attributes.day == tue) } else {
            Issue.record("expected a start, got \(plan.lessonSteps)")
        }
        #expect(plan.ledger.hasLesson(tue))
    }

    // M1
    @Test func aMovedExamStartsOnItsNewDay() {
        let moved = exam(wed, 10)
        // Swiped away on Tuesday, then moved to Wednesday: starts on Wednesday.
        let plan = planner.plan(input(sources(exams: [moved]), now: at(wed, 8), ledger: .init(exams: [.init(id: examID, day: tue)])))
        guard case .start(let attributes, _)? = plan.examSteps.first else {
            Issue.record("expected a start, got \(plan.examSteps)")
            return
        }
        #expect(attributes.examID == examID && plan.ledger.hasExam(examID, day: wed))
        // Swiped away on Wednesday itself: not again that day.
        let swiped = planner.plan(input(sources(exams: [moved]), now: at(wed, 8), ledger: .init(exams: [.init(id: examID, day: wed)])))
        #expect(swiped.examSteps.isEmpty)
        // Running on Tuesday while it is moved to Thursday: ended and forgotten, so Thursday can start it.
        let running = examActivity(exam(tue, 10), status: .active, now: at(tue, 8))
        let away = planner.plan(input(sources(exams: [exam(thu, 10)]), now: at(tue, 8, 30),
                                      ledger: .init(exams: [.init(id: examID, day: tue)]), exams: [running]))
        #expect(away.examSteps == [.end(id: "E", nil, .immediate)])
        #expect(away.ledger.exams.isEmpty)
    }

    // M2
    @Test func aChangedPendingActivityIsKeptInTheBackground() {
        var moved = lessonDay(wed)
        moved.lessons[0].start = at(wed, 7, 30)
        let lesson = planner.plan(input(sources(days: [lessonDay(tue), moved]), now: at(tue, 19), canStart: false,
                                        preferences: auto, ledger: .init(lessonDays: [wed]), lessons: [pendingLesson(wed)]))
        #expect(lesson.lessonSteps.isEmpty && lesson.ledger.hasLesson(wed) && lesson.keepsActivity)
        // Today's changed pending activity too.
        var today = lessonDay(tue)
        today.lessons[0].start = at(tue, 7, 40)
        let todayPlan = planner.plan(input(sources(days: [today]), now: at(tue, 6), canStart: false, preferences: auto,
                                           ledger: .init(lessonDays: [tue]), lessons: [pendingLesson(tue)]))
        #expect(todayPlan.lessonSteps.isEmpty && todayPlan.ledger.hasLesson(tue))
        // A pending exam whose room changed: kept in the background, replaced in the foreground.
        var edited = exam(wed, 10)
        edited.room = "B2"
        let pending = examActivity(exam(wed, 10), status: .pending, now: at(tue, 19))
        let background = planner.plan(input(sources(days: [], exams: [edited]), now: at(tue, 19), canStart: false,
                                            preferences: auto, ledger: .init(exams: [.init(id: examID, day: wed)]),
                                            exams: [pending]))
        #expect(background.examSteps.isEmpty && background.ledger.hasExam(examID, day: wed))
        let foreground = planner.plan(input(sources(days: [], exams: [edited]), now: at(tue, 19), preferences: auto,
                                            ledger: .init(exams: [.init(id: examID, day: wed)]), exams: [pending]))
        #expect(foreground.examSteps.count == 2 && foreground.examSteps.first == .end(id: "E", nil, .immediate))
        #expect(foreground.ledger.hasExam(examID, day: wed))
    }

    // m2
    @Test func theSecondExamOfADayStartsWhenTheFirstWasSwipedAway() {
        let first = exam(tue, 8, end: (9, 30))
        let second = exam(tue, 13, end: (14, 30), id: secondExamID)
        let src = sources(days: [], exams: [first, second])
        let swiped = LiveActivityLedger(exams: [.init(id: examID, day: tue)])
        #expect(planner.plan(input(src, now: at(tue, 6, 30), ledger: swiped)).examSteps.isEmpty)   // second not open yet
        let plan = planner.plan(input(src, now: at(tue, 7, 30), ledger: swiped))
        guard case .start(let attributes, _)? = plan.examSteps.first else {
            Issue.record("expected the second exam to start, got \(plan.examSteps)")
            return
        }
        #expect(attributes.examID == secondExamID)
        // One exam activity at a time: while the first runs, the second waits; it starts once the first ended.
        let firstRunning = examActivity(first, status: .active, now: at(tue, 7))
        let during = planner.plan(input(src, now: at(tue, 7, 30), ledger: .init(exams: [.init(id: examID, day: tue)]),
                                        exams: [firstRunning]))
        #expect(during.examSteps.allSatisfy { if case .start = $0 { false } else { true } })
        let after = planner.plan(input(src, now: at(tue, 9, 31), ledger: .init(exams: [.init(id: examID, day: tue)]),
                                       exams: [firstRunning]))
        #expect(after.examSteps.count == 2)
        if case .start(let next, _)? = after.examSteps.last { #expect(next.examID == secondExamID) } else {
            Issue.record("expected the second exam to start after the first, got \(after.examSteps)")
        }
        // The first one ended by the planner (not swiped) is forgotten; the second is recorded.
        #expect(after.ledger.hasExam(secondExamID, day: tue) && !after.ledger.hasExam(examID, day: tue))
    }

    // m3
    @Test func anEarlierExamAddedLaterReplacesThePendingOne() {
        let later = exam(thu, 10, id: secondExamID)
        let earlier = exam(wed, 10)
        let pending = examActivity(later, id: "X", status: .pending, now: at(tue, 20))
        let plan = planner.plan(input(sources(days: [], exams: [earlier, later]), now: at(tue, 20), preferences: auto,
                                      ledger: .init(exams: [.init(id: secondExamID, day: thu)]), exams: [pending]))
        #expect(plan.examSteps.first == .end(id: "X", nil, .immediate))
        guard case let .schedule(attributes, _, date, _)? = plan.examSteps.last else {
            Issue.record("expected a schedule, got \(plan.examSteps)")
            return
        }
        #expect(attributes.examID == examID && date == at(wed, 6))
        #expect(plan.ledger.hasExam(examID, day: wed) && !plan.ledger.hasExam(secondExamID, day: thu))
        // Without a new earlier exam the pending one is kept.
        let kept = planner.plan(input(sources(days: [], exams: [later]), now: at(tue, 20), preferences: auto,
                                      ledger: .init(exams: [.init(id: secondExamID, day: thu)]), exams: [pending]))
        #expect(kept.examSteps.isEmpty)
    }

    // m4
    @Test func aLongExamWindowIsCappedAtEightHours() {
        let long = exam(wed, 10, end: (17, 0))
        #expect(LiveActivityPlanner.window(long, context) == at(wed, 9)..<at(wed, 17))
        #expect(LiveActivityPlanner.window(exam(wed, 10), context).lowerBound == at(wed, 4))   // short exam: 6 h lead
    }

    // m5 + a system-ended activity
    @Test func onlyDismissedOrSystemEndedActivitiesBlockARestart() {
        // Today cleared by a data change (holiday), then restored: the planner's own end forgot the day.
        let active = running(tue, now: at(tue, 9))
        let cleared = planner.plan(input(sources(days: [lessonDay(wed)]), now: at(tue, 9), ledger: .init(lessonDays: [tue]),
                                         lessons: [active]))
        #expect(cleared.lessonSteps == [.end(id: "L1", nil, .immediate)] && !cleared.ledger.hasLesson(tue))
        let restored = planner.plan(input(sources(), now: at(tue, 9, 5), ledger: cleared.ledger))
        if case .start? = restored.lessonSteps.first {} else { Issue.record("expected a restart, got \(restored.lessonSteps)") }
        // Ended by the system after 8 h (or swiped away): still in Activity.activities as ended / dismissed, recorded →
        // not restarted that day (RISKS #75).
        for status in [LiveActivityStatus.ended, .dismissed] {
            let ended = running(tue, now: at(tue, 9), status: status)
            let plan = planner.plan(input(sources(), now: at(tue, 10), ledger: .init(lessonDays: [tue]), lessons: [ended]))
            #expect(plan.lessonSteps.isEmpty, "\(status)")
        }
        // A duplicate end keeps the key (the kept activity still covers the day).
        let a = running(tue, now: at(tue, 9), id: "A")
        let b = running(tue, now: at(tue, 9), id: "B")
        let dup = planner.plan(input(sources(), now: at(tue, 9), ledger: .init(lessonDays: [tue]), lessons: [a, b]))
        #expect(dup.ledger.hasLesson(tue) && dup.keepsActivity)
    }

    @Test func switchingAnActivityOffEndsItAndForgetsItsDay() {
        let plan = planner.plan(input(sources(), now: at(tue, 9), preferences: .init(lessonEnabled: false),
                                      ledger: .init(lessonDays: [tue]), lessons: [running(tue, now: at(tue, 9))]))
        #expect(plan.ledgerChanges == [.forgetLesson(tue)] && !plan.keepsActivity)
    }

    // DST (Europe/Bratislava, CEST → CET on Sun 2026-10-25 at 03:00)
    @Test func dstChangeKeepsWallClockWindowsAndBoundaries() {
        let sunday = day(2026, 10, 25)
        let src = sources(days: [lessonDay(sunday)])
        #expect(at(sunday, 8).timeIntervalSince(at(day(2026, 10, 24), 8)) == 25 * 3600)
        #expect(planner.plan(input(src, now: at(sunday, 7, 44))).lessonSteps.isEmpty)
        let plan = planner.plan(input(src, now: at(sunday, 7, 45)))
        guard case .start(_, let content)? = plan.lessonSteps.first else {
            Issue.record("expected a start")
            return
        }
        #expect(content.staleDate == at(sunday, 8))
        let shown = presenter.lesson(content.state, now: at(sunday, 8, 10))
        #expect(shown.timer == at(sunday, 8)...at(sunday, 8, 45))
    }

    @Test func sourcesUseWallClockTimesAcrossDSTAndAfterAZoneChange() throws {
        let scenario = SampleScenarios.secondary()
        let locale = Locale(identifier: "en_GB")
        let friday = at(day(2026, 10, 23), 9)
        let src = LiveActivitySourceBuilder.make(database: scenario.database, now: friday, context: context, locale: locale,
                                                 languageCode: "en")
        let snapshot = WidgetSnapshotBuilder.make(database: scenario.database, now: friday, context: context, tier: .pro,
                                                  locale: locale, languageCode: "en")
        #expect(src.lessonDays.contains { $0.day > day(2026, 10, 25) }, "no lesson day after the DST change")
        for lessonDay in src.lessonDays {
            let widgetDay = try #require(snapshot.day(lessonDay.day))
            let wallClock = WidgetTimelinePlanner.active(widgetDay, context).map(\.startTime)
            #expect(lessonDay.lessons.map { context.local(from: $0.start).time } == Array(wallClock.prefix(lessonDay.lessons.count)))
            #expect(lessonDay.lessons.allSatisfy { context.localDate(of: $0.start) == lessonDay.day })
        }
        // After moving to New York ("follow device" timetable): the same wall-clock times, in the new zone.
        let newYork = CalendarContext(timeZone: TimeZone(identifier: "America/New_York")!, firstWeekday: .monday)
        let nyNow = newYork.date(day(2026, 10, 23), LocalTime(hour: 7, minute: 0)!)
        let ny = LiveActivitySourceBuilder.make(database: scenario.database, now: nyNow, context: newYork, locale: locale,
                                                languageCode: "en")
        #expect(ny.style.timeZoneID == "America/New_York")
        let nyFirst = try #require(ny.lessonDays.first)
        let homeFirst = try #require(src.lessonDays.first { $0.day == nyFirst.day })
        #expect(newYork.local(from: nyFirst.lessons[0].start).time == context.local(from: homeFirst.lessons[0].start).time)
        #expect(nyFirst.lessons[0].start != homeFirst.lessons[0].start)
    }
}

@Suite("Live Activity ledger — QA fixes")
struct LiveActivityLedgerQAFixTests {
    @Test func preferenceTogglesAndTheSystemSwitchClearTheLedger() {
        var ledger = LiveActivityLedger(lessonDays: [tue.adding(days: -1), tue, wed], exams: [.init(id: examID, day: tue)])
        let off = LiveActivityPreferences(lessonEnabled: false, examEnabled: false)
        let on = LiveActivityPreferences()
        ledger.applyPreferenceChange(from: on, to: off, today: tue)   // switching off changes nothing here
        #expect(ledger.lessonDays.count == 3 && ledger.exams.count == 1)
        ledger.applyPreferenceChange(from: off, to: LiveActivityPreferences(lessonEnabled: true, examEnabled: false), today: tue)
        #expect(ledger.lessonDays == [tue.adding(days: -1)] && ledger.exams.count == 1)
        ledger.applyPreferenceChange(from: LiveActivityPreferences(examEnabled: false), to: on, today: tue)
        #expect(ledger.exams.isEmpty)
        var system = LiveActivityLedger(lessonDays: [tue], exams: [.init(id: examID, day: tue)])
        system.systemReenabled(today: tue)
        #expect(system.lessonDays.isEmpty && system.exams.isEmpty)
    }

    @Test func runChangesApplyOnTopOfConcurrentWrites() {
        // M3: the run planned with an old ledger; meanwhile Settings cleared today. Applying only the run's changes
        // keeps that write (a stale full save would bring `tue` back).
        let plan = planner.plan(input(sources(), now: at(tue, 19), preferences: auto, ledger: .init(lessonDays: [tue])))
        #expect(plan.ledgerChanges == [.recordLesson(wed)])
        var current = LiveActivityLedger()   // what Settings left in the store during the run
        current.apply(plan.ledgerChanges)
        #expect(current.lessonDays == [wed])
    }

    @Test func ledgerDecodesTheOldFormatWithoutExams() throws {
        let data = Data(#"{"days":["2026-10-13"],"exams":["E8A30000-0000-4000-8000-000000000001"]}"#.utf8)
        let ledger = try JSONDecoder().decode(LiveActivityLedger.self, from: data)
        #expect(ledger.lessonDays == [tue] && ledger.exams.isEmpty)
        let round = try JSONDecoder().decode(LiveActivityLedger.self, from: JSONEncoder().encode(
            LiveActivityLedger(lessonDays: [tue], exams: [.init(id: examID, day: wed)])))
        #expect(round.hasExam(examID, day: wed))
    }

    @Test func keepsActivityIsKnownBeforeTheSteps() {
        #expect(planner.plan(input(sources(), now: at(tue, 9))).keepsActivity)          // a start
        #expect(!planner.plan(input(sources(), now: at(tue, 6))).keepsActivity)         // nothing yet
        #expect(planner.plan(input(sources(), now: at(tue, 9), canStart: false,
                                   lessons: [running(tue, now: at(tue, 9))])).keepsActivity)
    }
}
