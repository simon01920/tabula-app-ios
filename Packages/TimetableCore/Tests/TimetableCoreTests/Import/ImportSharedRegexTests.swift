import Foundation
import Testing
@testable import TimetableCore

/// Phase 10 C6: the import regexes are built once and shared (`nonisolated(unsafe) static let`). Matching from
/// many tasks at once gives the same results as one task; `ImportEvalTests` pins the results themselves.
@Suite("Import: shared regexes")
struct ImportSharedRegexTests {
    static let samples = [
        "MAT 204 (A)", "A: FYZ\nNovák", "(B) ANJ 3P1", "MAT (A) / FYZ (B)", "Ján Novák", "SJL [cv] C1.04", "12.",
        "B-204", "Dejepis\nJ. Kováč\n2O4", "1. hod\n8:00-8:45", "1:00–1:50 p.m.", "第3节\n10:00-10:45", "2\n8h55-9h50",
        "12:30–1:15", "Period 4\n10:55",
    ]

    /// Every regex-backed entry point over `samples`, rendered as text.
    static func fingerprint() -> String {
        samples.map { text in
            // Sets are rendered sorted so the text never depends on hash order.
            let parts = ImportCellSplitter.split(text, options: ImportParserOptions(), languages: ["sk", "en"]).map { part in
                "\(part.weeks?.sorted() ?? [])·\(part.subject)·\(part.room ?? "-")·\(part.teacher ?? "-")"
                    + "·\(String(describing: part.lessonType))·\(part.notes)·\(part.reasons.sorted())·\(part.alternatives)"
            }
            return "\(parts)|\(ImportBellInference.header(text))|\(ImportBellInference.times(in: text))"
                + "|\(ImportBellInference.isHeaderLike(text))|\(ImportCellSplitter.isRoomToken(text))"
        }.joined(separator: "\n")
    }

    @Test func concurrentMatchingEqualsSerial() async {
        let serial = Self.fingerprint()
        let results = await withTaskGroup(of: String.self) { group in
            for _ in 0..<16 { group.addTask { Self.fingerprint() } }
            var all: [String] = []
            for await result in group { all.append(result) }
            return all
        }
        #expect(results.count == 16)
        #expect(results.allSatisfy { $0 == serial })
        #expect(Self.fingerprint() == serial)
    }
}
