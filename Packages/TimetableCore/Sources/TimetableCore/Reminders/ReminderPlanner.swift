import Foundation

/// The reminder planner: turns rules + tasks/exams/lessons/bring-lists into a bounded, prioritised set of
/// local notifications and loud alarms for the next `horizonDays`. Pure and deterministic (same input, same
/// plan, byte for byte); the iOS adapters (Phase 3) only diff and apply the result.
///
/// ## Pipeline (per item × matching rule × offset)
/// 1. **Items.** Tasks (not deleted, not completed, with a due date; target = task kind), exams (not deleted,
///    not completed), lesson occurrences (not cancelled) and pack-tonight days (≥ 1 item). Each item has an
///    *anchor* (the instant offsets count back from) and a *deadline* (no reminder may fire after it):
///    - timed items (task `dateTime`, exam with `start`, lesson start, first lesson of a pack-tonight day, a
///      date-only task linked to a lesson occurrence present in `lessons`): anchor = deadline = that instant;
///    - date-only items: anchor = the date at `dateOnlyAnchorTime` (08:00), deadline = end of that date.
/// 2. **Rules.** Enabled, non-deleted rules whose `target` matches. A `ReminderOverride` with
///    `isEnabled == false` silences the item; otherwise its `offsets`/`tier`/`followUp` replace the rule's.
///    Override offsets with no matching rule still plan (a "virtual" user rule, `ruleID == nil`). An override
///    `tier` counts as a user choice (origin `.user`).
/// 3. **Nominal time.** `.minutesBefore(m)`: anchor − m minutes (real elapsed time). `.daysBefore(n, at:)`:
///    wall-clock `at` on anchor date − n, via `CalendarContext.date` (a nonexistent DST time shifts forward
///    by the gap; an ambiguous one takes the earlier instant). Negative values and unknown offset kinds are
///    reported as dropped (`invalidOffset` / `unsupportedOffset`), never planned.
/// 4. **Alarm eligibility** (decision D7), for `.alarm` requests, in this order: follow-ups never ring;
///    preset-origin rules don't ring unless `alarmPolicy.allowsPresetRules`; `alarmPolicy.isEnabled` must be
///    on; `canScheduleAlarms` must be true. Each failure → `.timeSensitive` with a `TierChangeReason`.
/// 5. **Quiet hours.** Global and rule quiet hours (each `[start, end)`, may span midnight) move a reminder to
///    the end of the window it falls in, repeatedly until it is outside all windows. Loud alarms honour only
///    their rule's own quiet hours: the user picked that exact time for a loud alarm, so global quiet hours
///    must not shift a wake-up alarm.
/// 6. **Deadline.** Later than the deadline → dropped (`quietHoursAfterDue` if quiet hours caused it,
///    else `afterDue`).
/// 7. **Follow-ups** (tasks and exams only; they are the only completable items): one per surviving primary
///    reminder, `.afterMinutes(n)` after its (quiet-hours-adjusted) time or `.nextMorning(at:)` on the next
///    local day; then steps 5–6 again. Completed items plan nothing, so re-planning after completion removes
///    their follow-ups.
/// 8. **Window.** Reminders at or before `now` are elapsed (skipped silently); after `horizonEnd` they are
///    deferred to a later plan (skipped silently). Drops are reported only when the nominal time is inside
///    `(now, horizonEnd]`.
/// 9. **De-duplication.** Same item, same instant → keep the highest tier, then primaries over follow-ups,
///    then the smaller ID; the rest are dropped (`duplicate`).
/// 10. **Alarm soft limit.** Alarms beyond `alarmSoftLimit` (soonest kept) fall back to Time Sensitive
///     (`alarmLimitReached`) and are listed in `alarmOverflow`.
/// 11. **Time Sensitive policy** (decision D6): `timeSensitivePolicy.isEnabled == false` → standard; lead time
///     (anchor − fire) > `maxLeadMinutes` → standard (`leadTimeTooLong`). Exactly `maxLeadMinutes` stays.
/// 12. **Budget.** Notifications sorted by fire date, then tier (alarm > timeSensitive > standard), then ID;
///     the first `budget.available` are kept, the rest dropped (`budget`) and `isSaturated` is set.
///
/// ## IDs
/// See `ReminderID`: a hash of the canonical key `r1|<source>|<rule ID or "override">|<offset>|<wall clock>`
/// (+ `|f|<follow-up>` for follow-ups). Wall clock = nominal local fire date-time for `daysBefore`, the item's
/// local date-time for `minutesBefore`. No absolute instants → a time-zone change keeps every ID and only
/// re-maps `fireDate`.
///
/// ## Next re-plan
/// The earliest of: the last scheduled fire date (alarms included); `horizonEnd` − 1 day (wall clock;
/// `horizonEnd` itself when `horizonDays == 1`); the next local midnight when the plan contains lesson or
/// pack-tonight reminders (their sources are the caller's resolved schedule window, which starts today and
/// must slide daily).
public enum ReminderPlanner {
    /// Plans reminders for `input`. Deterministic; reads no clock, zone or locale.
    public static func plan(_ input: PlannerInput) -> ReminderPlan {
        var engine = Engine(input: input)
        return engine.run()
    }
}

