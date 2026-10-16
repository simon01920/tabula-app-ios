/// The outcome of building a payload: the payload plus what export had to change.
public struct ShareExportResult: Hashable, Sendable {
    /// The (validated) payload.
    public var payload: SharePayloadV1
    /// What was shortened, cleaned, skipped or dropped (empty when nothing was).
    public var warnings: [ShareWarning]
}

/// Builds share payloads from the user's database (docs/specs/SHARE_FORMAT.md §3).
///
/// What is shared: the live timetable, its live subjects, bell schedules, terms and lessons, live breaks of the
/// timetable plus global breaks, and — with "Include tasks" — open (not completed) live tasks and exams that
/// belong to the timetable (by `timetableID`, or without one but linked to one of its subjects). Never shared:
/// IDs and sync metadata, schedule overrides (v1), reminder rules, settings, task/exam completion, attachments
/// and reminder overrides, the timetable's sort index. Subjects carry their display order as the dense rank of
/// `sortIndex` (`ShareSubject.sortIndex`, wire key `o`).
///
/// Canonical order (determinism): every collection sorted by its source entity ID; periods by
/// (start, end, ID); period keys numbered by first appearance in that order; subtasks by (sortIndex, ID).
/// The same database therefore always yields the same payload, however its arrays are ordered.
public enum ShareExport {
    /// Builds and validates the payload for `timetableID`.
    ///
    /// Text is cleaned and shortened to the limits, lists are shortened, lessons whose subject or period is
    /// missing are skipped and malformed vocabulary/symbol values are dropped — each reported as a warning.
    /// - Throws: `.timetableNotFound`, `.tooMany` when a collection exceeds its limit, or any validation error
    ///   the source data still causes (e.g. a lesson whose end is before its start).
    public static func makePayload(from db: TabulaDatabase, timetableID: Timetable.ID,
                                   includeTasks: Bool) throws(ShareError) -> ShareExportResult {
        guard let source = db.timetables.first(where: { $0.id == timetableID && !$0.isDeleted }) else {
            throw .timetableNotFound
        }
        var builder = Builder(db: db, source: source, includeTasks: includeTasks)
        let payload = try builder.build()
        _ = try payload.validate()
        return ShareExportResult(payload: payload, warnings: builder.sanitizer.warnings(skippedLessons: builder.skippedLessons))
    }

    /// Builds, validates and encodes the payload for `timetableID`.
    public static func encode(from db: TabulaDatabase, timetableID: Timetable.ID,
                              includeTasks: Bool) throws(ShareError) -> (envelope: ShareEnvelope, warnings: [ShareWarning]) {
        let result = try makePayload(from: db, timetableID: timetableID, includeTasks: includeTasks)
        return (try ShareCodec.encode(result.payload), result.warnings)
    }

    // MARK: - Builder

    private struct Builder {
        let db: TabulaDatabase
        let source: Timetable
        let includeTasks: Bool
        var sanitizer = Sanitizer()
        var skippedLessons = 0

        init(db: TabulaDatabase, source: Timetable, includeTasks: Bool) {
            self.db = db
            self.source = source
            self.includeTasks = includeTasks
        }

