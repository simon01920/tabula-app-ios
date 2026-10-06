import Foundation

/// A bell schedule prepared for slot lookups: periods sorted by (start, end, id), positions by ID and
/// ordinals among periods of the same kind.
struct BellScheduleIndex: Hashable, Sendable {
    let schedule: BellSchedule
    /// Periods ascending by (start, end, id).
    let periods: [Period]
    /// Position in `periods` by ID (first occurrence wins for duplicate IDs, which validation reports).
    let positionByID: [Period.ID: Int]
    /// Positions in `periods` of each kind, ascending.
    let positionsByKind: [PeriodKind: [Int]]

    init(_ schedule: BellSchedule) {
        self.schedule = schedule
        let sorted = schedule.periods.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        self.periods = sorted
        var byID: [Period.ID: Int] = [:]
        var byKind: [PeriodKind: [Int]] = [:]
        for (position, period) in sorted.enumerated() {
            if byID[period.id] == nil { byID[period.id] = position }
            byKind[period.kind, default: []].append(position)
        }
        self.positionByID = byID
        self.positionsByKind = byKind
    }

    var id: BellSchedule.ID { schedule.id }

    /// Lesson-kind periods, ascending.
    var lessonPositions: [Int] { positionsByKind[.lesson] ?? [] }

    /// `(kind, 0-based ordinal among periods of that kind)` of period `id`.
    func ordinal(of id: Period.ID) -> (kind: PeriodKind, ordinal: Int)? {
        guard let position = positionByID[id] else { return nil }
        let kind = periods[position].kind
        guard let ordinal = positionsByKind[kind]?.firstIndex(of: position) else { return nil }
        return (kind, ordinal)
    }

    /// Position of the `ordinal`-th period of `kind`, if it exists.
    func position(ofOrdinal ordinal: Int, kind: PeriodKind) -> Int? {
        guard let positions = positionsByKind[kind], positions.indices.contains(ordinal) else { return nil }
        return positions[ordinal]
    }

    /// 1-based number of the lesson period at `position` (nil for non-lesson periods).
    func lessonNumber(atPosition position: Int) -> Int? {
        lessonPositions.firstIndex(of: position).map { $0 + 1 }
    }
}

/// Where a slot lands on a date.
struct PlacedSlot: Hashable, Sendable {
    var startTime: LocalTime
    var endTime: LocalTime
    /// First period actually used (in the applicable schedule), if slotted by period.
    var periodID: Period.ID?
    var periodLabel: String?
    var periodNumber: Int?
    var periodSpan: Int?
    /// Period positions covered in the applicable schedule (first … last).
    var coveredPeriodIDs: [Period.ID] = []
    /// The period ID was absent and the ordinal fallback was used.
    var mappedByOrdinal = false
    /// The requested span when it had to be shortened.
    var truncatedFromSpan: Int?
}

/// Why a slot could not be placed.
enum SlotFailure: Error, Hashable, Sendable {
    /// No bell schedule applies (free-form timetable or missing schedule).
    case noBellSchedule
    /// Period ID absent and no ordinal fallback.
    case periodNotInSchedule
    /// End is not after start.
    case invalidTimeRange
}

/// Places lesson slots in bell schedules (PHASE1_PLAN §4, orchestrator decisions 1 and 2).
enum SlotPlacement {
    /// Places `slot` in `schedule`.
    ///
    /// - `.time`: the explicit times (bell schedules are irrelevant); `end ≤ start` fails.
    /// - `.period(id, span)`: the period with `id` in `schedule`; if absent, the period with the same ordinal
    ///   among periods of the same kind (for lesson periods: "the n-th lesson period") in the first of
    ///   `ordinalSources` that contains `id` (the timetable's default schedule first). `span` (clamped to ≥ 1)
    ///   counts the start period plus the following lesson-kind periods; the occurrence runs from the first
    ///   period's start to the last covered period's end, including any break periods in between. A span that
    ///   runs past the last lesson period is shortened (`truncatedFromSpan`).
    static func place(_ slot: LessonSlot, in schedule: BellScheduleIndex?,
                      ordinalSources: [BellScheduleIndex]) -> Result<PlacedSlot, SlotFailure> {
        switch slot {
        case let .time(start, end):
            guard end > start else { return .failure(.invalidTimeRange) }
            return .success(PlacedSlot(startTime: start, endTime: end))
        case let .period(periodID, span):
            guard let schedule else { return .failure(.noBellSchedule) }
            var mapped = false
            var startPosition = schedule.positionByID[periodID]
            if startPosition == nil {
                for source in ordinalSources {
                    guard let (kind, ordinal) = source.ordinal(of: periodID) else { continue }
                    startPosition = schedule.position(ofOrdinal: ordinal, kind: kind)
                    mapped = true
                    break
                }
            }
            guard let first = startPosition else { return .failure(.periodNotInSchedule) }
            let requested = max(1, span)
            let following = schedule.lessonPositions.filter { $0 > first }.prefix(requested - 1)
            let covered = [first] + following
            let last = covered[covered.count - 1]
            let startPeriod = schedule.periods[first], endPeriod = schedule.periods[last]
            guard endPeriod.end > startPeriod.start else { return .failure(.invalidTimeRange) }
            return .success(PlacedSlot(
                startTime: startPeriod.start, endTime: endPeriod.end, periodID: startPeriod.id,
                periodLabel: startPeriod.label, periodNumber: schedule.lessonNumber(atPosition: first),
                periodSpan: covered.count, coveredPeriodIDs: covered.map { schedule.periods[$0].id },
                mappedByOrdinal: mapped, truncatedFromSpan: covered.count < requested ? requested : nil))
        }
    }
}