// MARK: - Engine

private struct Engine {
    let input: PlannerInput
    let context: CalendarContext
    let now: Date
    let today: LocalDate
    let horizonEnd: Date
    let replanBeforeHorizon: Date
    let rulesByTarget: [ReminderTarget: [ReminderRule]]
    let lessonsByID: [OccurrenceID: ResolvedLesson]

    var candidates: [Candidate] = []
    var dropped: [DroppedReminder] = []
    /// Canonical keys already handled; every ID in the plan (scheduled or dropped) is unique.
    var seenKeys = Set<String>()

    init(input: PlannerInput) {
        self.input = input
        context = input.context
        now = input.now
        let nowLocal = input.context.local(from: input.now)
        today = nowLocal.date
        let days = max(1, input.horizonDays)
        horizonEnd = input.context.date(nowLocal.date.adding(days: days), nowLocal.time)
        replanBeforeHorizon = days >= 2 ? input.context.date(nowLocal.date.adding(days: days - 1), nowLocal.time) : horizonEnd
        let live = input.rules.filter { !$0.isDeleted && $0.isEnabled }.sorted { $0.id < $1.id }
        rulesByTarget = Dictionary(grouping: live, by: \.target)
        var lessons: [OccurrenceID: ResolvedLesson] = [:]
        for lesson in input.lessons where lesson.status != .cancelled && lessons[lesson.id] == nil {
            lessons[lesson.id] = lesson
        }
        lessonsByID = lessons
    }

    mutating func run() -> ReminderPlan {
        for item in collectItems() {
            for rule in appliedRules(for: item) {
                planRule(rule, for: item)
            }
        }
        candidates = candidates.filter { $0.fire > now && $0.fire <= horizonEnd }
        deduplicate()
        applyAlarmSoftLimit()
        applyTimeSensitivePolicy()
        return finish()
    }

    // MARK: Items

    private func collectItems() -> [PlanItem] {
        var items: [PlanItem] = []
        for task in input.tasks where !task.isDeleted && !task.isCompleted {
            guard let due = task.due else { continue }
            let source = ReminderSource.task(task.id)
            let content = ContentSpec.task(title: task.title, due: due.date, time: due.time)
            let target = ReminderTarget(rawValue: task.kind.rawValue)
            switch due {
            case let .dateTime(date, time):
                items.append(timedItem(source, target, date, time, task.reminderOverride, content))
            case .date(let date):
                if let link = task.linkedLesson, link.date == date,
                   let lesson = lessonsByID[OccurrenceID.lesson(link.lessonID, on: link.date)] {
                    items.append(timedItem(source, target, date, lesson.startTime, task.reminderOverride, content))
                } else {
                    items.append(dateOnlyItem(source, target, date, task.reminderOverride, content))
                }
            }
        }
        for exam in input.exams where !exam.isDeleted && !exam.isCompleted {
            let source = ReminderSource.exam(exam.id)
            let content = ContentSpec.exam(title: exam.title, date: exam.date, start: exam.start, room: exam.room)
            if let start = exam.start {
                items.append(timedItem(source, .exam, exam.date, start, exam.reminderOverride, content))
            } else {
                items.append(dateOnlyItem(source, .exam, exam.date, exam.reminderOverride, content))
            }
        }
        for lesson in lessonsByID.values.sorted(by: { $0.id < $1.id }) {
            items.append(timedItem(.lesson(lesson.id), .lesson, lesson.date, lesson.startTime, nil, .lesson(lesson)))
        }
        for day in input.packTonight where day.itemCount > 0 {
            items.append(timedItem(.packTonight(day.date), .packTonight, day.date, day.firstLessonStart, nil,
                                   .packTonight(day)))
        }
        return items
    }

