// DEBUG-only widget gallery (PHASE4_PLAN §0.10): the simulator cannot screenshot Home Screen or Lock Screen widgets, so
// these routes render the real widget views (TimetableUI `NowNextWidgetView`, the same code the extension runs) at the
// exact family sizes of a 430×932 pt iPhone (Apple HIG widget size table; the closest documented size to the
// 440×956 pt iPhone 16/17 Pro Max) from the seeded secondary timetable at fixed instants (`WidgetGallerySamples`).
//
//   widgets.gallery          during a lesson + in a break
//   widgets.gallery-evening  after school + a holiday
//   widgets.gallery-pro      Pro placeholders (free tier, Lock Screen families) + the "Open Tabula" states
// Two scenes per route so each fits one screenshot (simctl cannot scroll). Timers are paused at the scene's instant.
// Accessory families are drawn on a dark rounded rectangle like the Lock Screen; the system's accented / vibrant
// rendering cannot be produced inside an app (`widgetRenderingMode` is read-only), so it stays a device check.
// Strings are verbatim developer labels (DEBUG only, not shipped); widget content uses the app's catalog.
#if DEBUG
import SwiftUI
import TimetableCore
import TimetableUI

/// Widget family point sizes (HIG, 430×932 pt screen).
enum WidgetGallerySize {
    static func size(_ family: WidgetFamilyKind) -> CGSize {
        switch family {
        case .systemSmall: return CGSize(width: 170, height: 170)
        case .systemMedium: return CGSize(width: 364, height: 170)
        case .systemLarge, .systemExtraLarge: return CGSize(width: 364, height: 382)
        case .accessoryCircular: return CGSize(width: 76, height: 76)
        case .accessoryRectangular: return CGSize(width: 172, height: 76)
        case .accessoryInline: return CGSize(width: 257, height: 26)
        }
    }
}

struct WidgetGalleryScreen: View {
    enum Page: Sendable { case daytime, evening, pro }

