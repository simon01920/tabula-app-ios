// Pure choice models of the Settings screens (stage B4): which options a picker offers and how a choice maps to the
// stored `AppSettings` value. Linux-tested; the SwiftUI screens in App/Sources/Settings only bind to these.
import Foundation
import TimetableCore

/// Week start picker: follow the system, or one fixed weekday.
public enum WeekStartChoice: Hashable, Sendable {
    case system
    case weekday(Weekday)

    /// The offered fixed weekdays (Monday, Sunday, Saturday; the common conventions).
    public static let offeredWeekdays: [Weekday] = [.monday, .sunday, .saturday]

    /// The choice for a stored override (`nil` = system).
    public init(_ override: Weekday?) {
        if let override { self = .weekday(override) } else { self = .system }
    }

    /// The value to store (`nil` = follow the locale's first weekday).
    public var override: Weekday? {
        if case .weekday(let day) = self { return day }
        return nil
    }

    /// System first, then the offered weekdays; a stored weekday outside the offered set (synced from elsewhere)
    /// is appended so the picker never shows a selection that is not in its list.
    public static func options(including current: Weekday?) -> [WeekStartChoice] {
        var list: [WeekStartChoice] = [.system] + offeredWeekdays.map { .weekday($0) }
        if let current, !offeredWeekdays.contains(current) { list.append(.weekday(current)) }
        return list
    }
}

/// 12/24 h picker. Unknown stored values behave as `system` (`HourCycle.effective`).
public enum HourCycleChoice: String, CaseIterable, Hashable, Sendable {
    case system, h12, h24

    public init(_ hourCycle: HourCycle) {
        switch hourCycle.effective {
        case .h12: self = .h12
        case .h24: self = .h24
        default: self = .system
        }
    }

    public var hourCycle: HourCycle {
        switch self {
        case .system: return .auto
        case .h12: return .h12
        case .h24: return .h24
        }
    }
}

/// Time-zone mode picker kind.
public enum TimeZoneModeKind: String, CaseIterable, Hashable, Sendable {
    case followDevice, fixed

    public init(_ mode: TimeZoneMode) {
        switch mode {
        case .followDevice: self = .followDevice
        case .fixed: self = .fixed
        }
    }
}

/// Fixed-time-zone choices.
public enum TimeZoneChoices {
    /// The mode after the user picks `kind`: switching to `.fixed` keeps a stored identifier if there is one, else
    /// starts from the device zone, so the first fixed value is the zone the user is already in.
    public static func mode(kind: TimeZoneModeKind, current: TimeZoneMode, deviceZone: TimeZone) -> TimeZoneMode {
        switch kind {
        case .followDevice: return .followDevice
        case .fixed:
            if case .fixed = current { return current }
            return .fixed(identifier: deviceZone.identifier)
        }
    }

    /// All selectable identifiers matching `query` (case-insensitive; underscores match spaces), sorted. `current`
    /// is listed first when it matches, even if the platform does not list it.
    public static func identifiers(matching query: String, current: String?,
                                   known: [String] = TimeZone.knownTimeZoneIdentifiers) -> [String] {
        let needle = normalized(query)
        var all = Set(known)
        if let current { all.insert(current) }
        let matching = all.filter { needle.isEmpty || normalized($0).contains(needle) }.sorted()
        guard let current, matching.contains(current) else { return matching }
        return [current] + matching.filter { $0 != current }
    }

    /// "America/New_York" -> "America / New York" (readable row text; the identifier stays the stored value).
    public static func displayName(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "/", with: " / ")
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// One palette pack as the picker shows it.
public struct PalettePackChoice: Equatable, Sendable, Identifiable {
    public let pack: PalettePack
    /// `false` when the pack needs a feature the current tier lacks (shown disabled with a Pro label).
    public let isSelectable: Bool
    public var id: PalettePackID { pack.id }

    /// The packs in presentation order for an entitlement check.
    public static func all(isAllowed: (ProFeature) -> Bool) -> [PalettePackChoice] {
        PalettePack.all.map { PalettePackChoice(pack: $0, isSelectable: !$0.requiresPro || isAllowed(.themePacks)) }
    }

    /// The pack whose colours are shown for `id`; an unknown stored ID shows Classic (what the app renders with).
    public static func displayedPack(for id: PalettePackID) -> PalettePack {
        PalettePack.pack(id) ?? .classic
    }

    /// The colour used for the live preview tile: the pack's first colour (stable, deterministic).
    public static func previewColor(of pack: PalettePack) -> PaletteColor { pack.colors[0] }
}

/// The profiles offered in Settings, in onboarding order.
public enum ProfileChoices {
    public static let offered: [UserProfile] = [.elementary, .secondary, .university, .other]

    /// The profile to show as selected; a stored unknown profile (newer app version) shows its `effective` one.
    public static func selection(for profile: UserProfile) -> UserProfile { profile.effective }

    /// Catalog key of the terminology the profile uses (`terminology.lesson` / `terminology.classLecture`).
    public static func terminologyKey(for profile: UserProfile) -> String { ProfilePreset.for(profile).terminologyKey }
}
