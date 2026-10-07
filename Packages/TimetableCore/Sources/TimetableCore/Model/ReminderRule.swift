import Foundation

/// A reminder rule: for a target kind, fire at these offsets before the due/start time, with this tier.
///
/// Presets create rules with `origin == .preset` and never use `.alarm`; the UI switches `origin` to
/// `.user` when the user edits a rule. Planning (64-notification window, quiet hours, tier downgrades)
/// is Stage 2C.
public struct ReminderRule: SyncEntity {
    public typealias ID = EntityID<ReminderRule>
    public static let entityType: EntityType = .reminderRule

    /// Stable identifier.
    public var id: ID
    /// Sync metadata.
    public var meta: EntityMeta
    /// What the rule applies to (open).
    public var target: ReminderTarget
    /// When to fire, relative to the item's due/start time.
    public var offsets: [ReminderOffset]
    /// Optional second reminder if the item is still not completed.
    public var followUp: FollowUp?
    /// Requested delivery tier.
    public var tier: DeliveryTier
    /// Rule-specific quiet hours (in addition to `AppSettings.globalQuietHours`).
    public var quietHours: QuietHours?
    /// Off rules are kept but plan nothing.
    public var isEnabled: Bool
    /// Preset or user-made.
    public var origin: RuleOrigin

    /// Creates a rule.
    public init(id: ID, meta: EntityMeta, target: ReminderTarget, offsets: [ReminderOffset],
                followUp: FollowUp? = nil, tier: DeliveryTier = .standard, quietHours: QuietHours? = nil,
                isEnabled: Bool = true, origin: RuleOrigin = .user) {
        self.id = id
        self.meta = meta
        self.target = target
        self.offsets = offsets
        self.followUp = followUp
        self.tier = tier
        self.quietHours = quietHours
        self.isEnabled = isEnabled
        self.origin = origin
    }
}

/// When a reminder fires relative to the item. **Open union:** unknown kinds decode as `.unknown`.
///
/// JSON: `{"kind":"minutesBefore","minutes":15}` or `{"kind":"daysBefore","days":1,"at":"19:00"}`.
/// "Morning of at 07:00" is `.daysBefore(0, at: 07:00)`.
public enum ReminderOffset: Hashable, Sendable {
    /// `minutes` (≥ 0) before the due/start instant.
    case minutesBefore(Int)
    /// At wall-clock `at` on the day `days` (≥ 0) calendar days before the due/start date.
    case daysBefore(Int, at: LocalTime)
    /// An offset kind from a newer app version; preserved, never planned.
    case unknown(JSONValue)
}

extension ReminderOffset: Codable {
    private enum CodingKeys: String, CodingKey { case kind, minutes, days, at }

    /// Decodes a known kind, or preserves the whole value as `.unknown`.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil else {
            self = .unknown(try JSONValue(from: decoder))
            return
        }
        switch kind {
        case "minutesBefore":
            self = .minutesBefore(try container.decode(Int.self, forKey: .minutes))
        case "daysBefore":
            self = .daysBefore(try container.decode(Int.self, forKey: .days),
                               at: try container.decode(LocalTime.self, forKey: .at))
        default:
            self = .unknown(try JSONValue(from: decoder))
        }
    }

    /// Encodes the tagged union; `.unknown` re-encodes its JSON unchanged.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .minutesBefore(let minutes):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("minutesBefore", forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        case let .daysBefore(days, at):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("daysBefore", forKey: .kind)
            try container.encode(days, forKey: .days)
            try container.encode(at, forKey: .at)
        case .unknown(let raw):
            try raw.encode(to: encoder)
        }
    }
}

/// A second reminder for items still incomplete.
///
/// JSON: `{"kind":"afterMinutes","minutes":120}` or `{"kind":"nextMorning","at":"07:00"}`.
/// **Open union** (since the pre-freeze QA): an unknown kind, a missing kind or a non-object decodes as
/// `.unknown` and re-encodes unchanged; the planner plans no follow-up for it (reported as
/// `DropReason.unsupportedOffset`). A known kind with a malformed payload is a decoding error.
public enum FollowUp: Hashable, Sendable {
    /// `minutes` after the first reminder.
    case afterMinutes(Int)
    /// The next morning at `at`.
    case nextMorning(at: LocalTime)
    /// A follow-up kind from a newer app version; preserved, never planned.
    case unknown(JSONValue)

