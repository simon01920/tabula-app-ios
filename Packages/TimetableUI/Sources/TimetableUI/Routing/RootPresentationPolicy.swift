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
//   - the permission offer never closes anything: it waits until no sheet is on screen;
//   - a request older than `maxAge` is dropped (a tap from ten minutes ago must not pop up unexpectedly).
import Foundation

public enum RootPresentationPolicy {
    /// What the shell wants to show.
    public enum Request: String, Sendable, Hashable, CaseIterable {
        /// A notification tap (deep link).
        case deepLink
        /// The in-context notification pre-explainer (`ReminderPermissionOffer`).
        case permissionOffer
    }

    /// The screen as the shell sees it.
    public struct Screen: Sendable, Hashable {
        /// Any sheet, alert or dialog is presented over the window's root (including the shell's own sheet).
        public var isAnySheetShown: Bool
        /// The shell's own root sheet is up (`isAnySheetShown` may also be `true` because of it).
        public var isRootSheetShown: Bool
        /// An open sheet holds unsaved work (registered by the editors and the voice recorder).
        public var hasUnsavedWork: Bool
        /// This request already asked the tab sheets to close.
        public var dismissRequested: Bool

        public init(isAnySheetShown: Bool, isRootSheetShown: Bool = false, hasUnsavedWork: Bool = false,
                    dismissRequested: Bool = false) {
            self.isAnySheetShown = isAnySheetShown
            self.isRootSheetShown = isRootSheetShown
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
    }

    /// Requests older than this (seconds) are dropped.
    public static let maxAge: TimeInterval = 600

    /// The next step for `request` on `screen`, `age` seconds after it was made.
    public static func step(for request: Request, screen: Screen, age: TimeInterval) -> Step {
        if age > maxAge { return .expire }
        // Nothing presented: nothing can be lost or block the sheet (a stale unsaved-work entry must not block it).
        if !screen.isAnySheetShown { return .present }
        if screen.hasUnsavedWork { return .wait }
        switch request {
        case .deepLink:
            let onlyRootSheet = screen.isRootSheetShown
            if onlyRootSheet { return .present }
            return screen.dismissRequested ? .wait : .dismissSheets
        case .permissionOffer:
            return .wait
        }
    }
}
