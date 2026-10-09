import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

private let today = LocalDate(year: 2026, month: 10, day: 13)! // Tuesday
private let names = OnboardingNames(timetable: "School", bellSchedule: "Bells", term: "Semester")
private let reference = Date(timeIntervalSince1970: 1_791_879_600)

private func build(_ draft: OnboardingDraft) -> TabulaDatabase {
    var ids = SequentialIDGenerator(namespace: 0xB1)
    var clock = HybridLogicalClock(node: 0xB1)
    return draft.makeDatabase(names: names, localeFirstWeekday: .monday,
                              localize: { $0.key }, ids: &ids, clock: &clock, now: reference)
}

@Suite("OnboardingDraft presets")
struct OnboardingDraftPresetTests {
    @Test func secondaryDefaults() {
        let draft = OnboardingDraft(today: today, profile: .secondary)
        #expect(draft.timeKind == .bellSchedule)
        #expect(draft.visibleFields == [.room, .teacher, .notes])
        #expect(draft.lessonMinutes == 45 && draft.lessonCount == 8 && draft.firstStartMinutes == 480)
        #expect(draft.availableRotations == RotationChoice.allCases)
        #expect(!draft.termEnabled)
    }

    @Test func elementaryHasLightRotationPromptAndBringList() {
        let draft = OnboardingDraft(today: today, profile: .elementary)
        #expect(draft.availableRotations == [.none, .oddEven, .dayAB])
        #expect(draft.visibleFields == [.room, .teacher, .bringList])
        #expect(draft.lessonCount == 6)
        #expect(draft.reminderTargets.contains(.packTonight))
    }

    @Test func universityIsFreeFormWithTermOn() {
        let draft = OnboardingDraft(today: today, profile: .university)
        #expect(draft.timeKind == .freeForm)
        #expect(draft.freeFormMinutes == 90)
        #expect(draft.termEnabled)
        #expect(draft.visibleFields == [.building, .room, .teacher, .lessonType, .notes])
        #expect(draft.preset.terminology == .classLecture)
    }

    @Test func otherStartsWithAllFieldsOffAndSecondaryBellFallback() {
        let draft = OnboardingDraft(today: today, profile: .other)
        #expect(draft.visibleFields.isEmpty)
        #expect(draft.timeKind == .bellSchedule)
        #expect(draft.bellTemplate.count == BellScheduleTemplate.secondary.count)
    }

    @Test func reselectingKeepsEditsButChangingProfileResets() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.set(.building, visible: true)
        draft.select(.secondary)
        #expect(draft.visibleFields.contains(.building))
        draft.select(.university)
        #expect(!draft.visibleFields.contains(.bringList))
        #expect(draft.timeKind == .freeForm)
    }

    @Test func noProfileBlocksTheProfileStepOnly() {
        let draft = OnboardingDraft(today: today)
        #expect(draft.profile == nil)
        #expect(!draft.canAdvance(from: .profile))
        #expect(draft.canAdvance(from: .welcome))
        #expect(draft.canAdvance(from: .rotation))
    }
}

@Suite("OnboardingDraft rotation and terms")
struct OnboardingDraftRotationTests {
    @Test func rotationMapping() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        #expect(draft.rotationScheme == .none)

        draft.choose(rotation: .oddEven)
        guard case .weekCycle(let odd) = draft.rotationScheme else { Issue.record("expected weekCycle"); return }
        #expect(odd.length == 2)
        #expect(odd.anchor == .isoWeekParity(policy: .strict, offset: 0))

        draft.choose(rotation: .cycle)
        draft.cycleLength = 4
        guard case .weekCycle(let cycle) = draft.rotationScheme else { Issue.record("expected weekCycle"); return }
        #expect(cycle.length == 4)
        #expect(cycle.anchor == .referenceWeek(date: today, cycleWeek: 1))

        draft.cycleLength = 99
        guard case .weekCycle(let clamped) = draft.rotationScheme else { Issue.record("expected weekCycle"); return }
        #expect(clamped.length == 6)

