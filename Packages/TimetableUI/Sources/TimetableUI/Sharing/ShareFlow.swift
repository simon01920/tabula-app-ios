// Sharing in the app (Phase 7 H1, PHASE7_PLAN decisions 2–4): the pure decisions behind the share sheet, the import
// entry points and the import preview. Foundation only, Linux-tested (ShareFlowTests). The codec, links and codes are
// TimetableCore's (`ShareExport`, `ShareImport`, `ShareLink`, `ShortCode`), used as they are.
//
//   ShareInbound          what an incoming link, scanned QR code, pasted text or typed code names (envelope or code)
//   ShareCodeInput        live validation of the 8-character code field
//   SharePlan             inline link (fits the inline budget) or upload for a short code; the inline fallback
//   ShareService          the share Worker contract (H2): URLs, request body, response decoding, plain-word problems
//   ShareImportSummary    what the import preview shows (name, subjects, lessons, bell schedules, conflicts)
//   DatabaseMutation.importShared   add as a new timetable, or replace one (never silently; the app backs up first)
import Foundation
import TimetableCore

// MARK: - Incoming

/// The shared timetable an incoming link, QR code, pasted text or typed code points at.
public enum ShareInbound: Hashable, Sendable {
    /// The payload itself (inline link / QR); decode with `ShareImport.decode(_:)`.
    case envelope(String)
    /// A short code; the envelope is fetched from the share service.
    case code(ShortCode)

    /// `tabula://import#<envelope>` or `tabula://import?code=<CODE>` (the landing page's "Open in Tabula" links).
    /// Strict: scheme and host in any case, nothing else in the URL, a canonical code, envelope characters only.
    public static func parse(url: URL) -> ShareInbound? {
        parse(appLink: url.absoluteString)
    }

    /// The app-link form of `parse(url:)` on text.
    public static func parse(appLink text: String) -> ShareInbound? {
        let prefix = "tabula://import"
        guard text.utf8.count <= ShareLimits.maxLinkBytes, text.utf8.count > prefix.utf8.count,
              String(decoding: text.utf8.prefix(prefix.utf8.count), as: UTF8.self).lowercased() == prefix else {
            return nil
        }
        let rest = Array(text.utf8.dropFirst(prefix.utf8.count))
        if rest.first == UInt8(ascii: "#") {
            let envelope = rest.dropFirst()
            guard !envelope.isEmpty, envelope.allSatisfy(isEnvelopeByte) else { return nil }
            return .envelope(String(decoding: envelope, as: UTF8.self))
        }
        let query = Array("?code=".utf8)
        if rest.starts(with: query), let code = ShortCode(String(decoding: rest.dropFirst(query.count), as: UTF8.self)) {
            return .code(code)
        }
        return nil
    }

    /// Pasted text or a scanned QR payload: a share link (`https://<domain>/t#…`, `/c/CODE`), an app link, or a code
    /// typed with or without the dash. Errors are the core's `ShareError` (`.invalidLink` / `.invalidShortCode`).
    public static func parse(pasted text: String, configuration: ShareConfiguration = .default) throws(ShareError) -> ShareInbound {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("tabula:") {
            guard let inbound = parse(appLink: trimmed) else { throw .invalidLink }
            return inbound
        }
        if trimmed.lowercased().hasPrefix("http") {
            switch try ShareLink.parse(trimmed, configuration: configuration) {
            case .inline(let envelope): return .envelope(envelope)
            case .shortCode(let code): return .code(code)
            }
        }
        if let code = ShortCode.normalize(trimmed) { return .code(code) }
        throw trimmed.contains("/") || trimmed.contains(":") ? .invalidLink : .invalidShortCode
    }

    private static func isEnvelopeByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."):
            return true
        default:
            return false
        }
    }
}

/// Live state of the code field (checked on every keystroke; spaces and dashes are ignored, letters any case).
public enum ShareCodeInput: Hashable, Sendable {
    case empty
    /// Valid so far, `remaining` characters to go.
    case incomplete(remaining: Int)
    /// A character that no code contains (0, O, 1, I, L, punctuation, non-Latin letters).
    case invalidCharacter
    /// More than 8 characters.
    case tooLong
    case complete(ShortCode)

