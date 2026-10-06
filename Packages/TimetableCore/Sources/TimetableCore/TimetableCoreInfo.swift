// Phase 0 placeholder. Domain models arrive in Phase 1 (see docs/specs/ARCHITECTURE.md).
// Rule: no Apple-only imports in this module (Foundation is fine: it exists on Linux).
// Named `TimetableCoreInfo` (not `TimetableCore`) so no type shadows the module name.

/// Module-level facts for the pure-Swift core.
public enum TimetableCoreInfo {
    /// Persisted schema version. Bumping it after Phase 1 requires human approval (CLAUDE.md).
    public static let schemaVersion = 1
}
