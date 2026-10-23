// Live Activity data (PHASE4_PLAN §0.5, Stage B2): the static attributes and the dynamic `ContentState` of the two
// Live Activities — (a) the current lesson, (b) exam day (decision P3-6). Shared by the app (which starts, updates and
// ends them with ActivityKit, App/Sources/Widgets/LiveActivityController.swift) and the widget extension (which renders
// them, WidgetExtension/Sources/*LiveActivity.swift). ActivityKit matches activities by the attributes TYPE, so both
// targets must use these exact types: they live in TimetableUI, which both link on both build paths.
//
// Pure Foundation + TimetableCore so the planner and the 4 KB size budget are Linux-tested; the `ActivityAttributes`
// conformance is added at the bottom only where ActivityKit exists (iOS; not watchOS, macOS or Linux).
//
// Instants, not wall-clock values: unlike the widget snapshot, the content carries precomputed `Date`s plus the zone
// (`LiveActivityStyle.timeZoneID`, for formatting only). The app re-plans and updates on every time-zone change
// (AppModel `.environment`), so the instants follow "follow device" timetables while the app runs; a zone change
// while the app is not running keeps the old instants until the next foreground / background refresh (RISKS).
//
// Size: "Static and dynamic data for a Live Activity … can't exceed a combined size of 4 KB" (Apple, ENVIRONMENT §31).
// User text is cut (`LiveActivityLimits`) and a lesson day carries at most `maxLessons` lessons; tests assert the
// worst case (every field at its maximum, 4-byte characters) stays under `LiveActivityLimits.maxEncodedBytes`.
//
// Keep the coding keys stable: an activity started by one app version may be updated or rendered by the next one.
// New fields must be optional.
import Foundation
import TimetableCore

/// Text and count limits that keep attributes + content state far below ActivityKit's 4 KB.
public enum LiveActivityLimits {
    /// Lessons carried by one lesson state (the first ones of the day; a school day rarely has more).
    public static let maxLessons = 10
    /// Subject name / exam title (characters).
    public static let maxTitleLength = 48
    /// Subject short name (characters).
    public static let maxShortNameLength = 4
    /// Room (characters).
    public static let maxRoomLength = 10
    /// UTF-8 byte cap of a title (keeps ten names of 4-byte characters inside the 4 KB budget; Latin-script names of
    /// 48 characters are well below it).
    public static let maxTitleBytes = 112
    /// Emoji / SF Symbol name of a subject (characters; longer symbols are dropped).
    public static let maxSymbolLength = 30
    /// Our own budget for attributes + state (JSON); ActivityKit's limit is 4 096 bytes.
    public static let maxEncodedBytes = 3_600

    /// `text` cut to `limit` characters (whole grapheme clusters, the ellipsis included) and, if given, `maxBytes`
    /// UTF-8 bytes. A cut value ends with "\u{2026}" so it reads as shortened. `nil` when blank.
    public static func cut(_ text: String?, _ limit: Int, maxBytes: Int? = nil) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let ellipsis = "\u{2026}"
        if text.count <= limit, maxBytes.map({ text.utf8.count <= $0 }) ?? true { return text }
        guard limit > 1 else { return String(text.prefix(limit)) }
        var result = ""
        var bytes = 0
        let byteBudget = (maxBytes ?? Int.max) - ellipsis.utf8.count
        for character in text.prefix(limit - 1) {
            let size = String(character).utf8.count
            if bytes + size > byteBudget { break }
            result.append(character)
            bytes += size
        }
        return result.trimmingCharacters(in: .whitespaces) + ellipsis
    }
}

/// How the extension formats the content: the app's locale, UI language, 12/24 h preference and the zone the
/// instants are shown in. Rendering happens in the extension, in the app's language (like the widgets, RISKS #69).
public struct LiveActivityStyle: Codable, Hashable, Sendable {
    public var localeID: String
    public var languageCode: String?
    public var hourCycle: HourCycle
    public var timeZoneID: String

    enum CodingKeys: String, CodingKey { case localeID = "loc", languageCode = "lang", hourCycle = "hc", timeZoneID = "tz" }

    public init(localeID: String, languageCode: String?, hourCycle: HourCycle, timeZoneID: String) {
        self.localeID = localeID
        self.languageCode = languageCode
        self.hourCycle = hourCycle
        self.timeZoneID = timeZoneID
    }

    /// The zone (device zone if the identifier is unknown).
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone.current }
}

/// A subject as a Live Activity shows it (no ID: the badge needs only name, short name, colour and symbol).
public struct LiveActivitySubject: Codable, Hashable, Sendable {
    public var name: String
    public var shortName: String?
    public var color: ColorValue
    public var symbol: SubjectSymbol?

    enum CodingKeys: String, CodingKey { case name = "n", shortName = "sn", color = "c", symbol = "sy" }

    public init(name: String, shortName: String? = nil, color: ColorValue, symbol: SubjectSymbol? = nil) {
        self.name = name
        self.shortName = shortName
        self.color = color
        self.symbol = symbol
    }

