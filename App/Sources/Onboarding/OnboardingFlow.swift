// View model of the onboarding flow: the current step plus the pure `OnboardingDraft` (TimetableUI, Linux-tested).
// All decisions (validation, presets, what gets written) live in TimetableUI; this class only holds state and
// hands the finished draft to `AppModel.apply`.
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
    private(set) var step: OnboardingStep
    /// Set when `AppModel.apply` refused the result (alert).
    var failureShown = false

    init(today: LocalDate, step: OnboardingStep, prefill: OnboardingPrefill) {
        var draft = OnboardingDraft(today: today)
        prefill(&draft)
        self.draft = draft
        self.step = step
    }

    var canAdvance: Bool { draft.canAdvance(from: step) }
    var isLastStep: Bool { step.next == nil }

    func advance() {
        guard canAdvance, let next = step.next else { return }
        step = next
    }

    func back() {
        if let previous = step.previous { step = previous }
    }

    /// Writes the result: replaces an empty database, otherwise adds to the existing one (never loses data).
    func finish(model: AppModel) {
        let renderer = model.renderer
        let names = OnboardingNames(
            timetable: renderer.string(forKey: "onboarding.default.timetableName"),
            bellSchedule: renderer.string(forKey: "onboarding.default.bellScheduleName"),
            term: renderer.string(forKey: "onboarding.default.termName"))
        let mutation = draft.finishMutation(
            existing: model.database, names: names, localeFirstWeekday: model.calendarContext.firstWeekday,
            localize: { renderer.string($0) }, now: model.now)
        // A user save: if the new rules already have something to deliver, the notification explainer is offered (Q1).
        if case .applied = model.apply(mutation, origin: .userSave) { return }
        failureShown = true
    }
}
