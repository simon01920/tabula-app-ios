// Phase 5 W1 (PHASE5_PLAN): what the Apple Watch receives and shows. Pure Foundation + TimetableCore, Linux-tested.
//
// Transfer: the iPhone sends the widget snapshot's encoded bytes (the same file the widgets read, ≤ 19 000 B) as a
// WatchConnectivity application context `["snapshot": Data]` (latest wins). The watch keeps the bytes only when they
// decode as a snapshot this version reads (`WidgetSnapshotStore.decode`, the trust boundary), stores them as its offline
// cache and renders only from that cache.
//
// Display: Now & Next (the widget presenter at the current instant), the rest of today and tomorrow (the Today
// presenter's rows), a "Open Tabula on your iPhone" state without usable data, and the Pro gate (`ProFeature.watchApp`,
// tier from the snapshot). Staleness is the planner's: a snapshot that no longer covers today is `.outdated`.
import Foundation
import TimetableCore

/// The WatchConnectivity application-context format of the snapshot.
public enum WatchSnapshotTransfer {
    /// Application-context key of the encoded snapshot.
    public static let key = "snapshot"

    /// The context carrying `data`, or `nil` above the snapshot cap (WatchConnectivity documents no size limit for
    /// application contexts; `WidgetSnapshotBuilder.maxEncodedBytes` keeps it small).
    public static func context(for data: Data) -> [String: Any]? {
        data.count <= WidgetSnapshotBuilder.maxEncodedBytes ? [key: data] : nil
    }

    /// The snapshot bytes in a received context, only when they decode as a snapshot this version can read.
    public static func snapshotData(in context: [String: Any]) -> Data? {
        guard let data = context[key] as? Data, WidgetSnapshotStore.decode(data) != nil else { return nil }
        return data
    }
}

/// What the watch app shows at one instant.
public struct WatchDisplay: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// No usable snapshot: open Tabula on the iPhone.
        case openPhone(title: String, detail: String)
        /// The snapshot's tier lacks the Watch feature.
        case pro(title: String)
        /// Now & Next, the rest of today (lessons not over yet, the current one excluded) and tomorrow.
        case content(nowNext: NowNextDisplay, today: TodayDisplay.Day?, tomorrow: TodayDisplay.Day?)
    }

    public var kind: Kind
}

public enum WatchPresenter {
    /// The display of `snapshot` at `now` on a watch in `deviceTimeZone`, strings through `lookup`.
    public static func display(snapshot: WidgetSnapshot?, now: Date, deviceTimeZone: TimeZone,
                               lookup: @escaping LocalizedTextRenderer.Lookup,
                               policy: FeaturePolicy = .standard) -> WatchDisplay {
        let context = snapshot.map { WidgetTimelinePlanner.context(for: $0, deviceTimeZone: deviceTimeZone) }
            ?? CalendarContext(timeZone: deviceTimeZone, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context, lookup: lookup)
        let title = renderer.string(forKey: "watch.open.title")
        guard let snapshot else {
            return WatchDisplay(kind: .openPhone(title: title, detail: renderer.string(forKey: "watch.open.noSnapshot")))
        }
        guard policy.isAllowed(.watchApp, tier: snapshot.tier) else {
            return WatchDisplay(kind: .pro(title: renderer.string(forKey: "widget.pro.title")))
        }
        let entry = WidgetTimelinePlanner.entry(snapshot: snapshot, at: now, context: context)
        if case .unavailable(let reason) = entry.state {
            let key = switch reason {
            case .noSnapshot: "watch.open.noSnapshot"
            case .noTimetable: "widget.open.noTimetable"
            case .outdated: "widget.open.outdated"
            }
            return WatchDisplay(kind: .openPhone(title: title, detail: renderer.string(forKey: key)))
        }
        let today = context.localDate(of: now)
        let presenter = TodayPresenter(renderer: renderer, context: context)
        var rest = presenter.day(snapshot: snapshot, date: today, entry: entry)
        rest?.rows.removeAll { $0.isPast || $0.isCurrent }
        return WatchDisplay(kind: .content(
            nowNext: NowNextPresenter(renderer: renderer, context: context).display(entry),
            today: rest?.rows.isEmpty == false ? rest : nil,
            tomorrow: presenter.day(snapshot: snapshot, date: today.adding(days: 1), entry: entry)))
    }
}