    private func timedItem(_ source: ReminderSource, _ target: ReminderTarget, _ date: LocalDate, _ time: LocalTime,
                           _ override: ReminderOverride?, _ content: ContentSpec) -> PlanItem {
        let anchor = context.date(date, time)
        return PlanItem(source: source, target: target, date: date, anchorTime: time, anchor: anchor, deadline: anchor,
                        override: override, content: content)
    }

    private func dateOnlyItem(_ source: ReminderSource, _ target: ReminderTarget, _ date: LocalDate,
                              _ override: ReminderOverride?, _ content: ContentSpec) -> PlanItem {
        let time = input.dateOnlyAnchorTime
        return PlanItem(source: source, target: target, date: date, anchorTime: time, anchor: context.date(date, time),
                        deadline: context.startOfDay(date.adding(days: 1)), override: override, content: content)
    }

    // MARK: Rules

    private func appliedRules(for item: PlanItem) -> [AppliedRule] {
        guard item.deadline > now else { return [] }
        let override = item.override
        if override?.isEnabled == false { return [] }
        let matching = rulesByTarget[item.target] ?? []
        if matching.isEmpty {
            guard let override, let offsets = override.offsets else { return [] }
            var followUp: FollowUp?
            if case .custom(let custom) = override.followUp { followUp = custom }
            return [AppliedRule(ruleID: nil, offsets: offsets, tier: override.tier ?? .standard, followUp: followUp,
                                quietHours: nil, origin: .user)]
        }
        return matching.map { rule in
            var followUp = rule.followUp
            switch override?.followUp {
            case nil, .inherit?: break
            case .none?: followUp = nil
            case .custom(let custom)?: followUp = custom
            }
            return AppliedRule(ruleID: rule.id, offsets: override?.offsets ?? rule.offsets,
                               tier: override?.tier ?? rule.tier, followUp: followUp, quietHours: rule.quietHours,
                               origin: override?.tier != nil ? .user : rule.origin)
        }
    }

    // MARK: Primaries and follow-ups

    private mutating func planRule(_ rule: AppliedRule, for item: PlanItem) {
        for offset in rule.offsets {
            let anchorKey = "\(item.date.isoString)T\(item.anchorTime.isoString)"
            let descriptor: String
            let wallClock: String
            let nominal: Date?
            switch offset {
            case .minutesBefore(let minutes):
                descriptor = "m\(minutes)"
                wallClock = anchorKey
                nominal = minutes >= 0 ? Self.representable(item.anchor.addingTimeInterval(-TimeInterval(minutes) * 60)) : nil
            case let .daysBefore(days, at):
                descriptor = "d\(days)@\(at.isoString)"
                if days >= 0, let date = item.date.addingIfValid(days: -days) {
                    wallClock = "\(date.isoString)T\(at.isoString)"
                    nominal = context.date(date, at)
                } else {
                    wallClock = anchorKey
                    nominal = nil
                }
            case .unknown(let raw):
                descriptor = "u:" + Self.canonicalJSON(raw)
                wallClock = anchorKey
                nominal = nil
            }
            let key = ["r1", item.source.rawValue, rule.ruleKey, descriptor, wallClock].joined(separator: "|")
            // The very same reminder generated twice (an offset listed twice, an item passed twice) is one reminder.
            guard seenKeys.insert(key).inserted else { continue }
            let id = ReminderID.make(key: key)
            guard let nominal else {
                if item.anchor <= horizonEnd {
                    let reason: DropReason = offset.isUnknown ? .unsupportedOffset : .invalidOffset
                    drop(id, item, rule, fire: nil, isFollowUp: false, reason)
                }
                continue
            }
            var tier = rule.tier
            var changes: [TierChangeReason] = []
            if tier == .alarm, let reason = alarmBlocker(isFollowUp: false, origin: rule.origin) {
                tier = .timeSensitive
                changes.append(reason)
            }
            guard let primary = place(id: id, key: key, item: item, rule: rule, nominal: nominal, tier: tier,
                                      changes: changes, isFollowUp: false) else { continue }
            if item.source.isCompletable, let followUp = rule.followUp {
                planFollowUp(followUp, after: primary, item: item, rule: rule)
            }
        }
    }

