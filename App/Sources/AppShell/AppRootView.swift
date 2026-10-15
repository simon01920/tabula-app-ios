// The root of the window: loading → onboarding / main tabs / blocking problem, the store banner on top, the
// appearance preference from settings, and the launch route (`-TabulaScreen`).
// APIs: View.preferredColorScheme(_:), VStack, ProgressView, NavigationStack, View.sheet(isPresented:content:),
//       Environment(AppModel.self) (Observation), ContentUnavailableView (iOS 17).
import SwiftUI
import TimetableUI

struct AppRootView: View {
    let launchRoute: LaunchRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .preferredColorScheme(model.appearance.colorScheme)
    }

    @ViewBuilder
    private var content: some View {
        if let route = launchRoute.route, case .standalone = route.placement {
            NavigationStack { route.makeView() }
        } else {
            VStack(spacing: 0) {
                if let banner = model.banners.first {
                    StoreBannerView(banner: banner) { model.dismissBanner() }
                }
                phaseView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch model.phase {
        case .loading:
            ProgressView {
                Text("shell.loading")
            }
        case .blocked(let problem):
            StoreProblemView(problem: problem)
        case .onboarding:
            if let route = launchRoute.route, case .onboarding = route.placement {
                route.makeView()
            } else {
                OnboardingRootView()
            }
        case .main:
            if let route = launchRoute.route, case .onboarding = route.placement {
                route.makeView()
            } else {
                MainTabView(launchRoute: launchRoute.route)
            }
        }
    }
}

/// Today · Timetable · Tasks · Exams · Settings (standard `TabView`, so iOS 26 applies Liquid Glass to the tab bar).
/// The selected tab lives in `AppNavigation` so notification taps (deep links) can switch it; a deep link to a task or
/// exam also presents the feature's detail route (`tasks.detail` / `exams.detail`) as a sheet when registered.
/// Root sheets come from `rootPresenter()`, which waits for or closes the tab sheets first (never unsaved editors).
struct MainTabView: View {
    let launchRoute: AppRoute?
    @Environment(AppNavigation.self) private var navigation
    @State private var sheetDismissed = false

    private var initialTab: AppTab {
        switch launchRoute?.placement {
        case .tabRoot(let tab)?, .sheet(let tab)?: return tab
        default: return .today
        }
    }

    // `nil` in `navigation.selectedTab` = not changed by the user yet → the launch route's choice.
    private var selection: Binding<AppTab> {
        Binding(get: { navigation.selectedTab ?? initialTab }, set: { navigation.selectedTab = $0 })
    }

    private var isSheetPresented: Binding<Bool> {
        Binding(get: {
            if sheetDismissed { return false }
            if case .sheet(_)? = launchRoute?.placement { return true }
            return false
        }, set: { presented in
            if !presented { sheetDismissed = true }
        })
    }

    var body: some View {
        TabView(selection: selection) {
            Tab("shell.tab.today", systemImage: "sun.max", value: AppTab.today) {
                root(for: .today) { TodayRootView() }
            }
            Tab("shell.tab.timetable", systemImage: "calendar", value: AppTab.timetable) {
                root(for: .timetable) { TimetableRootView() }
            }
            Tab("shell.tab.tasks", systemImage: "checklist", value: AppTab.tasks) {
                if let request = navigation.taskSegmentRequest {
                    // Phase 3 C1: Today's overdue chip asked for a segment; a new request id rebuilds the tab on it.
                    TasksRootView(initialSegment: request.segment).id(request.id)
                } else {
                    root(for: .tasks) { TasksRootView() }
                }
            }
            Tab("shell.tab.exams", systemImage: "graduationcap", value: AppTab.exams) {
                root(for: .exams) { ExamsRootView() }
            }
            Tab("shell.tab.settings", systemImage: "gearshape", value: AppTab.settings) {
                root(for: .settings) { SettingsRootView() }
            }
        }
        .sheet(isPresented: isSheetPresented) {
            launchRoute?.makeView()
        }
        .closesForDeepLink { sheetDismissed = true }
        // Deep links and the in-context notification pre-explainer (RootPresentation.swift, QA fixes Q1 + Q6).
        .rootPresenter()
    }

    /// The launch route's view when it targets `tab`, else the tab's normal root.
    @ViewBuilder
    private func root<Root: View>(for tab: AppTab, @ViewBuilder normal: () -> Root) -> some View {
        if let launchRoute, case .tabRoot(tab) = launchRoute.placement {
            launchRoute.makeView()
        } else {
            normal()
        }
    }
}
