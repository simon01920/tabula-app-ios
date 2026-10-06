extension SharePayloadV1 {
    /// Strict validation of an incoming (untrusted) or outgoing payload (docs/specs/SHARE_FORMAT.md §7).
    ///
    /// Throws the first problem in a fixed order (counts, timetable, subjects, bell schedules, terms, breaks,
    /// lessons, tasks, exams; elements in array order), so the same payload always yields the same error.
    /// Everything this accepts also passes `TabulaDatabase.validate()` without errors once materialized.
    /// - Returns: non-fatal findings (unknown vocabulary values, overlapping periods, …) in a fixed order.
    public func validate() throws(ShareError) -> [ShareWarning] {
        var validator = ShareValidator(payload: self)
        try validator.run()
        return validator.warnings
    }
}

/// The palette colour keys a subject's colour name may use (`ck`).
enum SharePalette {
    static let colorKeys: Set<String> = Set(PalettePack.all.flatMap { $0.colors.map(\.nameKey) })
}

struct ShareValidator {
    let payload: SharePayloadV1
    private(set) var warnings: [ShareWarning] = []
    private var seenUnknown: Set<String> = []
    private var periodKeys: Set<Int> = []

    /// Dates must lie in these years (keeps calendar arithmetic downstream far from `LocalDate`'s 1…9999 edges).
    static let validYears: ClosedRange<Int> = 1970...2199

    init(payload: SharePayloadV1) {
        self.payload = payload
    }

    mutating func run() throws(ShareError) {
        try checkCounts()
        try checkTimetable()
        for (index, subject) in payload.subjects.enumerated() { try checkSubject(subject, index) }
        for (index, schedule) in payload.bellSchedules.enumerated() { try checkSchedule(schedule, index) }
        for (index, term) in payload.terms.enumerated() {
            try ShareText.check(term.name, path: "r[\(index)].n", limit: ShareLimits.maxNameLength)
            try checkRange(term.range, path: "r[\(index)]")
        }
        for (index, item) in payload.breaks.enumerated() {
            try ShareText.check(item.name, path: "h[\(index)].n", limit: ShareLimits.maxNameLength)
            try checkRange(item.range, path: "h[\(index)]")
            try vocabulary(item.kind, field: "breakKind", path: "h[\(index)].t")
        }
        var disabledDayLessons = 0
        for (index, lesson) in payload.lessons.enumerated() {
            try checkLesson(lesson, index)
            if case .weekday(let weekday) = lesson.day, !payload.timetable.enabledDays.contains(weekday) {
                disabledDayLessons += 1
            }
        }
        if payload.lessons.isEmpty { warnings.append(.noLessons) }
        if disabledDayLessons > 0 { warnings.append(.lessonsOnDisabledDays(count: disabledDayLessons)) }
        for (index, task) in payload.tasks.enumerated() { try checkTask(task, index) }
        for (index, exam) in payload.exams.enumerated() { try checkExam(exam, index) }
    }

    // MARK: Counts

    private func checkCounts() throws(ShareError) {
        if !payload.includesTasks && !(payload.tasks.isEmpty && payload.exams.isEmpty) {
            throw .invalidValue(path: "k")
        }
        let counts: [(ShareCollection, Int)] = [
            (.subjects, payload.subjects.count), (.lessons, payload.lessons.count),
            (.bellSchedules, payload.bellSchedules.count), (.terms, payload.terms.count),
            (.breaks, payload.breaks.count), (.tasks, payload.tasks.count), (.exams, payload.exams.count),
        ]
        for (collection, count) in counts where count > collection.limit {
            throw .tooMany(collection, count: count)
        }
    }

    // MARK: Timetable

