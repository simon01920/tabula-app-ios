// *Homework* widget (PHASE4_PLAN §0.3, Stage B1): open tasks from the snapshot, overdue first and then due soonest, with
// subject badge, due text and a non-colour overdue mark; small = the count and the top task, medium = 3 rows, large = 9
// (a Pro family). Each medium / large row is a `Link` to `tabula://open/task/<id>`; the small family and the empty /
// "Open Tabula" states use `widgetURL`. A `StaticConfiguration` (no App Intents in this stage; RISKS #19).
//
// CHECKBOX SEAM (Stage B3): `HomeworkEntryView.checkbox(for:)` returns the view placed before each medium / large row,
// outside the row's `Link`. It is empty here; B3 returns `Button(intent: MarkDoneIntent(taskID: line.id)) { … }` (and
// keeps the empty view on builds without App Intent metadata, where the row's link stays the fallback).
//
// Data flow as Now & Next: `WidgetSnapshotReader` → `HomeworkPlanner.plan` (entries at midnights and one minute after
// each due time, ≤ 29, reload ≤ 6 h) → `HomeworkPresenter` → `HomeworkWidgetView` (TimetableUI).
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

struct HomeworkEntry: TimelineEntry, Sendable {
    let date: Date
    let display: HomeworkDisplay
    let tier: Tier?
    let proTitle: String
    let proShort: String
}

struct HomeworkProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeworkEntry {
        Self.sampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (HomeworkEntry) -> Void) {
        NSTimeZone.resetSystemTimeZone()   // RISKS #67
        let read = WidgetSnapshotReader.read()
        let entries = Self.entries(snapshot: read.snapshot, now: Date())
        if context.isPreview, case .unavailable = entries[0].display.kind {
            completion(Self.sampleEntry())
        } else {
            completion(entries[0])
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HomeworkEntry>) -> Void) {
        NSTimeZone.resetSystemTimeZone()
        let read = WidgetSnapshotReader.read()
        let now = Date()
        let plan = HomeworkPlanner.plan(snapshot: read.snapshot, now: now, deviceTimeZone: TimeZone.current)
        WidgetSnapshotReader.recordRead(read, now: now, entries: plan.entries.count, widget: "Homework")
        completion(Timeline(entries: Self.entries(snapshot: read.snapshot, plan: plan), policy: .after(plan.reloadDate)))
    }

    static func entries(snapshot: WidgetSnapshot?, now: Date) -> [HomeworkEntry] {
        entries(snapshot: snapshot, plan: HomeworkPlanner.plan(snapshot: snapshot, now: now, deviceTimeZone: TimeZone.current))
    }

    static func entries(snapshot: WidgetSnapshot?, plan: WidgetStatePlan<HomeworkState>) -> [HomeworkEntry] {
        let context = plan.context ?? CalendarContext(timeZone: TimeZone.current, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context,
                                                 lookup: WidgetSnapshotReader.lookup(language: snapshot?.languageCode))
        let presenter = HomeworkPresenter(renderer: renderer, context: context)
        let pro = presenter.proTexts()
        return plan.entries.map { entry in
            HomeworkEntry(date: entry.date, display: presenter.display(entry), tier: snapshot?.tier,
                          proTitle: pro.title, proShort: pro.short)
        }
    }

    /// Two sample tasks around now (placeholder / gallery preview), see `NowNextProvider.sampleEntry`.
    static func sampleEntry() -> HomeworkEntry {
        NSTimeZone.resetSystemTimeZone()
        let now = Date()
        let language = Bundle.main.preferredLocalizations.first
        let snapshot = WidgetGallerySamples.previewSnapshot(now: now, timeZone: TimeZone.current,
                                                            localeID: Locale.current.identifier, languageCode: language,
                                                            name: WidgetSnapshotReader.lookup(language: language))
        return entries(snapshot: snapshot, now: now)[0]
    }
}

struct HomeworkWidget: Widget {
    static let kind = "sk.simondev.tabula.widget.homework"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HomeworkProvider()) { entry in
            HomeworkEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("widget.homework.name")
        .description("widget.homework.description")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct HomeworkEntryView: View {
    let entry: HomeworkEntry
    @Environment(\.widgetFamily) private var widgetFamily

    /// Medium / large task rows carry their own `Link`s; everything else is one tap target.
    private var rowsAreLinks: Bool {
        if case .tasks = entry.display.kind { return widgetFamily != .systemSmall }
        return false
    }

    var body: some View {
        let family = NowNextEntryView.kind(of: widgetFamily)
        let decision = entry.tier.map { WidgetProGate.decision(for: family, tier: $0) } ?? .allowed
        if decision != .allowed {
            WidgetProPlaceholderView(family: family, title: entry.proTitle, short: entry.proShort)
                .widgetURL(ItemLinkURL.url(for: .today))
        } else if rowsAreLinks {
            HomeworkWidgetView(display: entry.display, family: family) { line in Self.checkbox(for: line) }
        } else {
            HomeworkWidgetView(display: entry.display, family: family) { line in Self.checkbox(for: line) }
                .widgetURL(ItemLinkURL.url(for: entry.display.link))
        }
    }

    /// The checkbox seam (see the file header): nothing until Stage B3.
    @ViewBuilder
    static func checkbox(for line: HomeworkDisplay.TaskLine) -> some View {
        EmptyView()
    }
}
