import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let today = LocalDate(year: 2026, month: 10, day: 13)! // Tuesday, ISO week 42 (even)
private let names = OnboardingNames(timetable: "School", bellSchedule: "Bells", term: "Semester")
private let reference = Date(timeIntervalSince1970: 1_791_879_600)

private func build(_ draft: OnboardingDraft, firstWeekday: Weekday = .monday) -> TabulaDatabase {
    var ids = SequentialIDGenerator(namespace: 0xB1)
    var clock = HybridLogicalClock(node: 0xB1)
    return draft.makeDatabase(names: names, localeFirstWeekday: firstWeekday,
                              localize: { $0.key }, ids: &ids, clock: &clock, now: reference)
}

@Suite("Onboarding steps (U6: 7 → 4)")
struct OnboardingStepTests {
    @Test func fourStepsInOrder() {
        #expect(OnboardingStep.count == 4)
        #expect(OnboardingStep.allCases == [.schoolType, .start, .week, .times])
        #expect(OnboardingStep.schoolType.previous == nil)
        #expect(OnboardingStep.times.next == nil)
        #expect(OnboardingStep.start.next == .week)
        #expect(OnboardingStep.allCases.map(\.index) == Array(0..<OnboardingStep.count))
    }

    @Test func navigationPathsPushEveryStepAfterTheRoot() {
        #expect(OnboardingStep.schoolType.path.isEmpty)
        #expect(OnboardingStep.start.path == [.start])
        #expect(OnboardingStep.times.path == [.start, .week, .times])
    }

    @Test func onlyRealStartChoicesExist() {
        // Import from photo / QR is hidden until it works (F09): no such choice exists.
        #expect(StartChoice.allCases == [.blank, .sample])
        #expect(OnboardingDraft(today: today).start == .blank)   // never the sample by default (F10)
    }
}

@Suite("OnboardingDraft presets and derived answers")
struct OnboardingDraftPresetTests {
    @Test func secondaryDefaults() {
        let draft = OnboardingDraft(today: today, profile: .secondary)
        #expect(draft.timeKind == .bellSchedule)
        #expect(draft.lessonMinutes == 45 && draft.lessonCount == 8 && draft.firstStartMinutes == 480)
        #expect(draft.availableRotations == RotationChoice.allCases)
        #expect(draft.enabledDays == Weekday.workweek)
        #expect(!draft.termEnabled)
    }

    @Test func elementaryHasTheShortRotationList() {
        let draft = OnboardingDraft(today: today, profile: .elementary)
        #expect(draft.availableRotations == [.none, .alternatingWeeks, .alternatingDays])
        #expect(draft.lessonCount == 6)
    }

    @Test func universityIsIndividualTimesWithTermOn() {
        let draft = OnboardingDraft(today: today, profile: .university)
        #expect(draft.timeKind == .freeForm)
        #expect(draft.freeFormMinutes == 90)
        #expect(draft.termEnabled)
        #expect(draft.preset.terminology == .classLecture)
    }

    /// F06/F12: no fields step; school types get room + teacher, university adds building and type.
    @Test func visibleFieldsAreDerivedFromTheProfile() {
        for profile in UserProfile.knownValues {
            let fields = OnboardingDraft(today: today, profile: profile).visibleFields
            #expect(fields.isSuperset(of: [.room, .teacher]), "\(profile.rawValue)")
            #expect(fields == ProfilePreset.for(profile).visibleFields)
        }
        let university = OnboardingDraft(today: today, profile: .university).visibleFields
        #expect(university.isSuperset(of: [.building, .lessonType]))
        #expect(!OnboardingDraft(today: today, profile: .secondary).visibleFields.contains(.building))
        let database = build(OnboardingDraft(today: today, profile: .other))
        #expect(database.timetables[0].fieldVisibility.visibleFields == [.room, .teacher])
    }

    @Test func otherStartsWithTheSecondaryBellFallback() {
        let draft = OnboardingDraft(today: today, profile: .other)
        #expect(draft.timeKind == .bellSchedule)
        #expect(draft.bellTemplate.count == BellScheduleTemplate.secondary.count)
    }

