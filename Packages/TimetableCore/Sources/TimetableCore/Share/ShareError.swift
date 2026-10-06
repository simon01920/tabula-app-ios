/// Why a share link, code or payload could not be produced or read. Every failure of the share pipeline is
/// one of these cases (APIs use typed `throws(ShareError)`).
///
/// `path` values are debug locations in wire terms (e.g. `"l[3].s"` = lesson 3, key `s`); they are never
/// shown to users. User-facing text comes from `message` (String Catalog keys, docs/specs/SHARE_FORMAT.md §9).
public enum ShareError: Error, Hashable, Sendable, CustomStringConvertible {
    // MARK: Links and codes
    /// Not a Tabula share link (wrong scheme, host, path shape, characters or length).
    case invalidLink
    /// Not an 8-character share code from the code alphabet.
    case invalidShortCode

    // MARK: Envelope and transport
    /// Empty input, no `"<version>."` prefix, or characters outside base64url.
    case malformedEnvelope
    /// An envelope prefix or payload version this app cannot read (not a version number, or below 1).
    case unsupportedVersion
    /// Written by a newer app (envelope prefix or payload `v` above what this app supports): "update the app".
    case newerVersion(Int)
    /// The envelope is longer than `ShareLimits.maxEnvelopeBytes`.
    case envelopeTooLarge(byteCount: Int)
    /// The base64url text is not canonical base64url without padding.
    case invalidBase64
    /// The DEFLATE stream is corrupt, truncated, or followed by extra bytes.
    case decompressionFailed
    /// Inflating would exceed `ShareLimits.maxJSONBytes` (zip-bomb guard).
    case decompressedTooLarge
    /// The decompressed bytes are not valid UTF-8.
    case invalidUTF8
    /// Not a JSON object of the expected shape (syntax, nesting depth, type, missing or malformed field).
    case malformedPayload(path: String)

    // MARK: Validation
    /// A collection exceeds its `ShareCollection.limit`.
    case tooMany(ShareCollection, count: Int)
    /// A string exceeds its limit (`length` in Unicode scalars).
    case stringTooLong(path: String, length: Int)
    /// A string contains a control, bidi-override/isolate or other forbidden character.
    case invalidCharacters(path: String)
    /// A value is out of range or not allowed here (e.g. an unknown palette key's shape, a span of 0).
    case invalidValue(path: String)
    /// A reference (subject, period, term, bell schedule, lesson index) points at nothing.
    case danglingReference(path: String)
    /// A value that must be unique appears twice (period keys in a schedule, entries of a set).
    case duplicate(path: String)
    /// A time range whose end is not after its start.
    case invalidTimeRange(path: String)
    /// A date range whose end is before its start.
    case invalidDateRange(path: String)

    // MARK: Export and import
    /// Export: the timetable does not exist or is deleted.
    case timetableNotFound
    /// Export: the system compressor failed (should not happen).
    case compressionFailed
    /// Import: a freshly generated ID already exists in the target database (nothing was inserted).
    case idCollision

    /// Catalog key of the user-facing message. Several technical cases share one message.
    public var l10nKey: String {
        switch self {
        case .invalidLink: return "share.error.invalidLink"
        case .invalidShortCode: return "share.error.invalidCode"
        case .malformedEnvelope, .invalidBase64, .decompressionFailed, .invalidUTF8, .malformedPayload:
            return "share.error.damaged"
        case .unsupportedVersion: return "share.error.unsupportedVersion"
        case .newerVersion: return "share.error.newerVersion"
        case .envelopeTooLarge, .decompressedTooLarge: return "share.error.tooLarge"
        case .tooMany(let collection, _):
            return collection.hasOwnLimitMessage ? "share.error.tooMany.\(collection.rawValue)" : "share.error.invalidContent"
        case .stringTooLong, .invalidCharacters, .invalidValue, .danglingReference, .duplicate, .invalidTimeRange,
             .invalidDateRange:
            return "share.error.invalidContent"
        case .timetableNotFound: return "share.error.timetableNotFound"
        case .compressionFailed, .idCollision: return "share.error.failed"
        }
    }