    public static func evaluate(_ text: String) -> ShareCodeInput {
        var count = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "-" || (0x2010...0x2015).contains(scalar.value) || scalar.value == 0x2212 {
                continue
            }
            guard scalar.isASCII, ShortCode.alphabet.unicodeScalars.contains(Unicode.Scalar(UInt8(scalar.value)).uppercased) else {
                return .invalidCharacter
            }
            count += 1
        }
        if count == 0 { return .empty }
        if count > ShortCode.length { return .tooLong }
        if count < ShortCode.length { return .incomplete(remaining: ShortCode.length - count) }
        return ShortCode.normalize(text).map(ShareCodeInput.complete) ?? .invalidCharacter
    }

    /// Catalog key of the hint under the field (`nil` when there is nothing to say). `share.code.remaining` takes
    /// the count (plural variations).
    public var messageKey: String? {
        switch self {
        case .empty, .complete: return nil
        case .incomplete: return "share.code.remaining"
        case .invalidCharacter: return "share.code.invalidCharacter"
        case .tooLong: return "share.code.tooLong"
        }
    }
}

private extension Unicode.Scalar {
    var uppercased: Unicode.Scalar {
        ("a"..."z").contains(self) ? Unicode.Scalar(value - 32)! : self
    }
}

// MARK: - Outgoing

/// How a timetable is shared: inline when the compressed payload fits `ShareLimits.inlineCompressedBytes`
/// (`ShareEnvelope.route`), otherwise uploaded for a short code.
public enum SharePlan: Hashable, Sendable {
    case inline(ShareLink)
    case upload(envelope: String)

    /// Bytes a QR code holds in byte mode at correction level L (version 40). SHARE_FORMAT §2.
    public static let qrByteCapacity = 2953

    public static func make(for envelope: ShareEnvelope) -> SharePlan {
        envelope.route == .inline ? .inline(.inline(envelope: envelope.text)) : .upload(envelope: envelope.text)
    }

    /// The inline link offered when the upload fails, if it still fits one QR code (the sheet's QR and a link a
    /// messenger keeps whole); `nil` when it does not.
    public static func fallback(envelope: String, configuration: ShareConfiguration = .default) -> ShareLink? {
        let link = ShareLink.inline(envelope: envelope)
        return link.urlString(configuration: configuration).utf8.count <= qrByteCapacity ? link : nil
    }
}

// MARK: - Share service (Worker, Phase 7 H2)

/// Why the share service could not store or return a timetable, in the words the user sees.
public enum ShareServiceProblem: Error, Hashable, Sendable {
    case offline, timedOut, rateLimited, notFound, tooLarge, unavailable, invalidResponse

    public var messageKey: String {
        switch self {
        case .offline: return "share.service.offline"
        case .timedOut: return "share.service.timedOut"
        case .rateLimited: return "share.service.rateLimited"
        case .notFound: return "share.service.notFound"
        case .tooLarge: return "share.error.tooLarge"
        case .unavailable: return "share.service.unavailable"
        case .invalidResponse: return "share.service.invalidResponse"
        }
    }
}

/// The share Worker's contract: `POST /v1/share {v:1,payload}` → 201 `{code,url,expiresAt}`;
/// `GET /v1/share/:code` → 200 `{v:1,payload}`; errors `{error}` with 400/404/413/415/429/503.
public enum ShareService {
    /// The one place the service's domain comes from (placeholder until deployment, docs/SHARING_DEPLOY.md).
    public static let configuration = ShareConfiguration.default
    public static let requestTimeout: TimeInterval = 15

    public static var baseURL: URL { URL(string: "https://\(configuration.domain)")! }
    public static var uploadURL: URL { baseURL.appendingPathComponent("v1/share") }
    public static func fetchURL(for code: ShortCode) -> URL { uploadURL.appendingPathComponent(code.rawValue) }

    private struct Body: Codable {
        var v: Int
        var payload: String
    }

    private struct Created: Decodable {
        var code: String
    }

    /// `{"payload":"<envelope>","v":1}`.
    public static func uploadBody(envelope: String) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(Body(v: 1, payload: envelope))) ?? Data()
    }

    /// The code of a successful upload. The service's own `url` is ignored: links are built from `configuration`.
    public static func decodeUpload(status: Int, data: Data) -> Result<ShortCode, ShareServiceProblem> {
        guard status == 201 else { return .failure(problem(status: status)) }
        guard let created = try? JSONDecoder().decode(Created.self, from: data), let code = ShortCode(created.code) else {
            return .failure(.invalidResponse)
        }
        return .success(code)
    }

    /// The envelope stored under a code (still untrusted: decode it with `ShareImport.decode(_:)`).
    public static func decodeFetch(status: Int, data: Data) -> Result<String, ShareServiceProblem> {
        guard status == 200 else { return .failure(problem(status: status)) }
        guard data.count <= ShareLimits.maxEnvelopeBytes + 256, let body = try? JSONDecoder().decode(Body.self, from: data),
              body.v == 1 else {
            return .failure(.invalidResponse)
        }
        return .success(body.payload)
    }

    static func problem(status: Int) -> ShareServiceProblem {
        switch status {
        case 404: return .notFound
        case 413: return .tooLarge
        case 429: return .rateLimited
        case 500...599: return .unavailable
        default: return .invalidResponse
        }
    }
}

