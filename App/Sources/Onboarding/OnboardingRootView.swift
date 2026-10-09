// PLACEHOLDER (Stage A) — stage B1 replaces this file with the real onboarding flow.
// Keep the type name `OnboardingRootView` and its no-argument init: the app shell shows it whenever no database exists
// or `settings.onboardingCompletedAt == nil`. Finish onboarding with
//     model.apply(.replaceDatabase(label: "onboarding") { ids, clock, now in
//         OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: now) })
// The shell switches to the tabs automatically once the database has a completed onboarding.
// This placeholder offers one button that creates a secondary-school timetable with preset defaults, so the
// foundation (first launch → onboarding → tabs → relaunch persistence) can be tested before B1 lands.
// APIs: ContentUnavailableView(label:description:actions:), Button(action:label:), buttonStyle(.borderedProminent).
import SwiftUI
import TimetableCore
import TimetableUI

struct OnboardingRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label { Text("onboarding.placeholder.title") } icon: { Image(systemName: "graduationcap") }
        } description: {
            Text("onboarding.placeholder.message")
        } actions: {
            Button(action: start) {
                Text("onboarding.placeholder.start")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func start() {
        let renderer = model.renderer
        let answers = OnboardingAnswers(
            profile: .secondary,
            timetableName: renderer.string(forKey: "onboarding.default.timetableName"),
            bellScheduleName: renderer.string(forKey: "onboarding.default.bellScheduleName"),
            localeFirstWeekday: model.calendarContext.firstWeekday)
        model.apply(.replaceDatabase(label: "onboarding") { ids, clock, now in
            OnboardingBuilder.makeInitialDatabase(answers: answers, ids: &ids, clock: &clock, now: now)
        })
    }
}