    private mutating func planFollowUp(_ followUp: FollowUp, after primary: Candidate, item: PlanItem, rule: AppliedRule) {
        let descriptor: String
        let nominal: Date?
        switch followUp {
        case .afterMinutes(let minutes):
            descriptor = "a\(minutes)"
            nominal = minutes > 0 ? Self.representable(primary.fire.addingTimeInterval(TimeInterval(minutes) * 60)) : nil
        case .nextMorning(let at):
            descriptor = "n\(at.isoString)"
            nominal = context.localDate(of: primary.fire).addingIfValid(days: 1).map { context.date($0, at) }
        }
        let key = primary.key + "|f|" + descriptor
        guard seenKeys.insert(key).inserted else { return }
        let id = ReminderID.make(key: key)
        guard let nominal else {
            if primary.fire > now && primary.fire <= horizonEnd {
                drop(id, item, rule, fire: nil, isFollowUp: true, .invalidOffset)
            }
            return
        }
        var tier = rule.tier
        var changes: [TierChangeReason] = []
        if tier == .alarm, let reason = alarmBlocker(isFollowUp: true, origin: rule.origin) {
            tier = .timeSensitive
            changes.append(reason)
        }
        _ = place(id: id, key: key, item: item, rule: rule, nominal: nominal, tier: tier, changes: changes,
                  isFollowUp: true)
    }

    /// Applies quiet hours and the deadline; appends and returns the candidate, or records the drop.
    private mutating func place(id: ReminderID, key: String, item: PlanItem, rule: AppliedRule, nominal: Date,
                                tier: DeliveryTier, changes: [TierChangeReason], isFollowUp: Bool) -> Candidate? {
        var windows: [QuietHours] = []
        if tier != .alarm, let global = input.settings.globalQuietHours { windows.append(global) }
        if let own = rule.quietHours { windows.append(own) }
        let (fire, moved) = QuietHoursShift.apply(nominal, windows: windows, context: context)
        guard fire <= item.deadline else {
            if nominal > now && nominal <= horizonEnd {
                let reason: DropReason = moved && nominal <= item.deadline ? .quietHoursAfterDue : .afterDue
                drop(id, item, rule, fire: fire, isFollowUp: isFollowUp, reason)
            }
            return nil
        }
        let candidate = Candidate(id: id, key: key, item: item, ruleID: rule.ruleID, requestedTier: rule.tier,
                                  tier: tier, changes: changes, fire: fire, moved: moved, isFollowUp: isFollowUp)
        candidates.append(candidate)
        return candidate
    }

    /// Why an alarm request cannot ring, or `nil` when it can (checks in the documented order).
    private func alarmBlocker(isFollowUp: Bool, origin: RuleOrigin) -> TierChangeReason? {
        let policy = input.settings.alarmPolicy
        if isFollowUp { return .followUpNeverAlarm }
        if origin == .preset && !policy.allowsPresetRules { return .presetRuleAlarm }
        if !policy.isEnabled { return .alarmsDisabled }
        if !input.canScheduleAlarms { return .alarmsUnavailable }
        return nil
    }

    private mutating func drop(_ id: ReminderID, _ item: PlanItem, _ rule: AppliedRule, fire: Date?, isFollowUp: Bool,
                               _ reason: DropReason) {
        dropped.append(DroppedReminder(id: id, source: item.source, ruleID: rule.ruleID, fireDate: fire,
                                       isFollowUp: isFollowUp, reason: reason))
    }

    // MARK: Window-wide passes

    private mutating func deduplicate() {
        let groups = Dictionary(grouping: candidates.indices) { DedupKey(source: candidates[$0].item.source, fire: candidates[$0].fire) }
        var keep = Set<Int>()
        for indices in groups.values {
            let ranked = indices.sorted { lhs, rhs in
                let a = candidates[lhs], b = candidates[rhs]
                if a.tier != b.tier { return a.tier > b.tier }
                if a.isFollowUp != b.isFollowUp { return !a.isFollowUp }
                return a.id < b.id
            }
            keep.insert(ranked[0])
            for loser in ranked.dropFirst() {
                let candidate = candidates[loser]
                dropped.append(DroppedReminder(id: candidate.id, source: candidate.item.source, ruleID: candidate.ruleID,
                                               fireDate: candidate.fire, isFollowUp: candidate.isFollowUp,
                                               reason: .duplicate))
            }
        }
        candidates = candidates.indices.filter(keep.contains).map { candidates[$0] }
    }

    private var overflow: [ReminderID] = []