        mutating func build() throws(ShareError) -> SharePayloadV1 {
            let ttID = source.id
            let subjects = db.subjects.filter { $0.timetableID == ttID && !$0.isDeleted }.sorted { $0.id < $1.id }
            let schedules = db.bellSchedules.filter { $0.timetableID == ttID && !$0.isDeleted }.sorted { $0.id < $1.id }
            let terms = db.terms.filter { $0.timetableID == ttID && !$0.isDeleted }.sorted { $0.id < $1.id }
            let breaks = db.breaks.filter { ($0.timetableID == nil || $0.timetableID == ttID) && !$0.isDeleted }
                .sorted { $0.id < $1.id }
            let lessons = db.lessons.filter { $0.timetableID == ttID && !$0.isDeleted }.sorted { $0.id < $1.id }

            try limit(.subjects, subjects.count)
            try limit(.bellSchedules, schedules.count)
            try limit(.terms, terms.count)
            try limit(.breaks, breaks.count)
            try limit(.lessons, lessons.count)

            let subjectIndex = Self.indexMap(subjects.map(\.id))
            let subjectRanks = SubjectOrder.denseRanks(subjects)
            let scheduleIndex = Self.indexMap(schedules.map(\.id))
            let termIndex = Self.indexMap(terms.map(\.id))

            // Period keys: first appearance over schedules (ID order) and periods (start, end, ID).
            var periodKey: [Period.ID: Int] = [:]
            var sharedSchedules: [ShareBellSchedule] = []
            for schedule in schedules {
                let periods = schedule.periods.sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
                var shared: [SharePeriod] = []
                for period in periods {
                    let key: Int
                    if let existing = periodKey[period.id] {
                        key = existing
                    } else {
                        key = periodKey.count
                        periodKey[period.id] = key
                    }
                    shared.append(SharePeriod(key: key, label: sanitizer.optionalName(period.label), start: period.start,
                                              end: period.end, kind: sanitizer.vocabulary(period.kind) ?? .lesson))
                }
                sharedSchedules.append(ShareBellSchedule(name: sanitizer.name(schedule.name), periods: shared))
            }

            var lessonIndex: [Lesson.ID: Int] = [:]
            var sharedLessons: [ShareLesson] = []
            for lesson in lessons {
                guard let subject = subjectIndex[lesson.subjectID] else { skippedLessons += 1; continue }
                let slot: ShareLessonSlot
                switch lesson.slot {
                case let .period(periodID, span):
                    guard let key = periodKey[periodID] else { skippedLessons += 1; continue }
                    slot = .period(key: key, span: span)
                case let .time(start, end):
                    slot = .time(start: start, end: end)
                }
                let validity: ShareValidity
                switch lesson.validity {
                case .always: validity = .always
                case .terms(let ids): validity = .terms(Set(ids.compactMap { termIndex[$0] }))
                case .range(let range): validity = .range(range)
                case .unknown:
                    // A validity kind from a newer version cannot be expressed in v1 and must not widen to
                    // "always": the lesson is left out (counted in `valuesDropped`).
                    sanitizer.dropped += 1
                    continue
                }
                lessonIndex[lesson.id] = sharedLessons.count
                sharedLessons.append(ShareLesson(
                    subject: subject, day: lesson.occurrence.day, cycleWeeks: lesson.occurrence.cycleWeeks, slot: slot,
                    validity: validity, room: sanitizer.optionalName(lesson.room),
                    building: sanitizer.optionalName(lesson.building), teacher: sanitizer.optionalName(lesson.teacher),
                    lessonType: lesson.lessonType.flatMap { sanitizer.vocabulary($0) },
                    notes: sanitizer.optionalNotes(lesson.notes),
                    bringList: sanitizer.list(lesson.bringList, maxItems: ShareLimits.maxBringListItems)))
            }

            let timeStructure: ShareTimeStructure
            switch source.timeStructure {
            case let .bellSchedule(defaultID, perWeekday):
                // A missing schedule maps to an out-of-range index, which validation reports.
                timeStructure = .bellSchedule(defaultIndex: scheduleIndex[defaultID] ?? -1,
                                              perWeekday: perWeekday.mapValues { scheduleIndex[$0] ?? -1 })
            case .freeForm(let minutes):
                timeStructure = .freeForm(defaultDurationMinutes: minutes)
            }

            let timetable = ShareTimetable(
                name: sanitizer.name(source.name), emoji: source.emoji.flatMap { sanitizer.emoji($0) },
                enabledDays: source.enabledDays, rotation: sanitizer.rotation(source.rotation),
                rotationWeekStart: source.rotationWeekStart, timeStructure: timeStructure,
                fieldVisibility: Set(source.fieldVisibility.visibleFields.compactMap { sanitizer.vocabulary($0) }),
                defaultView: sanitizer.vocabulary(source.defaultView) ?? .grid,
                density: sanitizer.vocabulary(source.density) ?? .comfortable,
                palettePackID: source.palettePackID.flatMap { sanitizer.vocabulary($0) })

            let sharedSubjects = subjects.map { subject in
                var shared = sanitizer.subject(subject)
                shared.sortIndex = subjectRanks[subject.id]
                return shared
            }
            let sharedTerms = terms.map { ShareTerm(name: sanitizer.name($0.name), range: $0.range) }
            let sharedBreaks = breaks.map {
                ShareBreak(name: sanitizer.name($0.name), range: $0.range, kind: sanitizer.vocabulary($0.kind) ?? .holiday)
            }
            var payload = SharePayloadV1(timetable: timetable, subjects: sharedSubjects, bellSchedules: sharedSchedules,
                                         lessons: sharedLessons, terms: sharedTerms, breaks: sharedBreaks)

            if includeTasks {
                let belongs: (Timetable.ID?, Subject.ID?) -> Bool = { timetableID, subjectID in
                    timetableID == ttID || (timetableID == nil && subjectID.map { subjectIndex[$0] != nil } == true)
                }
                let tasks = db.tasks.filter { !$0.isDeleted && !$0.isCompleted && belongs($0.timetableID, $0.subjectID) }
                    .sorted { $0.id < $1.id }
                let exams = db.exams.filter { !$0.isDeleted && !$0.isCompleted && belongs($0.timetableID, $0.subjectID) }
                    .sorted { $0.id < $1.id }
                try limit(.tasks, tasks.count)
                try limit(.exams, exams.count)
                payload.includesTasks = true
                payload.tasks = tasks.map { task in
                    let subtasks = task.subtasks.filter { !$0.meta.isDeleted }
                        .sorted { ($0.sortIndex, $0.id) < ($1.sortIndex, $1.id) }.map(\.title)
                    let repeatRule = task.repeatRule.flatMap { sanitizer.vocabulary($0.frequency) == nil ? nil : $0 }
                    return ShareTask(
                        title: sanitizer.name(task.title), kind: sanitizer.vocabulary(task.kind) ?? .homework,
                        subject: task.subjectID.flatMap { subjectIndex[$0] }, due: sanitizer.due(task.due),
                        linkedLesson: task.linkedLesson.flatMap { link in
                            lessonIndex[link.lessonID].map { ShareLessonLink(lesson: $0, date: link.date) }
                        },
                        priority: task.priority, notes: sanitizer.optionalNotes(task.notes), repeatRule: repeatRule,
                        subtasks: sanitizer.list(subtasks, maxItems: ShareLimits.maxSubtasks))
                }
                payload.exams = exams.map { exam in
                    ShareExam(
                        title: sanitizer.name(exam.title), kind: sanitizer.vocabulary(exam.kind) ?? .written,
                        subject: exam.subjectID.flatMap { subjectIndex[$0] }, date: exam.date, start: exam.start,
                        end: exam.end, room: sanitizer.optionalName(exam.room),
                        building: sanitizer.optionalName(exam.building),
                        topics: sanitizer.list(exam.topics, maxItems: ShareLimits.maxTopics),
                        notes: sanitizer.optionalNotes(exam.notes))
                }
            }
            return payload
        }

