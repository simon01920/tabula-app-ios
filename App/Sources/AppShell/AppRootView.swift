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

    private var presentedItem: Binding<ItemLink?> {
        Binding(get: { navigation.presentedItem }, set: { navigation.presentedItem = $0 })
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
        // Second sheet on a background view: two `.sheet` modifiers on the same view are not reliable.
        .background {
            Color.clear
                .sheet(item: presentedItem) { link in
                    if let id = AppNavigation.detailRouteID(for: link), let route = RouteRegistry.route(id: id) {
                        route.makeView()
                    }
                }
        }
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
