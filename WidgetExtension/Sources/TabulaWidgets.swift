// Widget extension (target/product `TabulaWidgets`). COMPILED 2026-10-06 (xtool path, base + macro variants, 0 warnings; XcodeGen CI run 37449454629).
// xtool packs this as a Foundation NSExtension (PlugIns/TabulaWidgets.appex, entry point
// _NSExtensionMain); ExtensionKit-style extensions are NOT supported by xtool (issue #138).
// APIs (docs checked): WidgetBundle, Widget, StaticConfiguration, TimelineProvider
//   (placeholder/getSnapshot/getTimeline with @Sendable completions), Timeline(entries:policy:),
//   TimelineEntry, containerBackground(_:for:) iOS 17, Text(timerInterval:pauseTime:countsDown:showsHours:),
//   supportedFamilies(_:), configurationDisplayName(_:), description(_:).
import SwiftUI
import TimetableCore
import TimetableUI
import WidgetKit

@main
struct TabulaWidgetBundle: WidgetBundle {
    var body: some Widget {
        Phase0HelloWidget()
        // Owned by the notifications agent (WidgetExtension/Sources/AlarmLiveActivity.swift).
        AlarmLiveActivity()
    }
}

// MARK: - Phase 0 hello widget: reads the App Group value written by the app

struct Phase0Entry: TimelineEntry {
    let date: Date
    let appGroupID: String
    let valueFromApp: String
    let containerAvailable: Bool
}

struct Phase0Provider: TimelineProvider {
    func placeholder(in context: Context) -> Phase0Entry {
        Phase0Entry(date: .now, appGroupID: "…", valueFromApp: "placeholder", containerAvailable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (Phase0Entry) -> Void) {
        completion(Self.readEntry(writeBack: false))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Phase0Entry>) -> Void) {
        let entry = Self.readEntry(writeBack: true)
        // One entry, refresh hourly. The app calls WidgetCenter.reloadAllTimelines() after writing.
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(3600))))
    }

    /// Reads what the app wrote and (for real timelines) writes back what the widget saw, so the
    /// app's debug screen can prove the extension -> app direction too.
    static func readEntry(writeBack: Bool) -> Phase0Entry {
        let groupID = AppGroup.identifier(forBundleIdentifier: Bundle.main.bundleIdentifier)
        let containerAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
        let defaults = UserDefaults(suiteName: groupID)
        let value = defaults?.string(forKey: Phase0ProbeKeys.appWrite) ?? "no value from app yet"
        let now = Date.now
        if writeBack {
            defaults?.set("\(value) @ \(now.ISO8601Format())", forKey: Phase0ProbeKeys.widgetSaw)
        }
        return Phase0Entry(date: now, appGroupID: groupID, valueFromApp: value, containerAvailable: containerAvailable)
    }
}

struct Phase0HelloWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sk.simondev.tabula.phase0.hello", provider: Phase0Provider()) { entry in
            Phase0WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        // Widget gallery strings are user-visible: they come from the String Catalog.
        // String literals resolve to the LocalizedStringKey overloads (Xcode template usage).
        .configurationDisplayName("probe.widget.name")
        .description("probe.widget.description")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Phase0WidgetView: View {
    let entry: Phase0Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Tabula · Phase 0")
                .font(.caption.weight(.semibold))
            Text(verbatim: entry.containerAvailable ? "App Group: OK" : "App Group: MISSING")
                .font(.caption2)
            Text(verbatim: entry.valueFromApp)
                .font(.caption2.monospaced())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            // Live countdown rendered by the system without timeline reloads.
            Text(timerInterval: entry.date...entry.date.addingTimeInterval(3600), countsDown: true)
                .font(.caption.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