        private func limit(_ collection: ShareCollection, _ count: Int) throws(ShareError) {
            if count > collection.limit { throw .tooMany(collection, count: count) }
        }

        private static func indexMap<T: Hashable>(_ ids: [T]) -> [T: Int] {
            Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        }
    }

    // MARK: - Sanitizer

    /// Applies the text policy and limits to outgoing values, counting every change.
    private struct Sanitizer {
        var shortened = 0
        var cleaned = 0
        var listsShortened = 0
        var dropped = 0

        mutating func text(_ value: String, limit: Int, kind: ShareText.Kind) -> String {
            let result = ShareText.sanitize(value, limit: limit, kind: kind)
            if result.removedCharacters { cleaned += 1 }
            if result.shortened { shortened += 1 }
            return result.text
        }

        mutating func name(_ value: String) -> String { text(value, limit: ShareLimits.maxNameLength, kind: .singleLine) }

        mutating func optionalName(_ value: String?) -> String? { value.map { name($0) } }

        mutating func optionalNotes(_ value: String?) -> String? {
            value.map { text($0, limit: ShareLimits.maxNotesLength, kind: .multiLine) }
        }

        mutating func list(_ items: [String], maxItems: Int) -> [String] {
            if items.count > maxItems { listsShortened += 1 }
            return items.prefix(maxItems).map { text($0, limit: ShareLimits.maxListItemLength, kind: .singleLine) }
        }

