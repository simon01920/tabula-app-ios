// What the shell does with a sheet it wants to show from the root (Phase 3 final QA fixes Q1 + Q6). Pure, Linux-tested.
//
// The shell presents two things from the root of the tab view: a notification deep link (the item's detail sheet, or
// just its tab) and the in-context notification pre-explainer. A root sheet cannot appear while a tab's own sheet
// (task editor, Today detail, lesson detail, …) is on screen, so:
//   - nothing on screen → present;
//   - a deep link and only the shell's own sheet is up → present (it replaces that sheet);
//   - anything with unsaved work open (a dirty or busy editor, a voice recording) → wait: it is never closed for us;
//     the request is shown once that sheet has closed (the user saves or cancels);
//   - a deep link and other sheets are up, nothing unsaved → ask the tab sheets to close once, then wait for them;
//   - the permission offer never closes or replaces anything: it waits until no sheet is on screen and no root sheet
//     is set or shown (Phase 3 polish: a deep link's sheet that is set but not presented yet is never overwritten);
//   - a request older than `maxAge` is dropped (a tap from ten minutes ago must not pop up unexpectedly).
// The root sheet's own state comes from its content's onAppear / onDisappear, not from the binding (Phase 3 polish):
// a root sheet that was set but has not appeared `appearTimeout` later (it lost a race with a tab sheet opening in the
// same tick) is cleared and the shell queues its request again, so the link is retried instead of lost.
import Foundation

public enum RootPresentationPolicy {
    /// What the shell wants to show.
    public enum Request: String, Sendable, Hashable, CaseIterable {
        /// A notification tap (deep link).
        case deepLink
        /// The in-context notification pre-explainer (`ReminderPermissionOffer`).
        case permissionOffer
    }

    /// The shell's own root sheet, as its content reported it.
    public enum RootSheetState: Sendable, Hashable {
        /// No root sheet is set.
        case none
        /// Set (the binding is non-nil) but its content has not appeared, `age` seconds after it was set.
        case pending(age: TimeInterval)
        /// Its content appeared and has not disappeared.
        case shown
    }

    /// The screen as the shell sees it.
    public struct Screen: Sendable, Hashable {
        /// Any sheet, alert or dialog is presented over the window's root (including the shell's own sheet).
        public var isAnySheetShown: Bool
        /// The shell's own root sheet (`isAnySheetShown` is usually also `true` because of it).
        public var rootSheet: RootSheetState
        /// An open sheet holds unsaved work (registered by the editors and the voice recorder).
        public var hasUnsavedWork: Bool
        /// This request already asked the tab sheets to close.
        public var dismissRequested: Bool

        public init(isAnySheetShown: Bool, rootSheet: RootSheetState = .none, hasUnsavedWork: Bool = false,
                    dismissRequested: Bool = false) {
            self.isAnySheetShown = isAnySheetShown
            self.rootSheet = rootSheet
            self.hasUnsavedWork = hasUnsavedWork
            self.dismissRequested = dismissRequested
        }
    }

    /// The next step for a request.
    public enum Step: String, Sendable, Hashable {
        /// Show it now.
        case present
        /// Ask the tab sheets to close (nothing unsaved is open), then check again.
        case dismissSheets
        /// Keep it and check again later.
        case wait
        /// Too old: drop it.
        case expire
        /// The root sheet was set but never appeared: clear it, queue its request again, then check again.
        case clearStaleRootSheet
    }

    /// Requests older than this (seconds) are dropped.
    public static let maxAge: TimeInterval = 600
    /// A root sheet whose content has not appeared this long (seconds) after it was set failed to present. Content
    /// appears when the presentation starts (well under a second); the margin covers a busy main thread.
    public static let appearTimeout: TimeInterval = 2

    /// The step for the root sheet itself, whatever is pending: `.clearStaleRootSheet` when it failed to appear,
    /// `.wait` while it is on its way up, `nil` when there is nothing to watch (none, or shown).
    public static func rootSheetStep(_ state: RootSheetState) -> Step? {
        guard case .pending(let age) = state else { return nil }
        return age > appearTimeout ? .clearStaleRootSheet : .wait
    }

    /// The next step for `request` on `screen`, `age` seconds after it was made.
    public static func step(for request: Request, screen: Screen, age: TimeInterval) -> Step {
        if age > maxAge { return .expire }
        // A root sheet on its way up is never overwritten; a stale one is cleared first.
        if let rootStep = rootSheetStep(screen.rootSheet) { return rootStep }
        switch request {
        case .deepLink:
            // Nothing presented: nothing can be lost or block the sheet (a stale unsaved-work entry must not block it).
            if !screen.isAnySheetShown { return .present }
            if screen.hasUnsavedWork { return .wait }
            if screen.rootSheet == .shown { return .present }   // only the shell's own sheet is up: replace it
            return screen.dismissRequested ? .wait : .dismissSheets
        case .permissionOffer:
            // Only onto an empty screen: nothing presented and no root sheet set or shown.
            return !screen.isAnySheetShown && screen.rootSheet == .none ? .present : .wait
        }
    }
}
