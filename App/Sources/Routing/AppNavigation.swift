// In-app navigation state shared by the shell and deep links (Phase 3 Stage A): the selected tab and the item a
// notification tap asked for. Views read it with `@Environment(AppNavigation.self)`.
//
// Deep links (notification tap → item):
//   task  → Tasks tab, then the route `tasks.detail` as a sheet if a feature registered it (stage B1)
//   exam  → Exams tab, then `exams.detail` (stage B2)
//   lesson → Timetable tab; pack tonight → Today tab (no detail sheet)
//   today  → Today tab (widget taps, Phase 4 A: `tabula://open/…` URLs from `ItemLinkURL`, handled by `onOpenURL`)
// Contract for B1/B2: register `AppRoute("tasks.detail", .sheet(over: .tasks)) { TaskDetailRouteView() }` (resp.
// `exams.detail`) in your *Routes.swift. The route's view reads `navigation.presentedItem` (`.task(id)` / `.exam(id)`)
// and shows that item; when it is `nil` (launched with `-TabulaScreen tasks.detail` for screenshots) it picks a
// sample from the seed data, like `timetable.lesson-detail` does.
// In-app links (Phase 3 C1): Today's "N overdue" chip calls `showTasks(.overdue)`; the shell then shows the Tasks tab
// rebuilt on that segment (`taskSegmentRequest`, see MainTabView), so App/Sources/Tasks needs no extra state.
//
// Final QA fix Q6 (a tap could do nothing visible while a tab sheet was open): `open(_:)` only records the link as
// `pendingLink`; the shell (MainTabView + RootPresentation.swift) shows it when the screen allows it, following
// `RootPresentationPolicy` (TimetableUI): nothing open → at once; clean tab sheets open → it bumps
// `sheetDismissRequest` (the tab roots close their sheets, `.closesForDeepLink`) and shows the link once they are gone;
// an editor with unsaved changes, a running attachment copy or a voice recording (`unsavedWork`, registered with
// `.protectsUnsavedWork`) is never closed: the link waits and is shown right after that sheet closes. Links older
// than 10 minutes are dropped. Phase 3 polish: whether the root sheet is on screen comes from its content's
// onAppear / onDisappear (`visibleRootSheet`); one that was set but never appeared (`rootSheetLaunch` older than
// `RootPresentationPolicy.appearTimeout`) is cleared and its link queued again (`clearStaleRootSheet()`).
// APIs: Observation.Observable (macro; allowed in app code outside Debug, PHASE2_PLAN §0.1).
import Foundation
import Observation
import TimetableCore
import TimetableUI

/// The sheet the shell presents from the root of the tab view.
enum RootSheet: Identifiable, Hashable {
    /// A deep link's detail route (`tasks.detail` / `exams.detail`).
    case item(ItemLink)
    /// The in-context notification pre-explainer (QA fix Q1).
    case permissionOffer

    var id: Self { self }
}

@MainActor
@Observable
final class AppNavigation {
    /// The tab the user (or a deep link) selected; `nil` = not changed yet → the launch route's tab.
    var selectedTab: AppTab?
    /// The item a deep link presents with its feature's detail route (read by the detail route views; kept after the
    /// sheet closes so the closing sheet does not flip to a sample).
    private(set) var presentedItem: ItemLink?
    /// What the shell presents from the root (`nil` = nothing): set by `presentRootSheet(_:requestedAt:)`, cleared by
    /// the sheet binding (`rootSheetBindingSet(_:)`, swipe / dismiss) or `clearStaleRootSheet()`.
    private(set) var rootSheet: RootSheet?
    /// The root sheet as its content reported it (onAppear / onDisappear): `nil` while none is on screen.
    private(set) var visibleRootSheet: RootSheet?
    /// The root sheet that was set and has not appeared yet (Phase 3 polish: a set binding does not prove the sheet
    /// is on screen; one that never appears is cleared and its request queued again).
    private(set) var rootSheetLaunch: RootSheetLaunch?

    /// A root sheet on its way up.
    struct RootSheetLaunch: Equatable {
        let id = UUID()
        let sheet: RootSheet
        /// Wall clock (UI timing only): when `rootSheet` was set.
        let setAt: Date
        /// When its request was made (kept when the request is queued again, so `maxAge` still applies).
        let requestedAt: Date
    }
    /// A deep link waiting to be shown (see the header).
    private(set) var pendingLink: PendingLink?
    /// Bumped to ask every tab root to close its sheets (`.closesForDeepLink`).
    private(set) var sheetDismissRequest = 0
    /// Open sheets that hold unsaved work (`.protectsUnsavedWork`); a deep link never closes them.
    private(set) var unsavedWork: Set<UUID> = []
    /// The last in-app request to show the Tasks tab on a segment (each request has its own `id`).
    private(set) var taskSegmentRequest: TaskSegmentRequest?

    /// A request to show the Tasks tab on `segment`; a new `id` per request rebuilds the tab even for the same segment.
    struct TaskSegmentRequest: Equatable {
        let segment: TaskSegment
        let id = UUID()
    }

