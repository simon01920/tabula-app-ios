// Where the Live Activity preferences and the ledger live (Stage B2): UserDefaults of the device (App Group suite when
// available, like the reminder state), NOT the synced database — Live Activities are per device, and the persisted
// schema is frozen (PHASE4_PLAN §0.11). JSON under one key each; unreadable values fall back to the defaults.
import Foundation

/// Storage of the Live Activity preferences and ledger.
public protocol LiveActivityPreferenceStore: Sendable {
    func loadPreferences() -> LiveActivityPreferences
    func savePreferences(_ preferences: LiveActivityPreferences)
    func loadLedger() -> LiveActivityLedger
    func saveLedger(_ ledger: LiveActivityLedger)
}

/// In memory (tests, seed / screenshot runs).
public final class InMemoryLiveActivityPreferenceStore: LiveActivityPreferenceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var preferences: LiveActivityPreferences
    private var ledger: LiveActivityLedger

    public init(preferences: LiveActivityPreferences = LiveActivityPreferences(), ledger: LiveActivityLedger = LiveActivityLedger()) {
        self.preferences = preferences
        self.ledger = ledger
    }

    public func loadPreferences() -> LiveActivityPreferences { lock.withLock { preferences } }
    public func savePreferences(_ preferences: LiveActivityPreferences) { lock.withLock { self.preferences = preferences } }
    public func loadLedger() -> LiveActivityLedger { lock.withLock { ledger } }
    public func saveLedger(_ ledger: LiveActivityLedger) { lock.withLock { self.ledger = ledger } }
}

/// UserDefaults (documented as thread-safe; the class holds no other state).
public final class UserDefaultsLiveActivityPreferenceStore: LiveActivityPreferenceStore, @unchecked Sendable {
    public static let preferencesKey = "tabula.liveActivities.preferences.v1"
    public static let ledgerKey = "tabula.liveActivities.ledger.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func loadPreferences() -> LiveActivityPreferences {
        load(Self.preferencesKey) ?? LiveActivityPreferences()
    }

    public func savePreferences(_ preferences: LiveActivityPreferences) { save(preferences, Self.preferencesKey) }

    public func loadLedger() -> LiveActivityLedger { load(Self.ledgerKey) ?? LiveActivityLedger() }

    public func saveLedger(_ ledger: LiveActivityLedger) { save(ledger, Self.ledgerKey) }

    private func load<Value: Decodable>(_ key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