    /// The summary cut to the Live Activity limits.
    public init(_ summary: SubjectSummary) {
        name = LiveActivityLimits.cut(summary.name, LiveActivityLimits.maxTitleLength,
                                      maxBytes: LiveActivityLimits.maxTitleBytes) ?? ""
        shortName = LiveActivityLimits.cut(summary.shortName, LiveActivityLimits.maxShortNameLength)
        color = summary.color
        switch summary.symbol {
        case .emoji(let value)?: symbol = value.count <= 2 ? .emoji(value) : nil
        case .systemImage(let value)?: symbol = value.count <= LiveActivityLimits.maxSymbolLength ? .systemImage(value) : nil
        case nil: symbol = nil
        }
    }

    /// A `SubjectSummary` for the shared badge views (fixed placeholder ID; never stored).
    public var summary: SubjectSummary {
        SubjectSummary(id: Subject.ID(LiveActivitySubject.placeholderID), name: name, shortName: shortName, color: color,
                       symbol: symbol)
    }

    static let placeholderID = UUID(uuidString: "00000000-0000-4000-8000-00000000AC71")!
}

/// One lesson of a lesson Live Activity.
public struct LiveActivityLesson: Codable, Hashable, Sendable {
    public var subject: LiveActivitySubject
    public var room: String?
    public var start: Date
    public var end: Date

    enum CodingKeys: String, CodingKey { case subject = "s", room = "r", start = "st", end = "et" }

    public init(subject: LiveActivitySubject, room: String?, start: Date, end: Date) {
        self.subject = subject
        self.room = room
        self.start = start
        self.end = max(start, end)
    }
}

/// (a) The current-lesson Live Activity. One per school day: the day is the static identity.
public struct LessonActivityAttributes: Codable, Hashable, Sendable {
    /// The school day this activity covers (`yyyy-MM-dd`).
    public var day: LocalDate

    enum CodingKeys: String, CodingKey { case day = "d" }

    public init(day: LocalDate) {
        self.day = day
    }

    /// The dynamic content.
    public struct ContentState: Codable, Hashable, Sendable {
        /// The day's lessons that take place, in start order (at most `LiveActivityLimits.maxLessons`). The remaining
        /// ones are `lessons[index...]`.
        public var lessons: [LiveActivityLesson]
        /// Index (in `lessons`) of the lesson in progress or, between lessons, of the next one at update time
        /// (`lessons.count` after the last one). Views compute the current lesson at render time from `lessons` and
        /// never go back before this index.
        public var index: Int
        /// The final content after the last lesson ("No more lessons today").
        public var isFinal: Bool
        /// Formatting.
        public var style: LiveActivityStyle

        enum CodingKeys: String, CodingKey { case lessons = "l", index = "i", isFinal = "f", style = "y" }

        public init(lessons: [LiveActivityLesson], index: Int, isFinal: Bool, style: LiveActivityStyle) {
            self.lessons = lessons
            self.index = index
            self.isFinal = isFinal
            self.style = style
        }
    }
}

/// (b) The exam-day Live Activity: one per exam (the exam's ID is the static identity).
public struct ExamActivityAttributes: Codable, Hashable, Sendable {
    /// `Exam.ID` raw UUID.
    public var examID: UUID

    enum CodingKeys: String, CodingKey { case examID = "id" }

    public init(examID: UUID) {
        self.examID = examID
    }

    /// The dynamic content (title, time and room can be edited while it runs).
    public struct ContentState: Codable, Hashable, Sendable {
        /// Exam title (user text, cut).
        public var title: String
        /// Subject, if any.
        public var subject: LiveActivitySubject?
        /// Room (field rule applied), if any.
        public var room: String?
        /// Start instant.
        public var start: Date
        /// End instant, if the exam has an end time.
        public var end: Date?
        /// The final content after the exam ("Exam finished").
        public var isFinal: Bool
        /// Formatting.
        public var style: LiveActivityStyle

        enum CodingKeys: String, CodingKey {
            case title = "t", subject = "s", room = "r", start = "st", end = "et", isFinal = "f", style = "y"
        }

        public init(title: String, subject: LiveActivitySubject?, room: String?, start: Date, end: Date?, isFinal: Bool,
                    style: LiveActivityStyle) {
            self.title = title
            self.subject = subject
            self.room = room
            self.start = start
            self.end = end.map { max(start, $0) }
            self.isFinal = isFinal
            self.style = style
        }

        /// When the activity's "in progress" phase ends: the end time, else `LiveActivityPolicy.examAssumedDuration`
        /// after the start.
        public var close: Date { end ?? start.addingTimeInterval(LiveActivityPolicy.examAssumedDuration) }
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

// The conformances ActivityKit needs (`protocol ActivityAttributes : Decodable, Encodable` with a
// `ContentState: Codable & Hashable`). Kept here, in the module both the app and the extension link.
extension LessonActivityAttributes: ActivityAttributes {}
extension ExamActivityAttributes: ActivityAttributes {}
#endif
