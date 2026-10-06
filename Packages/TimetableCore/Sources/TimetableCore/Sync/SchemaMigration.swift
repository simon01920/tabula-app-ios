import Foundation

/// One schema migration step `sourceVersion → sourceVersion + 1`, operating on the raw JSON tree before
/// typed decoding (DOMAIN_MODEL §7.6). The chain sets the root `schemaVersion` after each step.
public struct SchemaMigration: Sendable {
    /// The version this step reads.
    public let sourceVersion: Int
    /// Transforms a root object of `sourceVersion` into one of `sourceVersion + 1`.
    public let transform: @Sendable (JSONValue) throws -> JSONValue

    /// Creates a step.
    public init(from sourceVersion: Int, transform: @escaping @Sendable (JSONValue) throws -> JSONValue) {
        self.sourceVersion = sourceVersion
        self.transform = transform
    }
}

/// Errors of `MigrationChain`.
public enum MigrationError: Error, Hashable, Sendable {
    /// The root is not an object or has no integer `schemaVersion`.
    case missingSchemaVersion
    /// The data is newer than the chain's target (open read-only instead).
    case newerThanTarget(version: Int, target: Int)
    /// No step reads `version`.
    case noMigration(fromVersion: Int)
    /// A step failed or did not return an object.
    case stepFailed(fromVersion: Int, detail: String)
}

/// An ordered chain of migrations up to `targetVersion`.
///
/// Version 1 is the first persisted schema, so `standard` has no steps: migrating a version-1 document is
/// the identity. A future version 2 appends `SchemaMigration(from: 1) { … }` and raises the target.
public struct MigrationChain: Sendable {
    /// The version every migration ends at.
    public let targetVersion: Int
    private let steps: [Int: SchemaMigration]

    /// The app's chain: target `TabulaDatabase.currentSchemaVersion`, no steps (v1 = identity).
    public static let standard = MigrationChain(targetVersion: TabulaDatabase.currentSchemaVersion, migrations: [])

    /// Creates a chain. Traps on two steps for the same source version (a programming error).
    public init(targetVersion: Int, migrations: [SchemaMigration]) {
        var steps: [Int: SchemaMigration] = [:]
        for step in migrations {
            precondition(steps[step.sourceVersion] == nil, "duplicate migration from \(step.sourceVersion)")
            precondition(step.sourceVersion < targetVersion, "migration from \(step.sourceVersion) beyond target")
            steps[step.sourceVersion] = step
        }
        self.targetVersion = targetVersion
        self.steps = steps
    }

    /// `true` when a document of `version` can be brought to `targetVersion`.
    public func canMigrate(from version: Int) -> Bool {
        guard version <= targetVersion else { return false }
        return (version..<targetVersion).allSatisfy { steps[$0] != nil }
    }

    /// The `schemaVersion` of a root object.
    public static func schemaVersion(of root: JSONValue) -> Int? {
        guard case .integer(let version)? = root["schemaVersion"], let value = Int(exactly: version) else { return nil }
        return value
    }

    /// Applies the steps from the document's `schemaVersion` up to `targetVersion`. A document already at
    /// the target is returned unchanged.
    public func migrate(_ root: JSONValue) throws -> JSONValue {
        guard let start = Self.schemaVersion(of: root) else { throw MigrationError.missingSchemaVersion }
        guard start <= targetVersion else { throw MigrationError.newerThanTarget(version: start, target: targetVersion) }
        var current = root
        for version in start..<targetVersion {
            guard let step = steps[version] else { throw MigrationError.noMigration(fromVersion: version) }
            let next: JSONValue
            do {
                next = try step.transform(current)
            } catch {
                throw MigrationError.stepFailed(fromVersion: version, detail: String(describing: error))
            }
            guard case .object(var object) = next else {
                throw MigrationError.stepFailed(fromVersion: version, detail: "step did not return an object")
            }
            object["schemaVersion"] = .integer(Int64(version + 1))
            current = .object(object)
        }
        return current
    }
}
