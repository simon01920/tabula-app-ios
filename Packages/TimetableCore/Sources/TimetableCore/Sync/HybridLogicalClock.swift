import Foundation

/// A hybrid logical clock (Kulkarni et al., 2014) producing `HLCTimestamp`s for one node (device/install).
///
/// - Timestamps are **strictly increasing** for this clock, even when the wall clock jumps backwards
///   (manual time change, NTP correction): the physical part never decreases and the logical counter
///   orders events within the same millisecond.
/// - `receive(_:now:)` folds in a timestamp seen from another node, so every later local event sorts after
///   everything this node has observed (causality for last-writer-wins).
/// - **Logical overflow:** if the counter would exceed `UInt32.max`, the physical part is advanced by one
///   millisecond and the counter restarts at 0. The clock therefore stays monotonic; the physical part may
///   run ahead of the wall clock by at most that millisecond per 2³² events.
/// - The node comes from injected randomness (or is given); it breaks ties between nodes deterministically.
///   Persist `node` per install and resume `last` from the database (`TabulaDatabase.latestTimestamp`) so a
///   restarted app never issues a timestamp it issued before.
/// - A remote timestamp far in the future (a device with a wrong clock) is accepted: ordering stays correct,
///   only the physical part stops tracking real time until the wall clock catches up (Phase 6 may add a drift
///   warning; see `driftMillis(of:now:)`).
public struct HybridLogicalClock: TimestampClock, Hashable, Sendable, Codable {
    /// Identifier of this node; written into every timestamp it issues.
    public let node: UInt64
    /// The latest timestamp issued or observed (`.zero` for a fresh clock).
    public private(set) var last: HLCTimestamp

    /// Creates a clock for `node`, resuming after `last`.
    public init(node: UInt64, last: HLCTimestamp = .zero) {
        self.node = node
        self.last = last
    }

    /// Creates a clock with a random, non-zero node drawn from `generator`.
    public init(randomNodeUsing generator: inout some RandomNumberGenerator, last: HLCTimestamp = .zero) {
        var node: UInt64 = 0
        while node == 0 { node = generator.next() }
        self.init(node: node, last: last)
    }

    /// A timestamp for a local event at wall-clock time `now`, strictly greater than every timestamp this
    /// clock issued or observed before.
    public mutating func tick(now: Date) -> HLCTimestamp {
        let wall = Self.wallMillis(now)
        if wall > last.physicalMillis {
            last = HLCTimestamp(physicalMillis: wall, logical: 0, node: node)
        } else {
            last = successor(physical: last.physicalMillis, logical: last.logical)
        }
        return last
    }

    /// Folds in `remote` (a timestamp received from another node) and returns a timestamp for the receive
    /// event, strictly greater than both `remote` and every timestamp this clock issued or observed before.
    @discardableResult
    public mutating func receive(_ remote: HLCTimestamp, now: Date) -> HLCTimestamp {
        let wall = Self.wallMillis(now)
        let physical = max(wall, last.physicalMillis, remote.physicalMillis)
        if physical == last.physicalMillis && physical == remote.physicalMillis {
            last = successor(physical: physical, logical: max(last.logical, remote.logical))
        } else if physical == last.physicalMillis {
            last = successor(physical: physical, logical: last.logical)
        } else if physical == remote.physicalMillis {
            last = successor(physical: physical, logical: remote.logical)
        } else {
            last = HLCTimestamp(physicalMillis: physical, logical: 0, node: node)
        }
        return last
    }

    /// How far `timestamp` is ahead of the wall clock `now`, in milliseconds (negative when behind).
    public static func driftMillis(of timestamp: HLCTimestamp, now: Date) -> Int64 {
        timestamp.physicalMillis - wallMillis(now)
    }

    /// The next timestamp after (`physical`, `logical`) on this node, carrying a logical overflow into the
    /// physical part. At the very end of the representable range (only reachable by receiving a hostile or
    /// corrupt timestamp near year 33658) it saturates at the maximum instead of trapping (Stage 3); the clock
    /// then stops advancing, which is reported as a risk, not a crash.
    private func successor(physical: Int64, logical: UInt32) -> HLCTimestamp {
        if logical < UInt32.max {
            return HLCTimestamp(physicalMillis: physical, logical: logical + 1, node: node)
        }
        guard physical < HLCTimestamp.maxPhysicalMillis else {
            return HLCTimestamp(physicalMillis: HLCTimestamp.maxPhysicalMillis, logical: UInt32.max, node: node)
        }
        return HLCTimestamp(physicalMillis: physical + 1, logical: 0, node: node)
    }

    /// Wall-clock milliseconds since 1970, clamped to the encodable range.
    static func wallMillis(_ date: Date) -> Int64 {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds > 0 else { return 0 }
        guard seconds < Double(HLCTimestamp.maxPhysicalMillis) / 1000 else { return HLCTimestamp.maxPhysicalMillis }
        return min(max(TabulaJSON.milliseconds(from: date), 0), HLCTimestamp.maxPhysicalMillis)
    }
}
