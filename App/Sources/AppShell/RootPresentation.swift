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
//   - the permission offer never closes anything: it waits until no sheet is open (e.g. the lesson detail after
//     "Add homework");
//   - requests older than 10 minutes are dropped.
// "Presented" is read from UIKit (`presentedViewController` of the window's root), which covers every SwiftUI sheet,
// alert, dialog and Quick Look; nothing is dismissed through UIKit (SwiftUI state stays the source of truth).
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

    /// Restarts the loop when a new request arrives or one was shown / dropped.
    private struct Key: Equatable {
        let link: UUID?
        let offer: UUID?
    }

    private struct Pending {
        let kind: RootPresentationPolicy.Request
        let requestedAt: Date
        let dismissRequested: Bool
    }

    private var rootSheet: Binding<RootSheet?> {
        Binding(get: { navigation.rootSheet }, set: { navigation.rootSheet = $0 })
    }

    func body(content: Content) -> some View {
        content
            // On a background view: a second `.sheet` on the same view as the launch-route sheet is not reliable.
            .background {
                Color.clear
                    .sheet(item: rootSheet) { sheet in
                        sheetContent(sheet)
                    }
            }
            .task(id: Key(link: navigation.pendingLink?.id, offer: reminders.permissionOffer?.id)) {
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
            ReminderPermissionSheet()
                .onDisappear { Task { await reminders.permissionOfferClosed() } }
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
            guard let pending = next else { return }
            let screen = RootPresentationPolicy.Screen(isAnySheetShown: WindowPresentationProbe.isPresenting(),
                                                       isRootSheetShown: navigation.rootSheet != nil,
                                                       hasUnsavedWork: !navigation.unsavedWork.isEmpty,
                                                       dismissRequested: pending.dismissRequested)
            let age = Date().timeIntervalSince(pending.requestedAt)
            switch RootPresentationPolicy.step(for: pending.kind, screen: screen, age: age) {
            case .present:
                switch pending.kind {
                case .deepLink: navigation.showPendingLink()
                case .permissionOffer:
                    navigation.rootSheet = .permissionOffer
                    reminders.permissionOfferShown()
                }
                return   // the key changed: the loop restarts for whatever is still pending
            case .dismissSheets:
                navigation.requestSheetDismissal()
            case .wait:
                break
            case .expire:
                switch pending.kind {
                case .deepLink: navigation.dropPendingLink()
                case .permissionOffer: reminders.permissionOfferShown()   // dropped; the next save may offer it again
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
