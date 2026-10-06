import Foundation
import Testing
@testable import TimetableCore

/// Keeps docs/specs/SHARE_FORMAT.md in sync with the code.
@Suite("SHARE_FORMAT.md")
struct ShareFormatDocTests {
    static var allL10nKeys: [String] { ShareError.allL10nKeys + ShareWarning.allL10nKeys }

    @Test func everyL10nKeyIsDocumented() throws {
        let doc = try RepositoryFile.text("docs/specs/SHARE_FORMAT.md")
        let keys = Self.allL10nKeys
        #expect(Set(keys).count == keys.count)
        let missing = keys.filter { !doc.contains("`\($0)`") }
        #expect(missing.isEmpty, "missing from SHARE_FORMAT.md: \(missing)")
        #expect(doc.contains("Total: \(keys.count) keys"), "§9 total must be \(keys.count)")
    }

    @Test func limitsAreDocumented() throws {
        let doc = try RepositoryFile.text("docs/specs/SHARE_FORMAT.md")
        for (name, value) in [("inlineCompressedBytes", ShareLimits.inlineCompressedBytes),
                              ("maxEnvelopeBytes", ShareLimits.maxEnvelopeBytes), ("maxJSONBytes", ShareLimits.maxJSONBytes),
                              ("maxJSONDepth", ShareLimits.maxJSONDepth), ("maxSubjects", ShareLimits.maxSubjects),
                              ("maxLessons", ShareLimits.maxLessons), ("maxBellSchedules", ShareLimits.maxBellSchedules),
                              ("maxPeriodsPerSchedule", ShareLimits.maxPeriodsPerSchedule), ("maxTerms", ShareLimits.maxTerms),
                              ("maxBreaks", ShareLimits.maxBreaks), ("maxTasks", ShareLimits.maxTasks),
                              ("maxExams", ShareLimits.maxExams), ("maxBringListItems", ShareLimits.maxBringListItems),
                              ("maxSubtasks", ShareLimits.maxSubtasks), ("maxTopics", ShareLimits.maxTopics),
                              ("maxNameLength", ShareLimits.maxNameLength), ("maxNotesLength", ShareLimits.maxNotesLength),
                              ("maxListItemLength", ShareLimits.maxListItemLength), ("maxEmojiLength", ShareLimits.maxEmojiLength),
                              ("maxSystemImageLength", ShareLimits.maxSystemImageLength),
                              ("maxVocabularyLength", ShareLimits.maxVocabularyLength), ("maxSpan", ShareLimits.maxSpan),
                              ("maxRepeatInterval", ShareLimits.maxRepeatInterval)] {
            #expect(doc.contains("| `\(name)` | \(value) |"), "\(name) = \(value) not documented")
        }
    }
}
