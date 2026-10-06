import Foundation

/// Generates the lesson periods of a regular bell schedule: `count` lessons of `lessonMinutes`, starting at
/// `firstStart`, separated by breaks.
///
/// `breakMinutes[i]` is the break after lesson `i + 1`. A shorter array repeats its **last** value; an empty
/// array means no breaks. Breaks are gaps (no `.breakTime` periods are generated). Lessons that would end
/// after 23:59 are dropped (periods never span midnight), so the result may have fewer than `count` periods.
public struct BellScheduleTemplate: Hashable, Sendable {
    /// Start of the first lesson.
    public var firstStart: LocalTime
    /// Length of every lesson, ≥ 1.
    public var lessonMinutes: Int
    /// Breaks between lessons (see type docs), each ≥ 0.
    public var breakMinutes: [Int]
    /// Number of lessons, ≥ 0.
    public var count: Int

    /// Creates a template.
    public init(firstStart: LocalTime, lessonMinutes: Int, breakMinutes: [Int], count: Int) {
        self.firstStart = firstStart
        self.lessonMinutes = lessonMinutes
        self.breakMinutes = breakMinutes
        self.count = count
    }

    /// Typical primary school: 6 × 45 min from 08:00, 20-minute break after the 2nd lesson.
    public static let elementary = BellScheduleTemplate(firstStart: LocalTime(hour: 8, minute: 0)!, lessonMinutes: 45,
                                                        breakMinutes: [10, 20, 10], count: 6)

    /// Typical secondary school: 8 × 45 min from 08:00, 20-minute break after the 2nd lesson.
    public static let secondary = BellScheduleTemplate(firstStart: LocalTime(hour: 8, minute: 0)!, lessonMinutes: 45,
                                                       breakMinutes: [10, 20, 10], count: 8)

    /// The break after lesson `index + 1`.
    public func breakAfter(lesson index: Int) -> Int {
        guard let last = breakMinutes.last else { return 0 }
        return index < breakMinutes.count ? breakMinutes[index] : last
    }

    /// Start/end of each generated lesson (truncated before midnight; empty for invalid parameters).
    public func lessonTimes() -> [(start: LocalTime, end: LocalTime)] {
        guard lessonMinutes >= 1, count >= 1, breakMinutes.allSatisfy({ $0 >= 0 }) else { return [] }
        var result: [(start: LocalTime, end: LocalTime)] = []
        var startMinute = firstStart.minuteOfDay
        for index in 0..<count {
            guard let start = LocalTime(minuteOfDay: startMinute),
                  let end = LocalTime(minuteOfDay: startMinute + lessonMinutes) else { break }
            result.append((start, end))
            startMinute = end.minuteOfDay + breakAfter(lesson: index)
        }
        return result
    }

    /// The generated lesson periods with fresh IDs (labels `nil`: the UI numbers them).
    public func makePeriods<G: IDGenerator>(ids: inout G) -> [Period] {
        lessonTimes().map { Period(id: ids.next(), start: $0.start, end: $0.end, kind: .lesson) }
    }
}
