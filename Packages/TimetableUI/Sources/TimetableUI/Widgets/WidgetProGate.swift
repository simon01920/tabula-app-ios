// Free/Pro gate of widget families (PHASE4_PLAN §0.4, MONETIZATION.md, PRODUCT.md "Free vs Pro": small/medium
// widgets free; large widgets, Lock Screen widgets and the Live Activity Pro). The tier comes from the snapshot, so
// the extension never needs StoreKit. A gated family is never removed from the gallery: it shows an "Available in
// Tabula Pro" view instead. Pure, Linux-tested; the current shipping tier is all-access (`AllAccessEntitlements`).
import Foundation
import TimetableCore

/// Widget families as WidgetKit names them, without importing WidgetKit (pure code; the watch has other families).
public enum WidgetFamilyKind: String, CaseIterable, Sendable {
    case systemSmall, systemMedium, systemLarge, systemExtraLarge
    case accessoryCircular, accessoryRectangular, accessoryInline
}

/// Whether a family may show its content.
public enum WidgetGateDecision: Equatable, Sendable {
    case allowed
    /// Show the Pro placeholder for `feature`.
    case requiresPro(ProFeature)
}

public enum WidgetProGate {
    /// The Pro feature a family needs, or `nil` for free families.
    public static func feature(for family: WidgetFamilyKind) -> ProFeature? {
        switch family {
        case .systemSmall, .systemMedium: return nil
        case .systemLarge, .systemExtraLarge: return .largeWidgets
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return .lockScreenWidgets
        }
    }

    /// The decision for `family` on `tier` under `policy`.
    public static func decision(for family: WidgetFamilyKind, tier: Tier,
                                policy: FeaturePolicy = .standard) -> WidgetGateDecision {
        guard let feature = feature(for: family), !policy.isAllowed(feature, tier: tier) else { return .allowed }
        return .requiresPro(feature)
    }

    /// The decision for `family` with `snapshot`'s tier. Without a snapshot the content is the "Open Tabula" view,
    /// which is never gated (it carries no Pro content).
    public static func decision(for family: WidgetFamilyKind, snapshot: WidgetSnapshot?,
                                policy: FeaturePolicy = .standard) -> WidgetGateDecision {
        guard let snapshot else { return .allowed }
        return decision(for: family, tier: snapshot.tier, policy: policy)
    }
}
