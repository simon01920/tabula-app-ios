// Persistence of this install's `HybridLogicalClock` (node + last timestamp) and how it resumes at launch.
// The app stores it in the App Group UserDefaults (`UserDefaultsClockStore` in App/Sources/Environment); tests and
// seed mode use `InMemoryClockStore`. Pure resume logic, Linux-tested.
import Foundation
import TimetableCore

/// Where the clock is kept between launches.
public protocol ClockStore: Sendable {
    /// The stored clock, if any.
    func load() -> HybridLogicalClock?
    /// Stores the clock.
    func save(_ clock: HybridLogicalClock)
}

/// A clock store in memory (tests, `-TabulaSeed`).
public final class InMemoryClockStore: ClockStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HybridLogicalClock?

    /// Creates a store, optionally pre-filled.
    public init(_ clock: HybridLogicalClock? = nil) {
        stored = clock
    }

    public func load() -> HybridLogicalClock? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ clock: HybridLogicalClock) {
        lock.lock(); defer { lock.unlock() }
        stored = clock
    }
}

/// Resuming the clock at launch.
public enum ClockBootstrap {
    /// The clock to use after loading `database`: the stored node (or a new random non-zero node), advanced past
    /// everything in the stored clock and the database, so no timestamp is ever issued twice — also after a
    /// restore from backup or when UserDefaults were lost.
    public static func resume<G: RandomNumberGenerator>(stored: HybridLogicalClock?, database: TabulaDatabase?,
                                                        now: Date, generator: inout G) -> HybridLogicalClock {
        var clock = stored ?? HybridLogicalClock(randomNodeUsing: &generator)
        if let database {
            let latest = database.latestTimestamp
            if latest > clock.last { clock.receive(latest, now: now) }
        }
        return clock
    }
}
