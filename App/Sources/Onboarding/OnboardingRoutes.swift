// Launch routes of onboarding. `.onboarding` placement shows the view even when onboarding was completed (screenshots
// with any seed). Each step route opens that step (with the back chevron of the real navigation path) and sensible
// answers pre-filled; none preselects "Just look around" (F10).
// Phase 4U U6: the 4-step flow (school type → start → week → times) plus the sample-data banner over Today.
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI
import TimetableUI

enum OnboardingRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            // Step 1 as on first launch: nothing selected.
            AppRoute("onboarding", .onboarding) { OnboardingRootView() },
            AppRoute("onboarding.school-type", .onboarding) {
                OnboardingRootView(step: .schoolType) { $0.select(.secondary) }
            },
            AppRoute("onboarding.start", .onboarding) {
                OnboardingRootView(step: .start) { $0.select(.secondary) }
            },
            // Step 3 with the alternating-weeks anchor and term dates visible.
            AppRoute("onboarding.week", .onboarding) {
                OnboardingRootView(step: .week) {
                    $0.select(.secondary)
                    $0.rotation = .alternatingWeeks
                    $0.followsCalendarParity = true
                    $0.termEnabled = true
                }
            },
            AppRoute("onboarding.week-days", .onboarding) {
                OnboardingRootView(step: .week) {
                    $0.select(.elementary)
                    $0.rotation = .alternatingDays
                }
            },
            AppRoute("onboarding.times", .onboarding) {
                OnboardingRootView(step: .times) { $0.select(.secondary) }
            },
            AppRoute("onboarding.times-individual", .onboarding) {
                OnboardingRootView(step: .times) { $0.select(.university) }
            },
            // The "This is sample data · Remove" banner over Today (marks the seed's timetable as sample content).
            AppRoute("onboarding.sample-banner", .tabRoot(.today)) {
                SampleBannerRoute()
            },
        ]
    }
}

/// Today with the seed's active timetable marked as sample content (in-memory store in seed runs).
private struct SampleBannerRoute: View {
    @Environment(AppModel.self) private var model
    @Environment(SampleContentController.self) private var samples

    var body: some View {
        TodayRootView()
            .task {
                #if DEBUG
                samples.markActiveTimetableAsSample(in: model)
                #endif
            }
    }
}
