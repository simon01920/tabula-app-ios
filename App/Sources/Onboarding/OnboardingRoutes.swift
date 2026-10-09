// Launch routes of onboarding (owned by stage B1): `onboarding`, later one per step, e.g. `onboarding.profile`,
// `onboarding.rotation`, `onboarding.time-structure`, `onboarding.fields`, `onboarding.reminders`, `onboarding.start`.
// `.onboarding` placement shows the view even when onboarding was completed (screenshots with any seed).
// Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI

enum OnboardingRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("onboarding", .onboarding) { OnboardingRootView() },
        ]
    }
}
