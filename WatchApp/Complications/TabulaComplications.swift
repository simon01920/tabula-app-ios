// Watch complications + Smart Stack widget (Phase 5 W1): the Now & Next widget on Apple Watch. XcodeGen/CI path ONLY
// (target TabulaWatchWidgets, embedded in TabulaWatch.app/PlugIns). Reads the watch app's cache (`WatchCache`, App
// Group), plans with the shared `WidgetTimelinePlanner` (entries at lesson boundaries and midnights, ≤ 29, reload ≤ 6 h)
// and renders the shared views: `NowNextWidgetView` for circular / rectangular / inline, `NowNextCornerView` for corner.
// Live time is `Text(timerInterval:)` / `ProgressView(timerInterval:)`, never per-second entries.
// Pro gate: `ProFeature.watchApp` on the snapshot's tier → `WidgetProPlaceholderView`.
// Smart Stack: `TimelineEntry.relevance` scores the entries during a lesson (cheap; RelevanceConfiguration not used).
//
// HIG: widgets.md › "Widget sizes" (corner = watch complications only; circular and rectangular also in the Smart
// Stack), › "Rendering modes" ("in watchOS, the system may invert colors … Use text and symbols"): the shared views
// switch to outlined marks and `widgetAccentable` groups outside full colour.
// APIs (watchOS 27 SDK WidgetKit.swiftinterface, 2026-10-30): WidgetFamily.accessoryCorner (watchOS 9, iOS unavailable),
//   accessoryCircular / accessoryRectangular / accessoryInline (watchOS 9), TimelineEntryRelevance(score:duration:)
//   (watchOS 9), StaticConfiguration, TimelineProvider, View.containerBackground(_:for:).
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let display: NowNextDisplay
    /// `false` when the snapshot's tier lacks the Watch feature.
    let allowed: Bool
    let proTitle: String
    let proShort: String

    /// Most relevant while a lesson runs, for the rest of it.
    var relevance: TimelineEntryRelevance? {
        guard case .current = display.kind, let end = display.timer?.upperBound else { return nil }
        return TimelineEntryRelevance(score: 1, duration: end.timeIntervalSince(date))
    }
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        Self.timeline(snapshot: Self.sample()).entries[0]
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ComplicationEntry) -> Void) {
        let snapshot = WatchCache.read() ?? (context.isPreview ? Self.sample() : nil)
        completion(Self.timeline(snapshot: snapshot).entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ComplicationEntry>) -> Void) {
        completion(Self.timeline(snapshot: WatchCache.read()))
    }

    static func timeline(snapshot: WidgetSnapshot?) -> Timeline<ComplicationEntry> {
        NSTimeZone.resetSystemTimeZone()   // the extension process can outlive a time-zone change (RISKS #67)
        let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, now: Date(), deviceTimeZone: TimeZone.current)
        let context = plan.context ?? CalendarContext(timeZone: TimeZone.current, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context,
                                                 lookup: WatchCache.lookup(language: snapshot?.languageCode))
        let presenter = NowNextPresenter(renderer: renderer, context: context)
        let pro = presenter.proTexts()
        let allowed = snapshot.map { FeaturePolicy.standard.isAllowed(.watchApp, tier: $0.tier) } ?? true
        let entries = plan.entries.map {
            ComplicationEntry(date: $0.date, display: presenter.display($0), allowed: allowed,
                              proTitle: pro.title, proShort: pro.short)
        }
        return Timeline(entries: entries, policy: .after(plan.reloadDate))
    }

    /// A "during a lesson" sample around now (placeholder / face gallery), in the watch's language.
    static func sample() -> WidgetSnapshot {
        let language = Bundle.main.preferredLocalizations.first
        return WidgetGallerySamples.previewSnapshot(now: Date(), timeZone: TimeZone.current,
                                                    localeID: Locale.current.identifier, languageCode: language,
                                                    name: WatchCache.lookup(language: language))
    }
}

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let kind = Self.kind(of: family)
        if !entry.allowed {
            WidgetProPlaceholderView(family: kind ?? .accessoryCircular, title: entry.proTitle, short: entry.proShort)
        } else if let kind {
            NowNextWidgetView(display: entry.display, family: kind)
        } else {
            NowNextCornerView(display: entry.display)
        }
    }

    /// Our family for WidgetKit's; `nil` for the corner (watch-only, no `WidgetFamilyKind` case).
    static func kind(of family: WidgetFamily) -> WidgetFamilyKind? {
        switch family {
        case .accessoryCircular: return .accessoryCircular
        case .accessoryRectangular: return .accessoryRectangular
        case .accessoryInline: return .accessoryInline
        default: return nil
        }
    }
}

@main
struct NowNextComplication: Widget {
    static let kind = "sk.simondev.tabula.watch.nowNext"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.background, for: .widget)
                .tint(Color.ink)
        }
        .configurationDisplayName("widget.nowNext.name")
        .description("widget.nowNext.description")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