    private mutating func applyAlarmSoftLimit() {
        let limit = max(0, input.alarmSoftLimit)
        let alarmIndices = candidates.indices.filter { candidates[$0].tier == .alarm }
            .sorted { Candidate.scheduleOrder(candidates[$0], candidates[$1]) }
        for index in alarmIndices.dropFirst(limit) {
            candidates[index].tier = .timeSensitive
            candidates[index].changes.append(.alarmLimitReached)
            overflow.append(candidates[index].id)
        }
    }

    private mutating func applyTimeSensitivePolicy() {
        let policy = input.settings.timeSensitivePolicy
        let maxLead = TimeInterval(max(0, policy.maxLeadMinutes)) * 60
        for index in candidates.indices where candidates[index].tier == .timeSensitive {
            if !policy.isEnabled {
                candidates[index].tier = .standard
                candidates[index].changes.append(.timeSensitiveDisabled)
            } else if candidates[index].item.anchor.timeIntervalSince(candidates[index].fire) > maxLead {
                candidates[index].tier = .standard
                candidates[index].changes.append(.leadTimeTooLong)
            }
        }
    }

    // MARK: Output

    private mutating func finish() -> ReminderPlan {
        let ordered = candidates.sorted(by: Candidate.scheduleOrder)
        let alarmCandidates = ordered.filter { $0.tier == .alarm }
        let notificationCandidates = ordered.filter { $0.tier != .alarm }
        let available = input.budget.available
        let kept = notificationCandidates.prefix(available)
        let overBudget = notificationCandidates.dropFirst(available)
        for candidate in overBudget {
            dropped.append(DroppedReminder(id: candidate.id, source: candidate.item.source, ruleID: candidate.ruleID,
                                           fireDate: candidate.fire, isFollowUp: candidate.isFollowUp, reason: .budget))
        }
        let notifications = kept.map { makeNotification($0) }
        let alarms = alarmCandidates.map { makeAlarm($0) }

        var next = replanBeforeHorizon
        if let last = (notifications.map(\.fireDate) + alarms.map(\.fireDate)).max() { next = min(next, last) }
        let sources = notifications.map(\.source) + alarms.map(\.source) + dropped.map(\.source)
        if sources.contains(where: { !$0.isCompletable }) {
            next = min(next, context.startOfDay(today.adding(days: 1)))
        }
        let sortedDropped = dropped.sorted {
            ($0.fireDate ?? .distantFuture, $0.id, $0.reason.rawValue) < ($1.fireDate ?? .distantFuture, $1.id, $1.reason.rawValue)
        }
        return ReminderPlan(generatedAt: now, horizonEnd: horizonEnd, notifications: notifications, alarms: alarms,
                            dropped: sortedDropped, isSaturated: !overBudget.isEmpty, alarmOverflow: overflow.sorted(),
                            nextReplanDate: next)
    }

    private func makeNotification(_ candidate: Candidate) -> PlannedNotification {
        let local = context.local(from: candidate.fire)
        return PlannedNotification(
            id: candidate.id, fireDate: candidate.fire, localFireTime: local, requestedTier: candidate.requestedTier,
            effectiveTier: candidate.tier, tierChanges: candidate.changes,
            content: candidate.item.content.build(fire: local.date, isFollowUp: candidate.isFollowUp),
            threadID: candidate.item.source.threadID, categoryID: candidate.item.source.category,
            source: candidate.item.source, ruleID: candidate.ruleID, isFollowUp: candidate.isFollowUp,
            movedByQuietHours: candidate.moved)
    }

    private func makeAlarm(_ candidate: Candidate) -> PlannedAlarm {
        let local = context.local(from: candidate.fire)
        return PlannedAlarm(id: candidate.id, alarmID: StableHash.uuid(candidate.key), fireDate: candidate.fire,
                            localFireTime: local,
                            content: candidate.item.content.build(fire: local.date, isFollowUp: false),
                            source: candidate.item.source, ruleID: candidate.ruleID, movedByQuietHours: candidate.moved)
    }

    /// `date` when it is a persistable instant (`TabulaJSON.millisecondsRange`), else `nil`. Offsets from persisted
    /// data (`minutesBefore(Int.max)`, a huge `afterMinutes`) then become `invalidOffset` drops instead of
    /// instants outside the calendar's years 1…9999.
    static func representable(_ date: Date) -> Date? {
        TabulaJSON.checkedMilliseconds(from: date) == nil ? nil : date
    }

