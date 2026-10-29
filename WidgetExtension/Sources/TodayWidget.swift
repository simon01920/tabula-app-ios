// *Today* widget (PHASE4_PLAN §0.3, Stage B1): the day's lessons with times, subject badge, room, cancelled lessons
// struck through, changes badged and the current lesson highlighted; large adds the tasks due that day. After school it
// shows tomorrow under a "Tomorrow" header; holiday / free day / "Open Tabula" states reuse the Now & Next semantics.
// A `StaticConfiguration` on the xtool path, an `AppIntentConfiguration` (timetable choice, Phase 4 B3) on builds with
// `TABULA_APP_INTENTS` (RISKS #19); systemMedium + systemLarge (large = `.largeWidgets`, a Pro family gated by
// `WidgetProGate` on the snapshot's tier).
//
// Data flow as Now & Next (NowNextWidget.swift): `WidgetSnapshotReader` → `WidgetTimelinePlanner.plan` (entries at lesson
// boundaries, cancelled ones included, and midnights, ≤ 29, reload ≤ 6 h) → `TodayPresenter` (pure, Linux-tested) →
// `TodayWidgetView` (TimetableUI, shared with the DEBUG gallery). Tap: `widgetURL(tabula://open/today)`.
// APIs: as NowNextWidget.swift (StaticConfiguration, TimelineProvider, containerBackground, widgetURL, widgetFamily).
import AppIntents
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

struct TodayEntry: TimelineEntry, Sendable {
    let date: Date
    let display: TodayDisplay
    /// Snapshot tier; `nil` without a snapshot (the "Open Tabula" view is never gated).
    let tier: Tier?
    let proTitle: String
    let proShort: String
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        Self.sampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        completion(Self.snapshotEntry(isPreview: context.isPreview, timetableID: nil))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        completion(Self.timeline(timetableID: nil))
    }

    /// The gallery / transient entry for `timetableID` (`nil` = the active timetable).
    static func snapshotEntry(isPreview: Bool, timetableID: String?) -> TodayEntry {
        NSTimeZone.resetSystemTimeZone()   // RISKS #67
        let snapshot = WidgetSnapshotReader.read().snapshot?.selecting(timetableID: timetableID)
        let entries = Self.entries(snapshot: snapshot, now: Date())
        if isPreview, case .unavailable = entries[0].display.kind { return Self.sampleEntry() }
        return entries[0]
    }

    /// The timeline for `timetableID` (`nil` = the active timetable; B3 `selecting(timetableID:)`).
    static func timeline(timetableID: String?) -> Timeline<TodayEntry> {
        NSTimeZone.resetSystemTimeZone()
        let read = WidgetSnapshotReader.read()
        let snapshot = read.snapshot?.selecting(timetableID: timetableID)
        let now = Date()
        let plan = Self.plan(snapshot: snapshot, now: now)
        WidgetSnapshotReader.recordRead(read, now: now, entries: plan.entries.count, widget: "Today")
        return Timeline(entries: Self.entries(snapshot: snapshot, plan: plan), policy: .after(plan.reloadDate))
    }

    static func plan(snapshot: WidgetSnapshot?, now: Date) -> NowNextTimelinePlan {
        WidgetTimelinePlanner.plan(snapshot: snapshot, now: now, deviceTimeZone: TimeZone.current,
                                   includeCancelledBoundaries: true, includeTaskDueBoundaries: true)
    }

    static func entries(snapshot: WidgetSnapshot?, now: Date) -> [TodayEntry] {
        entries(snapshot: snapshot, plan: plan(snapshot: snapshot, now: now))
    }

    static func entries(snapshot: WidgetSnapshot?, plan: NowNextTimelinePlan) -> [TodayEntry] {
        let context = plan.context ?? CalendarContext(timeZone: TimeZone.current, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context,
                                                 lookup: WidgetSnapshotReader.lookup(language: snapshot?.languageCode))
        let presenter = TodayPresenter(renderer: renderer, context: context)
        let pro = presenter.proTexts()
        return plan.entries.map { entry in
            TodayEntry(date: entry.date, display: presenter.display(snapshot: snapshot, entry: entry),
                       tier: snapshot?.tier, proTitle: pro.title, proShort: pro.short)
        }
    }

    /// A tiny "during a lesson" sample around now (placeholder / gallery preview), see `NowNextProvider.sampleEntry`.
    static func sampleEntry() -> TodayEntry {
        NSTimeZone.resetSystemTimeZone()
        let now = Date()
        let language = Bundle.main.preferredLocalizations.first
        let snapshot = WidgetGallerySamples.previewSnapshot(now: now, timeZone: TimeZone.current,
                                                            localeID: Locale.current.identifier, languageCode: language,
                                                            name: WidgetSnapshotReader.lookup(language: language))
        return entries(snapshot: snapshot, now: now)[0]
    }
}

/// Phase 4 B3: the same provider for a widget configured with `SelectTimetableIntent` (Xcode / TestFlight builds).
struct TodayIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayProvider.sampleEntry()
    }

    func snapshot(for configuration: SelectTimetableIntent, in context: Context) async -> TodayEntry {
        TodayProvider.snapshotEntry(isPreview: context.isPreview, timetableID: configuration.timetable?.id)
    }

    func timeline(for configuration: SelectTimetableIntent, in context: Context) async -> Timeline<TodayEntry> {
        TodayProvider.timeline(timetableID: configuration.timetable?.id)
    }
}

struct TodayWidget: Widget {
    static let kind = "sk.simondev.tabula.widget.today"

    var body: some WidgetConfiguration {
        // As NowNextWidget: configurable with App Intents metadata (TABULA_APP_INTENTS), static otherwise; same kind.
        #if TABULA_APP_INTENTS
        AppIntentConfiguration(kind: Self.kind, intent: SelectTimetableIntent.self, provider: TodayIntentProvider()) { entry in
            TodayEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
                .tint(Color.ink)   // Phase 4U U1 (D1): the app tint in widgets
                .widgetURL(ItemLinkURL.url(for: entry.display.link))
        }
        .configurationDisplayName("widget.today.name")
        .description("widget.today.description")
        .supportedFamilies([.systemMedium, .systemLarge])
        #else
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
                .tint(Color.ink)   // Phase 4U U1 (D1): the app tint in widgets
                .widgetURL(ItemLinkURL.url(for: entry.display.link))
        }
        .configurationDisplayName("widget.today.name")
        .description("widget.today.description")
        .supportedFamilies([.systemMedium, .systemLarge])
        #endif
    }
}

struct TodayEntryView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let family = NowNextEntryView.kind(of: widgetFamily)
        let decision = entry.tier.map { WidgetProGate.decision(for: family, tier: $0) } ?? .allowed
        if decision == .allowed {
            TodayWidgetView(display: entry.display, family: family)
        } else {
            WidgetProPlaceholderView(family: family, title: entry.proTitle, short: entry.proShort)
        }
    }
}
