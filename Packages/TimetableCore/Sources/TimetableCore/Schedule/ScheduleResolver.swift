import Foundation

/// Resolves one timetable's schedule on concrete dates: rotation, enabled days, terms and validity, breaks,
/// one-off overrides, bell schedules (including per-weekday schedules) and subject defaults.
///
/// A pure value: build it once from the data (indexes are precomputed), then query any date. Deterministic —
/// same data, context and date give the same result; no clock, locale or random source is read.
/// Tombstoned entities are ignored.
///
/// ## Resolution of a date
/// 1. **Rotation** (`RotationResolver`): cycle week / cycle day of the date. Overrides never shift it.
/// 2. **Day key**: the date's weekday (or cycle day) if the weekday is enabled, unless a break covers the date.
/// 3. **`followDay`** replaces the day key (and, if given, the cycle week). It is an explicit per-date
///    decision, so it also makes a disabled weekday or a break day a school day (make-up Saturdays).
/// 4. **Bell schedule**: `timeStructure.bellScheduleID(for: date.weekday)` — the *calendar* weekday, also
///    under `followDay` (a followed day changes which lessons run, not the school's bell times; stack a
///    `useBellSchedule` for that) — replaced by a `useBellSchedule` override.
/// 5. **Lessons** with that day key, in the cycle week (`cycleWeeks`; ignored without a week cycle), valid
///    on the date (`validity` uses the date itself, also under `followDay`).
/// 6. **`cancelDay`** cancels every regular occurrence (kept with status `.cancelled`).
/// 7. **`cancelLesson` / `modifyLesson`** per lesson, then **`addLesson`**.
///
/// ## Precedence of overrides on one date
/// Overrides are processed in ascending (`meta.updatedAt`, `id`) order, so "later wins" means the latest
/// `updatedAt` (ties: the larger ID).
/// - Several `followDay` (or several `useBellSchedule`): the latest wins; the others are reported as
///   `supersededOverride`.
/// - Several `cancelDay`: redundant; `cancellingOverrideID` is the latest.
/// - `cancelLesson`/`modifyLesson` on the same lesson are replayed in order: patches merge field by field
///   (later field values win), and the latest of the two kinds decides whether the occurrence is cancelled
///   (a later modify revives an earlier cancel). A `cancelDay` always cancels, whatever the order.
/// - `addLesson` occurrences are independent and survive a `cancelDay` (a cancelled day can still carry an
///   extra event, e.g. "Sports day 08:00–12:00").
///
/// ## Statuses
/// `.cancelled` (cancelDay/cancelLesson), `.added` (addLesson), `.modified` when the occurrence differs from
/// the same lesson on that date without overrides (`ModificationReason`s: a `useBellSchedule` that moves its
/// times, a patched slot, subject, room, …), else `.scheduled`. `followDay` alone keeps `.scheduled`.
public struct ScheduleResolver: Sendable {
    /// The timetable resolved.
    public let timetable: Timetable
    /// Time zone and week start used for instants and week arithmetic.
    public let context: CalendarContext
    /// The timetable's rotation, bound to the breaks that apply to it and to `timetable.rotationWeekStart` (never
    /// `context.firstWeekday`: the device's week start must not move an A/B week).
    public let rotation: RotationResolver

    let subjectsByID: [Subject.ID: Subject]
    let schedulesByID: [BellSchedule.ID: BellScheduleIndex]
    /// Live lessons of the timetable, ascending by ID.
    let lessons: [Lesson]
    let lessonsByDayKey: [DayKey: [Lesson]]
    let termsByID: [Term.ID: Term]
    /// Live terms of this timetable, ascending by (start, end, id).
    let ownTerms: [Term]
    /// Live breaks that apply to this timetable, ascending by (start, end, id).
    let breaks: [CalendarBreak]
    let overridesByDate: [LocalDate: [ScheduleOverride]]