    @Test func reselectingKeepsEditsButChangingProfileResets() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.lessonCount = 4
        draft.set(.saturday, enabled: true)
        draft.select(.secondary)
        #expect(draft.lessonCount == 4 && draft.enabledDays.contains(.saturday))
        draft.select(.university)
        #expect(draft.timeKind == .freeForm)
        #expect(draft.enabledDays == Weekday.workweek)
    }

    @Test func schoolTypeIsRequiredFirst() {
        let draft = OnboardingDraft(today: today)
        #expect(draft.profile == nil)
        #expect(!draft.canAdvance(from: .schoolType))
        #expect(!draft.canFinish(from: .start))
        let chosen = OnboardingDraft(today: today, profile: .secondary)
        #expect(chosen.canAdvance(from: .schoolType) && chosen.canFinish(from: .start))
    }

    /// Reminders are not a step any more: every preset rule is created with its default switch, so homework and
    /// exams are on for every profile and nothing ever uses the alarm tier.
    @Test func reminderRulesKeepThePresetDefaults() {
        for profile in UserProfile.knownValues {
            let draft = OnboardingDraft(today: today, profile: profile)
            #expect(draft.answers(names: names, localeFirstWeekday: .monday).enabledReminderTargets == nil)
            let rules = build(draft).reminderRules
            let preset = ProfilePreset.for(profile).reminderRules
            #expect(rules.map(\.target) == preset.map(\.target), "\(profile.rawValue)")
            #expect(rules.map(\.isEnabled) == preset.map(\.isEnabled), "\(profile.rawValue)")
            #expect(rules.first { $0.target == .homework }?.isEnabled == true, "\(profile.rawValue)")
            #expect(rules.first { $0.target == .exam }?.isEnabled == true, "\(profile.rawValue)")
            #expect(rules.allSatisfy { $0.tier != .alarm })
        }
    }
}

@Suite("OnboardingDraft week: days, rotation anchor, terms")
struct OnboardingDraftWeekTests {
    @Test func weekdayChipsFollowTheWeekStart() {
        #expect(OnboardingDraft.orderedWeekdays(firstWeekday: .monday).first == .monday)
        #expect(OnboardingDraft.orderedWeekdays(firstWeekday: .sunday) ==
                [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    }

    @Test func schoolDaysReachTheTimetableAndAtLeastOneIsRequired() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.set(.friday, enabled: false)
        draft.set(.saturday, enabled: true)
        #expect(build(draft).timetables[0].enabledDays == [.monday, .tuesday, .wednesday, .thursday, .saturday])
        for day in Weekday.allCases { draft.set(day, enabled: false) }
        #expect(!draft.canAdvance(from: .week))
    }

    @Test func sameEveryWeekHasNoRotation() {
        let draft = OnboardingDraft(today: today, profile: .secondary)
        #expect(draft.rotationScheme(firstWeekday: .monday) == .none)
    }