    let page: Page
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch page {
                case .daytime:
                    ForEach(scenes.filter { ["lesson", "break"].contains($0.id) }) { scene($0) }
                case .evening:
                    ForEach(scenes.filter { ["after", "holiday"].contains($0.id) }) { scene($0) }
                case .pro:
                    proPage
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.gray.opacity(0.18))
        .toolbar(.hidden, for: .navigationBar)
    }

    private var scenes: [WidgetGalleryScene] {
        WidgetGallerySamples.scenes(locale: model.formatter.locale,
                                    languageCode: Bundle.main.preferredLocalizations.first)
    }

    private func presenter(for snapshot: WidgetSnapshot?, context: CalendarContext) -> NowNextPresenter {
        NowNextPresenter(renderer: NowNextPresenter.renderer(for: snapshot, context: context,
                                                             lookup: model.environment.catalogLookup),
                         context: context)
    }

    private func display(_ scene: WidgetGalleryScene) -> NowNextDisplay {
        let plan = WidgetTimelinePlanner.plan(snapshot: scene.snapshot, now: scene.date,
                                              deviceTimeZone: WidgetGallerySamples.context.timeZone)
        let context = plan.context ?? WidgetGallerySamples.context
        return presenter(for: scene.snapshot, context: context).display(plan.entries[0])
    }

    // MARK: Scenes

    private func scene(_ scene: WidgetGalleryScene) -> some View {
        let shown = display(scene)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "\(scene.title) · \(scene.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                home(.systemSmall) { NowNextWidgetView(display: shown, family: .systemSmall, pauseTime: scene.date) }
                VStack(alignment: .leading, spacing: 8) {
                    lock(.accessoryRectangular) {
                        NowNextWidgetView(display: shown, family: .accessoryRectangular, pauseTime: scene.date)
                    }
                    lock(.accessoryCircular) {
                        NowNextWidgetView(display: shown, family: .accessoryCircular, pauseTime: scene.date)
                    }
                }
            }
            home(.systemMedium) { NowNextWidgetView(display: shown, family: .systemMedium, pauseTime: scene.date) }
            lock(.accessoryInline) {
                NowNextWidgetView(display: shown, family: .accessoryInline, pauseTime: scene.date)
            }
        }
    }

    // MARK: Pro + unavailable

    private var proPage: some View {
        let context = WidgetGallerySamples.context
        let texts = presenter(for: nil, context: context).proTexts()
        let free = WidgetGallerySamples.scenes(locale: model.formatter.locale,
                                               languageCode: Bundle.main.preferredLocalizations.first, tier: .free)[0]
        let freeDisplay = display(free)
        let unavailable: [NowNextState.Unavailable] = [.noSnapshot, .noTimetable, .outdated]
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Free tier: small stays, Lock Screen families gated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                home(.systemSmall) {
                    gated(.systemSmall, tier: free.snapshot.tier, texts: texts) {
                        NowNextWidgetView(display: freeDisplay, family: .systemSmall, pauseTime: free.date)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    lock(.accessoryRectangular) {
                        gated(.accessoryRectangular, tier: free.snapshot.tier, texts: texts) {
                            NowNextWidgetView(display: freeDisplay, family: .accessoryRectangular, pauseTime: free.date)
                        }
                    }
                    lock(.accessoryCircular) {
                        gated(.accessoryCircular, tier: free.snapshot.tier, texts: texts) {
                            NowNextWidgetView(display: freeDisplay, family: .accessoryCircular, pauseTime: free.date)
                        }
                    }
                }
            }
            lock(.accessoryInline) {
                gated(.accessoryInline, tier: free.snapshot.tier, texts: texts) {
                    NowNextWidgetView(display: freeDisplay, family: .accessoryInline, pauseTime: free.date)
                }
            }
            Text(verbatim: "Open Tabula: no snapshot · no timetable · outdated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(unavailable.prefix(2).enumerated()), id: \.offset) { _, reason in
                    home(.systemSmall) {
                        NowNextWidgetView(display: unavailableDisplay(reason, context: context), family: .systemSmall)
                    }
                }
            }
            lock(.accessoryRectangular) {
                NowNextWidgetView(display: unavailableDisplay(.outdated, context: context), family: .accessoryRectangular)
            }
        }
    }

    private func unavailableDisplay(_ reason: NowNextState.Unavailable, context: CalendarContext) -> NowNextDisplay {
        presenter(for: nil, context: context)
            .display(NowNextTimelineEntry(date: SampleScenarios.referenceNow, state: .unavailable(reason)))
    }

    @ViewBuilder
    private func gated<Content: View>(_ family: WidgetFamilyKind, tier: Tier, texts: (title: String, short: String),
                                      @ViewBuilder content: () -> Content) -> some View {
        if WidgetProGate.decision(for: family, tier: tier) == .allowed {
            content()
        } else {
            WidgetProPlaceholderView(family: family, title: texts.title, short: texts.short)
        }
    }

    // MARK: Frames

    /// A Home Screen widget frame: system background, 16 pt content margins, continuous corners.
    private func home<Content: View>(_ family: WidgetFamilyKind, @ViewBuilder content: () -> Content) -> some View {
        let size = WidgetGallerySize.size(family)
        return content()
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.background))
    }

    /// A Lock Screen accessory frame: dark backdrop, white content.
    private func lock<Content: View>(_ family: WidgetFamilyKind, @ViewBuilder content: () -> Content) -> some View {
        let size = WidgetGallerySize.size(family)
        return content()
            .padding(family == .accessoryInline ? 2 : 4)
            .frame(width: size.width, height: size.height)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .background(RoundedRectangle(cornerRadius: family == .accessoryCircular ? 38 : 12, style: .continuous)
                .fill(Color(white: 0.12)))
    }
}
#endif // DEBUG