    /// Creates a resolver from entity collections. Tombstones are skipped; lessons, bell schedules,
    /// overrides and terms (for `DaySchedule.termID`) are restricted to `timetable`; breaks to those with
    /// `timetableID == nil` or this timetable. Subjects and terms are looked up by ID across timetables
    /// (cross-timetable references are a validation warning, not an error).
    public init(timetable: Timetable, subjects: [Subject], bellSchedules: [BellSchedule], lessons: [Lesson],
                terms: [Term], breaks: [CalendarBreak], overrides: [ScheduleOverride], context: CalendarContext) {
        let ttID = timetable.id
        self.timetable = timetable
        self.context = context

        var subjectsByID: [Subject.ID: Subject] = [:]
        for subject in subjects.sorted(by: { $0.id < $1.id }) where !subject.isDeleted && subjectsByID[subject.id] == nil {
            subjectsByID[subject.id] = subject
        }
        self.subjectsByID = subjectsByID

        var schedulesByID: [BellSchedule.ID: BellScheduleIndex] = [:]
        for schedule in bellSchedules.sorted(by: { $0.id < $1.id })
        where !schedule.isDeleted && schedule.timetableID == ttID && schedulesByID[schedule.id] == nil {
            schedulesByID[schedule.id] = BellScheduleIndex(schedule)
        }
        self.schedulesByID = schedulesByID

        let liveLessons = lessons.filter { !$0.isDeleted && $0.timetableID == ttID }.sorted { $0.id < $1.id }
        self.lessons = liveLessons
        self.lessonsByDayKey = Dictionary(grouping: liveLessons, by: \.occurrence.day)

        var termsByID: [Term.ID: Term] = [:]
        for term in terms.sorted(by: { $0.id < $1.id }) where !term.isDeleted && termsByID[term.id] == nil {
            termsByID[term.id] = term
        }
        self.termsByID = termsByID
        self.ownTerms = termsByID.values.filter { $0.timetableID == ttID && !$0.range.isEmpty }
            .sorted { ($0.range.start, $0.range.end, $0.id) < ($1.range.start, $1.range.end, $1.id) }

        let ownBreaks = breaks.filter { !$0.isDeleted && ($0.timetableID == nil || $0.timetableID == ttID) && !$0.range.isEmpty }
            .sorted { ($0.range.start, $0.range.end, $0.id) < ($1.range.start, $1.range.end, $1.id) }
        self.breaks = ownBreaks
        self.overridesByDate = Dictionary(grouping: overrides.filter { !$0.isDeleted && $0.timetableID == ttID },
                                          by: \.date)
        self.rotation = RotationResolver(scheme: timetable.rotation, firstWeekday: timetable.rotationWeekStart,
                                         breaks: ownBreaks.map(\.range))
    }

    /// A resolver for timetable `timetableID` of `database`, or `nil` when it does not exist or is deleted.
    public init?(database: TabulaDatabase, timetableID: Timetable.ID, context: CalendarContext) {
        guard let timetable = database.timetables.first(where: { $0.id == timetableID && !$0.isDeleted }) else {
            return nil
        }
        self.init(timetable: timetable, subjects: database.subjects, bellSchedules: database.bellSchedules,
                  lessons: database.lessons, terms: database.terms, breaks: database.breaks,
                  overrides: database.overrides, context: context)
    }

