// Root presentation (Phase 3 final QA fixes Q1 + Q6): the one place that presents sheets from the root of the tab
// view — a notification deep link (`AppNavigation.pendingLink` → the item's detail route) and the in-context
// notification pre-explainer (`ReminderCoordinator.permissionOffer`).
//
// A root sheet cannot appear while a tab's own sheet is on screen, so `rootPresenter()` checks the screen every
// 0.3 s while something is pending and follows `RootPresentationPolicy` (TimetableUI, Linux-tested):
//   - nothing presented → present (deep links first, then the offer);
//   - a deep link over clean tab sheets → `navigation.requestSheetDismissal()`: every tab root closes its sheets
//     (`.closesForDeepLink`, nested sheets close with their parent), then the link is shown;
//   - unsaved work open (`.protectsUnsavedWork`: a dirty or busy editor, a voice recording) → never closed; the request
//     waits and appears right after the user saves or cancels;
//   - the permission offer never closes or replaces anything: it waits until no sheet is open and no root sheet is
//     set (e.g. the lesson detail after "Add homework", or a deep link's sheet still on its way up);
//   - requests older than 10 minutes are dropped.
// "Presented" is read from UIKit (`presentedViewController` of the window's root), which covers every SwiftUI sheet,
// alert, dialog and Quick Look; nothing is dismissed through UIKit (SwiftUI state stays the source of truth).
// Whether the root sheet itself is on screen comes from its content's onAppear / onDisappear (Phase 3 polish), not
// from the binding: a root sheet that was set but has not appeared `RootPresentationPolicy.appearTimeout` later (it
// lost a race with a tab sheet opening in the same tick) is cleared and its link (or offer) queued again, so the
// loop also runs while a root sheet is on its way up.
// APIs: View.sheet(item:onDismiss:content:), View.task(id:priority:_:), View.onChange(of:initial:_:) (iOS 17),
//       View.onAppear / onDisappear, UIApplication.connectedScenes, UIWindowScene.windows, UIWindow.windowLevel,
//       UIViewController.presentedViewController, Task.sleep(for:). Docs checked 2026-10-15.
import SwiftUI
import TimetableUI
import UIKit

extension View {
    /// Closes this view's sheet(s) when a notification deep link needs the screen. Apply on each tab root (and any
    /// view whose sheets are not nested in a tab root's sheet); `close` sets the sheet state to `nil` / `false`.
    func closesForDeepLink(_ close: @escaping () -> Void) -> some View {
        modifier(CloseForDeepLink(close: close))
    }

    /// Marks unsaved work held by this sheet (dirty or busy editor, a recording) while `isActive`: a deep link never
    /// closes it, and root sheets wait until it is gone.
    func protectsUnsavedWork(_ isActive: Bool) -> some View {
        modifier(UnsavedWorkGuard(isActive: isActive))
    }

    /// The shell's root sheet and its presenter loop. Apply once, on the tab view.
    func rootPresenter() -> some View {
        modifier(RootPresenter())
    }
}

/// Whether anything is presented over the app's windows.
@MainActor
enum WindowPresentationProbe {
    /// `true` while a sheet, alert, dialog or full-screen cover is presented over a normal-level window's root.
    static func isPresenting() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.windowLevel == .normal && $0.rootViewController?.presentedViewController != nil }
    }
}

private struct CloseForDeepLink: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    let close: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: navigation.sheetDismissRequest) { close() }
    }
}

private struct UnsavedWorkGuard: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    let isActive: Bool
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { navigation.setUnsavedWork(token, isActive) }
            .onChange(of: isActive) { _, active in navigation.setUnsavedWork(token, active) }
            .onDisappear { navigation.setUnsavedWork(token, false) }
    }
}

private struct RootPresenter: ViewModifier {
    @Environment(AppNavigation.self) private var navigation
    @Environment(ReminderCoordinator.self) private var reminders

    /// Restarts the loop when a new request arrives, one was shown / dropped, or a root sheet was set / appeared.
    private struct Key: Equatable {
        let link: UUID?
        let offer: UUID?
        let launch: UUID?
    }

    private struct Pending {
        let kind: RootPresentationPolicy.Request
        let requestedAt: Date
        let dismissRequested: Bool
    }

    private var rootSheet: Binding<RootSheet?> {
        Binding(get: { navigation.rootSheet }, set: { navigation.rootSheetBindingSet($0) })
    }

    func body(content: Content) -> some View {
        content
            // On a background view: a second `.sheet` on the same view as the launch-route sheet is not reliable.
            .background {
                Color.clear
                    .sheet(item: rootSheet) { sheet in
                        sheetContent(sheet)
                            .onAppear { navigation.rootSheetAppeared(sheet) }
                            .onDisappear { navigation.rootSheetDisappeared(sheet) }
                    }
            }
            .task(id: Key(link: navigation.pendingLink?.id, offer: reminders.permissionOffer?.id,
                          launch: navigation.rootSheetLaunch?.id)) {
                await run()
            }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: RootSheet) -> some View {
        switch sheet {
        case .item(let link):
            if let id = AppNavigation.detailRouteID(for: link), let route = RouteRegistry.route(id: id) {
                route.makeView()
            }
        case .permissionOffer:
            ReminderPermissionSheet()   // reports its own close (permissionExplainerClosed), like every entry point
        }
    }

    private var next: Pending? {
        if let link = navigation.pendingLink {
            return Pending(kind: .deepLink, requestedAt: link.requestedAt, dismissRequested: link.dismissRequested)
        }
        if let offer = reminders.permissionOffer {
            return Pending(kind: .permissionOffer, requestedAt: offer.requestedAt, dismissRequested: false)
        }
        return nil
    }

    private func run() async {
        while !Task.isCancelled {
            let now = Date()
            let rootState = navigation.rootSheetState(now: now)
            let pending = next
            let step: RootPresentationPolicy.Step
            if let pending {
                let screen = RootPresentationPolicy.Screen(isAnySheetShown: WindowPresentationProbe.isPresenting(),
                                                           rootSheet: rootState,
                                                           hasUnsavedWork: !navigation.unsavedWork.isEmpty,
                                                           dismissRequested: pending.dismissRequested)
                step = RootPresentationPolicy.step(for: pending.kind, screen: screen,
                                                   age: now.timeIntervalSince(pending.requestedAt))
            } else if let rootStep = RootPresentationPolicy.rootSheetStep(rootState) {
                step = rootStep   // nothing pending: only watch the root sheet on its way up
            } else {
                return
            }
            switch step {
            case .present:
                guard let pending else { return }
                switch pending.kind {
                case .deepLink: navigation.showPendingLink()
                case .permissionOffer:
                    navigation.presentRootSheet(.permissionOffer, requestedAt: pending.requestedAt)
                    reminders.permissionOfferShown()
                }
                return   // the key changed: the loop restarts for whatever is still pending or on its way up
            case .dismissSheets:
                navigation.requestSheetDismissal()
            case .wait:
                break
            case .expire:
                switch pending?.kind {
                case .deepLink: navigation.dropPendingLink()
                case .permissionOffer: reminders.permissionOfferShown()   // dropped; the next save may offer it again
                case nil: break
                }
                return
            case .clearStaleRootSheet:
                // Never appeared: clear it and queue its request again (a link goes back to `pendingLink`).
                if let cleared = navigation.clearStaleRootSheet(), cleared.sheet == .permissionOffer {
                    reminders.restorePermissionOffer(requestedAt: cleared.requestedAt)
                }
                continue   // re-check at once (if the key changed, this task is cancelled and a new one starts)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