// MARK: - Import preview

/// What the import preview shows before anything is written (decision 4).
public struct ShareImportSummary: Hashable, Sendable {
    public struct Schedule: Hashable, Sendable {
        public var name: String
        public var periods: [Period]
    }

    public struct Period: Hashable, Sendable {
        public var start: LocalTime
        public var end: LocalTime
    }

    public var name: String
    public var emoji: String?
    /// Subject names in the sender's order (`o`), then by name.
    public var subjectNames: [String]
    public var lessonCount: Int
    public var bellSchedules: [Schedule]
    /// Lessons that overlap another lesson in the weekly template (`ConflictDetector.templateConflicts`).
    public var conflictCount: Int
    public var includesTasks: Bool
    public var taskCount: Int
    public var examCount: Int
    public var warnings: [ShareWarning]

    /// Validates `payload` (`ShareImport.preview`) and resolves it in a scratch database to count conflicts.
    public init(payload: SharePayloadV1, context: CalendarContext) throws(ShareError) {
        let preview = try ShareImport.preview(payload)
        name = preview.timetableName
        emoji = preview.emoji
        subjectNames = payload.subjects
            .sorted { ($0.sortIndex ?? Int.max, $0.name.lowercased()) < ($1.sortIndex ?? Int.max, $1.name.lowercased()) }
            .map(\.name)
        lessonCount = preview.lessonCount
        bellSchedules = payload.bellSchedules.map { schedule in
            Schedule(name: schedule.name, periods: schedule.periods
                .filter { $0.kind == .lesson }
                .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
                .map { Period(start: $0.start, end: $0.end) })
        }
        includesTasks = preview.includesTasks
        taskCount = preview.taskCount
        examCount = preview.examCount
        warnings = preview.warnings

        var ids = SequentialIDGenerator(namespace: 0x5348)
        var clock = HybridLogicalClock(node: 0x5348)
        let imported = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Date(timeIntervalSince1970: 0))
        let scratch = try imported.inserted(into: TabulaDatabase(settings: .untouchedDefaults))
        let resolver = ScheduleResolver(database: scratch, timetableID: imported.timetable.id, context: context)
        conflictCount = resolver.map { Set(ConflictDetector.templateConflicts(in: $0).flatMap(\.lessonIDs)).count } ?? 0
    }
}

// MARK: - Import mutation

extension DatabaseMutation {
    /// Adds the shared timetable as a new timetable (`replacing == nil`) or in place of `replacing` (same position;
    /// the old timetable is deleted like "Delete Timetable": its tasks and exams stay, unlinked). The new timetable
    /// becomes active and onboarding counts as finished; `profile` is set when given (import from onboarding).
    /// `replacesDatabase` only when nothing is stored yet (first launch), so the model accepts it without a base.
    public static func importShared(_ payload: SharePayloadV1, replacing: Timetable.ID? = nil, profile: UserProfile? = nil,
                                    startsFromScratch: Bool = false) -> DatabaseMutation {
        DatabaseMutation(label: replacing == nil ? "import shared timetable" : "import shared timetable (replace)",
                         replacesDatabase: startsFromScratch) { database, clock, now in
            let replaced = replacing.flatMap { id in database.timetables.first { $0.id == id && !$0.isDeleted } }
            let sortIndex: Int
            if let replaced {
                sortIndex = replaced.sortIndex
            } else {
                let append = TimetableManagement.appendIndex(in: database)
                for step in append.steps { try step.step(&database, &clock, now) }
                sortIndex = append.sortIndex
            }
            var ids = SystemIDGenerator()
            let imported = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: now, sortIndex: sortIndex)
            database = try imported.inserted(into: database)
            if let replaced, let delete = TimetableManagement.deleteMutation(replaced.id, in: database) {
                try delete.step(&database, &clock, now)
            }
            let newID = imported.timetable.id
            try DatabaseMutation.settings { settings in
                settings.activeTimetableID = newID
                if settings.onboardingCompletedAt == nil { settings.onboardingCompletedAt = now }
                if let profile { settings.profile = profile }
            }.step(&database, &clock, now)
        }
    }
}
