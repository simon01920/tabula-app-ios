// *Now & Next* widget (PHASE4_PLAN §0.3, Stage A): the current lesson with its live remaining time and the next
// lesson; small, medium and the three Lock Screen families (accessory families also serve StandBy / CarPlay styles).
// A `StaticConfiguration` (works on both build paths; App Intent configuration comes later, RISKS #19).
//
// Data flow: the app writes `WidgetSnapshot` to the App Group (App/Sources/Widgets/WidgetSnapshotWriter.swift) →
// `WidgetSnapshotReader` reads it here → `WidgetTimelinePlanner` (pure, Linux-tested) plans entries at lesson
// boundaries and midnights (≤ 29) → `NowNextPresenter` renders the strings in the app's language →
// `NowNextWidgetView` (TimetableUI, shared with the app's DEBUG gallery) lays them out. Live time is
// `Text(timerInterval:)` / `ProgressView(timerInterval:)`: no per-second or per-minute entries.
// No App Group / no snapshot / outdated snapshot → the "Open Tabula" view (never stale or invented data).
// Pro gate: `WidgetProGate` on the snapshot's tier (Lock Screen families = `.lockScreenWidgets`).
// Tap: `widgetURL(ItemLinkURL.url(for: .today))` → the app's `onOpenURL` → `AppNavigation.open`.
//
// APIs (Apple docs JSON, checked 2026-10-16, ENVIRONMENT.md §27): StaticConfiguration(kind:provider:content:),
//   TimelineProvider (placeholder(in:), getSnapshot(in:completion:), getTimeline(in:completion:) with @Sendable
//   completions), TimelineProviderContext.isPreview, Timeline(entries:policy:), TimelineReloadPolicy.after(_:),
//   WidgetConfiguration.supportedFamilies(_:) / configurationDisplayName(_:) / description(_:),
//   View.containerBackground(_:for:) (iOS 17; ContainerBackgroundPlacement.widget), View.widgetURL(_:) (iOS 14; one per
//   hierarchy), EnvironmentValues.widgetFamily, WidgetFamily (.systemSmall, .systemMedium, .accessoryCircular,
//   .accessoryRectangular, .accessoryInline: iOS 16).
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

struct NowNextEntry: TimelineEntry, Sendable {
    let date: Date
    let display: NowNextDisplay
    /// Snapshot tier; `nil` without a snapshot (the "Open Tabula" view is never gated).
    let tier: Tier?
    let proTitle: String
    let proShort: String
}

struct NowNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowNextEntry {
        Self.sampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NowNextEntry) -> Void) {
        // The extension process can outlive a time-zone change: drop Foundation's cached zone first (RISKS #67).
        NSTimeZone.resetSystemTimeZone()
        let read = WidgetSnapshotReader.read()
        let entries = Self.entries(snapshot: read.snapshot, now: Date())
        // The widget gallery (preview) shows sample content when there is nothing real to show yet.
        if context.isPreview, case .unavailable = entries[0].display.kind {
            completion(Self.sampleEntry())
        } else {
            completion(entries[0])
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NowNextEntry>) -> Void) {
        NSTimeZone.resetSystemTimeZone()   // see getSnapshot; the plan's reload is ≤ 6 h away for the same reason
        let read = WidgetSnapshotReader.read()
        let now = Date()
        let plan = WidgetTimelinePlanner.plan(snapshot: read.snapshot, now: now, deviceTimeZone: TimeZone.current)
        WidgetSnapshotReader.recordRead(read, now: now, entries: plan.entries.count)
        completion(Timeline(entries: Self.entries(snapshot: read.snapshot, plan: plan), policy: .after(plan.reloadDate)))
    }

    // MARK: Building entries

    static func entries(snapshot: WidgetSnapshot?, now: Date) -> [NowNextEntry] {
        entries(snapshot: snapshot, plan: WidgetTimelinePlanner.plan(snapshot: snapshot, now: now,
                                                                     deviceTimeZone: TimeZone.current))
    }

    static func entries(snapshot: WidgetSnapshot?, plan: NowNextTimelinePlan) -> [NowNextEntry] {
        let context = plan.context ?? CalendarContext(timeZone: TimeZone.current, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context,
                                                 lookup: WidgetSnapshotReader.lookup(language: snapshot?.languageCode))
        let presenter = NowNextPresenter(renderer: renderer, context: context)
        let pro = presenter.proTexts()
        return plan.entries.map { entry in
            NowNextEntry(date: entry.date, display: presenter.display(entry), tier: snapshot?.tier,
                         proTitle: pro.title, proShort: pro.short)
        }
    }

    /// A tiny "during a lesson" sample around now (placeholder / gallery preview), in the device language. Built by
    /// hand (`WidgetGallerySamples.previewSnapshot`), not from the seeded database, to stay within the extension's
    /// memory limit; its live timers run because the lesson is placed around `Date()`.
    static func sampleEntry() -> NowNextEntry {
        NSTimeZone.resetSystemTimeZone()
        let now = Date()
        let language = Bundle.main.preferredLocalizations.first
        let lookup = WidgetSnapshotReader.lookup(language: language)
        let snapshot = WidgetGallerySamples.previewSnapshot(now: now, timeZone: TimeZone.current,
                                                            localeID: Locale.current.identifier, languageCode: language,
                                                            name: lookup)
        let plan = WidgetTimelinePlanner.plan(snapshot: snapshot, now: now, deviceTimeZone: TimeZone.current)
        return entries(snapshot: snapshot, plan: plan)[0]
    }
}

struct NowNextWidget: Widget {
    static let kind = "sk.simondev.tabula.widget.nowNext"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowNextProvider()) { entry in
            NowNextEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(ItemLinkURL.url(for: entry.display.link))
        }
        // Widget gallery strings are user-visible: they come from the String Catalog.
        .configurationDisplayName("widget.nowNext.name")
        .description("widget.nowNext.description")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NowNextEntryView: View {
    let entry: NowNextEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let family = Self.kind(of: widgetFamily)
        let decision = entry.tier.map { WidgetProGate.decision(for: family, tier: $0) } ?? .allowed
        if decision == .allowed {
            NowNextWidgetView(display: entry.display, family: family)
        } else {
            WidgetProPlaceholderView(family: family, title: entry.proTitle, short: entry.proShort)
        }
    }

    /// Our family for WidgetKit's. Not a `switch`: the iOS 27 SDK adds `systemExtraLargePortrait` (iOS 27 only) and the
    /// watch-only `accessoryCorner`, which an iOS 26 target can neither match nor leave out without a warning. Families
    /// this widget does not list in `supportedFamilies` are never requested.
    static func kind(of family: WidgetFamily) -> WidgetFamilyKind {
        let known: [(WidgetFamily, WidgetFamilyKind)] = [
            (.systemSmall, .systemSmall), (.systemMedium, .systemMedium), (.systemLarge, .systemLarge),
            (.systemExtraLarge, .systemExtraLarge), (.accessoryCircular, .accessoryCircular),
            (.accessoryRectangular, .accessoryRectangular), (.accessoryInline, .accessoryInline),
        ]
        return known.first { $0.0 == family }?.1 ?? .systemSmall
    }
}
