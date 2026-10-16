import Foundation

// Wire coding of the share DTOs (docs/specs/SHARE_FORMAT.md §4). Rules:
// - short keys, sorted by `TabulaJSON`; `nil` optionals, empty optional lists and default values are omitted;
// - sets are written as ascending arrays; a set written with a repeated element is rejected (`.duplicate`);
// - "exactly one of" key groups (lesson day, slot, validity, colour name, symbol) are rejected when violated
//   (`.malformedPayload`);
// - unknown keys are ignored (forward compatibility within `v` = 1).
// Decoders throw `ShareError` for shape violations they detect themselves; `ShareCodec` maps every other
// `DecodingError` to `.malformedPayload(path:)`.

/// Wire paths for diagnostics: `l[3].cw` = key `cw` of element 3 of `l`.
enum SharePath {
    static func string(_ codingPath: [any CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }
}

extension KeyedDecodingContainer {
    /// The wire path of `key` in this container.
    func sharePath(_ key: Key) -> String { SharePath.string(codingPath + [key]) }

    /// Decodes an array as a set; a repeated element throws `ShareError.duplicate`. Absent → `nil`.
    func decodeShareSet<T: Decodable & Hashable>(_ type: T.Type, forKey key: Key) throws -> Set<T>? {
        guard let array = try decodeIfPresent([T].self, forKey: key) else { return nil }
        let set = Set(array)
        guard set.count == array.count else { throw ShareError.duplicate(path: sharePath(key)) }
        return set
    }

    /// Decodes an optional list; absent → empty.
    func decodeShareList<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }
}

extension KeyedEncodingContainer {
    /// Encodes `list` unless it is empty.
    mutating func encodeShareList<T: Encodable>(_ list: [T], forKey key: Key) throws {
        if !list.isEmpty { try encode(list, forKey: key) }
    }

    /// Encodes `value` unless it equals `defaultValue`.
    mutating func encodeShare<T: Encodable & Equatable>(_ value: T, forKey key: Key, unless defaultValue: T) throws {
        if value != defaultValue { try encode(value, forKey: key) }
    }
}

// MARK: - Root

extension SharePayloadV1: Codable {
    enum CodingKeys: String, CodingKey { case v, t, s, b, l, r, h, k, x }

    /// Decodes a payload. A `v` other than 1 throws `.newerVersion` / `.unsupportedVersion`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .v)
        guard version == Self.version else {
            throw version > Self.version ? ShareError.newerVersion(version) : ShareError.unsupportedVersion
        }
        timetable = try c.decode(ShareTimetable.self, forKey: .t)
        subjects = try c.decodeShareList(ShareSubject.self, forKey: .s)
        bellSchedules = try c.decodeShareList(ShareBellSchedule.self, forKey: .b)
        lessons = try c.decodeShareList(ShareLesson.self, forKey: .l)
        terms = try c.decodeShareList(ShareTerm.self, forKey: .r)
        breaks = try c.decodeShareList(ShareBreak.self, forKey: .h)
        let tasks = try c.decodeIfPresent([ShareTask].self, forKey: .k)
        let exams = try c.decodeIfPresent([ShareExam].self, forKey: .x)
        includesTasks = tasks != nil || exams != nil
        self.tasks = tasks ?? []
        self.exams = exams ?? []
    }

    /// Encodes the payload; `k` and `x` are written (possibly empty) exactly when `includesTasks`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.version, forKey: .v)
        try c.encode(timetable, forKey: .t)
        try c.encodeShareList(subjects, forKey: .s)
        try c.encodeShareList(bellSchedules, forKey: .b)
        try c.encodeShareList(lessons, forKey: .l)
        try c.encodeShareList(terms, forKey: .r)
        try c.encodeShareList(breaks, forKey: .h)
        if includesTasks {
            try c.encode(tasks, forKey: .k)
            try c.encode(exams, forKey: .x)
        }
    }
}

// MARK: - Timetable