    /// Resolvers for every live timetable of `database`, ascending by (`sortIndex`, `id`).
    public static func all(database: TabulaDatabase, context: CalendarContext) -> [ScheduleResolver] {
        database.timetables.filter { !$0.isDeleted }
            .sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }
            .compactMap { ScheduleResolver(database: database, timetableID: $0.id, context: context) }
    }

    // MARK: Public queries

    /// The schedule of `date`.
    public func day(_ date: LocalDate, options: ResolutionOptions = .actual) -> DaySchedule {
        resolution(for: date, options: options).schedule
    }

    /// The schedules of every date in `range` (ascending; empty for an empty range).
    public func days(in range: LocalDateRange, options: ResolutionOptions = .actual) -> [DaySchedule] {
        range.days.map { day($0, options: options) }
    }

    /// Occurrences whose time span intersects `interval` (half-open; a zero-length occurrence counts when its
    /// start lies in the interval), ascending by (start, end, id). Serves widgets and the reminder planner.
    /// Cancelled occurrences are excluded unless `includeCancelled`.
    public func occurrences(in interval: DateInterval, includeCancelled: Bool = false,
                            options: ResolutionOptions = .actual) -> [ResolvedLesson] {
        let first = context.localDate(of: interval.start)
        let last = context.localDate(of: interval.end)
        guard first <= last else { return [] }
        var result: [ResolvedLesson] = []
        for date in LocalDateRange(start: first, end: last).days {
            for entry in day(date, options: options).entries
            where (includeCancelled || entry.status != .cancelled) && Self.intersects(entry, interval) {
                result.append(entry)
            }
        }
        return result.sorted(by: Self.instantOrder)
    }

    /// The first school day strictly after `date` within `horizonDays` days (for "pack tonight").
    public func nextSchoolDay(after date: LocalDate, horizonDays: Int = 31,
                              options: ResolutionOptions = .actual) -> DaySchedule? {
        guard horizonDays > 0 else { return nil }
        for offset in 1...horizonDays {
            let schedule = day(date.adding(days: offset), options: options)
            if schedule.isSchoolDay { return schedule }
        }
        return nil
    }

    /// Now & Next at `instant`: the lesson in progress with its remaining time, the next lesson (searching
    /// up to `horizonDays` days ahead) and the gap state. Cancelled occurrences are ignored.
    ///
    /// Boundaries are half-open: at a lesson's exact start it is current; at its exact end it is not (the
    /// state becomes `betweenLessons`/`afterLastLesson`). Overlapping lessons: the current one is the one that
    /// started last (ties: earlier end, then ID).
    public func nowAndNext(at instant: Date, horizonDays: Int = 31) -> NowNext {
        let today = context.localDate(of: instant)
        let schedule = day(today)
        let active = schedule.entries.filter { $0.status != .cancelled }.sorted(by: Self.instantOrder)
        let running = active.filter { $0.start <= instant && instant < $0.end }
        let current = running.max { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end > rhs.end }
            return lhs.id > rhs.id
        }
        var next = active.first { $0.start > instant }
        if next == nil, horizonDays > 0 {
            for offset in 1...horizonDays {
                let later = day(today.adding(days: offset)).entries
                    .filter { $0.status != .cancelled }.sorted(by: Self.instantOrder)
                if let first = later.first(where: { $0.start > instant }) {
                    next = first
                    break
                }
            }
        }
        let state: NowNext.State
        if current != nil {
            state = .inLesson
        } else if active.isEmpty {
            state = schedule.activeBreakID.map(NowNext.State.inBreak) ?? .noLessonsToday
        } else if instant < active[0].start {
            state = .beforeFirstLesson
        } else if let lastEnd = active.map(\.end).max(), instant >= lastEnd {
            state = .afterLastLesson
        } else {
            state = .betweenLessons
        }
        return NowNext(at: instant, current: current, remaining: current.map { $0.end.timeIntervalSince(instant) },
                       next: next, untilNext: next.map { $0.start.timeIntervalSince(instant) }, state: state)
    }

    // MARK: Day resolution

    /// Resolves `date` with every detail (`DaySchedule` plus natural rotation, applied day-level overrides,
    /// modification reasons and warnings). See the type documentation for the algorithm.
    public func resolution(for date: LocalDate, options: ResolutionOptions = .actual) -> DayResolution {
        var warnings: [ResolutionWarning] = []
        var conflicts: [Conflict] = []
        var entries: [ResolvedLesson] = []
        var changes: [OccurrenceChanges] = []

        let weekday = date.weekday
        let activeBreak = breaks.first { $0.range.contains(date) }
        let term = ownTerms.first { $0.range.contains(date) }
        let overrides = options.appliesOverrides ? classifiedOverrides(on: date, warnings: &warnings) : DayOverrides()

        // Rotation and day key.
        let naturalCycleWeek = rotation.cycleWeek(on: date)
        let naturalDayKey: DayKey? = timetable.enabledDays.contains(weekday) ? rotation.dayKey(on: date) : nil
        var dayKey = (options.appliesBreaks && activeBreak != nil) ? nil : naturalDayKey
        var cycleWeek = naturalCycleWeek
        if let follow = overrides.followDay {
            dayKey = follow.day
            if let week = follow.cycleWeek, case .weekCycle(let cycle) = timetable.rotation,
               (1...max(1, cycle.length)).contains(week) {
                cycleWeek = week
            }
            if !keyMatchesRotation(follow.day) {
                warnings.append(ResolutionWarning(kind: .followDayKindMismatch, date: date, overrideID: follow.override.id))
            }
        }

        // Bell schedules.
        var defaultIndex: BellScheduleIndex?
        var naturalIndex: BellScheduleIndex?
        var naturalScheduleID: BellSchedule.ID?
        if case let .bellSchedule(defaultID, _) = timetable.timeStructure {
            defaultIndex = schedulesByID[defaultID]
            naturalScheduleID = timetable.timeStructure.bellScheduleID(for: weekday)
            naturalIndex = naturalScheduleID.flatMap { schedulesByID[$0] }
        }
        var effectiveIndex = naturalIndex
        var bellOverrideID: ScheduleOverride.ID?
        if let use = overrides.bellSchedule {
            if let index = schedulesByID[use.scheduleID] {
                effectiveIndex = index
                bellOverrideID = use.override.id
            } else {
                warnings.append(ResolutionWarning(kind: .missingBellSchedule, date: date, overrideID: use.override.id,
                                                  bellScheduleID: use.scheduleID))
            }
        }
        if let missing = naturalScheduleID, naturalIndex == nil, bellOverrideID == nil,
           dayKey != nil || !overrides.adds.isEmpty {
            warnings.append(ResolutionWarning(kind: .missingBellSchedule, date: date, bellScheduleID: missing))
        }
        var ordinalSources: [BellScheduleIndex] = []
        var followedWeekdayIndex: BellScheduleIndex?
        if case .weekday(let followed)? = overrides.followDay?.day {
            followedWeekdayIndex = timetable.timeStructure.bellScheduleID(for: followed).flatMap { schedulesByID[$0] }
        }
        for candidate in [defaultIndex, naturalIndex, followedWeekdayIndex].compactMap({ $0 })
        where !ordinalSources.contains(where: { $0.id == candidate.id }) {
            ordinalSources.append(candidate)
        }

        let cancelDayIDs = overrides.cancelDays.map(\.id)
        let followID = overrides.followDay?.override.id

        // Regular lessons.
        var occurringLessonIDs = Set<Lesson.ID>()
        var dayClock: DayClock?
        if let key = dayKey {
            for lesson in lessonsByDayKey[key] ?? [] {
                guard occurs(lesson, inCycleWeek: cycleWeek) else { continue }
                // An unknown validity (newer app version) hides the lesson everywhere, also in template views.
                if !lesson.validity.isKnown || (options.appliesValidity && !isValid(lesson.validity, on: date)) { continue }
                occurringLessonIDs.insert(lesson.id)
                let occurrenceID = OccurrenceID.lesson(lesson.id, on: date)

                var patch = LessonPatch()
                var cancelledByLessonOverride = false
                var applied: [ScheduleOverride.ID] = []
                for op in overrides.lessonOps[lesson.id] ?? [] {
                    switch op.change {
                    case .cancelLesson: cancelledByLessonOverride = true
                    case .modifyLesson(_, let lessonPatch):
                        cancelledByLessonOverride = false
                        patch = patch.merging(lessonPatch)
                    default: break
                    }
                    applied.append(op.id)
                }
                let isCancelled = !cancelDayIDs.isEmpty || cancelledByLessonOverride
                applied += cancelDayIDs
                if let followID { applied.append(followID) }

                guard let baseSubject = subjectsByID[lesson.subjectID] else {
                    warnings.append(ResolutionWarning(kind: .missingSubject, date: date, occurrenceID: occurrenceID,
                                                      lessonID: lesson.id, subjectID: lesson.subjectID))
                    if !isCancelled { conflicts.append(Conflict(kind: .missingSubject, date: date, occurrenceIDs: [occurrenceID])) }
                    continue
                }
                var subject = baseSubject
                if let substituteID = patch.subjectID, substituteID != baseSubject.id {
                    if let substitute = subjectsByID[substituteID] {
                        subject = substitute
                    } else {
                        warnings.append(ResolutionWarning(kind: .missingSubject, date: date, occurrenceID: occurrenceID,
                                                          lessonID: lesson.id, subjectID: substituteID))
                        if !isCancelled { conflicts.append(Conflict(kind: .missingSubject, date: date, occurrenceIDs: [occurrenceID])) }
                    }
                }

                let slot = patch.slot ?? lesson.slot
                let placement: PlacedSlot
                switch SlotPlacement.place(slot, in: effectiveIndex, ordinalSources: ordinalSources) {
                case .failure(let failure):
                    report(failure, slot: slot, occurrenceID: occurrenceID, lessonID: lesson.id, date: date,
                           isCancelled: isCancelled, warnings: &warnings, conflicts: &conflicts)
                    continue
                case .success(let placed):
                    placement = placed
                }
                reportAdjustments(placement, slot: slot, occurrenceID: occurrenceID, lessonID: lesson.id, date: date,
                                  isCancelled: isCancelled, warnings: &warnings, conflicts: &conflicts)
                if case .period = slot, let bellOverrideID { applied.append(bellOverrideID) }

                var reasons: [ModificationReason] = []
                if case .success(let baseline) = SlotPlacement.place(lesson.slot, in: naturalIndex, ordinalSources: ordinalSources) {
                    if baseline.startTime != placement.startTime || baseline.endTime != placement.endTime {
                        reasons.append(.timeChanged)
                    }
                } else {
                    reasons.append(.timeChanged)
                }
                if subject.id != baseSubject.id { reasons.append(.subjectChanged) }
                let fields = EffectiveFields(lesson: lesson, subject: subject, patch: patch)
                reasons += EffectiveFields(lesson: lesson, subject: baseSubject).differences(to: fields)
                if !reasons.isEmpty { changes.append(OccurrenceChanges(occurrenceID: occurrenceID, reasons: reasons)) }

                let status: ResolvedLesson.Status = isCancelled ? .cancelled : (reasons.isEmpty ? .scheduled : .modified)
                entries.append(makeEntry(id: occurrenceID, source: .lesson(lesson.id), date: date, subject: subject,
                                         placement: placement, fields: fields, status: status, applied: applied, clock: &dayClock))
            }
        }

        // Lesson overrides whose target does not occur on this date.
        for (lessonID, ops) in overrides.lessonOps.sorted(by: { $0.key < $1.key }) where !occurringLessonIDs.contains(lessonID) {
            for op in ops.sorted(by: { $0.id < $1.id }) {
                warnings.append(ResolutionWarning(kind: .overrideTargetNotScheduled, date: date, lessonID: lessonID,
                                                  overrideID: op.id))
            }
        }

        // One-off lessons.
        for (override, oneOff) in overrides.adds {
            let occurrenceID = OccurrenceID.oneOff(override.id)
            guard let subject = subjectsByID[oneOff.subjectID] else {
                warnings.append(ResolutionWarning(kind: .missingSubject, date: date, occurrenceID: occurrenceID,
                                                  overrideID: override.id, subjectID: oneOff.subjectID))
                conflicts.append(Conflict(kind: .missingSubject, date: date, occurrenceIDs: [occurrenceID]))
                continue
            }
            let placement: PlacedSlot
            switch SlotPlacement.place(oneOff.slot, in: effectiveIndex, ordinalSources: ordinalSources) {
            case .failure(let failure):
                report(failure, slot: oneOff.slot, occurrenceID: occurrenceID, lessonID: nil, date: date,
                       isCancelled: false, warnings: &warnings, conflicts: &conflicts, overrideID: override.id)
                continue
            case .success(let placed):
                placement = placed
            }
            reportAdjustments(placement, slot: oneOff.slot, occurrenceID: occurrenceID, lessonID: nil, date: date,
                              isCancelled: false, warnings: &warnings, conflicts: &conflicts, overrideID: override.id)
            var applied = [override.id]
            if case .period = oneOff.slot, let bellOverrideID { applied.append(bellOverrideID) }
            entries.append(makeEntry(id: occurrenceID, source: .oneOff(override.id), date: date, subject: subject,
                                     placement: placement, fields: EffectiveFields(oneOff: oneOff, subject: subject),
                                     status: .added, applied: applied, clock: &dayClock))
        }

        entries.sort(by: Self.wallClockOrder)
        conflicts += ConflictDetector.overlaps(in: entries, on: date)
        conflicts.sort(by: Self.conflictOrder)
        changes.sort { $0.occurrenceID < $1.occurrenceID }

        let schedule = DaySchedule(
            date: date, timetableID: timetable.id, dayKey: dayKey, cycleWeek: cycleWeek,
            cycleLabel: rotation.label(for: dayKey, cycleWeek: cycleWeek),
            isSchoolDay: dayKey != nil && cancelDayIDs.isEmpty, activeBreakID: activeBreak?.id,
            cancellingOverrideID: overrides.cancelDays.last?.id, bellScheduleID: effectiveIndex?.id, termID: term?.id,
            entries: entries, conflicts: conflicts)
        return DayResolution(schedule: schedule, naturalDayKey: naturalDayKey, naturalCycleWeek: naturalCycleWeek,
                             followDayOverrideID: followID, bellScheduleOverrideID: bellOverrideID,
                             changes: changes, warnings: warnings)
    }

    // MARK: Helpers

    /// Overrides of one date, classified. Each list is in ascending (`updatedAt`, `id`) order.
    struct DayOverrides {
        var followDay: (override: ScheduleOverride, day: DayKey, cycleWeek: Int?)?
        var bellSchedule: (override: ScheduleOverride, scheduleID: BellSchedule.ID)?
        var cancelDays: [ScheduleOverride] = []
        var lessonOps: [Lesson.ID: [ScheduleOverride]] = [:]
        var adds: [(override: ScheduleOverride, lesson: OneOffLesson)] = []
    }

    func classifiedOverrides(on date: LocalDate, warnings: inout [ResolutionWarning]) -> DayOverrides {
        var result = DayOverrides()
        let ordered = (overridesByDate[date] ?? []).sorted { ($0.meta.updatedAt, $0.id) < ($1.meta.updatedAt, $1.id) }
        var supersededFollow: [ScheduleOverride] = []
        var supersededBell: [ScheduleOverride] = []
        for override in ordered {
            switch override.change {
            case let .followDay(day, cycleWeek):
                if let previous = result.followDay?.override { supersededFollow.append(previous) }
                result.followDay = (override, day, cycleWeek)
            case .useBellSchedule(let scheduleID):
                if let previous = result.bellSchedule?.override { supersededBell.append(previous) }
                result.bellSchedule = (override, scheduleID)
            case .cancelDay:
                result.cancelDays.append(override)
            case .cancelLesson(let lessonID), .modifyLesson(let lessonID, _):
                result.lessonOps[lessonID, default: []].append(override)
            case .addLesson(let lesson):
                result.adds.append((override, lesson))
            case .unknown:
                warnings.append(ResolutionWarning(kind: .unknownOverride, date: date, overrideID: override.id))
            }
        }
        for loser in supersededFollow {
            warnings.append(ResolutionWarning(kind: .supersededOverride, date: date, overrideID: loser.id,
                                              supersededByID: result.followDay?.override.id))
        }
        for loser in supersededBell {
            warnings.append(ResolutionWarning(kind: .supersededOverride, date: date, overrideID: loser.id,
                                              supersededByID: result.bellSchedule?.override.id))
        }
        result.adds.sort { $0.override.id < $1.override.id }
        return result
    }

    /// `true` when `lesson` runs in `cycleWeek`. `cycleWeeks == nil` = every week; without a week cycle the
    /// restriction is ignored (validation warns), so switching a timetable to "no rotation" shows every lesson.
    func occurs(_ lesson: Lesson, inCycleWeek cycleWeek: Int?) -> Bool {
        guard let weeks = lesson.occurrence.cycleWeeks, case .weekCycle = timetable.rotation, let cycleWeek else {
            return true
        }
        return weeks.contains(cycleWeek)
    }

    /// `true` when `validity` admits `date` (deleted or unknown terms and unknown validity kinds admit nothing).
    func isValid(_ validity: LessonValidity, on date: LocalDate) -> Bool {
        switch validity {
        case .always: return true
        case .unknown: return false
        case .range(let range): return range.contains(date)
        case .terms(let ids): return ids.contains { termsByID[$0]?.range.contains(date) ?? false }
        }
    }

    private func keyMatchesRotation(_ key: DayKey) -> Bool {
        switch (key, timetable.rotation) {
        case (.cycleDay, .dayCycle), (.weekday, .none), (.weekday, .weekCycle): return true
        default: return false
        }
    }

    private func makeEntry(id: OccurrenceID, source: ResolvedLesson.Source, date: LocalDate, subject: Subject,
                           placement: PlacedSlot, fields: EffectiveFields, status: ResolvedLesson.Status,
                           applied: [ScheduleOverride.ID], clock: inout DayClock?) -> ResolvedLesson {
        if clock == nil { clock = DayClock(context: context, date: date) }
        return ResolvedLesson(
            id: id, source: source, timetableID: timetable.id, date: date, subject: SubjectSummary(subject),
            startTime: placement.startTime, endTime: placement.endTime,
            start: clock!.instant(placement.startTime), end: clock!.instant(placement.endTime),
            periodID: placement.periodID, periodLabel: placement.periodLabel, periodNumber: placement.periodNumber,
            periodSpan: placement.periodSpan, room: fields.room, building: fields.building, teacher: fields.teacher,
            lessonType: fields.lessonType, notes: fields.notes, bringList: fields.bringList, status: status,
            appliedOverrideIDs: Array(Set(applied)).sorted())
    }

    private func report(_ failure: SlotFailure, slot: LessonSlot, occurrenceID: OccurrenceID, lessonID: Lesson.ID?,
                        date: LocalDate, isCancelled: Bool, warnings: inout [ResolutionWarning],
                        conflicts: inout [Conflict], overrideID: ScheduleOverride.ID? = nil) {
        var periodID: Period.ID?
        if case .period(let id, _) = slot { periodID = id }
        let kind: (ResolutionWarning.Kind, Conflict.Kind)
        switch failure {
        case .noBellSchedule, .periodNotInSchedule: kind = (.periodNotInSchedule, .periodNotInSchedule)
        case .invalidTimeRange: kind = (.invalidTimeRange, .invalidTimeRange)
        }
        warnings.append(ResolutionWarning(kind: kind.0, date: date, occurrenceID: occurrenceID, lessonID: lessonID,
                                          overrideID: overrideID, periodID: periodID))
        if !isCancelled { conflicts.append(Conflict(kind: kind.1, date: date, occurrenceIDs: [occurrenceID])) }
    }

    private func reportAdjustments(_ placement: PlacedSlot, slot: LessonSlot, occurrenceID: OccurrenceID,
                                   lessonID: Lesson.ID?, date: LocalDate, isCancelled: Bool,
                                   warnings: inout [ResolutionWarning], conflicts: inout [Conflict],
                                   overrideID: ScheduleOverride.ID? = nil) {
        guard case .period(let requestedID, _) = slot else { return }
        if placement.mappedByOrdinal {
            warnings.append(ResolutionWarning(kind: .periodMappedByOrdinal, date: date, occurrenceID: occurrenceID,
                                              lessonID: lessonID, overrideID: overrideID, periodID: requestedID))
        }
        if placement.truncatedFromSpan != nil {
            warnings.append(ResolutionWarning(kind: .spanExceedsSchedule, date: date, occurrenceID: occurrenceID,
                                              lessonID: lessonID, overrideID: overrideID, periodID: requestedID))
            if !isCancelled { conflicts.append(Conflict(kind: .spanExceedsSchedule, date: date, occurrenceIDs: [occurrenceID])) }
        }
    }

    static func intersects(_ entry: ResolvedLesson, _ interval: DateInterval) -> Bool {
        let lower = interval.start, upper = interval.end
        if entry.start == entry.end { return lower <= entry.start && (entry.start < upper || lower == upper) }
        if lower == upper { return entry.start <= lower && lower < entry.end }
        return entry.start < upper && entry.end > lower
    }

    /// Wall-clock order used for `DaySchedule.entries`: (startTime, endTime, id).
    static func wallClockOrder(_ lhs: ResolvedLesson, _ rhs: ResolvedLesson) -> Bool {
        (lhs.startTime, lhs.endTime, lhs.id) < (rhs.startTime, rhs.endTime, rhs.id)
    }

    /// Instant order used across days: (start, end, id).
    static func instantOrder(_ lhs: ResolvedLesson, _ rhs: ResolvedLesson) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        return lhs.id < rhs.id
    }

    static func conflictOrder(_ lhs: Conflict, _ rhs: Conflict) -> Bool {
        let lhsKind = Conflict.Kind.allCases.firstIndex(of: lhs.kind)!
        let rhsKind = Conflict.Kind.allCases.firstIndex(of: rhs.kind)!
        if lhsKind != rhsKind { return lhsKind < rhsKind }
        return lhs.occurrenceIDs.lexicographicallyPrecedes(rhs.occurrenceIDs)
    }
}