    @Test func alternatingWeeksAnchorOnThisWeek() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.rotation = .alternatingWeeks
        #expect(draft.rotationScheme(firstWeekday: .monday)
                == .weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: today, cycleWeek: 1))))
        draft.currentCycleWeek = 2
        let scheme = draft.rotationScheme(firstWeekday: .monday)
        #expect(scheme == .weekCycle(WeekCycle(length: 2, anchor: .referenceWeek(date: today, cycleWeek: 2))))
        // The resolver agrees: this week is B, next week A.
        let resolver = RotationResolver(scheme: scheme, firstWeekday: .monday)
        #expect(resolver.cycleWeek(on: today) == 2)
        #expect(resolver.cycleWeek(on: today.adding(days: 7)) == 1)
    }

    /// F07: calendar odd/even weeks are an explicit option; this week keeps the chosen letter.
    @Test func calendarParityGetsTheOffsetThatMakesThisWeekTheChosenOne() {
        var draft = OnboardingDraft(today: today, profile: .secondary)   // ISO week 42: even
        draft.rotation = .alternatingWeeks
        draft.followsCalendarParity = true
        #expect(draft.currentISOWeek(firstWeekday: .monday).week == 42)
        for chosen in 1...2 {
            draft.currentCycleWeek = chosen
            let scheme = draft.rotationScheme(firstWeekday: .monday)
            guard case .weekCycle(let cycle) = scheme, case .isoWeekParity(let policy, _) = cycle.anchor else {
                Issue.record("expected an ISO-parity week cycle"); return
            }
            #expect(policy == .strict && cycle.length == 2)
            let resolver = RotationResolver(scheme: scheme, firstWeekday: .monday)
            #expect(resolver.cycleWeek(on: today) == chosen)
            #expect(resolver.cycleWeek(on: today.adding(days: 7)) == 3 - chosen)
        }
        draft.currentCycleWeek = 1
        #expect(!draft.weekAIsOdd(firstWeekday: .monday))   // week 42 is A → A is even
        draft.currentCycleWeek = 2
        #expect(draft.weekAIsOdd(firstWeekday: .monday))
        // The plain odd = A mapping has offset 0.
        #expect(draft.rotationScheme(firstWeekday: .monday)
                == .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 0))))
    }

    @Test func customCycleUsesTheChosenLengthAndWeek() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.rotation = .customCycle
        #expect(draft.cycleWeekCount == 3)
        draft.customCycleLength = 4
        draft.currentCycleWeek = 3
        #expect(draft.rotationScheme(firstWeekday: .monday)
                == .weekCycle(WeekCycle(length: 4, anchor: .referenceWeek(date: today, cycleWeek: 3))))
        draft.customCycleLength = 99   // clamped
        guard case .weekCycle(let clamped) = draft.rotationScheme(firstWeekday: .monday) else {
            Issue.record("expected weekCycle"); return
        }
        #expect(clamped.length == 6)
        draft.customCycleLength = 3    // a shorter cycle keeps the chosen week in range
        draft.currentCycleWeek = 5
        #expect(draft.effectiveCycleWeek == 3)
        // Switching back to alternating weeks never keeps an impossible week.
        draft.rotation = .alternatingWeeks
        #expect(draft.effectiveCycleWeek == 2)
    }

    @Test func alternatingDaysAnchorOnTheNextSchoolDayWithTheChosenDay() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.rotation = .alternatingDays
        draft.currentCycleDay = 2
        guard case .dayCycle(let days) = draft.rotationScheme(firstWeekday: .monday) else {
            Issue.record("expected dayCycle"); return
        }
        #expect(days.length == 2 && days.anchorDate == today && days.anchorIndex == 2)
        #expect(days.schoolDays == Weekday.workweek && days.skipsBreaks)

        let saturday = LocalDate(year: 2026, month: 10, day: 17)!
        var weekend = OnboardingDraft(today: saturday, profile: .secondary)
        weekend.rotation = .alternatingDays
        weekend.set(.monday, enabled: false)   // school days are the chosen chips
        #expect(weekend.dayCycleAnchorDate.weekday == .tuesday)
        guard case .dayCycle(let cycle) = weekend.rotationScheme(firstWeekday: .monday) else {
            Issue.record("expected dayCycle"); return
        }
        #expect(cycle.anchorDate.weekday == .tuesday && !cycle.schoolDays.contains(.monday))
    }

    /// Term dates are independent of the pattern: they combine with alternating weeks (F07 acceptance).
    @Test func termDatesCombineWithAnyPattern() {
        var draft = OnboardingDraft(today: today, profile: .university)
        draft.rotation = .alternatingWeeks
        draft.termStart = LocalDate(year: 2026, month: 9, day: 21)!
        draft.termEnd = LocalDate(year: 2027, month: 1, day: 31)!
        let database = build(draft)
        #expect(database.terms.count == 1)
        #expect(database.terms[0].name == "Semester")
        #expect(database.terms[0].range == LocalDateRange(start: draft.termStart, end: draft.termEnd))
        guard case .weekCycle = database.timetables[0].rotation else { Issue.record("expected weekCycle"); return }
    }

    @Test func termValidation() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        #expect(draft.termIssue == nil)
        draft.termEnabled = true
        #expect(draft.termIssue == nil)
        draft.termEnd = today.adding(days: -1)
        #expect(draft.termIssue == .endBeforeStart)
        #expect(!draft.canAdvance(from: .week))
        draft.termEnd = today
        #expect(draft.termIssue == nil) // a single-day term is valid
        draft.termEnd = today.adding(days: OnboardingDraft.maxTermDays)
        #expect(draft.termIssue == .tooLong)
        draft.termEnabled = false // skipping the term clears the problem
        #expect(draft.termIssue == nil && draft.canAdvance(from: .week))
    }

    @Test func invalidTermIsDroppedFromAnswers() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.termEnabled = true
        draft.termEnd = today.adding(days: -5)
        #expect(draft.answers(names: names, localeFirstWeekday: .monday).term == nil)
    }
}