    private static func canonicalJSON(_ value: JSONValue) -> String {
        guard let data = try? TabulaJSON.makeEncoder().encode(value) else { return "?" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Engine values

/// Something reminders are planned for.
private struct PlanItem {
    let source: ReminderSource
    let target: ReminderTarget
    /// The item's date (due date, exam date, lesson date, school day).
    let date: LocalDate
    /// The wall-clock time `anchor` was built from.
    let anchorTime: LocalTime
    /// `minutesBefore` offsets and the Time Sensitive lead time count back from here.
    let anchor: Date
    /// No reminder may fire after this.
    let deadline: Date
    let override: ReminderOverride?
    let content: ContentSpec
}

/// What to render for an item.
private enum ContentSpec {
    case task(title: String, due: LocalDate, time: LocalTime?)
    case exam(title: String, date: LocalDate, start: LocalTime?, room: String?)
    case lesson(ResolvedLesson)
    case packTonight(PackTonightDay)

    func build(fire: LocalDate, isFollowUp: Bool) -> ReminderContent {
        switch self {
        case let .task(title, due, time):
            return ReminderContentBuilder.task(title: title, due: due, time: time, fire: fire, isFollowUp: isFollowUp)
        case let .exam(title, date, start, room):
            return ReminderContentBuilder.exam(title: title, date: date, start: start, room: room, fire: fire,
                                               isFollowUp: isFollowUp)
        case .lesson(let lesson):
            return ReminderContentBuilder.lesson(lesson, fire: fire)
        case .packTonight(let day):
            return ReminderContentBuilder.packTonight(day, fire: fire)
        }
    }
}

/// A rule as applied to one item (after the item's override).
private struct AppliedRule {
    let ruleID: ReminderRule.ID?
    let offsets: [ReminderOffset]
    let tier: DeliveryTier
    let followUp: FollowUp?
    let quietHours: QuietHours?
    let origin: RuleOrigin

    var ruleKey: String { ruleID?.uuidString ?? "override" }
}

private struct Candidate {
    let id: ReminderID
    let key: String
    let item: PlanItem
    let ruleID: ReminderRule.ID?
    let requestedTier: DeliveryTier
    var tier: DeliveryTier
    var changes: [TierChangeReason]
    let fire: Date
    let moved: Bool
    let isFollowUp: Bool

    /// Fire date ascending, then tier descending, then ID ascending.
    static func scheduleOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.fire != rhs.fire { return lhs.fire < rhs.fire }
        if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
        return lhs.id < rhs.id
    }
}

private struct DedupKey: Hashable {
    let source: ReminderSource
    let fire: Date
}

extension ReminderOffset {
    fileprivate var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }
}

extension ReminderSource {
    /// Notification thread: per task/exam, one shared thread for lessons and one for pack-tonight.
    var threadID: String {
        switch self {
        case .task, .exam: return rawValue
        case .lesson: return "lessons"
        case .packTonight: return "packTonight"
        }
    }

    /// Category by source kind.
    var category: ReminderCategory {
        switch self {
        case .task: return .task
        case .exam: return .exam
        case .lesson: return .lesson
        case .packTonight: return .packTonight
        }
    }
}

// MARK: - Quiet hours

/// Moves instants out of quiet-hours windows.
enum QuietHoursShift {
    /// Moves `instant` to the end of every window (in `context`) it falls into, until it is in none.
    /// Empty windows (`start == end`) are ignored. Bounded: windows that cover the whole day cannot be
    /// escaped, and the result then stays inside one (the deadline check usually drops it).
    static func apply(_ instant: Date, windows: [QuietHours], context: CalendarContext) -> (Date, moved: Bool) {
        let active = windows.filter { $0.start != $0.end }
        guard !active.isEmpty else { return (instant, false) }
        var current = instant
        var moved = false
        for _ in 0..<8 {
            var changed = false
            for window in active {
                let local = context.local(from: current)
                guard window.contains(local.time) else { continue }
                let endDate = window.spansMidnight && local.time >= window.start ? local.date.adding(days: 1) : local.date
                // In a fall-back overlap the window end can occur twice; take the first occurrence after `current`
                // (inside the repeated hour the earlier one may already be past).
                let end: Date
                switch context.resolve(endDate, window.end) {
                case .repeated(let earlier, let later): end = earlier > current ? earlier : later
                case let resolution: end = resolution.date
                }
                if end > current {
                    current = end
                    moved = true
                    changed = true
                }
            }
            if !changed { break }
        }
        return (current, moved)
    }
}