        draft.choose(rotation: .dayAB)
        guard case .dayCycle(let days) = draft.rotationScheme else { Issue.record("expected dayCycle"); return }
        #expect(days.length == 2 && days.anchorDate == today && days.schoolDays == Weekday.workweek)
    }

    @Test func dayCycleAnchorSkipsWeekend() {
        let saturday = LocalDate(year: 2026, month: 10, day: 17)!
        var draft = OnboardingDraft(today: saturday, profile: .secondary)
        draft.choose(rotation: .dayAB)
        guard case .dayCycle(let days) = draft.rotationScheme else { Issue.record("expected dayCycle"); return }
        #expect(days.anchorDate.weekday == .monday)
    }

    @Test func cycleAnchorFollowsTermStart() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.choose(rotation: .cycle)
        draft.termEnabled = true
        draft.termStart = LocalDate(year: 2026, month: 9, day: 1)!
        draft.termEnd = LocalDate(year: 2027, month: 1, day: 31)!
        guard case .weekCycle(let cycle) = draft.rotationScheme else { Issue.record("expected weekCycle"); return }
        #expect(cycle.anchor == .referenceWeek(date: draft.termStart, cycleWeek: 1))
    }

    @Test func perSemesterTurnsTermOnWithoutRotation() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.choose(rotation: .perSemester)
        #expect(draft.termEnabled)
        #expect(draft.rotationScheme == .none)
    }

    @Test func termValidation() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        #expect(draft.termIssue == nil)
        draft.termEnabled = true
        #expect(draft.termIssue == nil)
        draft.termEnd = today.adding(days: -1)
        #expect(draft.termIssue == .endBeforeStart)
        #expect(!draft.canAdvance(from: .rotation))
        draft.termEnd = today
        #expect(draft.termIssue == nil) // a single-day term is valid
        draft.termEnd = today.adding(days: OnboardingDraft.maxTermDays)
        #expect(draft.termIssue == .tooLong)
        draft.termEnabled = false // skipping the term clears the problem
        #expect(draft.termIssue == nil && draft.canAdvance(from: .rotation))
    }

    @Test func invalidTermIsDroppedFromAnswers() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.termEnabled = true
        draft.termEnd = today.adding(days: -5)
        #expect(draft.answers(names: names, localeFirstWeekday: .monday).term == nil)
    }
}

@Suite("OnboardingDraft time structure")
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
        #expect(draft.canAdvance(from: .time))
        draft.firstStartMinutes = 23 * 60 + 59
        #expect(!draft.canAdvance(from: .time)) // not even one lesson fits
    }

    @Test func freeFormStructure() {
        var draft = OnboardingDraft(today: today, profile: .university)
        #expect(draft.timeStructure == .freeForm(defaultDurationMinutes: 90))
        draft.freeFormMinutes = 0
        #expect(!draft.canAdvance(from: .time))
    }
}

@Suite("OnboardingDraft output")
struct OnboardingDraftOutputTests {
    @Test func everyProfileBuildsAValidDatabase() {
        for profile in UserProfile.knownValues {
            var draft = OnboardingDraft(today: today, profile: profile)
            draft.choose(rotation: .dayAB)
            let database = build(draft)
            #expect(database.validate().filter { $0.severity == .error }.isEmpty, "profile \(profile.rawValue)")
            #expect(database.settings.onboardingCompletedAt != nil)
            #expect(database.timetables.count == 1)
        }
    }

    @Test func fieldAndTimeAnswersReachTheTimetable() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.set(.room, visible: false)
        draft.set(.bringList, visible: true)
        draft.lessonCount = 5
        let database = build(draft)
        let timetable = database.timetables[0]
        #expect(timetable.fieldVisibility.visibleFields == [.teacher, .notes, .bringList])
        #expect(database.bellSchedules.first?.lessonPeriods.count == 5)
    }

    @Test func termBecomesATerm() {
        var draft = OnboardingDraft(today: today, profile: .university)
        draft.termStart = LocalDate(year: 2026, month: 9, day: 21)!
        draft.termEnd = LocalDate(year: 2027, month: 1, day: 31)!
        let database = build(draft)
        #expect(database.terms.count == 1)
        #expect(database.terms[0].name == "Semester")
        #expect(database.terms[0].range == LocalDateRange(start: draft.termStart, end: draft.termEnd))
    }

    @Test func reminderTogglesDecideEnabledRules() {
        var draft = OnboardingDraft(today: today, profile: .secondary)
        draft.set(reminder: .exam, enabled: false)
        let database = build(draft)
        #expect(database.reminderRules.first { $0.target == .exam }?.isEnabled == false)
        #expect(database.reminderRules.first { $0.target == .homework }?.isEnabled == true)
        #expect(database.reminderRules.allSatisfy { $0.tier != .alarm })
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

@Suite("Onboarding steps")
struct OnboardingStepTests {
    @Test func navigation() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.start.next == nil)
        #expect(OnboardingStep.profile.next == .rotation)
        #expect(OnboardingStep.allCases.map(\.index) == Array(0..<OnboardingStep.count))
    }

    @Test func importChoicesAreNotSelectable() {
        #expect(StartChoice.allCases.filter(\.isAvailable) == [.blank, .sample])
    }
}