    /// `false` for `.unknown`.
    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

extension FollowUp: Codable {
    private enum CodingKeys: String, CodingKey { case kind, minutes, at }

    /// Decodes a known kind, or preserves the whole value as `.unknown`.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil else {
            self = .unknown(try JSONValue(from: decoder))
            return
        }
        switch kind {
        case "afterMinutes": self = .afterMinutes(try container.decode(Int.self, forKey: .minutes))
        case "nextMorning": self = .nextMorning(at: try container.decode(LocalTime.self, forKey: .at))
        default: self = .unknown(try JSONValue(from: decoder))
        }
    }

    /// Encodes the tagged union; `.unknown` re-encodes its JSON unchanged.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .afterMinutes(let minutes):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("afterMinutes", forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        case .nextMorning(let at):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("nextMorning", forKey: .kind)
            try container.encode(at, forKey: .at)
        case .unknown(let raw):
            try raw.encode(to: encoder)
        }
    }
}

/// A daily quiet window. `end < start` spans midnight (22:00–07:00); `start == end` is an empty window.
/// JSON: `{"end":"07:00","start":"22:00"}`.
public struct QuietHours: Hashable, Sendable, Codable {
    /// Start (inclusive).
    public var start: LocalTime
    /// End (exclusive).
    public var end: LocalTime

    /// Creates quiet hours.
    public init(start: LocalTime, end: LocalTime) {
        self.start = start
        self.end = end
    }

    /// `true` when the window crosses midnight.
    public var spansMidnight: Bool { end < start }

    /// `true` when `time` is inside `[start, end)` (wrapping past midnight when needed).
    public func contains(_ time: LocalTime) -> Bool {
        if start == end { return false }
        return spansMidnight ? (time >= start || time < end) : (time >= start && time < end)
    }
}

/// Per-task / per-exam replacement of the matching rules' behaviour.
///
/// JSON: `{"followUp":{"kind":"inherit"},"isEnabled":true,"offsets":[…],"tier":"standard"}`
/// (`offsets` and `tier` omitted = inherit).
public struct ReminderOverride: Hashable, Sendable, Codable {
    /// `false` = no reminders at all for this item.
    public var isEnabled: Bool
    /// Replacement offsets; `nil` = the rule's.
    public var offsets: [ReminderOffset]?
    /// Replacement tier; `nil` = the rule's.
    public var tier: DeliveryTier?
    /// Follow-up handling.
    public var followUp: FollowUpOverride

    /// Creates an override.
    public init(isEnabled: Bool = true, offsets: [ReminderOffset]? = nil, tier: DeliveryTier? = nil,
                followUp: FollowUpOverride = .inherit) {
        self.isEnabled = isEnabled
        self.offsets = offsets
        self.tier = tier
        self.followUp = followUp
    }
}

/// Follow-up part of a `ReminderOverride`.
///
/// JSON: `{"kind":"inherit"}`, `{"kind":"none"}` or `{"kind":"custom","followUp":{…}}`. Closed union.
public enum FollowUpOverride: Hashable, Sendable {
    /// Use the rule's follow-up.
    case inherit
    /// No follow-up for this item.
    case none
    /// This follow-up instead of the rule's.
    case custom(FollowUp)
}

extension FollowUpOverride: Codable {
    private enum CodingKeys: String, CodingKey { case kind, followUp }

    /// Decodes the tagged union; an unknown kind is a decoding error (closed union).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeKind(forKey: .kind)
        switch kind {
        case "inherit": self = .inherit
        case "none": self = .none
        case "custom": self = .custom(try container.decode(FollowUp.self, forKey: .followUp))
        default: throw TabulaCodingError.unknownKind(kind, key: .kind, in: container, type: "FollowUpOverride")
        }
    }

    /// Encodes the tagged union.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inherit: try container.encode("inherit", forKey: .kind)
        case .none: try container.encode("none", forKey: .kind)
        case .custom(let followUp):
            try container.encode("custom", forKey: .kind)
            try container.encode(followUp, forKey: .followUp)
        }
    }
}