extension ShareTimetable: Codable {
    enum CodingKeys: String, CodingKey { case n, e, d, ro, ws, ts, fv, dv, de, pp }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .n)
        emoji = try c.decodeIfPresent(String.self, forKey: .e)
        enabledDays = try c.decodeShareSet(Weekday.self, forKey: .d) ?? []
        rotation = try c.decodeIfPresent(WireRotation.self, forKey: .ro)?.value ?? .none
        rotationWeekStart = try c.decodeIfPresent(Weekday.self, forKey: .ws) ?? .monday
        timeStructure = try c.decode(ShareTimeStructure.self, forKey: .ts)
        fieldVisibility = try c.decodeShareSet(LessonField.self, forKey: .fv) ?? []
        defaultView = try c.decode(TimetableViewKind.self, forKey: .dv)
        density = try c.decode(Density.self, forKey: .de)
        palettePackID = try c.decodeIfPresent(PalettePackID.self, forKey: .pp)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encodeIfPresent(emoji, forKey: .e)
        try c.encodeSorted(enabledDays, forKey: .d)
        if rotation != .none { try c.encode(WireRotation(value: rotation), forKey: .ro) }
        if rotationWeekStart != .monday { try c.encode(rotationWeekStart, forKey: .ws) }
        try c.encode(timeStructure, forKey: .ts)
        if !fieldVisibility.isEmpty { try c.encodeSorted(fieldVisibility, forKey: .fv) }
        try c.encode(defaultView, forKey: .dv)
        try c.encode(density, forKey: .de)
        try c.encodeIfPresent(palettePackID, forKey: .pp)
    }
}

/// Wire form of `RotationScheme`:
/// `{"k":"n"}` · `{"k":"w","n":2,"a":{…},"lb":[…]}` · `{"k":"d","n":6,"d":"…","i":1,"sd":[…],"sb":true,"lb":[…]}`.
/// Week anchor: `{"k":"iso","p":"strict","o":0}` · `{"k":"ref","d":"…","w":1}`. Closed unions.
struct WireRotation: Codable {
    var value: RotationScheme

    enum CodingKeys: String, CodingKey { case k, n, a, lb, d, i, sd, sb }
    enum AnchorKeys: String, CodingKey { case k, p, o, d, w }

    init(value: RotationScheme) { self.value = value }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .k) {
        case "n":
            value = .none
        case "w":
            let a = try c.nestedContainer(keyedBy: AnchorKeys.self, forKey: .a)
            let anchor: WeekCycleAnchor
            switch try a.decode(String.self, forKey: .k) {
            case "iso":
                anchor = .isoWeekParity(policy: try a.decode(ISOWeekParityPolicy.self, forKey: .p),
                                        offset: try a.decodeIfPresent(Int.self, forKey: .o) ?? 0)
            case "ref":
                anchor = .referenceWeek(date: try a.decode(LocalDate.self, forKey: .d),
                                        cycleWeek: try a.decode(Int.self, forKey: .w))
            default:
                throw ShareError.malformedPayload(path: a.sharePath(.k))
            }
            value = .weekCycle(WeekCycle(length: try c.decode(Int.self, forKey: .n), anchor: anchor,
                                         labels: try c.decodeIfPresent([String].self, forKey: .lb)))
        case "d":
            value = .dayCycle(DayCycle(length: try c.decode(Int.self, forKey: .n),
                                       anchorDate: try c.decode(LocalDate.self, forKey: .d),
                                       anchorIndex: try c.decode(Int.self, forKey: .i),
                                       schoolDays: try c.decodeShareSet(Weekday.self, forKey: .sd) ?? [],
                                       skipsBreaks: try c.decode(Bool.self, forKey: .sb),
                                       labels: try c.decodeIfPresent([String].self, forKey: .lb)))
        default:
            throw ShareError.malformedPayload(path: c.sharePath(.k))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch value {
        case .none:
            try c.encode("n", forKey: .k)
        case .weekCycle(let cycle):
            try c.encode("w", forKey: .k)
            try c.encode(cycle.length, forKey: .n)
            try c.encodeIfPresent(cycle.labels, forKey: .lb)
            var a = c.nestedContainer(keyedBy: AnchorKeys.self, forKey: .a)
            switch cycle.anchor {
            case let .isoWeekParity(policy, offset):
                try a.encode("iso", forKey: .k)
                try a.encode(policy, forKey: .p)
                try a.encode(offset, forKey: .o)
            case let .referenceWeek(date, cycleWeek):
                try a.encode("ref", forKey: .k)
                try a.encode(date, forKey: .d)
                try a.encode(cycleWeek, forKey: .w)
            }
        case .dayCycle(let cycle):
            try c.encode("d", forKey: .k)
            try c.encode(cycle.length, forKey: .n)
            try c.encode(cycle.anchorDate, forKey: .d)
            try c.encode(cycle.anchorIndex, forKey: .i)
            try c.encodeSorted(cycle.schoolDays, forKey: .sd)
            try c.encode(cycle.skipsBreaks, forKey: .sb)
            try c.encodeIfPresent(cycle.labels, forKey: .lb)
        }
    }
}

