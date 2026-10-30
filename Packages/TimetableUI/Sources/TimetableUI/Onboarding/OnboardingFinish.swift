// How onboarding writes its result without ever destroying data (QA finding): the shell shows onboarding whenever
// there is no live timetable, which also happens to existing users (they deleted their last timetable).
//   - no entities at all (first launch)  -> `.replaceDatabase`
//   - any entity, even only tombstones   -> ADD the new timetable and its children with upserts and update only the
//                                      settings fields onboarding owns; tasks, exams and other timetables stay.
// Entities are built by `OnboardingBuilder` into a scratch database with fresh IDs; the app's clock re-stamps them
// when the upserts are applied. Sample data uses the same fresh IDs, the app's clock, `now` and `today` (never
// the fixed `SampleScenarios`).
import Foundation
import TimetableCore

extension TabulaDatabase {
    /// `true` when the database holds no entity at all, not even tombstones (those must survive for sync).
    public var hasNoEntities: Bool {
        timetables.isEmpty && subjects.isEmpty && bellSchedules.isEmpty && lessons.isEmpty && terms.isEmpty
            && breaks.isEmpty && overrides.isEmpty && tasks.isEmpty && exams.isEmpty && reminderRules.isEmpty
    }
    // `hasLiveContent` moved to TimetableCore (Sync/CloudSync.swift, Phase 6 S1: the first-sync check needs it).
}

extension OnboardingDraft {
    /// The mutation that finishes onboarding on top of `existing` (`nil` = nothing stored yet).
    public func finishMutation(existing: TabulaDatabase?, names: OnboardingNames, localeFirstWeekday: Weekday,
                               localize: @escaping @Sendable (LocalizedText) -> String, now: Date) -> DatabaseMutation {
        let draft = self
        guard let existing, !existing.hasNoEntities else {
            return .replaceDatabase(label: "onboarding") { ids, clock, now in
                draft.makeDatabase(names: names, localeFirstWeekday: localeFirstWeekday, localize: localize,
                                   ids: &ids, clock: &clock, now: now)
            }
        }
        var ids = SystemIDGenerator()
        var scratchClock = HybridLogicalClock(node: 0x0B0A)
        let built = draft.makeDatabase(names: names, localeFirstWeekday: localeFirstWeekday, localize: localize,
                                       ids: &ids, clock: &scratchClock, now: now)
        var timetable = built.timetables[0]
        let append = TimetableManagement.appendIndex(in: existing)    // overflow-safe (renumbers on Int.max)
        timetable.sortIndex = append.sortIndex
        var steps: [DatabaseMutation] = append.steps + [.upsert(timetable)]
        steps += built.bellSchedules.map { .upsert($0) }
        steps += built.terms.map { .upsert($0) }
        steps += built.subjects.map { .upsert($0) }
        steps += built.lessons.map { .upsert($0) }
        steps += built.tasks.map { .upsert($0) }
        steps += built.exams.map { .upsert($0) }
        // Existing reminder rules are the user's; only a database without rules gets the presets.
        if !existing.reminderRules.contains(where: { !$0.isDeleted }) {
            steps += built.reminderRules.map { .upsert($0) }
        }
        let profile = built.settings.profile
        let timetableID = timetable.id
        steps.append(.settings { settings in
            settings.profile = profile
            settings.onboardingCompletedAt = now
            settings.activeTimetableID = timetableID
        })
        return .batch(steps, label: "onboarding (add)")
    }
}
