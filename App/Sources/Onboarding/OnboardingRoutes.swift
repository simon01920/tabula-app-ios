// Launch routes of onboarding (owned by stage B1). `.onboarding` placement shows the view even when onboarding was
// completed (screenshots with any seed). Each step route opens that step with sensible answers pre-filled.
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI
import TimetableUI

enum OnboardingRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("onboarding", .onboarding) { OnboardingRootView() },
            AppRoute("onboarding.profile", .onboarding) {
                OnboardingRootView(step: .profile) { $0.select(.secondary) }
            },
            AppRoute("onboarding.rotation", .onboarding) {
                OnboardingRootView(step: .rotation) {
                    $0.select(.secondary)
                    $0.choose(rotation: .oddEven)
                    $0.termEnabled = true
                }
            },
            AppRoute("onboarding.time", .onboarding) {
                OnboardingRootView(step: .time) { $0.select(.secondary) }
            },
            AppRoute("onboarding.fields", .onboarding) {
                OnboardingRootView(step: .fields) { $0.select(.secondary) }
            },
            AppRoute("onboarding.reminders", .onboarding) {
                OnboardingRootView(step: .reminders) { $0.select(.secondary) }
            },
            AppRoute("onboarding.start", .onboarding) {
                OnboardingRootView(step: .start) {
                    $0.select(.secondary)
                    $0.start = .sample
                }
            },
        ]
    }
}
