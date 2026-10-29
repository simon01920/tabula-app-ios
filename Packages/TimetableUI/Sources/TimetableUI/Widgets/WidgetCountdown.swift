// Presentation of a widget / Live Activity countdown (Phase 4U U7, finding H2 "25:00 is ambiguous"), shared by the
// Now & Next widget, the Next exam widget and both Live Activities. Pure, Linux-tested; the views
// (`WidgetCountdownText`, WidgetIdentity.swift) only lay it out.
//
// Rules (H2):
//   - A countdown always carries a unit word ("left" while something runs, "until start" before it), never a bare
//     "25:00" that reads as a clock time.
//   - Under 60 minutes remaining the value is the live system timer (`Text(timerInterval:)`, the system keeps it
//     counting without timeline entries); at 60 minutes or more it is minutes only, "1 h 30 min", no seconds
//     (`Text(date, style: .relative)` live, the static `durationText` where a live value cannot be shown).
//   - Exam countdowns never show seconds: they are always in the minutes mode.
// Durations come from the catalog (`widget.duration.*`, abbreviated units), never from concatenated fragments, so the
// words follow the app's language in every family; the unit words and the sentence forms are catalog keys too.
import Foundation
import TimetableCore

/// One countdown, ready for a view.
public struct WidgetCountdown: Equatable, Sendable {
    /// How the value is shown.
    public enum Mode: Equatable, Sendable {
        /// Live `mm:ss` / `h:mm:ss` system timer (under `timerLimit` remaining, lessons only).
        case timer
        /// Minutes only ("25 min", "1 h 30 min"), no seconds.
        case minutes
    }

    /// What the countdown counts to.
    public enum Kind: Equatable, Sendable {
        /// To the end of something in progress ("left").
        case left
        /// To the start of something ("until start").
        case untilStart
    }

    /// Remaining time at or above which the minutes mode is used.
    public static let timerLimit: TimeInterval = 3600

    public var mode: Mode
    public var kind: Kind
    /// Start…target. `upperBound` is the target; the live timer counts `lowerBound…upperBound` down.
    public var interval: ClosedRange<Date>
    /// "left" / "until start" (the unit word shown beside the value).
    public var unitLabel: String
    /// "25 min" / "1 h 30 min" at the instant the presenter ran (rounded up to a whole minute).
    public var durationText: String
    /// One phrase for static text and VoiceOver: "25 min left" / "in 1 h 30 min".
    public var phrase: String
}

/// Builds `WidgetCountdown` values.
public struct WidgetCountdownBuilder: Sendable {
    public let renderer: LocalizedTextRenderer

    public init(renderer: LocalizedTextRenderer) {
        self.renderer = renderer
    }

    /// The countdown of `interval` at `now`. `allowsSeconds: false` (exams) always uses the minutes mode.
    public func make(interval: ClosedRange<Date>, now: Date, kind: WidgetCountdown.Kind,
                     allowsSeconds: Bool) -> WidgetCountdown {
        let remaining = max(0, interval.upperBound.timeIntervalSince(max(now, interval.lowerBound)))
        let mode: WidgetCountdown.Mode = allowsSeconds && remaining < WidgetCountdown.timerLimit ? .timer : .minutes
        let duration = durationText(remaining)
        let unit = renderer.string(forKey: kind == .left ? "widget.countdown.left" : "widget.countdown.untilStart")
        let phrase = renderer.format(key: kind == .left ? "widget.countdown.leftPhrase" : "widget.countdown.inPhrase",
                                     arguments: [.text(duration)])
        return WidgetCountdown(mode: mode, kind: kind, interval: interval, unitLabel: unit, durationText: duration,
                               phrase: phrase)
    }

    /// "5 min", "1 h", "1 h 30 min": whole minutes rounded up (a lesson with 20 s left still has "1 min"), no seconds.
    public func durationText(_ remaining: TimeInterval) -> String {
        let minutes = max(0, Int((remaining / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return renderer.format(key: "widget.duration.min", arguments: [.integer(Int64(rest))]) }
        if rest == 0 { return renderer.format(key: "widget.duration.h", arguments: [.integer(Int64(hours))]) }
        return renderer.format(key: "widget.duration.hm", arguments: [.integer(Int64(hours)), .integer(Int64(rest))])
    }
}

/// Short subject names for the Lock Screen (finding M29: "25 min · SJL" instead of "Slovenský jazyk a literatúra").
public enum SubjectAbbreviation {
    /// Longest derived abbreviation.
    public static let maxLength = 3

    /// The subject's short name when it has one, else letters derived from its name: the initials of its words
    /// (words of one or two letters, such as "a" or "of", skipped; "Slovenský jazyk a literatúra" → "SJL"), or the first
    /// three letters of a single word ("Mathematics" → "MAT"); upper-cased, at most `maxLength` letters.
    public static func short(for subject: SubjectSummary) -> String {
        if let short = subject.shortName?.trimmingCharacters(in: .whitespacesAndNewlines), !short.isEmpty { return short }
        return derived(from: subject.name)
    }

    /// The derived abbreviation of `name` (see `short(for:)`).
    public static func derived(from name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty else { return "" }
        if words.count == 1 { return String(words[0].prefix(maxLength)).uppercased() }
        let significant = words.filter { $0.count > 2 }
        let source = significant.isEmpty ? words : significant
        if source.count == 1 { return String(source[0].prefix(maxLength)).uppercased() }
        return String(source.compactMap(\.first).prefix(maxLength)).uppercased()
    }
}
