import Foundation

/// Period headers ("1", "7.00", "08:00–08:45", "8.00-8.45", "1. hod", "第3节") and bell-schedule inference.
enum ImportBellInference {
    struct Header: Hashable {
        var number: Int?
        var start: LocalTime?
        var end: LocalTime?
    }

    private static var timePattern: Regex<(Substring, Substring, Substring)> { /(\d{1,2})[:.h](\d{2})(?!\d)/ } // Regex is not Sendable; "8h00" is French
    /// Words that may accompany a period number; a cell of only these, numbers and times is a header, not a lesson.
    private static let periodWords: Set<String> = Set([
        "hod", "hodina", "h", "period", "lesson", "hour", "std", "stunde", "lekcja", "lekce", "lekc", "ora", "heure",
        "cours", "ura", "урок", "час", "пара", "节", "節", "限", "時限", "时", "第", "óra", "tiet",
    ].map(ImportText.fold))

    /// The times in `text`, in order (hour 0…23, minute 0…59).
    static func times(in text: String) -> [LocalTime] {
        text.matches(of: timePattern).compactMap { match in
            guard let hour = Int(match.output.1), let minute = Int(match.output.2) else { return nil }
            return LocalTime(hour: hour, minute: minute)
        }
    }

    /// `text` with its times removed.
    private static func withoutTimes(_ text: String) -> String { text.replacing(timePattern, with: " ") }

    /// Number, start and end printed in a header cell.
    static func header(_ text: String) -> Header {
        let found = times(in: text)
        let rest = withoutTimes(text)
        let number = rest.split(whereSeparator: { !($0.isASCII && $0.isNumber) }).lazy.compactMap { Int($0) }
            .first { (0...20).contains($0) }
        var header = Header(number: number, start: found.first, end: nil)
        if found.count >= 2, found[0] < found[1] { header.end = found[1] }
        return header
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
        // Drop starts that break the order (misread digits); they are interpolated below.
        var last: LocalTime?
        for index in starts.indices {
            guard let start = starts[index] else { continue }
            if let last, start <= last { starts[index] = nil; ends[index] = nil } else { last = start }
        }
        let known = starts.indices.filter { starts[$0] != nil }
        guard !known.isEmpty else {
            let periods = numbers.indices.map { index in
                let start = LocalTime(minuteOfDay: min(8 * 60 + index * 55, 1380))!
                return ImportPeriod(number: numbers[index], start: start, end: start.adding(minutes: 45) ?? start,
                                    timeSource: .assumed)
            }
            return (periods, [.timesAssumed])
        }
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
        if periods.contains(where: { $0.timeSource == .inferredEnd }) { notices.append(.endTimesInferred) }
        if periods.contains(where: { $0.timeSource == .assumed }) { notices.append(.timesAssumed) }
        return (periods, notices)
    }

    private static func mostCommon(_ values: [Int]) -> Int? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key
    }
}