extension ShareTimeStructure: Codable {
    enum CodingKeys: String, CodingKey { case k, d, w, m }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .k) {
        case "b":
            let raw = try c.decodeIfPresent([String: Int].self, forKey: .w) ?? [:]
            var perWeekday: [Weekday: Int] = [:]
            for (key, index) in raw {
                // Canonical keys only: "1"…"7".
                guard let number = Int(key), let weekday = Weekday(rawValue: number), key == String(number) else {
                    throw ShareError.invalidValue(path: c.sharePath(.w))
                }
                perWeekday[weekday] = index
            }
            self = .bellSchedule(defaultIndex: try c.decode(Int.self, forKey: .d), perWeekday: perWeekday)
        case "f":
            self = .freeForm(defaultDurationMinutes: try c.decode(Int.self, forKey: .m))
        default:
            throw ShareError.malformedPayload(path: c.sharePath(.k))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bellSchedule(defaultIndex, perWeekday):
            try c.encode("b", forKey: .k)
            try c.encode(defaultIndex, forKey: .d)
            if !perWeekday.isEmpty {
                try c.encode(Dictionary(uniqueKeysWithValues: perWeekday.map { (String($0.key.rawValue), $0.value) }),
                             forKey: .w)
            }
        case .freeForm(let minutes):
            try c.encode("f", forKey: .k)
            try c.encode(minutes, forKey: .m)
        }
    }
}

// MARK: - Subjects and bell schedules

extension ShareSubject: Codable {
    enum CodingKeys: String, CodingKey { case n, sn, c, ck, cl, se, si, r, bd, te, no, o }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .n)
        shortName = try c.decodeIfPresent(String.self, forKey: .sn)
        color = try c.decode(ColorValue.self, forKey: .c)
        switch (try c.decodeIfPresent(String.self, forKey: .ck), try c.decodeIfPresent(String.self, forKey: .cl)) {
        case (nil, nil): colorName = nil
        case (let key?, nil): colorName = .key(key)
        case (nil, let literal?): colorName = .literal(literal)
        default: throw ShareError.malformedPayload(path: c.sharePath(.ck))
        }
        switch (try c.decodeIfPresent(String.self, forKey: .se), try c.decodeIfPresent(String.self, forKey: .si)) {
        case (nil, nil): symbol = nil
        case (let emoji?, nil): symbol = .emoji(emoji)
        case (nil, let name?): symbol = .systemImage(name)
        default: throw ShareError.malformedPayload(path: c.sharePath(.se))
        }
        defaultRoom = try c.decodeIfPresent(String.self, forKey: .r)
        defaultBuilding = try c.decodeIfPresent(String.self, forKey: .bd)
        defaultTeacher = try c.decodeIfPresent(String.self, forKey: .te)
        notes = try c.decodeIfPresent(String.self, forKey: .no)
        sortIndex = try c.decodeIfPresent(Int.self, forKey: .o)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encodeIfPresent(shortName, forKey: .sn)
        try c.encode(color, forKey: .c)
        switch colorName {
        case .key(let key)?: try c.encode(key, forKey: .ck)
        case .literal(let literal)?: try c.encode(literal, forKey: .cl)
        case nil: break
        }
        switch symbol {
        case .emoji(let emoji)?: try c.encode(emoji, forKey: .se)
        case .systemImage(let name)?: try c.encode(name, forKey: .si)
        case nil: break
        }
        try c.encodeIfPresent(defaultRoom, forKey: .r)
        try c.encodeIfPresent(defaultBuilding, forKey: .bd)
        try c.encodeIfPresent(defaultTeacher, forKey: .te)
        try c.encodeIfPresent(notes, forKey: .no)
        try c.encodeIfPresent(sortIndex, forKey: .o)
    }
}

extension ShareBellSchedule: Codable {
    enum CodingKeys: String, CodingKey { case n, p }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .n)
        periods = try c.decodeShareList(SharePeriod.self, forKey: .p)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encodeShareList(periods, forKey: .p)
    }
}

extension SharePeriod: Codable {
    enum CodingKeys: String, CodingKey { case k, l, a, z, t }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(Int.self, forKey: .k)
        label = try c.decodeIfPresent(String.self, forKey: .l)
        start = try c.decode(LocalTime.self, forKey: .a)
        end = try c.decode(LocalTime.self, forKey: .z)
        kind = try c.decodeIfPresent(PeriodKind.self, forKey: .t) ?? .lesson
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .k)
        try c.encodeIfPresent(label, forKey: .l)
        try c.encode(start, forKey: .a)
        try c.encode(end, forKey: .z)
        try c.encodeShare(kind, forKey: .t, unless: .lesson)
    }
}

