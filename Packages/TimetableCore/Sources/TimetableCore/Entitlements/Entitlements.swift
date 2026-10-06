import Foundation

/// Features that the Free/Pro split can gate. Raw values are stable identifiers (analytics-free; logs only).
public enum ProFeature: String, CaseIterable, Codable, Sendable {
    /// More than `Limit.maxTimetables(free)` timetables.
    case unlimitedTimetables
    /// Large widget family (small/medium stay free).
    case largeWidgets
    /// Lock Screen (accessory) widgets.
    case lockScreenWidgets
    /// Live Activity / Dynamic Island.
    case liveActivity
    /// Apple Watch app and complications.
    case watchApp
    /// AlarmKit loud alarm reminders.
    case loudAlarms
    /// On-device AI timetable import.
    case aiImport
    /// Image/PDF/CSV/XLSX/ICS exports.
    case exports
    /// Wallpapers and palette packs beyond Classic.
    case themePacks
    /// Attachment quota above the free quota.
    case extraAttachmentCapacity
    /// Statistics.
    case statistics
}

/// Purchase tier.
public enum Tier: String, CaseIterable, Codable, Sendable {
    case free, pro
}

/// Numeric limits that depend on the tier. `nil` from `limit(_:)` means unlimited.
public enum Limit: String, CaseIterable, Codable, Sendable {
    /// Maximum number of live timetables.
    case maxTimetables
    /// Attachment storage quota in megabytes (10⁶ bytes).
    case attachmentQuotaMB
}

/// The Free/Pro split as data — the single table that mirrors PRODUCT.md "Free vs Pro".
///
/// The split is a human decision (CLAUDE.md "Ask the human before … changing the Free/Pro split"); change
/// it only here, and keep `EntitlementsTests` (which re-reads PRODUCT.md) green.
public struct FeaturePolicy: Hashable, Sendable {
    /// Features available only on Pro.
    public var proFeatures: Set<ProFeature>
    /// Limits per tier; a missing entry means unlimited.
    public var limits: [Tier: [Limit: Int]]

    /// Creates a policy.
    public init(proFeatures: Set<ProFeature>, limits: [Tier: [Limit: Int]]) {
        self.proFeatures = proFeatures
        self.limits = limits
    }

    /// The shipping policy (PRODUCT.md, "Free vs Pro (proposal)").
    ///
    /// Free: 1 timetable, grid/day/tile views, tasks, exams, standard + Time Sensitive reminders,
    /// small/medium widgets, iCloud sync, QR/code share and import.
    /// Pro: everything in `ProFeature`. Attachment quotas (100 MB free / 2 000 MB Pro) are placeholders
    /// pending a human decision.
    public static let standard = FeaturePolicy(
        proFeatures: Set(ProFeature.allCases),
        limits: [
            .free: [.maxTimetables: 1, .attachmentQuotaMB: 100],
            .pro: [.attachmentQuotaMB: 2_000],
        ]
    )

    /// `true` when `feature` is usable on `tier`.
    public func isAllowed(_ feature: ProFeature, tier: Tier) -> Bool {
        tier == .pro || !proFeatures.contains(feature)
    }

    /// The limit on `tier`, or `nil` for unlimited.
    public func limit(_ limit: Limit, tier: Tier) -> Int? { limits[tier]?[limit] }
}

/// The app-wide entitlement query surface. StoreKit lives in the app target; core only sees this protocol.
public protocol EntitlementsProvider: Sendable {
    /// Current tier.
    var tier: Tier { get }
    /// `true` when `feature` may be used.
    func isAllowed(_ feature: ProFeature) -> Bool
    /// The numeric limit, or `nil` for unlimited.
    func limit(_ limit: Limit) -> Int?
}

/// Entitlements computed from a tier and a `FeaturePolicy`.
public struct PolicyEntitlements: EntitlementsProvider, Hashable {
    /// Current tier.
    public let tier: Tier
    /// The policy table.
    public let policy: FeaturePolicy

    /// Creates entitlements for `tier` under `policy` (default `.standard`).
    public init(tier: Tier, policy: FeaturePolicy = .standard) {
        self.tier = tier
        self.policy = policy
    }

    /// See `FeaturePolicy.isAllowed(_:tier:)`.
    public func isAllowed(_ feature: ProFeature) -> Bool { policy.isAllowed(feature, tier: tier) }

    /// See `FeaturePolicy.limit(_:tier:)`.
    public func limit(_ limit: Limit) -> Int? { policy.limit(limit, tier: tier) }
}

/// Development entitlements: Pro tier, everything allowed, no limits. Never ship as the default provider.
public struct AllAccessEntitlements: EntitlementsProvider, Hashable {
    /// Creates all-access entitlements.
    public init() {}

    /// Always `.pro`.
    public var tier: Tier { .pro }

    /// Always `true`.
    public func isAllowed(_ feature: ProFeature) -> Bool { true }

    /// Always `nil` (unlimited).
    public func limit(_ limit: Limit) -> Int? { nil }
}