    private mutating func checkTimetable() throws(ShareError) {
        let timetable = payload.timetable
        try ShareText.check(timetable.name, path: "t.n", limit: ShareLimits.maxNameLength)
        if let emoji = timetable.emoji { try checkEmoji(emoji, path: "t.e") }
        try checkRotation(timetable.rotation)
        switch timetable.timeStructure {
        case let .bellSchedule(defaultIndex, perWeekday):
            guard payload.bellSchedules.indices.contains(defaultIndex) else { throw .danglingReference(path: "t.ts.d") }
            for weekday in perWeekday.keys.sorted() where !payload.bellSchedules.indices.contains(perWeekday[weekday]!) {
                throw .danglingReference(path: "t.ts.w.\(weekday.rawValue)")
            }
        case .freeForm(let minutes):
            guard (1...1439).contains(minutes) else { throw .invalidValue(path: "t.ts.m") }
        }
        for field in timetable.fieldVisibility.sorted() {
            try vocabulary(field, field: "lessonField", path: "t.fv")
        }
        try vocabulary(timetable.defaultView, field: "timetableView", path: "t.dv")
        if let pack = timetable.palettePackID { try vocabulary(pack, field: "palettePack", path: "t.pp") }
    }

    private func checkRotation(_ rotation: RotationScheme) throws(ShareError) {
        switch rotation {
        case .none:
            break
        case .weekCycle(let cycle):
            guard WeekCycle.validLengths.contains(cycle.length) else { throw .invalidValue(path: "t.ro.n") }
            switch cycle.anchor {
            case .isoWeekParity(_, let offset):
                guard (0..<cycle.length).contains(offset) else { throw .invalidValue(path: "t.ro.a.o") }
            case let .referenceWeek(date, cycleWeek):
                try checkDate(date, path: "t.ro.a.d")
                guard (1...cycle.length).contains(cycleWeek) else { throw .invalidValue(path: "t.ro.a.w") }
            }
            try checkLabels(cycle.labels)
        case .dayCycle(let cycle):
            guard DayCycle.validLengths.contains(cycle.length) else { throw .invalidValue(path: "t.ro.n") }
            try checkDate(cycle.anchorDate, path: "t.ro.d")
            guard (1...cycle.length).contains(cycle.anchorIndex) else { throw .invalidValue(path: "t.ro.i") }
            guard !cycle.schoolDays.isEmpty else { throw .invalidValue(path: "t.ro.sd") }
            try checkLabels(cycle.labels)
        }
    }

    private func checkLabels(_ labels: [String]?) throws(ShareError) {
        guard let labels else { return }
        // A label count different from the length is tolerated (the persisted model only warns), but bounded.
        guard labels.count <= DayCycle.validLengths.upperBound else { throw .invalidValue(path: "t.ro.lb") }
        for (index, label) in labels.enumerated() {
            try ShareText.check(label, path: "t.ro.lb[\(index)]", limit: ShareLimits.maxNameLength)
        }
    }

    // MARK: Subjects and schedules

    private mutating func checkSubject(_ subject: ShareSubject, _ index: Int) throws(ShareError) {
        let path = "s[\(index)]"
        try ShareText.check(subject.name, path: "\(path).n", limit: ShareLimits.maxNameLength)
        try optionalName(subject.shortName, path: "\(path).sn")
        switch subject.colorName {
        case .key(let key)?:
            guard isWellFormedKey(key) else { throw .invalidValue(path: "\(path).ck") }
            if !SharePalette.colorKeys.contains(key) { warnings.append(.unknownColorName(subjectIndex: index)) }
        case .literal(let literal)?:
            try ShareText.check(literal, path: "\(path).cl", limit: ShareLimits.maxNameLength)
        case nil:
            break
        }
        switch subject.symbol {
        case .emoji(let emoji)?:
            try checkEmoji(emoji, path: "\(path).se")
        case .systemImage(let name)?:
            guard ShareText.isValidSystemImage(name) else { throw .invalidValue(path: "\(path).si") }
        case nil:
            break
        }
        try optionalName(subject.defaultRoom, path: "\(path).r")
        try optionalName(subject.defaultBuilding, path: "\(path).bd")
        try optionalName(subject.defaultTeacher, path: "\(path).te")
        try optionalNotes(subject.notes, path: "\(path).no")
    }

