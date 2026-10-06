/// Every limit of the share format in one place (docs/specs/SHARE_FORMAT.md §5).
///
/// Import rejects anything over a limit with a typed `ShareError`; export shortens text and lists to fit (with a
/// `ShareWarning`) and refuses whole collections that are too large (`ShareError.tooMany`).
/// String lengths are counted in **Unicode scalars** (platform-independent, unlike grapheme clusters) and
/// export never splits a grapheme cluster when it shortens text.
public enum ShareLimits {
    // MARK: Transport

    /// Largest compressed payload that still goes into an inline link / QR code (`ShareRoute.inline`).
    /// 2048 bytes → 2731 base64url characters → a link of about 2.8 KB, inside the ~2.9 KB binary capacity of
    /// a QR code at error-correction level L.
    public static let inlineCompressedBytes = 2048
    /// Largest envelope string (`"1." + base64url`), in bytes. Larger input is rejected before decoding.
    public static let maxEnvelopeBytes = 65_536
    /// Largest decompressed JSON, in bytes (zip-bomb guard: inflating stops as soon as it is exceeded).
    public static let maxJSONBytes = 1_048_576
    /// Deepest JSON nesting accepted (the v1 payload needs 5); checked before `JSONDecoder` runs.
    public static let maxJSONDepth = 16
    /// Longest link accepted by `ShareLink.parse` (envelope plus scheme, host and path).
    public static let maxLinkBytes = maxEnvelopeBytes + 512

    // MARK: Counts

    /// Subjects per payload.
    public static let maxSubjects = 200
    /// Lessons per payload.
    public static let maxLessons = 2000
    /// Bell schedules per payload.
    public static let maxBellSchedules = 20
    /// Periods per bell schedule.
    public static let maxPeriodsPerSchedule = 40
    /// Terms per payload.
    public static let maxTerms = 20
    /// Calendar breaks per payload.
    public static let maxBreaks = 200
    /// Tasks per payload.
    public static let maxTasks = 1000
    /// Exams per payload.
    public static let maxExams = 1000
    /// Items of one lesson's bring list.
    public static let maxBringListItems = 50
    /// Subtasks of one task.
    public static let maxSubtasks = 50
    /// Topics of one exam.
    public static let maxTopics = 50

    // MARK: Strings (Unicode scalars)

    /// Names and other single-line text: timetable/subject/schedule/term/break names, short names, rooms,
    /// buildings, teachers, period labels, rotation labels, task/exam titles.
    public static let maxNameLength = 100
    /// Multi-line notes (subject, lesson, task, exam).
    public static let maxNotesLength = 4000
    /// One bring-list item, subtask title or exam topic.
    public static let maxListItemLength = 100
    /// An emoji (timetable emoji, subject emoji symbol); a long ZWJ family sequence needs 11.
    public static let maxEmojiLength = 16
    /// An SF Symbol name (ASCII `a-z 0-9 .`).
    public static let maxSystemImageLength = 100
    /// An open-vocabulary raw value (ASCII `A-Z a-z 0-9 _ . -`), e.g. a lesson type from a newer app.
    public static let maxVocabularyLength = 40

    // MARK: Values

    /// Largest `span` of a period slot (cannot exceed the periods of a schedule).
    public static let maxSpan = maxPeriodsPerSchedule
    /// Largest repeat interval of a task.
    public static let maxRepeatInterval = 365
}