        mutating func vocabulary<V: OpenVocabulary>(_ value: V) -> V? {
            if ShareText.isValidVocabulary(value.rawValue) { return value }
            dropped += 1
            return nil
        }

        /// The due date, or `nil` (counted as dropped) for a due kind from a newer version.
        mutating func due(_ value: TaskDue?) -> TaskDue? {
            guard let value, !value.isKnown else { return value }
            dropped += 1
            return nil
        }

        mutating func emoji(_ value: String) -> String? {
            if ShareText.isValidEmoji(value) { return value }
            dropped += 1
            return nil
        }

        mutating func labels(_ labels: [String]?) -> [String]? {
            guard let labels else { return nil }
            guard labels.count <= DayCycle.validLengths.upperBound else { dropped += 1; return nil }
            return labels.map { name($0) }
        }

        mutating func rotation(_ rotation: RotationScheme) -> RotationScheme {
            switch rotation {
            case .none:
                return .none
            case .weekCycle(var cycle):
                if case let .isoWeekParity(policy, offset) = cycle.anchor, WeekCycle.validLengths.contains(cycle.length) {
                    // Offsets are equivalent modulo the cycle length; the wire format requires 0..<length.
                    cycle.anchor = .isoWeekParity(policy: policy, offset: LocalDate.floorMod(offset, cycle.length))
                }
                cycle.labels = labels(cycle.labels)
                return .weekCycle(cycle)
            case .dayCycle(var cycle):
                cycle.labels = labels(cycle.labels)
                return .dayCycle(cycle)
            }
        }

        mutating func subject(_ subject: Subject) -> ShareSubject {
            var colorName: TextValue?
            switch subject.colorName {
            case .key(let key)?:
                if SharePalette.colorKeys.contains(key) { colorName = .key(key) } else { dropped += 1 }
            case .literal(let literal)?:
                colorName = .literal(name(literal))
            case nil:
                break
            }
            var symbol: SubjectSymbol?
            switch subject.symbol {
            case .emoji(let value)?:
                symbol = emoji(value).map(SubjectSymbol.emoji)
            case .systemImage(let value)?:
                if ShareText.isValidSystemImage(value) { symbol = .systemImage(value) } else { dropped += 1 }
            case nil:
                break
            }
            return ShareSubject(
                name: name(subject.name), shortName: optionalName(subject.shortName), color: subject.color,
                colorName: colorName, symbol: symbol, defaultRoom: optionalName(subject.defaultRoom),
                defaultBuilding: optionalName(subject.defaultBuilding), defaultTeacher: optionalName(subject.defaultTeacher),
                notes: optionalNotes(subject.notes))
        }

        func warnings(skippedLessons: Int) -> [ShareWarning] {
            var result: [ShareWarning] = []
            if shortened > 0 { result.append(.textShortened(count: shortened)) }
            if cleaned > 0 { result.append(.charactersRemoved(count: cleaned)) }
            if listsShortened > 0 { result.append(.listsShortened(count: listsShortened)) }
            if skippedLessons > 0 { result.append(.skippedLessons(count: skippedLessons)) }
            if dropped > 0 { result.append(.valuesDropped(count: dropped)) }
            return result
        }
    }
}
