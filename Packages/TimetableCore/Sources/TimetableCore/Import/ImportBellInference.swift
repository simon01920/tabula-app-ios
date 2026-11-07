import Foundation

/// Period headers ("1", "7.00", "08:00–08:45", "8.00-8.45", "1. hod", "第3节") and bell-schedule inference.
enum ImportBellInference {
    struct Header: Hashable {
        var number: Int?
        var start: LocalTime?
        var end: LocalTime?
    }

    // "8h00" is French; "1:00 p.m." / "1:00PM" is 12-hour. Built once (Phase 10 C6); `nonisolated(unsafe)`
    // because `Regex` is not `Sendable` although it is safe to share for matching (see `ImportCellSplitter`).
    nonisolated(unsafe) private static let timePattern: Regex<(Substring, Substring, Substring, Substring?)> =
        /(\d{1,2})[:.h](\d{2})(?!\d)(?:\s?([AaPp])\.?\s?[Mm]\b\.?)?/
    /// Words that may accompany a period number; a cell of only these, numbers and times is a header, not a lesson.
    private static let periodWords: Set<String> = Set([
        "hod", "hodina", "h", "period", "lesson", "hour", "std", "stunde", "lekcja", "lekce", "lekc", "ora", "heure",
        "cours", "ura", "урок", "час", "пара", "节", "節", "限", "時限", "时", "第", "óra", "tiet",
    ].map(ImportText.fold))

    /// The times in `text`, in order, with their a.m./p.m. marker ("a", "p") when printed.
    private static func clockTimes(in text: String) -> [(hour: Int, minute: Int, meridiem: String?)] {
        text.matches(of: timePattern).compactMap { match in
            guard let hour = Int(match.output.1), let minute = Int(match.output.2) else { return nil }
            return (hour, minute, match.output.3.map { $0.lowercased() })
        }
    }

    /// A 12-hour reading in 24 hours: 1 p.m. → 13, 12 a.m. → 0; without a marker the hour is taken as printed.
    private static func time(_ hour: Int, _ minute: Int, _ meridiem: String?) -> LocalTime? {
        guard meridiem == nil || (1...12).contains(hour) else { return nil }
        var hour = hour
        if meridiem == "p", hour < 12 { hour += 12 }
        if meridiem == "a", hour == 12 { hour = 0 }
        return LocalTime(hour: hour, minute: minute)
    }

    /// The times in `text`, in order (24-hour).
    static func times(in text: String) -> [LocalTime] {
        clockTimes(in: text).compactMap { time($0.hour, $0.minute, $0.meridiem) }
    }

    /// `text` with its times removed.
    private static func withoutTimes(_ text: String) -> String { text.replacing(timePattern, with: " ") }

