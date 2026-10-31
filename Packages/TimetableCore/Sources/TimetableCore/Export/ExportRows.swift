import Foundation

/// One lesson occurrence as exported (CSV, ICS, XLSX). Derived from the schedule engine, never persisted.
public struct ExportRow: Hashable, Sendable {
    /// Occurrence ID from the engine.
    public var occurrenceID: OccurrenceID
    /// The recurring lesson's ID, or the `addLesson` override's ID for a one-off (ICS UID stem).
    public var sourceID: UUID
    /// Date (wall clock).
    public var date: LocalDate
    /// Start (wall clock).
    public var start: LocalTime
    /// End (wall clock).
    public var end: LocalTime
    /// Subject name after patches.
    public var subject: String
    /// Effective room, if any.
    public var room: String?
    /// Effective teacher, if any.
    public var teacher: String?
    /// `.scheduled`, `.modified`, `.added` or `.cancelled`.
    public var status: ResolvedLesson.Status
    /// Modification reasons (empty unless modified or a patched cancellation).
    public var reasons: [ModificationReason]

    /// Creates a row.
    public init(occurrenceID: OccurrenceID, sourceID: UUID, date: LocalDate, start: LocalTime, end: LocalTime,
                subject: String, room: String? = nil, teacher: String? = nil,
                status: ResolvedLesson.Status = .scheduled, reasons: [ModificationReason] = []) {
        self.occurrenceID = occurrenceID
        self.sourceID = sourceID
        self.date = date
        self.start = start
        self.end = end
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.status = status
        self.reasons = reasons
    }
}

/// Builds export rows from the schedule engine (`ScheduleResolver`, `.actual`): rotations, holidays, validity
/// and overrides are resolved there, never here.
public enum ExportRows {
    /// Every occurrence of timetable `timetableID` on the dates of `range`, cancelled ones included (flagged by
    /// `status`), in date then engine order (start, end, ID). Empty for an empty range or an unknown timetable.
    public static func build(database: TabulaDatabase, timetableID: Timetable.ID, range: LocalDateRange,
                             context: CalendarContext) -> [ExportRow] {
        guard let resolver = ScheduleResolver(database: database, timetableID: timetableID, context: context) else {
            return []
        }
        return range.days.flatMap { date in
            let resolution = resolver.resolution(for: date)
            return resolution.schedule.entries.map { entry in
                let sourceID: UUID
                switch entry.source {
                case .lesson(let id): sourceID = id.uuid
                case .oneOff(let id): sourceID = id.uuid
                }
                return ExportRow(occurrenceID: entry.id, sourceID: sourceID, date: entry.date, start: entry.startTime,
                                 end: entry.endTime, subject: entry.subject.name, room: entry.room,
                                 teacher: entry.teacher, status: entry.status,
                                 reasons: resolution.reasons(for: entry.id))
            }
        }
    }
}

/// Localised column titles and change text, supplied by the app (String Catalog); Core never translates.
public struct ExportLabels: Sendable {
    /// Column titles.
    public var date, start, end, subject, room, teacher, change: String
    /// Text of the change column / ICS description line for a row ("" when unchanged). The app formats
    /// `status` and `reasons` (e.g. with a list formatter) so no translated fragments are concatenated here.
    public var changeText: @Sendable (ExportRow) -> String

    /// Creates labels.
    public init(date: String, start: String, end: String, subject: String, room: String, teacher: String,
                change: String, changeText: @escaping @Sendable (ExportRow) -> String) {
        self.date = date
        self.start = start
        self.end = end
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.change = change
        self.changeText = changeText
    }

    /// Header cells: date, start, end, subject, room, teacher, change.
    var header: [String] { [date, start, end, subject, room, teacher, change] }

    /// Table cells of `row` (dates `yyyy-MM-dd`, times `HH:mm`; absent fields empty), in `header` order.
    func cells(_ row: ExportRow) -> [String] {
        [row.date.isoString, row.start.isoString, row.end.isoString, row.subject, row.room ?? "", row.teacher ?? "",
         changeText(row)]
    }
}