    private mutating func checkSchedule(_ schedule: ShareBellSchedule, _ index: Int) throws(ShareError) {
        let path = "b[\(index)]"
        try ShareText.check(schedule.name, path: "\(path).n", limit: ShareLimits.maxNameLength)
        guard schedule.periods.count <= ShareLimits.maxPeriodsPerSchedule else {
            throw .tooMany(.periods, count: schedule.periods.count)
        }
        var keys: Set<Int> = []
        for (periodIndex, period) in schedule.periods.enumerated() {
            let periodPath = "\(path).p[\(periodIndex)]"
            guard (0..<Self.maxPeriodKey).contains(period.key) else { throw .invalidValue(path: "\(periodPath).k") }
            guard keys.insert(period.key).inserted else { throw .duplicate(path: "\(periodPath).k") }
            try optionalName(period.label, path: "\(periodPath).l")
            guard period.end > period.start else { throw .invalidTimeRange(path: periodPath) }
            try vocabulary(period.kind, field: "periodKind", path: "\(periodPath).t")
        }
        periodKeys.formUnion(keys)
        let sorted = schedule.periods.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        if zip(sorted, sorted.dropFirst()).contains(where: { $1.start < $0.end }) {
            warnings.append(.overlappingPeriods(scheduleIndex: index))
        }
    }

    /// Period keys are small: at most every period of every schedule has its own key.
    static let maxPeriodKey = ShareLimits.maxBellSchedules * ShareLimits.maxPeriodsPerSchedule

    // MARK: Lessons

    private mutating func checkLesson(_ lesson: ShareLesson, _ index: Int) throws(ShareError) {
        let path = "l[\(index)]"
        guard payload.subjects.indices.contains(lesson.subject) else { throw .danglingReference(path: "\(path).s") }
        let rotation = payload.timetable.rotation
        switch (lesson.day, rotation) {
        case (.weekday, .dayCycle):
            throw .invalidValue(path: "\(path).w")
        case (.weekday, _):
            break
        case let (.cycleDay(day), .dayCycle(cycle)):
            guard (1...cycle.length).contains(day) else { throw .invalidValue(path: "\(path).c") }
        case (.cycleDay, _):
            throw .invalidValue(path: "\(path).c")
        }
        if let weeks = lesson.cycleWeeks {
            let maxWeek: Int
            if case .weekCycle(let cycle) = rotation { maxWeek = cycle.length } else { maxWeek = WeekCycle.validLengths.upperBound }
            guard weeks.allSatisfy({ (1...maxWeek).contains($0) }) else { throw .invalidValue(path: "\(path).cw") }
        }
        switch lesson.slot {
        case let .period(key, span):
            guard periodKeys.contains(key) else { throw .danglingReference(path: "\(path).p") }
            guard (1...ShareLimits.maxSpan).contains(span) else { throw .invalidValue(path: "\(path).n") }
        case let .time(start, end):
            guard end > start else { throw .invalidTimeRange(path: path) }
        }
        switch lesson.validity {
        case .always:
            break
        case .terms(let terms):
            guard terms.allSatisfy({ payload.terms.indices.contains($0) }) else {
                throw .danglingReference(path: "\(path).vt")
            }
        case .range(let range):
            try checkRange(range, path: "\(path).vr")
        }
        try optionalName(lesson.room, path: "\(path).r")
        try optionalName(lesson.building, path: "\(path).bd")
        try optionalName(lesson.teacher, path: "\(path).te")
        if let type = lesson.lessonType { try vocabulary(type, field: "lessonType", path: "\(path).ty") }
        try optionalNotes(lesson.notes, path: "\(path).no")
        try checkList(lesson.bringList, collection: .bringList, path: "\(path).br")
    }

    // MARK: Tasks and exams