// MARK: - Lessons, terms, breaks

/// Wire form of an inclusive date range: `{"a":"start","z":"end"}`.
struct WireRange: Codable {
    var value: LocalDateRange

    enum CodingKeys: String, CodingKey { case a, z }

    init(_ value: LocalDateRange) { self.value = value }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = LocalDateRange(start: try c.decode(LocalDate.self, forKey: .a), end: try c.decode(LocalDate.self, forKey: .z))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value.start, forKey: .a)
        try c.encode(value.end, forKey: .z)
    }
}

extension ShareLesson: Codable {
    enum CodingKeys: String, CodingKey { case s, w, c, cw, p, n, a, z, vt, vr, r, bd, te, ty, no, br }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subject = try c.decode(Int.self, forKey: .s)
        switch (try c.decodeIfPresent(Weekday.self, forKey: .w), try c.decodeIfPresent(Int.self, forKey: .c)) {
        case (let weekday?, nil): day = .weekday(weekday)
        case (nil, let index?): day = .cycleDay(index)
        default: throw ShareError.malformedPayload(path: c.sharePath(.w))
        }
        cycleWeeks = try c.decodeShareSet(Int.self, forKey: .cw)
        let period = try c.decodeIfPresent(Int.self, forKey: .p)
        let span = try c.decodeIfPresent(Int.self, forKey: .n)
        let start = try c.decodeIfPresent(LocalTime.self, forKey: .a)
        let end = try c.decodeIfPresent(LocalTime.self, forKey: .z)
        switch (period, start, end) {
        case (let key?, nil, nil): slot = .period(key: key, span: span ?? 1)
        case (nil, let start?, let end?) where span == nil: slot = .time(start: start, end: end)
        default: throw ShareError.malformedPayload(path: c.sharePath(.p))
        }
        switch (try c.decodeShareSet(Int.self, forKey: .vt), try c.decodeIfPresent(WireRange.self, forKey: .vr)) {
        case (nil, nil): validity = .always
        case (let terms?, nil): validity = .terms(terms)
        case (nil, let range?): validity = .range(range.value)
        default: throw ShareError.malformedPayload(path: c.sharePath(.vt))
        }
        room = try c.decodeIfPresent(String.self, forKey: .r)
        building = try c.decodeIfPresent(String.self, forKey: .bd)
        teacher = try c.decodeIfPresent(String.self, forKey: .te)
        lessonType = try c.decodeIfPresent(LessonType.self, forKey: .ty)
        notes = try c.decodeIfPresent(String.self, forKey: .no)
        bringList = try c.decodeShareList(String.self, forKey: .br)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(subject, forKey: .s)
        switch day {
        case .weekday(let weekday): try c.encode(weekday, forKey: .w)
        case .cycleDay(let index): try c.encode(index, forKey: .c)
        }
        try c.encodeSortedIfPresent(cycleWeeks, forKey: .cw)
        switch slot {
        case let .period(key, span):
            try c.encode(key, forKey: .p)
            try c.encodeShare(span, forKey: .n, unless: 1)
        case let .time(start, end):
            try c.encode(start, forKey: .a)
            try c.encode(end, forKey: .z)
        }
        switch validity {
        case .always: break
        case .terms(let terms): try c.encodeSorted(terms, forKey: .vt)
        case .range(let range): try c.encode(WireRange(range), forKey: .vr)
        }
        try c.encodeIfPresent(room, forKey: .r)
        try c.encodeIfPresent(building, forKey: .bd)
        try c.encodeIfPresent(teacher, forKey: .te)
        try c.encodeIfPresent(lessonType, forKey: .ty)
        try c.encodeIfPresent(notes, forKey: .no)
        try c.encodeShareList(bringList, forKey: .br)
    }
}

extension ShareTerm: Codable {
    enum CodingKeys: String, CodingKey { case n, a, z }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .n)
        range = LocalDateRange(start: try c.decode(LocalDate.self, forKey: .a), end: try c.decode(LocalDate.self, forKey: .z))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encode(range.start, forKey: .a)
        try c.encode(range.end, forKey: .z)
    }
}

extension ShareBreak: Codable {
    enum CodingKeys: String, CodingKey { case n, a, z, t }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .n)
        range = LocalDateRange(start: try c.decode(LocalDate.self, forKey: .a), end: try c.decode(LocalDate.self, forKey: .z))
        kind = try c.decodeIfPresent(BreakKind.self, forKey: .t) ?? .holiday
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .n)
        try c.encode(range.start, forKey: .a)
        try c.encode(range.end, forKey: .z)
        try c.encodeShare(kind, forKey: .t, unless: .holiday)
    }
}

