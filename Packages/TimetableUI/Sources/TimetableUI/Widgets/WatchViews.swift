// The watch app's one screen (Phase 5 W1): lays out a `WatchDisplay` (WatchPresentation.swift, Linux-tested) with the
// widget views, so the watch, the widgets and the Today tab use the same words, NowMarker and tokens. Lives in
// TimetableUI because it reuses internal widget views (`TodayLessonRow`); type-checked for watchOS by
// scripts/watch-typecheck.sh.
//
// HIG (apple-design skill, references/hig/widgets.md › "Widget sizes" table: accessory families are watch
// complications and Smart Stack widgets; › "Rendering modes": "Convey meaning without relying on specific colors"):
// the current lesson and its remaining time come first and largest (the Now & Next small-widget column: big rounded
// monospaced countdown with its unit word, U7 H2), then a plain List of the lessons still to come today and tomorrow.
// Meaning is carried by words and the NOW marker, never by the subject colour alone.
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

/// The watch app's screen.
public struct WatchHomeView: View {
    private let display: WatchDisplay

    public init(display: WatchDisplay) {
        self.display = display
    }

    public var body: some View {
        NavigationStack {   // PHASE5_PLAN decision 3; the title is the app name, not translated
            list.navigationTitle(Text(verbatim: "Tabula"))
        }
    }

    private var list: some View {
        List {
            switch display.kind {
            case let .openPhone(title, detail):
                WatchMessage(symbol: .date, title: title, detail: detail)
            case let .pro(title):
                WatchMessage(symbol: .proLocked, title: title, detail: nil)
            case let .content(nowNext, today, tomorrow):
                Section {
                    NowNextWidgetView(display: nowNext, family: .systemSmall)
                        .padding(.vertical, 4)
                }
                if let today { WatchDaySection(day: today) }
                if let tomorrow, !tomorrow.rows.isEmpty { WatchDaySection(day: tomorrow) }
            }
        }
    }
}

private struct WatchMessage: View {
    let symbol: AppSymbol
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(symbol)
                .font(.title3)
                .foregroundStyle(Color.ink)
                .accessibilityHidden(true)
            Text(verbatim: title).font(.headline)
            if let detail {
                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WatchDaySection: View {
    let day: TodayDisplay.Day

    var body: some View {
        Section {
            ForEach(day.rows) { row in
                TodayLessonRow(row: row)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: row.spoken))
            }
        } header: {
            // Two texts, not one concatenated string (CLAUDE.md: never concatenate translated fragments).
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: day.header)
                Spacer(minLength: 4)
                Text(verbatim: day.dateText).lineLimit(1)
            }
        }
    }
}
#endif