    private mutating func checkTask(_ task: ShareTask, _ index: Int) throws(ShareError) {
        let path = "k[\(index)]"
        try ShareText.check(task.title, path: "\(path).n", limit: ShareLimits.maxNameLength)
        try vocabulary(task.kind, field: "taskKind", path: "\(path).t")
        if let subject = task.subject, !payload.subjects.indices.contains(subject) {
            throw .danglingReference(path: "\(path).s")
        }
        if let due = task.due { try checkDate(due.date, path: "\(path).dd") }
        if let link = task.linkedLesson {
            guard payload.lessons.indices.contains(link.lesson) else { throw .danglingReference(path: "\(path).ll") }
            try checkDate(link.date, path: "\(path).ll.d")
        }
        try optionalNotes(task.notes, path: "\(path).no")
        if let rule = task.repeatRule {
            try vocabulary(rule.frequency, field: "repeatFrequency", path: "\(path).rp.f")
            guard (1...ShareLimits.maxRepeatInterval).contains(rule.interval) else {
                throw .invalidValue(path: "\(path).rp.i")
            }
            if let until = rule.until { try checkDate(until, path: "\(path).rp.u") }
        }
        try checkList(task.subtasks, collection: .subtasks, path: "\(path).st")
    }

    private mutating func checkExam(_ exam: ShareExam, _ index: Int) throws(ShareError) {
        let path = "x[\(index)]"
        try ShareText.check(exam.title, path: "\(path).n", limit: ShareLimits.maxNameLength)
        try vocabulary(exam.kind, field: "examKind", path: "\(path).t")
        if let subject = exam.subject, !payload.subjects.indices.contains(subject) {
            throw .danglingReference(path: "\(path).s")
        }
        try checkDate(exam.date, path: "\(path).d")
        if let start = exam.start, let end = exam.end, end <= start { throw .invalidTimeRange(path: path) }
        try optionalName(exam.room, path: "\(path).r")
        try optionalName(exam.building, path: "\(path).bd")
        try checkList(exam.topics, collection: .topics, path: "\(path).tp")
        try optionalNotes(exam.notes, path: "\(path).no")
    }

    // MARK: Helpers

    private func optionalName(_ text: String?, path: @autoclosure () -> String) throws(ShareError) {
        if let text { try ShareText.check(text, path: path(), limit: ShareLimits.maxNameLength) }
    }

    private func optionalNotes(_ text: String?, path: @autoclosure () -> String) throws(ShareError) {
        if let text { try ShareText.check(text, path: path(), limit: ShareLimits.maxNotesLength, kind: .multiLine) }
    }

    private func checkList(_ items: [String], collection: ShareCollection, path: String) throws(ShareError) {
        guard items.count <= collection.limit else { throw .tooMany(collection, count: items.count) }
        for (index, item) in items.enumerated() {
            try ShareText.check(item, path: "\(path)[\(index)]", limit: ShareLimits.maxListItemLength)
        }
    }

    private func checkEmoji(_ emoji: String, path: String) throws(ShareError) {
        try ShareText.check(emoji, path: path, limit: ShareLimits.maxEmojiLength)
        guard !emoji.isEmpty else { throw .invalidValue(path: path) }
    }

    private func checkDate(_ date: LocalDate, path: @autoclosure () -> String) throws(ShareError) {
        guard Self.validYears.contains(date.year) else { throw .invalidValue(path: path()) }
    }

    private func checkRange(_ range: LocalDateRange, path: String) throws(ShareError) {
        try checkDate(range.start, path: "\(path).a")
        try checkDate(range.end, path: "\(path).z")
        guard range.end >= range.start else { throw .invalidDateRange(path: path) }
    }

    /// Checks an open-vocabulary value's shape and records a warning (once per field and value) when this
    /// version does not know it. Unknown values are kept.
    private mutating func vocabulary<V: OpenVocabulary>(_ value: V, field: String, path: @autoclosure () -> String)
        throws(ShareError) {
        try ShareText.checkVocabulary(value.rawValue, path: path())
        if !value.isKnown, seenUnknown.insert("\(field)=\(value.rawValue)").inserted {
            warnings.append(.unknownValue(field: field, value: value.rawValue))
        }
    }

    /// A catalog key's shape: 1…100 ASCII characters from `A–Z a–z 0–9 _ . -`.
    private func isWellFormedKey(_ key: String) -> Bool {
        let bytes = key.utf8
        guard (1...ShareLimits.maxNameLength).contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "-"):
                return true
            default:
                return false
            }
        }
    }
}