// MARK: - Tasks and exams

extension ShareLessonLink: Codable {
    enum CodingKeys: String, CodingKey { case l, d }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lesson = try c.decode(Int.self, forKey: .l)
        date = try c.decode(LocalDate.self, forKey: .d)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lesson, forKey: .l)
        try c.encode(date, forKey: .d)
    }
}

/// Wire form of `RepeatRule`: `{"f":"weekly","i":2,"w":[1,3],"u":"2027-01-31"}` (`i` omitted when 1, `w` when
/// empty, `u` when absent).
struct WireRepeat: Codable {
    var value: RepeatRule

    enum CodingKeys: String, CodingKey { case f, i, w, u }

    init(_ value: RepeatRule) { self.value = value }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = RepeatRule(frequency: try c.decode(RepeatFrequency.self, forKey: .f),
                           interval: try c.decodeIfPresent(Int.self, forKey: .i) ?? 1,
                           weekdays: try c.decodeShareSet(Weekday.self, forKey: .w) ?? [],
                           until: try c.decodeIfPresent(LocalDate.self, forKey: .u))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value.frequency, forKey: .f)
        try c.encodeShare(value.interval, forKey: .i, unless: 1)
        if !value.weekdays.isEmpty { try c.encodeSorted(value.weekdays, forKey: .w) }
        try c.encodeIfPresent(value.until, forKey: .u)
    }
}

extension ShareTask: Codable {
    enum CodingKeys: String, CodingKey { case n, t, s, dd, dt, ll, pr, no, rp, st }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .n)
        kind = try c.decodeIfPresent(TaskKind.self, forKey: .t) ?? .homework
        subject = try c.decodeIfPresent(Int.self, forKey: .s)
        switch (try c.decodeIfPresent(LocalDate.self, forKey: .dd), try c.decodeIfPresent(LocalTime.self, forKey: .dt)) {
        case (nil, nil): due = nil
        case (let date?, nil): due = .date(date)
        case (let date?, let time?): due = .dateTime(date, time)
        case (nil, _?): throw ShareError.malformedPayload(path: c.sharePath(.dt))
        }
        linkedLesson = try c.decodeIfPresent(ShareLessonLink.self, forKey: .ll)
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .pr) ?? .normal
        notes = try c.decodeIfPresent(String.self, forKey: .no)
        repeatRule = try c.decodeIfPresent(WireRepeat.self, forKey: .rp)?.value
        subtasks = try c.decodeShareList(String.self, forKey: .st)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .n)
        try c.encodeShare(kind, forKey: .t, unless: .homework)
        try c.encodeIfPresent(subject, forKey: .s)
        try c.encodeIfPresent(due?.date, forKey: .dd)
        try c.encodeIfPresent(due?.time, forKey: .dt)
        try c.encodeIfPresent(linkedLesson, forKey: .ll)
        try c.encodeShare(priority, forKey: .pr, unless: .normal)
        try c.encodeIfPresent(notes, forKey: .no)
        try c.encodeIfPresent(repeatRule.map(WireRepeat.init), forKey: .rp)
        try c.encodeShareList(subtasks, forKey: .st)
    }
}

extension ShareExam: Codable {
    enum CodingKeys: String, CodingKey { case n, t, s, d, a, z, r, bd, tp, no }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .n)
        kind = try c.decodeIfPresent(ExamKind.self, forKey: .t) ?? .written
        subject = try c.decodeIfPresent(Int.self, forKey: .s)
        date = try c.decode(LocalDate.self, forKey: .d)
        start = try c.decodeIfPresent(LocalTime.self, forKey: .a)
        end = try c.decodeIfPresent(LocalTime.self, forKey: .z)
        room = try c.decodeIfPresent(String.self, forKey: .r)
        building = try c.decodeIfPresent(String.self, forKey: .bd)
        topics = try c.decodeShareList(String.self, forKey: .tp)
        notes = try c.decodeIfPresent(String.self, forKey: .no)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .n)
        try c.encodeShare(kind, forKey: .t, unless: .written)
        try c.encodeIfPresent(subject, forKey: .s)
        try c.encode(date, forKey: .d)
        try c.encodeIfPresent(start, forKey: .a)
        try c.encodeIfPresent(end, forKey: .z)
        try c.encodeIfPresent(room, forKey: .r)
        try c.encodeIfPresent(building, forKey: .bd)
        try c.encodeShareList(topics, forKey: .tp)
        try c.encodeIfPresent(notes, forKey: .no)
    }
}
