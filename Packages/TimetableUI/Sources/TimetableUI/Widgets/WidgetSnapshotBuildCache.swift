// One widget snapshot build per change (Phase 10 WP2, P3 / C2). The Live Activity controller (600 ms debounce) and the
// widget writer (800 ms) both react to every `AppModel.onChange`; before Phase 10 each built the identical snapshot on
// the main actor. Both now ask one cache (App/Sources/Widgets/WidgetSnapshotSource.swift), which builds again only when
// an input of the build changed. Pure, Linux-tested.
//
// Key = everything `WidgetSnapshotBuilder.build` reads: the database (Equatable; arrays that did not change compare by
// buffer identity, so a hit is cheap), the calendar context, the tier, the locale identifier, the UI language, and
// `now` to the minute. The builder reads `now` only as the local date and minute (`CalendarContext.local(from:)` has
// minute precision) and in "exam end > now", where the end is a whole minute; so every instant of one UTC minute gives
// the same content in zones with whole-minute offsets (every current zone). The key holds the UTC minute AND the local
// date-time, so a local minute that repeats (DST fall-back) is a new key. Resolvers are not part of the key: they are
// derived from the database and the context, and the builder ignores one that does not match.
// A reused build keeps the first caller's `generatedAt` (same minute; diagnostics only, never used to decide what to
// show; the writer compares `contentOnly`).
import Foundation
import TimetableCore

public struct WidgetSnapshotBuildCache: Sendable {
    struct Key: Equatable, Sendable {
        let database: TabulaDatabase?
        let context: CalendarContext
        let tier: Tier
        let localeID: String
        let languageCode: String?
        let minute: Int64
        let local: LocalDateTime

        init(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier, locale: Locale,
             languageCode: String?) {
            self.database = database
            self.context = context
            self.tier = tier
            localeID = locale.identifier
            self.languageCode = languageCode
            let seconds = now.timeIntervalSince1970
            minute = seconds.isFinite && abs(seconds) < 1e15 ? Int64((seconds / 60).rounded(.down)) : 0
            local = context.local(from: now)
        }
    }

    private var last: (key: Key, build: WidgetSnapshotBuild)?
    /// How many builds ran (tests and the developer screen).
    public private(set) var buildCount = 0

    public init() {}

    /// The build for these inputs: the cached one when nothing the builder reads changed, else a new one.
    /// `resolvers`: `AppModel.resolvers` (built from `database` in `context`).
    public mutating func build(database: TabulaDatabase?, now: Date, context: CalendarContext, tier: Tier, locale: Locale,
                               languageCode: String?,
                               resolvers: [Timetable.ID: ScheduleResolver]?) -> WidgetSnapshotBuild {
        let key = Key(database: database, now: now, context: context, tier: tier, locale: locale,
                      languageCode: languageCode)
        if let last, last.key == key { return last.build }
        let build = WidgetSnapshotBuilder.build(database: database, now: now, context: context, tier: tier, locale: locale,
                                                languageCode: languageCode, resolvers: resolvers)
        last = (key, build)
        buildCount += 1
        return build
    }
}
