// Pure part of the launch-route registry (App/Sources/Routing/RouteRegistry.swift).
// Linux-tested: id syntax, duplicate detection, resolution of `-TabulaScreen <id>`.
//
// Route ids: lowercase ASCII words separated by "." or "-", e.g. `today`, `timetable.week`, `editor.lesson`,
// `debug-platform`. Each feature folder owns a prefix (`onboarding.`, `today`, `timetable.`, `editor.`,
// `settings.`, `debug`), so ids from different feature providers can never collide by accident.

/// Validation and lookup of route ids.
public struct RouteTable: Sendable, Equatable {
    /// Why an id was rejected at registration.
    public enum Problem: Sendable, Equatable, CustomStringConvertible {
        /// The same id was registered more than once (all positions after the first).
        case duplicate(id: String, positions: [Int])
        /// The id does not match the route id syntax.
        case invalidID(id: String, position: Int)

        public var description: String {
            switch self {
            case let .duplicate(id, positions): return "duplicate route id \"\(id)\" at positions \(positions)"
            case let .invalidID(id, position): return "invalid route id \"\(id)\" at position \(position)"
            }
        }
    }

    /// Outcome of resolving a requested id.
    public enum Resolution: Sendable, Equatable {
        /// No `-TabulaScreen` given: the app shell's normal start.
        case none
        /// A registered id; `position` indexes the registration order.
        case matched(id: String, position: Int)
        /// An id was requested but nothing is registered under it: the app shell is shown and the debug screen
        /// lists the id, so a typo is visible.
        case unknown(id: String)
    }

    /// Registered ids in registration order (first registration of each id wins).
    public let ids: [String]
    /// Problems found while registering.
    public let problems: [Problem]
    private let index: [String: Int]

    /// Builds the table from ids in registration order.
    public init(ids: [String]) {
        var index: [String: Int] = [:]
        var duplicates: [String: [Int]] = [:]
        var problems: [Problem] = []
        for (position, id) in ids.enumerated() {
            if !Self.isValidID(id) { problems.append(.invalidID(id: id, position: position)) }
            if index[id] == nil {
                index[id] = position
            } else {
                duplicates[id, default: []].append(position)
            }
        }
        for id in duplicates.keys.sorted() {
            problems.append(.duplicate(id: id, positions: duplicates[id] ?? []))
        }
        self.ids = ids
        self.index = index
        self.problems = problems
    }

    /// Resolves a requested id (`LaunchOptions.screen`).
    public func resolve(_ requested: String?) -> Resolution {
        guard let requested else { return .none }
        guard let position = index[requested] else { return .unknown(id: requested) }
        return .matched(id: requested, position: position)
    }

    /// `true` for ids like `today`, `timetable.week`, `debug-platform`: lowercase ASCII letters and digits in
    /// words separated by single `.` or `-`, starting with a letter.
    public static func isValidID(_ id: String) -> Bool {
        var previousWasSeparator = true
        var isFirst = true
        for scalar in id.unicodeScalars {
            switch scalar {
            case "a"..."z":
                previousWasSeparator = false
            case "0"..."9":
                if isFirst { return false }
                previousWasSeparator = false
            case ".", "-":
                if previousWasSeparator { return false }
                previousWasSeparator = true
            default:
                return false
            }
            isFirst = false
        }
        return !id.isEmpty && !previousWasSeparator
    }

    /// One-line developer description of a resolution, e.g. `requested "today" → today`.
    public static func summary(_ resolution: Resolution) -> String {
        switch resolution {
        case .none: return "no -TabulaScreen → app shell"
        case .matched(let id, _): return "requested \"\(id)\" → \(id)"
        case .unknown(let id): return "UNKNOWN \"\(id)\" → app shell"
        }
    }
}