    /// The localisable message. `tooMany.<collection>` keys take (1) the count and (2) the limit (plural
    /// variations on both); every other key takes no arguments.
    public var message: LocalizedText {
        if case let .tooMany(collection, count) = self, collection.hasOwnLimitMessage {
            return LocalizedText(key: l10nKey, args: [.integer(count), .integer(collection.limit)])
        }
        return LocalizedText(key: l10nKey)
    }

    /// Every catalog key `message` can produce (docs and catalog checks).
    public static var allL10nKeys: [String] {
        var keys = ["share.error.invalidLink", "share.error.invalidCode", "share.error.damaged",
                    "share.error.unsupportedVersion", "share.error.newerVersion", "share.error.tooLarge",
                    "share.error.invalidContent", "share.error.timetableNotFound", "share.error.failed"]
        keys += ShareCollection.allCases.filter(\.hasOwnLimitMessage).map { "share.error.tooMany.\($0.rawValue)" }
        return keys
    }

    /// Debug rendering (never shown to users).
    public var description: String {
        switch self {
        case .invalidLink: return "invalidLink"
        case .invalidShortCode: return "invalidShortCode"
        case .malformedEnvelope: return "malformedEnvelope"
        case .unsupportedVersion: return "unsupportedVersion"
        case .newerVersion(let version): return "newerVersion(\(version))"
        case .envelopeTooLarge(let count): return "envelopeTooLarge(\(count))"
        case .invalidBase64: return "invalidBase64"
        case .decompressionFailed: return "decompressionFailed"
        case .decompressedTooLarge: return "decompressedTooLarge"
        case .invalidUTF8: return "invalidUTF8"
        case .malformedPayload(let path): return "malformedPayload(\(path))"
        case let .tooMany(collection, count): return "tooMany(\(collection.rawValue), \(count))"
        case let .stringTooLong(path, length): return "stringTooLong(\(path), \(length))"
        case .invalidCharacters(let path): return "invalidCharacters(\(path))"
        case .invalidValue(let path): return "invalidValue(\(path))"
        case .danglingReference(let path): return "danglingReference(\(path))"
        case .duplicate(let path): return "duplicate(\(path))"
        case .invalidTimeRange(let path): return "invalidTimeRange(\(path))"
        case .invalidDateRange(let path): return "invalidDateRange(\(path))"
        case .timetableNotFound: return "timetableNotFound"
        case .compressionFailed: return "compressionFailed"
        case .idCollision: return "idCollision"
        }
    }
}

/// The counted collections of a share payload, with their limits.
public enum ShareCollection: String, CaseIterable, Hashable, Sendable {
    case subjects, lessons, bellSchedules, periods, terms, breaks, tasks, exams, bringList, subtasks, topics

    /// The maximum number of elements (per payload; `periods` per schedule; list kinds per item).
    public var limit: Int {
        switch self {
        case .subjects: return ShareLimits.maxSubjects
        case .lessons: return ShareLimits.maxLessons
        case .bellSchedules: return ShareLimits.maxBellSchedules
        case .periods: return ShareLimits.maxPeriodsPerSchedule
        case .terms: return ShareLimits.maxTerms
        case .breaks: return ShareLimits.maxBreaks
        case .tasks: return ShareLimits.maxTasks
        case .exams: return ShareLimits.maxExams
        case .bringList: return ShareLimits.maxBringListItems
        case .subtasks: return ShareLimits.maxSubtasks
        case .topics: return ShareLimits.maxTopics
        }
    }

    /// `true` when exceeding the limit is reported with its own message (export refuses these); per-item lists
    /// are shortened by export and only a hostile payload exceeds them.
    var hasOwnLimitMessage: Bool {
        switch self {
        case .bringList, .subtasks, .topics: return false
        default: return true
        }
    }
}