@Suite("OnboardingDraft lesson times")
struct OnboardingDraftTimeTests {
    @Test func bellPreviewMatchesTemplate() {
        let draft = OnboardingDraft(today: today, profile: .secondary)
        let times = draft.bellPreview
        #expect(times.count == 8)
        #expect(times[0].start == LocalTime(hour: 8, minute: 0))
        #expect(times[0].end == LocalTime(hour: 8, minute: 45))
        #expect(times[1].start == LocalTime(hour: 8, minute: 55)) // 10 min break
        #expect(times[2].start == LocalTime(hour: 10, minute: 0)) // 20 min break after the 2nd
    }

    @Test func editingChangesThePreview() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.firstStartMinutes = 7 * 60 + 30
        draft.lessonMinutes = 50
        draft.lessonCount = 5
        draft.shortBreakMinutes = 5
        let times = draft.bellPreview
        #expect(times.count == 5)
        #expect(times[0].start == LocalTime(hour: 7, minute: 30))
        #expect(times[1].start == LocalTime(hour: 8, minute: 25))
    }

    @Test func lateStartTruncatesButStaysValid() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.firstStartMinutes = 22 * 60
        draft.lessonCount = 14
        #expect(draft.bellPreview.count < 14)
        #expect(draft.canAdvance(from: .times))
        draft.firstStartMinutes = 23 * 60 + 59
        #expect(!draft.canAdvance(from: .times)) // not even one lesson fits
        #expect(!draft.canFinish(from: .times))
    }

    @Test func individualTimes() {
        var draft = OnboardingDraft(today: today, profile: .university)
        #expect(draft.timeStructure == .freeForm(defaultDurationMinutes: 90))
        draft.freeFormMinutes = 0
        #expect(!draft.canAdvance(from: .times))
    }

    /// "I'll do this later" restores the profile's suggestion (always valid).
    @Test func suggestedTimesRestoreThePreset() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.firstStartMinutes = 23 * 60 + 59
        draft.timeKind = .freeForm
        draft.freeFormMinutes = 0
        draft.applyPresetTimes()
        #expect(draft.timeKind == .bellSchedule && draft.firstStartMinutes == 480 && draft.lessonCount == 8)
        #expect(draft.canFinish(from: .times))
    }
}

@Suite("OnboardingDraft output")
struct OnboardingDraftOutputTests {
    @Test func everyProfileAndPatternBuildsAValidDatabase() {
        for profile in UserProfile.knownValues {
            for rotation in RotationChoice.allCases {
                var draft = OnboardingDraft(today: today, profile: profile)
                draft.rotation = rotation
                draft.followsCalendarParity = rotation == .alternatingWeeks
                for start in StartChoice.allCases {
                    draft.start = start
                    let database = build(draft)
                    #expect(database.validate().filter { $0.severity == .error }.isEmpty,
                            "\(profile.rawValue) \(rotation) \(start)")
                    #expect(database.settings.onboardingCompletedAt != nil)
                    #expect(database.timetables.count == 1)
                }
            }
        }
    }

    @Test func timeAnswersReachTheTimetable() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.lessonCount = 5
        let database = build(draft)
        #expect(database.bellSchedules.first?.lessonPeriods.count == 5)
    }

    @Test func rotationWeekStartIsTheLocaleWeekStart() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.rotation = .alternatingWeeks
        #expect(build(draft, firstWeekday: .sunday).timetables[0].rotationWeekStart == .sunday)
    }

    @Test func blankStartHasNoContentAndSampleStartDoes() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.start = .blank
        #expect(build(draft).lessons.isEmpty)
        draft.start = .sample
        let sample = build(draft)
        #expect(!sample.lessons.isEmpty && !sample.subjects.isEmpty)
        #expect(sample.validate().filter { $0.severity == .error }.isEmpty)
    }

    @Test func buildingIsDeterministic() {
        var draft = OnboardingDraft(today: today, profile: .elementary)
        draft.start = .sample
        #expect(build(draft) == build(draft))
    }
}
