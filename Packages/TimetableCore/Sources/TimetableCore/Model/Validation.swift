import Foundation

/// A problem found by `TabulaDatabase.validate()`.
///
/// Validation never mutates or rejects data; callers decide (import preview, debug screen, repair).
/// "Passes validation" means **no `.error` issues**; warnings and infos are allowed.
public struct ValidationIssue: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Severity, ordered `info < warning < error`.
    public enum Severity: String, Hashable, Sendable, Codable, Comparable, CaseIterable {
        /// Worth knowing (e.g. an enabled day without lessons, a value from a newer app version).
        case info
        /// Suspicious but usable (e.g. overlapping periods, a reference to a deleted entity).
        case warning
        /// Broken data (dangling reference, duplicate ID, end ≤ start, out-of-range value).
        case error

        private var rank: Int {
            switch self {
            case .info: return 0
            case .warning: return 1
            case .error: return 2
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    /// Kind of issue. Raw values are stable (used in l10n keys and logs).
    public enum Code: String, Hashable, Sendable, Codable, CaseIterable {
        /// `schemaVersion` differs from `TabulaDatabase.currentSchemaVersion`.
        case unsupportedSchemaVersion
        /// The same UUID is used twice (entities, or children/periods within their parent).
        case duplicateID
        /// A referenced entity/period does not exist.
        case danglingReference
        /// A live entity references a tombstoned one.
        case referencesDeletedEntity
        /// A reference points into a different timetable than the referencing entity's.
        case crossTimetableReference
        /// End is not after start (periods, lessons, exams) or an empty quiet-hours window.
        case invalidTimeRange
        /// A date range ends before it starts.
        case invalidDateRange
        /// Two periods of one bell schedule overlap.
        case overlappingPeriods
        /// A value is out of its allowed range or inconsistent with its timetable.
        case invalidValue
        /// A cycle week (`followDay.cycleWeek`, `occurrence.cycleWeeks`) outside 1…length of the timetable's week
        /// cycle (error): the override or lesson can never apply as intended.
        case cycleWeekOutOfRange
        /// A day cycle's `schoolDays` and the timetable's `enabledDays` disagree (warning): a school day that is
        /// not shown silently consumes a cycle day, and a shown day that is not a school day never has lessons.
        case schoolDaysMismatch
        /// A value from an open vocabulary / open union this version does not know (preserved as is).
        case unknownValue
        /// An enabled weekday (or cycle day) has no lessons.
        case emptyScheduleDay

        /// Catalog key of the message.
        public var l10nKey: String { "validation.\(rawValue)" }
    }

    /// Severity.
    public var severity: Severity
    /// Kind.
    public var code: Code
    /// Type of the entity that has the problem.
    public var entityType: EntityType
    /// ID of the entity that has the problem.
    public var entityID: UUID
    /// ID of the child record/period concerned, if any.
    public var childID: UUID?
    /// JSON field name concerned, if any (e.g. `"subjectID"`, `"slot"`, `"enabledDays"`).
    public var field: String?
    /// The other entity involved (the missing/deleted target, the overlapping period, …), if any.
    public var relatedID: UUID?
    /// The offending value in text form (e.g. an unknown raw value, a weekday number), if useful.
    public var value: String?

    /// Creates an issue.
    public init(severity: Severity, code: Code, entityType: EntityType, entityID: UUID, childID: UUID? = nil,
                field: String? = nil, relatedID: UUID? = nil, value: String? = nil) {
        self.severity = severity
        self.code = code
        self.entityType = entityType
        self.entityID = entityID
        self.childID = childID
        self.field = field
        self.relatedID = relatedID
        self.value = value
    }

    /// Localisable message `validation.<code>` with arguments (entity type name, field name, value) — always
    /// three arguments; absent ones are empty strings.
    public var message: LocalizedText {
        LocalizedText(key: code.l10nKey, args: [
            .text(LocalizedText(key: entityType.l10nKey)),
            .string(field ?? ""),
            .string(value ?? ""),
        ])
    }

    /// Debug rendering.
    public var description: String {
        var parts = ["\(severity.rawValue) \(code.rawValue) \(entityType.rawValue) \(entityID.uuidString)"]
        if let childID { parts.append("child=\(childID.uuidString)") }
        if let field { parts.append("field=\(field)") }
        if let relatedID { parts.append("related=\(relatedID.uuidString)") }
        if let value { parts.append("value=\(value)") }
        return parts.joined(separator: " ")
    }

    fileprivate var sortKey: [String] {
        [entityType.rawValue, entityID.uuidString, field ?? "", code.rawValue, childID?.uuidString ?? "",
         relatedID?.uuidString ?? "", value ?? ""]
    }
}

extension TabulaDatabase {
    /// Checks referential integrity and invariants. Deterministic: the same database yields the same issues
    /// in the same order. Tombstoned entities are skipped (except for duplicate-ID and metadata checks).
    public func validate() -> [ValidationIssue] {
        var validator = Validator(db: self)
        validator.run()
        return validator.issues.sorted { $0.sortKey.lexicographicallyPrecedes($1.sortKey) }
    }

    /// `true` when `validate()` reports no `.error` issue.
    public var isValid: Bool { !validate().contains { $0.severity == .error } }
}

// MARK: - Validator

private struct Owner {
    let type: EntityType
    let id: UUID
}

private struct Validator {
    let db: TabulaDatabase
    var issues: [ValidationIssue] = []

    let timetables: [Timetable.ID: Timetable]
    let subjects: [Subject.ID: Subject]
    let bellSchedules: [BellSchedule.ID: BellSchedule]
    let lessons: [Lesson.ID: Lesson]
    let terms: [Term.ID: Term]

    init(db: TabulaDatabase) {
        self.db = db
        timetables = Self.index(db.timetables)
        subjects = Self.index(db.subjects)
        bellSchedules = Self.index(db.bellSchedules)
        lessons = Self.index(db.lessons)
        terms = Self.index(db.terms)
    }

    private static func index<T: SyncEntity>(_ items: [T]) -> [T.ID: T] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    mutating func run() {
        checkSchemaVersion()
        checkDuplicateIDs()
        checkMetadata()
        checkSettings()
        for timetable in db.timetables where !timetable.isDeleted { check(timetable) }
        for subject in db.subjects where !subject.isDeleted {
            reference(subject.timetableID, timetables, owner: owner(subject), field: "timetableID")
        }
        for schedule in db.bellSchedules where !schedule.isDeleted { check(schedule) }
        for lesson in db.lessons where !lesson.isDeleted { check(lesson) }
        for term in db.terms where !term.isDeleted {
            reference(term.timetableID, timetables, owner: owner(term), field: "timetableID")
            if term.range.isEmpty { add(.error, .invalidDateRange, owner(term), field: "range") }
        }
        for item in db.breaks where !item.isDeleted { check(item) }
        for item in db.overrides where !item.isDeleted { check(item) }
        for task in db.tasks where !task.isDeleted { check(task) }
        for exam in db.exams where !exam.isDeleted { check(exam) }
        for rule in db.reminderRules where !rule.isDeleted { check(rule) }
    }

    // MARK: Helpers

    private func owner<T: SyncEntity>(_ entity: T) -> Owner { Owner(type: T.entityType, id: entity.id.uuid) }

    private mutating func add(_ severity: ValidationIssue.Severity, _ code: ValidationIssue.Code, _ owner: Owner,
                              child: UUID? = nil, field: String? = nil, related: UUID? = nil, value: String? = nil) {
        issues.append(ValidationIssue(severity: severity, code: code, entityType: owner.type, entityID: owner.id,
                                      childID: child, field: field, relatedID: related, value: value))
    }

    /// Checks that `id` exists, is live and (optionally) belongs to `timetable`.
    private mutating func reference<T: SyncEntity>(_ id: T.ID, _ index: [T.ID: T], owner: Owner, field: String,
                                                   timetable: Timetable.ID? = nil,
                                                   timetableOf: (T) -> Timetable.ID? = { _ in nil }) {
        guard let target = index[id] else {
            add(.error, .danglingReference, owner, field: field, related: id.uuid)
            return
        }
        if target.isDeleted {
            add(.warning, .referencesDeletedEntity, owner, field: field, related: id.uuid)
            return
        }
        if let timetable, let actual = timetableOf(target), actual != timetable {
            add(.warning, .crossTimetableReference, owner, field: field, related: id.uuid)
        }
    }

    private mutating func unknown<V: OpenVocabulary>(_ value: V?, _ owner: Owner, child: UUID? = nil, field: String) {
        if let value, !value.isKnown { add(.info, .unknownValue, owner, child: child, field: field, value: value.rawValue) }
    }

    // MARK: Database-wide

    private mutating func checkSchemaVersion() {
        if db.schemaVersion != TabulaDatabase.currentSchemaVersion {
            add(.error, .unsupportedSchemaVersion, Owner(type: .settings, id: db.settings.id.uuid),
                field: "schemaVersion", value: String(db.schemaVersion))
        }
    }

    private mutating func checkDuplicateIDs() {
        var all: [(EntityType, UUID)] = [(.settings, db.settings.id.uuid)]
        all += db.timetables.map { (.timetable, $0.id.uuid) }
        all += db.subjects.map { (.subject, $0.id.uuid) }
        all += db.bellSchedules.map { (.bellSchedule, $0.id.uuid) }
        all += db.lessons.map { (.lesson, $0.id.uuid) }
        all += db.terms.map { (.term, $0.id.uuid) }
        all += db.breaks.map { (.calendarBreak, $0.id.uuid) }
        all += db.overrides.map { (.scheduleOverride, $0.id.uuid) }
        all += db.tasks.map { (.task, $0.id.uuid) }
        all += db.exams.map { (.exam, $0.id.uuid) }
        all += db.reminderRules.map { (.reminderRule, $0.id.uuid) }
        var seen = Set<UUID>()
        for (type, id) in all where !seen.insert(id).inserted {
            add(.error, .duplicateID, Owner(type: type, id: id), field: "id")
        }
        for task in db.tasks {
            var children = Set<UUID>()
            for id in task.subtasks.map(\.id.uuid) + task.attachments.map(\.id.uuid) where !children.insert(id).inserted {
                add(.error, .duplicateID, owner(task), child: id, field: "id")
            }
        }
        for schedule in db.bellSchedules {
            var periods = Set<UUID>()
            for period in schedule.periods where !periods.insert(period.id.uuid).inserted {
                add(.error, .duplicateID, owner(schedule), child: period.id.uuid, field: "periods")
            }
        }
    }

    private mutating func checkMetadata() {
        func check(_ meta: EntityMeta, _ owner: Owner, child: UUID? = nil) -> [ValidationIssue] {
            var found: [ValidationIssue] = []
            if meta.updatedAt < meta.createdAt {
                found.append(ValidationIssue(severity: .warning, code: .invalidValue, entityType: owner.type,
                                             entityID: owner.id, childID: child, field: "meta.updatedAt"))
            }
            if meta.fieldClocks.values.contains(where: { $0 > meta.updatedAt || $0 < meta.createdAt }) {
                found.append(ValidationIssue(severity: .warning, code: .invalidValue, entityType: owner.type,
                                             entityID: owner.id, childID: child, field: "meta.fieldClocks"))
            }
            return found
        }
        issues += check(db.settings.meta, Owner(type: .settings, id: db.settings.id.uuid))
        for item in db.timetables { issues += check(item.meta, owner(item)) }
        for item in db.subjects { issues += check(item.meta, owner(item)) }
        for item in db.bellSchedules { issues += check(item.meta, owner(item)) }
        for item in db.lessons { issues += check(item.meta, owner(item)) }
        for item in db.terms { issues += check(item.meta, owner(item)) }
        for item in db.breaks { issues += check(item.meta, owner(item)) }
        for item in db.overrides { issues += check(item.meta, owner(item)) }
        for item in db.tasks {
            issues += check(item.meta, owner(item))
            for child in item.subtasks { issues += check(child.meta, owner(item), child: child.id.uuid) }
            for child in item.attachments { issues += check(child.meta, owner(item), child: child.id.uuid) }
        }
        for item in db.exams { issues += check(item.meta, owner(item)) }
        for item in db.reminderRules { issues += check(item.meta, owner(item)) }
    }

    // MARK: Settings

    private mutating func checkSettings() {
        let settings = db.settings
        let me = Owner(type: .settings, id: settings.id.uuid)
        if settings.id != AppSettings.singletonID { add(.warning, .invalidValue, me, field: "id") }
        if settings.isDeleted { add(.error, .invalidValue, me, field: "meta.isDeleted") }
        if let active = settings.activeTimetableID {
            reference(active, timetables, owner: me, field: "activeTimetableID")
        }
        if case .fixed(let identifier) = settings.timeZoneMode, TimeZone(identifier: identifier) == nil {
            add(.warning, .invalidValue, me, field: "timeZoneMode", value: identifier)
        }
        unknown(settings.palettePackID, me, field: "palettePackID")
        if let quiet = settings.globalQuietHours, quiet.start == quiet.end {
            add(.warning, .invalidTimeRange, me, field: "globalQuietHours")
        }
        if settings.timeSensitivePolicy.maxLeadMinutes < 0 {
            add(.error, .invalidValue, me, field: "timeSensitivePolicy", value: String(settings.timeSensitivePolicy.maxLeadMinutes))
        }
    }

    // MARK: Timetable

    private mutating func check(_ timetable: Timetable) {
        let me = owner(timetable)
        if timetable.enabledDays.isEmpty { add(.warning, .invalidValue, me, field: "enabledDays") }
        switch timetable.rotation {
        case .none:
            break
        case .weekCycle(let cycle):
            if !WeekCycle.validLengths.contains(cycle.length) {
                add(.error, .invalidValue, me, field: "rotation", value: String(cycle.length))
            }
            if let labels = cycle.labels, labels.count != cycle.length {
                add(.warning, .invalidValue, me, field: "rotation.labels", value: String(labels.count))
            }
            if case .referenceWeek(_, let week) = cycle.anchor, !(1...max(1, cycle.length)).contains(week) {
                add(.error, .invalidValue, me, field: "rotation.anchor", value: String(week))
            }
        case .dayCycle(let cycle):
            if !DayCycle.validLengths.contains(cycle.length) {
                add(.error, .invalidValue, me, field: "rotation", value: String(cycle.length))
            }
            if !(1...max(1, cycle.length)).contains(cycle.anchorIndex) {
                add(.error, .invalidValue, me, field: "rotation.anchorIndex", value: String(cycle.anchorIndex))
            }
            if cycle.schoolDays.isEmpty { add(.error, .invalidValue, me, field: "rotation.schoolDays") }
            checkSchoolDays(cycle, timetable: timetable)
            if let labels = cycle.labels, labels.count != cycle.length {
                add(.warning, .invalidValue, me, field: "rotation.labels", value: String(labels.count))
            }
        }
        switch timetable.timeStructure {
        case .bellSchedule:
            for id in timetable.timeStructure.referencedBellScheduleIDs {
                reference(id, bellSchedules, owner: me, field: "timeStructure", timetable: timetable.id,
                          timetableOf: { $0.timetableID })
            }
        case .freeForm(let minutes):
            if !(1..<LocalTime.minutesPerDay).contains(minutes) {
                add(.error, .invalidValue, me, field: "timeStructure", value: String(minutes))
            }
        }
        for field in timetable.fieldVisibility.visibleFields.sorted() { unknown(field, me, field: "fieldVisibility") }
        unknown(timetable.defaultView, me, field: "defaultView")
        unknown(timetable.palettePackID, me, field: "palettePackID")
        checkEmptyDays(timetable)
    }

    /// Day cycle vs. shown weekdays (Phase 1 Stage 3): one warning per weekday that is a school day but not
    /// enabled (`rotation.schoolDays`) or enabled but not a school day (`enabledDays`). An empty set is reported
    /// elsewhere.
    private mutating func checkSchoolDays(_ cycle: DayCycle, timetable: Timetable) {
        guard !cycle.schoolDays.isEmpty, !timetable.enabledDays.isEmpty else { return }
        let me = owner(timetable)
        for day in cycle.schoolDays.subtracting(timetable.enabledDays).sorted() {
            add(.warning, .schoolDaysMismatch, me, field: "rotation.schoolDays", value: String(day.rawValue))
        }
        for day in timetable.enabledDays.subtracting(cycle.schoolDays).sorted() {
            add(.warning, .schoolDaysMismatch, me, field: "enabledDays", value: String(day.rawValue))
        }
    }

    private mutating func checkEmptyDays(_ timetable: Timetable) {
        let keys = Set(db.lessons.filter { !$0.isDeleted && $0.timetableID == timetable.id }.map(\.occurrence.day))
        switch timetable.rotation {
        case .none, .weekCycle:
            for day in timetable.enabledDays.sorted() where !keys.contains(.weekday(day)) {
                add(.info, .emptyScheduleDay, owner(timetable), field: "enabledDays", value: String(day.rawValue))
            }
        case .dayCycle(let cycle):
            guard DayCycle.validLengths.contains(cycle.length) else { return }
            for index in 1...cycle.length where !keys.contains(.cycleDay(index)) {
                add(.info, .emptyScheduleDay, owner(timetable), field: "rotation", value: String(index))
            }
        }
    }

    // MARK: Bell schedule

    private mutating func check(_ schedule: BellSchedule) {
        let me = owner(schedule)
        reference(schedule.timetableID, timetables, owner: me, field: "timetableID")
        let periods = schedule.periods
        for period in periods {
            if period.end <= period.start { add(.error, .invalidTimeRange, me, child: period.id.uuid, field: "periods") }
            unknown(period.kind, me, child: period.id.uuid, field: "periods.kind")
        }
        let valid = periods.filter { $0.end > $0.start }
        for i in valid.indices {
            for j in valid.indices where j > i {
                let a = valid[i], b = valid[j]
                if a.start < b.end && b.start < a.end {
                    let (first, second) = (a.start, a.id) <= (b.start, b.id) ? (a, b) : (b, a)
                    add(.warning, .overlappingPeriods, me, child: second.id.uuid, field: "periods", related: first.id.uuid)
                }
            }
        }
    }

    // MARK: Lesson

    private mutating func check(_ lesson: Lesson) {
        let me = owner(lesson)
        reference(lesson.timetableID, timetables, owner: me, field: "timetableID")
        reference(lesson.subjectID, subjects, owner: me, field: "subjectID", timetable: lesson.timetableID,
                  timetableOf: { $0.timetableID })
        let timetable = timetables[lesson.timetableID]
        if let timetable {
            checkDayKey(lesson.occurrence.day, timetable: timetable, owner: me, field: "occurrence")
            if case .weekday(let day) = lesson.occurrence.day, !timetable.enabledDays.contains(day) {
                add(.warning, .invalidValue, me, field: "occurrence", value: String(day.rawValue))
            }
            if let weeks = lesson.occurrence.cycleWeeks {
                checkCycleWeeks(weeks, timetable: timetable, owner: me)
            }
        }
        checkSlot(lesson.slot, timetable: timetable, owner: me, field: "slot")
        switch lesson.validity {
        case .always:
            break
        case .terms(let ids):
            if ids.isEmpty { add(.warning, .invalidValue, me, field: "validity") }
            for id in ids.sorted() {
                reference(id, terms, owner: me, field: "validity", timetable: lesson.timetableID,
                          timetableOf: { $0.timetableID })
            }
        case .range(let range):
            if range.isEmpty { add(.error, .invalidDateRange, me, field: "validity") }
        }
        unknown(lesson.lessonType, me, field: "lessonType")
    }

    private mutating func checkDayKey(_ key: DayKey, timetable: Timetable, owner: Owner, field: String) {
        switch (key, timetable.rotation) {
        case (.weekday, .dayCycle):
            add(.error, .invalidValue, owner, field: field, value: "weekday")
        case (.cycleDay(let index), .dayCycle(let cycle)):
            if !(1...max(1, cycle.length)).contains(index) {
                add(.error, .invalidValue, owner, field: field, value: String(index))
            }
        case (.cycleDay(let index), _):
            add(.error, .invalidValue, owner, field: field, value: String(index))
        case (.weekday, _):
            break
        }
    }

    private mutating func checkCycleWeeks(_ weeks: Set<Int>, timetable: Timetable, owner: Owner) {
        guard case .weekCycle(let cycle) = timetable.rotation else {
            add(.warning, .invalidValue, owner, field: "occurrence.cycleWeeks")
            return
        }
        if weeks.isEmpty { add(.warning, .invalidValue, owner, field: "occurrence.cycleWeeks") }
        for week in weeks.sorted() where !(1...max(1, cycle.length)).contains(week) {
            add(.error, .cycleWeekOutOfRange, owner, field: "occurrence.cycleWeeks", value: String(week))
        }
    }

    private mutating func checkSlot(_ slot: LessonSlot, timetable: Timetable?, owner: Owner, field: String) {
        switch slot {
        case let .time(start, end):
            if end <= start { add(.error, .invalidTimeRange, owner, field: field) }
        case let .period(periodID, span):
            if span < 1 { add(.error, .invalidValue, owner, field: field, value: String(span)) }
            guard let timetable else { return }
            guard case .bellSchedule(let defaultID, _) = timetable.timeStructure else {
                add(.warning, .invalidValue, owner, field: field, value: "freeForm")
                return
            }
            let schedules = db.bellSchedules.filter { !$0.isDeleted && $0.timetableID == timetable.id }
            guard schedules.contains(where: { $0.period(periodID) != nil }) else {
                add(.error, .danglingReference, owner, field: field, related: periodID.uuid)
                return
            }
            guard let defaultSchedule = bellSchedules[defaultID], let period = defaultSchedule.period(periodID) else { return }
            if period.kind != .lesson {
                add(.warning, .invalidValue, owner, field: field, value: period.kind.rawValue)
                return
            }
            let lessonPeriods = defaultSchedule.lessonPeriods
            if span >= 1, let index = lessonPeriods.firstIndex(where: { $0.id == periodID }),
               span > lessonPeriods.count - index {   // not `index + span`: a hostile span would overflow
                add(.warning, .invalidValue, owner, field: field, value: String(span))
            }
        }
    }

    // MARK: Break / override

    private mutating func check(_ item: CalendarBreak) {
        let me = owner(item)
        if let timetableID = item.timetableID { reference(timetableID, timetables, owner: me, field: "timetableID") }
        if item.range.isEmpty { add(.error, .invalidDateRange, me, field: "range") }
        unknown(item.kind, me, field: "kind")
    }

    private mutating func check(_ item: ScheduleOverride) {
        let me = owner(item)
        reference(item.timetableID, timetables, owner: me, field: "timetableID")
        let timetable = timetables[item.timetableID]
        switch item.change {
        case .cancelLesson(let lessonID):
            reference(lessonID, lessons, owner: me, field: "change", timetable: item.timetableID,
                      timetableOf: { $0.timetableID })
        case let .modifyLesson(lessonID, patch):
            reference(lessonID, lessons, owner: me, field: "change", timetable: item.timetableID,
                      timetableOf: { $0.timetableID })
            if let subjectID = patch.subjectID {
                reference(subjectID, subjects, owner: me, field: "change.patch.subjectID", timetable: item.timetableID,
                          timetableOf: { $0.timetableID })
            }
            if let slot = patch.slot { checkSlot(slot, timetable: timetable, owner: me, field: "change.patch.slot") }
            unknown(patch.lessonType, me, field: "change.patch.lessonType")
        case .addLesson(let lesson):
            reference(lesson.subjectID, subjects, owner: me, field: "change.lesson.subjectID",
                      timetable: item.timetableID, timetableOf: { $0.timetableID })
            checkSlot(lesson.slot, timetable: timetable, owner: me, field: "change.lesson.slot")
            unknown(lesson.lessonType, me, field: "change.lesson.lessonType")
        case .cancelDay:
            break
        case .useBellSchedule(let scheduleID):
            reference(scheduleID, bellSchedules, owner: me, field: "change", timetable: item.timetableID,
                      timetableOf: { $0.timetableID })
        case let .followDay(key, cycleWeek):
            if let timetable {
                checkDayKey(key, timetable: timetable, owner: me, field: "change.day")
                if let cycleWeek {
                    if case .weekCycle(let cycle) = timetable.rotation {
                        if !(1...max(1, cycle.length)).contains(cycleWeek) {
                            add(.error, .cycleWeekOutOfRange, me, field: "change.cycleWeek", value: String(cycleWeek))
                        }
                    } else {
                        add(.warning, .invalidValue, me, field: "change.cycleWeek", value: String(cycleWeek))
                    }
                }
            }
        case .unknown(let raw):
            add(.info, .unknownValue, me, field: "change", value: raw["kind"]?.stringValue)
        }
    }

    // MARK: Task / exam / rule

    private mutating func check(_ task: TaskItem) {
        let me = owner(task)
        if let subjectID = task.subjectID { reference(subjectID, subjects, owner: me, field: "subjectID") }
        if let timetableID = task.timetableID { reference(timetableID, timetables, owner: me, field: "timetableID") }
        if let link = task.linkedLesson { reference(link.lessonID, lessons, owner: me, field: "linkedLesson") }
        unknown(task.kind, me, field: "kind")
        if let rule = task.repeatRule {
            if rule.interval < 1 { add(.error, .invalidValue, me, field: "repeatRule", value: String(rule.interval)) }
            unknown(rule.frequency, me, field: "repeatRule.frequency")
        }
        for attachment in task.attachments where !attachment.meta.isDeleted {
            unknown(attachment.kind, me, child: attachment.id.uuid, field: "attachments.kind")
        }
        if let override = task.reminderOverride, let offsets = override.offsets {
            checkOffsets(offsets, owner: me, field: "reminderOverride.offsets")
        }
    }

    private mutating func check(_ exam: Exam) {
        let me = owner(exam)
        if let subjectID = exam.subjectID { reference(subjectID, subjects, owner: me, field: "subjectID") }
        if let timetableID = exam.timetableID { reference(timetableID, timetables, owner: me, field: "timetableID") }
        if let start = exam.start, let end = exam.end, end <= start { add(.error, .invalidTimeRange, me, field: "end") }
        unknown(exam.kind, me, field: "kind")
        if let override = exam.reminderOverride, let offsets = override.offsets {
            checkOffsets(offsets, owner: me, field: "reminderOverride.offsets")
        }
    }

    private mutating func check(_ rule: ReminderRule) {
        let me = owner(rule)
        unknown(rule.target, me, field: "target")
        if rule.offsets.isEmpty { add(.warning, .invalidValue, me, field: "offsets") }
        checkOffsets(rule.offsets, owner: me, field: "offsets")
        if case .afterMinutes(let minutes) = rule.followUp, minutes <= 0 {
            add(.error, .invalidValue, me, field: "followUp", value: String(minutes))
        }
        if let quiet = rule.quietHours, quiet.start == quiet.end { add(.warning, .invalidTimeRange, me, field: "quietHours") }
        if rule.origin == .preset && rule.tier == .alarm {
            add(.warning, .invalidValue, me, field: "tier", value: rule.tier.rawValue)
        }
    }

    private mutating func checkOffsets(_ offsets: [ReminderOffset], owner: Owner, field: String) {
        for offset in offsets {
            switch offset {
            case .minutesBefore(let minutes) where minutes < 0:
                add(.error, .invalidValue, owner, field: field, value: String(minutes))
            case .daysBefore(let days, _) where days < 0:
                add(.error, .invalidValue, owner, field: field, value: String(days))
            case .unknown(let raw):
                add(.info, .unknownValue, owner, field: field, value: raw["kind"]?.stringValue)
            default:
                break
            }
        }
    }
}