    /// Number, start and end printed in a header cell.
    static func header(_ text: String) -> Header {
        let clocks = clockTimes(in: text)
        let rest = withoutTimes(text)
        let number = rest.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).lazy.compactMap { Int($0) }
            .first { (0...20).contains($0) }
        guard let first = clocks.first else { return Header(number: number) }
        var start = time(first.hour, first.minute, first.meridiem)
        var end: LocalTime?
        if clocks.count >= 2 {
            let second = clocks[1]
            end = time(second.hour, second.minute, second.meridiem)
            // "1:00–1:50 p.m.": the end's marker also applies to the start when that keeps start < end.
            if first.meridiem == nil, let marked = time(first.hour, first.minute, second.meridiem), let end, marked < end {
                start = marked
            }
            // "11:30–12:20" is fine; "12:30–1:15" means 1:15 p.m.
            if let start, let value = end, value <= start, value.minuteOfDay < 720, let later = value.adding(minutes: 720),
               start < later {
                end = later
            }
            if let start, let value = end, value <= start { end = nil }
        }
        return Header(number: number, start: start, end: end)
    }

    /// `true` when `text` holds only period numbers, times and period words (a header, never a lesson).
    static func isHeaderLike(_ text: String) -> Bool {
        let rest = withoutTimes(text)
        guard text.contains(where: { $0.isASCII && $0.isNumber }) else { return false }
        let words = ImportText.fold(rest).split(whereSeparator: { !$0.isLetter })
            .flatMap { word -> [String] in
                // CJK words are not space-separated: "第3节" → "第", "节".
                word.allSatisfy(\.isASCII) || word.count <= 2 ? [String(word)] : word.map(String.init)
            }
        return words.allSatisfy { periodWords.contains($0) }
    }

    /// Lesson lengths tried in order when only start times are printed (45 and 90 are the common school/uni ones).
    private static let standardLengths = [45, 90, 60, 50, 40, 30, 120, 100, 80, 75, 55, 35]

    /// The periods for headers in column order, with the notices that apply. Numbers must already be set.
    /// - Printed ranges are used as they are. Missing ends: the most common printed length, else the standard length
    ///   that fits the smallest gap between consecutive starts (gap 50 → 45 min, gap 105 → 90 min), never past the
    ///   next start. Missing starts are interpolated. No times at all: 08:00, 45 min, 10 min breaks (`.timesAssumed`).
    static func periods(numbers: [Int], headers: [Header]) -> (periods: [ImportPeriod], notices: [ImportNotice]) {
        var starts = headers.map(\.start)
        var ends = headers.map(\.end)
        // A start just after noon printed in 12 hours ("12:00" then "1:00") moves on by 12 h; any other start
        // before the previous one is a misread, dropped and interpolated below.
        var last: LocalTime?
        for index in starts.indices {
            guard var start = starts[index] else { continue }
            if let previous = last, start <= previous, previous.minuteOfDay >= 660, start.minuteOfDay < 720,
               let later = start.adding(minutes: 720), previous < later, previous.minutes(to: later) <= 180 {
                start = later
                starts[index] = later
                if let end = ends[index], end.minuteOfDay < 720 { ends[index] = end.adding(minutes: 720) }
            }
            if let previous = last, start <= previous { starts[index] = nil; ends[index] = nil } else { last = start }
        }
        let known = starts.indices.filter { starts[$0] != nil }
        guard !known.isEmpty else { return (assumed(numbers), [.timesAssumed]) }
        var gaps: [Int] = []
        for (a, b) in zip(known, known.dropFirst()) { gaps.append(starts[a]!.minutes(to: starts[b]!) / (b - a)) }
        let printedLengths = starts.indices.compactMap { index in ends[index].map { starts[index]!.minutes(to: $0) } }
        let step = gaps.min() ?? 55
        let length: Int
        if let common = mostCommon(printedLengths) {
            length = common
        } else {
            length = standardLengths.first { (step - 20...step).contains($0) } ?? max(5, step - 5)
        }
        // Interpolate missing starts from the nearest known start.
        var source = [ImportTimeSource](repeating: .printed, count: starts.count)
        for index in starts.indices where starts[index] == nil {
            let anchor = known.min { abs($0 - index) < abs($1 - index) }!
            let minute = starts[anchor]!.minuteOfDay + (index - anchor) * max(step, length)
            starts[index] = LocalTime(minuteOfDay: min(max(minute, 0), 1438))
            source[index] = .assumed
        }
        var periods: [ImportPeriod] = []
        var notices: [ImportNotice] = []
        for index in starts.indices {
            let start = starts[index]!
            var end: LocalTime
            if let printed = ends[index] {
                end = printed
            } else {
                end = start.adding(minutes: length) ?? LocalTime(minuteOfDay: 1439)!
                if source[index] == .printed { source[index] = .inferredEnd }
            }
            if index + 1 < starts.count, let next = starts[index + 1], next < end { end = next }
            if end <= start { end = start.adding(minutes: 1) ?? start } // keeps one period per column
            periods.append(ImportPeriod(number: numbers[index], start: start, end: end, timeSource: source[index]))
        }
        // Interpolated starts can run into a printed one or past midnight: push them back to back, and when the day
        // is too short for that, fall back to the assumed schedule (never duplicate or overlapping periods).
        var previousEnd = -1
        for index in periods.indices {
            var start = periods[index].start.minuteOfDay, end = periods[index].end.minuteOfDay
            if start < previousEnd { start = previousEnd; periods[index].timeSource = .assumed }
            if end <= start { end = start + 1 }
            guard end < LocalTime.minutesPerDay else { return (assumed(numbers), [.timesAssumed]) }
            periods[index].start = LocalTime(minuteOfDay: start)!
            periods[index].end = LocalTime(minuteOfDay: end)!
            previousEnd = end
        }
        if periods.contains(where: { $0.timeSource == .inferredEnd }) { notices.append(.endTimesInferred) }
        if periods.contains(where: { $0.timeSource == .assumed }) { notices.append(.timesAssumed) }
        return (periods, notices)
    }

    /// No usable times: 08:00, 45-minute lessons with 10-minute breaks, squeezed so that up to
    /// `ShareLimits.maxPeriodsPerSchedule` periods still end before midnight.
    static func assumed(_ numbers: [Int]) -> [ImportPeriod] {
        let step = max(2, min(55, (LocalTime.minutesPerDay - 1 - 8 * 60) / max(1, numbers.count)))
        let length = max(1, min(45, step - 10))
        return numbers.indices.compactMap { index in
            guard let start = LocalTime(minuteOfDay: 8 * 60 + index * step), let end = start.adding(minutes: length) else { return nil }
            return ImportPeriod(number: numbers[index], start: start, end: end, timeSource: .assumed)
        }
    }

    private static func mostCommon(_ values: [Int]) -> Int? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
    }
}
