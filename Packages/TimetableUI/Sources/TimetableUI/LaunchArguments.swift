// Launch-argument parsing for the screen router (CI iOS Simulator screenshots, manual QA).
// Pure Swift, no Foundation/SwiftUI: builds and is unit-tested on Linux (Tests/TimetableUITests).
// Candidate to move into TimetableCore once Phase 1 owners agree (CLAUDE.md rule 1); kept here because
// TimetableCore is owned by the Phase 1 agents right now.
//
// Form: `-<Name> <value>`, as passed by `xcrun simctl launch <device> <bundle-id> -TabulaScreen debug`
// and by Xcode scheme "Arguments Passed On Launch".

/// Read-only view over the process arguments.
public struct LaunchArguments: Sendable, Equatable {
    /// `-TabulaScreen <screen id>` selects the first screen (see the app's `AppScreen`).
    public static let screenKey = "TabulaScreen"

    public let arguments: [String]

    public init(_ arguments: [String]) {
        self.arguments = arguments
    }

    /// The value after the last `-<name>` flag (the last occurrence wins, like Foundation's argument domain).
    /// `nil` if the flag is absent, is the final argument, or is followed by another `-flag`.
    public func value(for name: String) -> String? {
        let flag = "-" + name
        var result: String?
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == flag {
                let next = arguments.index(after: index)
                if next < arguments.endIndex, !arguments[next].hasPrefix("-") {
                    result = arguments[next]
                    index = next
                } else {
                    result = nil
                }
            }
            index = arguments.index(after: index)
        }
        return result
    }
}

/// Outcome of resolving `-TabulaScreen`: which screen to show and what was asked for, so a typo is visible
/// on screen (and therefore in CI screenshots) instead of silently showing the default.
public struct ScreenRoute<Screen: RawRepresentable & Sendable & Equatable>: Sendable, Equatable
where Screen.RawValue == String {
    public let screen: Screen
    /// Raw id passed on launch, or `nil` when no `-TabulaScreen` argument was given.
    public let requested: String?
    /// `true` when an id was requested but no screen is registered under it (the fallback is shown).
    public let isUnknown: Bool

    public init(arguments: LaunchArguments, fallback: Screen) {
        let requested = arguments.value(for: LaunchArguments.screenKey)
        self.requested = requested
        if let requested, let screen = Screen(rawValue: requested) {
            self.screen = screen
            self.isUnknown = false
        } else {
            self.screen = fallback
            self.isUnknown = requested != nil
        }
    }

    /// One-line developer description, e.g. `requested "debug" → debug`.
    public var summary: String {
        switch (requested, isUnknown) {
        case (nil, _): return "default → \(screen.rawValue)"
        case (let id?, false): return "requested \"\(id)\" → \(screen.rawValue)"
        case (let id?, true): return "UNKNOWN \"\(id)\" → fallback \(screen.rawValue)"
        }
    }
}
