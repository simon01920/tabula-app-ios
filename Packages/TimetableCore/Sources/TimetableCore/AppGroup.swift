// Phase 0 build-environment helper (not domain code).
//
// Why this exists: when xtool signs for a device it rewrites identifiers (verified in xtool 1.20.1
// source, Sources/XKit/Utilities/ProvisioningIdentifiers.swift):
//   bundle ID  sk.simondev.tabula            -> XTL-<ID>.sk.simondev.tabula
//   App Group  group.sk.simondev.tabula      -> group.XTL-<ID>.sk.simondev.tabula
// where <ID> is derived from the signing identity. The CI/XcodeGen path keeps the canonical IDs.
// Hard-coding the canonical App Group would therefore silently break App Group access on xtool
// builds, so the app and the widget resolve the group from their own (possibly prefixed) bundle ID.
// See docs/ENVIRONMENT.md ("Bundle-ID prefix").

/// Resolves the App Group identifier shared by the app, widgets and (later) other extensions.
public enum AppGroup {
    /// The canonical App Group used by the XcodeGen/CI (App Store) build.
    public static let canonicalIdentifier = "group.sk.simondev.tabula"

    /// Prefix xtool adds to re-signed bundle and group identifiers.
    public static let xtoolPrefix = "XTL-"

    private static let groupScheme = "group."

    /// Returns the App Group identifier matching the way the running bundle was signed.
    ///
    /// Rules (Linux-tested in TimetableCoreTests):
    /// - `nil`, `""` or any ID without the `XTL-` prefix → `canonicalIdentifier`.
    /// - `XTL-<ID>.<rest>` with a non-empty `<ID>` → `group.XTL-<ID>.sk.simondev.tabula`, for the app and
    ///   every extension alike (the suffix after the first dot is ignored).
    /// - Malformed xtool IDs (`XTL-` with no dot, or an empty `<ID>` as in `XTL-.sk…`) → canonical. xtool
    ///   never produces these (its `<ID>` is the first non-empty segment of the signing identity ID).
    ///
    /// - Parameter bundleIdentifier: `Bundle.main.bundleIdentifier` of the running app or extension.
    public static func identifier(forBundleIdentifier bundleIdentifier: String?) -> String {
        guard let bundleIdentifier, bundleIdentifier.hasPrefix(xtoolPrefix),
              let firstDot = bundleIdentifier.firstIndex(of: "."),
              bundleIdentifier.distance(from: bundleIdentifier.startIndex, to: firstDot) > xtoolPrefix.count else {
            return canonicalIdentifier
        }
        let xtoolComponent = bundleIdentifier[..<firstDot]           // "XTL-ABCD1234"
        let sanitizedGroup = canonicalIdentifier.dropFirst(groupScheme.count) // "sk.simondev.tabula"
        return "\(groupScheme)\(xtoolComponent).\(sanitizedGroup)"
    }

    /// `true` when the bundle was re-signed by xtool (local WSL build path).
    public static func isXtoolSigned(bundleIdentifier: String?) -> Bool {
        bundleIdentifier?.hasPrefix(xtoolPrefix) ?? false
    }
}