/// A non-fatal finding of export or import validation. Import warnings appear in `SharePreview.warnings`;
/// export warnings in `ShareExport.Result.warnings`.
public enum ShareWarning: Hashable, Sendable, CustomStringConvertible {
    // MARK: Import
    /// An open-vocabulary value this version does not know (kept unchanged), e.g. a lesson type from a newer app.
    case unknownValue(field: String, value: String)
    /// A subject's colour name refers to a palette colour this version does not know; the name is dropped
    /// on import (the colour itself is kept).
    case unknownColorName(subjectIndex: Int)
    /// Two periods of a bell schedule overlap.
    case overlappingPeriods(scheduleIndex: Int)
    /// Lessons on weekdays the timetable does not show.
    case lessonsOnDisabledDays(count: Int)
    /// The timetable has no lessons.
    case noLessons

    // MARK: Export
    /// Texts shortened to their limit.
    case textShortened(count: Int)
    /// Texts from which control or bidi-override characters were removed.
    case charactersRemoved(count: Int)
    /// Bring lists, subtasks or topics shortened to their limit.
    case listsShortened(count: Int)
    /// Lessons left out because their subject or period no longer exists.
    case skippedLessons(count: Int)
    /// Values that cannot be shared and were dropped or replaced by a default (malformed vocabulary values,
    /// symbols or emoji).
    case valuesDropped(count: Int)

    /// Catalog key `share.warning.<case>`.
    public var l10nKey: String { "share.warning.\(name)" }

    /// Localisable message. Count-carrying cases pass the count (plural variations); `unknownValue` passes
    /// the raw value as verbatim text; the others take no arguments.
    public var message: LocalizedText {
        switch self {
        case .unknownValue(_, let value): return LocalizedText(key: l10nKey, args: [.string(value)])
        case .lessonsOnDisabledDays(let count), .textShortened(let count), .charactersRemoved(let count),
             .listsShortened(let count), .skippedLessons(let count), .valuesDropped(let count):
            return LocalizedText(key: l10nKey, args: [.integer(count)])
        case .unknownColorName, .overlappingPeriods, .noLessons:
            return LocalizedText(key: l10nKey)
        }
    }

    /// Every catalog key `message` can produce.
    public static let allL10nKeys: [String] = [
        "unknownValue", "unknownColorName", "overlappingPeriods", "lessonsOnDisabledDays", "noLessons",
        "textShortened", "charactersRemoved", "listsShortened", "skippedLessons", "valuesDropped",
    ].map { "share.warning.\($0)" }

    private var name: String {
        switch self {
        case .unknownValue: return "unknownValue"
        case .unknownColorName: return "unknownColorName"
        case .overlappingPeriods: return "overlappingPeriods"
        case .lessonsOnDisabledDays: return "lessonsOnDisabledDays"
        case .noLessons: return "noLessons"
        case .textShortened: return "textShortened"
        case .charactersRemoved: return "charactersRemoved"
        case .listsShortened: return "listsShortened"
        case .skippedLessons: return "skippedLessons"
        case .valuesDropped: return "valuesDropped"
        }
    }

    /// Debug rendering.
    public var description: String {
        switch self {
        case let .unknownValue(field, value): return "unknownValue(\(field)=\(value))"
        case .unknownColorName(let index): return "unknownColorName(s[\(index)])"
        case .overlappingPeriods(let index): return "overlappingPeriods(b[\(index)])"
        case .lessonsOnDisabledDays(let count): return "lessonsOnDisabledDays(\(count))"
        case .noLessons: return "noLessons"
        case .textShortened(let count): return "textShortened(\(count))"
        case .charactersRemoved(let count): return "charactersRemoved(\(count))"
        case .listsShortened(let count): return "listsShortened(\(count))"
        case .skippedLessons(let count): return "skippedLessons(\(count))"
        case .valuesDropped(let count): return "valuesDropped(\(count))"
        }
    }
}
