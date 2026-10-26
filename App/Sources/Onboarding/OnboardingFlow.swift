// View model of the onboarding flow: the navigation path plus the pure `OnboardingDraft` (TimetableUI, Linux-tested).
// All decisions (validation, presets, what gets written, what counts as sample data) live in TimetableUI; this class
// only holds state and hands the finished draft to `AppModel.apply`.
// APIs: Observation.Observable (macro; allowed in app code, PHASE2_PLAN §0.1), @Bindable (iOS 17).
import Foundation
import Observation
import TimetableCore
import TimetableUI

/// Adjusts a fresh draft (screenshot routes pre-fill answers; the real flow passes nothing).
typealias OnboardingPrefill = @Sendable (inout OnboardingDraft) -> Void

@MainActor
@Observable
final class OnboardingFlow {
    var draft: OnboardingDraft
    /// The pushed steps (NavigationStack path); the school-type step is the root.
    var path: [OnboardingStep]
    /// Set when `AppModel.apply` refused the result (alert).
    var failureShown = false
    @ObservationIgnored private let localStore: any OnboardingLocalStore

    init(today: LocalDate, step: OnboardingStep, prefill: OnboardingPrefill, localStore: any OnboardingLocalStore) {
        var draft = OnboardingDraft(today: today)
        // The school type chosen before an app-language change (iOS relaunches the app; F13).
        if let pending = localStore.loadPendingProfile() { draft.select(pending) }
        prefill(&draft)
        self.draft = draft
        self.localStore = localStore
        path = step.path
    }

    /// Pushes the step after `step` when its answers are valid.
    func advance(from step: OnboardingStep) {
        guard draft.canAdvance(from: step), let next = step.next else { return }
        path = next.path
    }

    /// Remembers the school type before iOS Settings opens (a language change relaunches the app).
    func rememberProgressForLanguageChange() {
        localStore.savePendingProfile(draft.profile)
    }

    /// "I'll do this later": the suggested lesson times, then finish.
    func finishWithSuggestedTimes(model: AppModel, samples: SampleContentController) {
        draft.applyPresetTimes()
        finish(from: .times, model: model, samples: samples)
    }

    /// "Just look around": the profile's sample timetable, then finish (the banner offers to remove it).
    func lookAround(model: AppModel, samples: SampleContentController) {
        draft.start = .sample
        finish(from: .start, model: model, samples: samples)
    }

    /// Writes the result: replaces an empty database, otherwise adds to the existing one (never loses data;
    /// OnboardingFinish). Sample content is recorded device-locally for the "Remove" banner.
    func finish(from step: OnboardingStep, model: AppModel, samples: SampleContentController) {
        guard draft.canFinish(from: step) else { return }
        if step != .start { draft.start = .blank }
        let renderer = model.renderer
        let names = OnboardingNames(
            timetable: renderer.string(forKey: "onboarding.default.timetableName"),
            bellSchedule: renderer.string(forKey: "onboarding.default.bellScheduleName"),
            term: renderer.string(forKey: "onboarding.default.termName"))
        let mutation = draft.finishMutation(
            existing: model.database, names: names, localeFirstWeekday: model.calendarContext.firstWeekday,
            localize: { renderer.string($0) }, now: model.now)
        let isSample = draft.start == .sample
        // A user save offers the notification explainer when the new rules already have something to deliver (Q1).
        // The sample's homework is not the user's, so looking around never triggers it.
        guard case .applied = model.apply(mutation, origin: isSample ? .other : .userSave) else {
            failureShown = true
            return
        }
        localStore.savePendingProfile(nil)
        if isSample, let database = model.database, let id = database.settings.activeTimetableID {
            samples.remember(SampleContent.record(for: id, in: database))
        } else {
            samples.remember(nil)
        }
    }
}