    /// A deep link not shown yet.
    struct PendingLink: Equatable {
        let link: ItemLink
        let id = UUID()
        /// Wall clock (UI timing only): links that could not be shown for `RootPresentationPolicy.maxAge` are dropped.
        let requestedAt: Date
        /// The tab sheets were already asked to close for this link.
        var dismissRequested = false
    }

    /// Selects the Tasks tab on `segment` (Today's overdue chip).
    func showTasks(_ segment: TaskSegment) {
        taskSegmentRequest = TaskSegmentRequest(segment: segment)
        selectedTab = .tasks
    }

    /// Opens `link` (notification tap). The shell shows it as soon as the screen allows (header); a newer link
    /// replaces one still waiting.
    func open(_ link: ItemLink?) {
        guard let link else { return }
        pendingLink = PendingLink(link: link, requestedAt: Date())
    }

    // MARK: Shell (MainTabView / RootPresentation.swift)

    /// Shows the pending link now: its tab and, when the feature registered one, its detail route.
    func showPendingLink() {
        guard let pending = pendingLink else { return }
        let link = pending.link
        pendingLink = nil
        selectedTab = Self.tab(for: link)
        if Self.detailRouteID(for: link).flatMap({ RouteRegistry.route(id: $0) }) != nil {
            presentedItem = link
            presentRootSheet(.item(link), requestedAt: pending.requestedAt)
        }
    }

    /// Sets the root sheet and watches for its content to appear (`rootSheetAppeared(_:)`).
    func presentRootSheet(_ sheet: RootSheet, requestedAt: Date) {
        rootSheet = sheet
        // The same sheet already on screen (the same item tapped again): SwiftUI keeps it, nothing will appear.
        rootSheetLaunch = visibleRootSheet == sheet ? nil : RootSheetLaunch(sheet: sheet, setAt: Date(), requestedAt: requestedAt)
    }

    /// The `.sheet(item:)` binding's setter (SwiftUI sets `nil` when the sheet is swiped away or dismissed).
    func rootSheetBindingSet(_ sheet: RootSheet?) {
        rootSheet = sheet
        if sheet == nil { rootSheetLaunch = nil }
    }

    /// The root sheet's content appeared.
    func rootSheetAppeared(_ sheet: RootSheet) {
        visibleRootSheet = sheet
        if rootSheetLaunch?.sheet == sheet { rootSheetLaunch = nil }
    }

    /// The root sheet's content disappeared (a replacement may already have appeared: only clear our own).
    func rootSheetDisappeared(_ sheet: RootSheet) {
        if visibleRootSheet == sheet { visibleRootSheet = nil }
    }

    /// The root sheet as `RootPresentationPolicy` sees it.
    func rootSheetState(now: Date) -> RootPresentationPolicy.RootSheetState {
        if let launch = rootSheetLaunch { return .pending(age: now.timeIntervalSince(launch.setAt)) }
        if visibleRootSheet != nil { return .shown }
        // Set, never appeared and no launch record (it went away while the binding stayed set): stale.
        return rootSheet == nil ? .none : .pending(age: .infinity)
    }

    /// Clears a root sheet that never appeared and returns it (with its request time) so the shell queues its request
    /// again. A link goes back to `pendingLink` (unless a newer link is waiting: the newer one wins).
    func clearStaleRootSheet() -> (sheet: RootSheet, requestedAt: Date)? {
        guard let sheet = rootSheet else { return nil }
        let requestedAt = rootSheetLaunch?.requestedAt ?? Date()
        rootSheet = nil
        rootSheetLaunch = nil
        if case .item(let link) = sheet, pendingLink == nil {
            pendingLink = PendingLink(link: link, requestedAt: requestedAt)
        }
        return (sheet, requestedAt)
    }

    /// Drops the pending link (too old to show).
    func dropPendingLink() {
        pendingLink = nil
    }

    /// Asks the tab roots to close their sheets for the pending link (once per link).
    func requestSheetDismissal() {
        pendingLink?.dismissRequested = true
        sheetDismissRequest &+= 1
    }

    /// Registers (`true`) or clears (`false`) unsaved work held by an open sheet.
    func setUnsavedWork(_ token: UUID, _ isActive: Bool) {
        if isActive {
            if !unsavedWork.contains(token) { unsavedWork.insert(token) }
        } else if unsavedWork.contains(token) {
            unsavedWork.remove(token)
        }
    }

    /// The tab that shows `link`.
    static func tab(for link: ItemLink) -> AppTab {
        switch link {
        case .task: return .tasks
        case .exam: return .exams
        case .lesson: return .timetable
        case .packTonight, .today: return .today
        }
    }

    /// The detail route id for `link` (registered by the feature stages), or `nil`.
    static func detailRouteID(for link: ItemLink) -> String? {
        switch link {
        case .task: return "tasks.detail"
        case .exam: return "exams.detail"
        case .lesson, .packTonight, .today: return nil
        }
    }
}
