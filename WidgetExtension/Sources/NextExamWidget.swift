// *Next exam* widget (PHASE4_PLAN §0.3, Stage B1): subject, title, date, time and room of the next exam with a countdown
// that escalates ("in 9 days" → "Tomorrow" → "Today, 10:00" + a live `Text(timerInterval:)` to the start → "In progress"
// → "Finished") and an icon per level. systemSmall (free) + accessoryRectangular / accessoryCircular (`.lockScreenWidgets`,
// Pro, gated by `WidgetProGate`). Tap: `widgetURL(tabula://open/exam/<id>)`; empty state: "No Upcoming Exams".
// A `StaticConfiguration` (no App Intents in this stage; RISKS #19).
//
// Data flow as Now & Next: `WidgetSnapshotReader` → `ExamPlanner.plan` (entries at midnights up to the exam day and at the
// exam's start / end, ≤ 29, reload ≤ 6 h) → `ExamPresenter` → `NextExamWidgetView` (TimetableUI). The live countdown is
// never a timeline entry per second: the system ticks `Text(timerInterval:)`.
import Foundation
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

struct NextExamEntry: TimelineEntry, Sendable {
    let date: Date
    let display: ExamDisplay
    let tier: Tier?
    let proTitle: String
    let proShort: String
}

struct NextExamProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextExamEntry {
        Self.sampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextExamEntry) -> Void) {
        NSTimeZone.resetSystemTimeZone()   // RISKS #67
        let read = WidgetSnapshotReader.read()
        let entries = Self.entries(snapshot: read.snapshot, now: Date())
        if context.isPreview, case .unavailable = entries[0].display.kind {
            completion(Self.sampleEntry())
        } else {
            completion(entries[0])
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextExamEntry>) -> Void) {
        NSTimeZone.resetSystemTimeZone()
        let read = WidgetSnapshotReader.read()
        let now = Date()
        let plan = ExamPlanner.plan(snapshot: read.snapshot, now: now, deviceTimeZone: TimeZone.current)
        WidgetSnapshotReader.recordRead(read, now: now, entries: plan.entries.count, widget: "Next exam")
        completion(Timeline(entries: Self.entries(snapshot: read.snapshot, plan: plan), policy: .after(plan.reloadDate)))
    }

    static func entries(snapshot: WidgetSnapshot?, now: Date) -> [NextExamEntry] {
        entries(snapshot: snapshot, plan: ExamPlanner.plan(snapshot: snapshot, now: now, deviceTimeZone: TimeZone.current))
    }

    static func entries(snapshot: WidgetSnapshot?, plan: WidgetStatePlan<ExamState>) -> [NextExamEntry] {
        let context = plan.context ?? CalendarContext(timeZone: TimeZone.current, firstWeekday: .monday)
        let renderer = NowNextPresenter.renderer(for: snapshot, context: context,
                                                 lookup: WidgetSnapshotReader.lookup(language: snapshot?.languageCode))
        let presenter = ExamPresenter(renderer: renderer, context: context)
        let pro = presenter.proTexts()
        return plan.entries.map { entry in
            NextExamEntry(date: entry.date, display: presenter.display(entry), tier: snapshot?.tier,
                          proTitle: pro.title, proShort: pro.short)
        }
    }

    /// A sample exam in five days (placeholder / gallery preview), see `NowNextProvider.sampleEntry`.
    static func sampleEntry() -> NextExamEntry {
        NSTimeZone.resetSystemTimeZone()
        let now = Date()
        let language = Bundle.main.preferredLocalizations.first
        let snapshot = WidgetGallerySamples.previewSnapshot(now: now, timeZone: TimeZone.current,
                                                            localeID: Locale.current.identifier, languageCode: language,
                                                            name: WidgetSnapshotReader.lookup(language: language))
        return entries(snapshot: snapshot, now: now)[0]
    }
}

struct NextExamWidget: Widget {
    static let kind = "sk.simondev.tabula.widget.nextExam"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextExamProvider()) { entry in
            NextExamEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("widget.exam.name")
        .description("widget.exam.description")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct NextExamEntryView: View {
    let entry: NextExamEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        let family = NowNextEntryView.kind(of: widgetFamily)
        let decision = entry.tier.map { WidgetProGate.decision(for: family, tier: $0) } ?? .allowed
        if decision == .allowed {
            NextExamWidgetView(display: entry.display, family: family)
                .widgetURL(ItemLinkURL.url(for: entry.display.link))
        } else {
            // A gated placeholder taps to the Today tab (as Homework), not to an exam the user cannot see here.
            WidgetProPlaceholderView(family: family, title: entry.proTitle, short: entry.proShort)
                .widgetURL(ItemLinkURL.url(for: .today))
        }
    }
}
