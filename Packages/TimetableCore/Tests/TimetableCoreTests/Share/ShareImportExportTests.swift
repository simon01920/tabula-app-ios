import Foundation
import Testing
@testable import TimetableCore

@Suite("Share import/export: preview, materialize, insert, export sanitising")
struct ShareImportExportTests {
    @Test func previewSummarisesThePayload() throws {
        let envelope = try ShareExport.encode(from: ShareFixture.secondary(), timetableID: ShareFixture.secondaryTimetableID,
                                              includeTasks: true).envelope
        let preview = try ShareImport.preview(envelope.text)
        #expect(preview.timetableName == "3.A Gymnázium")
        #expect(preview.emoji == "🏫")
        #expect(preview.subjectCount == 14 && preview.lessonCount == 32 && preview.bellScheduleCount == 2)
        #expect(preview.termCount == 2 && preview.breakCount == 6)
        #expect(preview.includesTasks && preview.taskCount == 3 && preview.examCount == 1)
        #expect(preview.warnings.isEmpty)
        if case .weekCycle(let cycle) = preview.rotation { #expect(cycle.labels == ["A", "B"]) } else { Issue.record("rotation") }

        let without = try ShareExport.encode(from: ShareFixture.secondary(), timetableID: ShareFixture.secondaryTimetableID,
                                             includeTasks: false).envelope
        let plain = try ShareImport.preview(without.text)
        #expect(!plain.includesTasks && plain.taskCount == 0 && plain.examCount == 0)

        // "Include tasks" with nothing to include still says so.
        var empty = ShareFixture.minimalPayload()
        empty.includesTasks = true
        #expect(try ShareImport.preview(ShareCodec.decode(ShareCodec.encode(empty).text)).includesTasks)
    }

    @Test func materializeCreatesFreshEntitiesAndNeverReusesIDs() throws {
        let source = ShareFixture.secondary()
        let payload = try ShareFixture.payload(source, ShareFixture.secondaryTimetableID, includeTasks: true)
        var ids = SequentialIDGenerator(namespace: 0x1234)
        var clock = TestClock(node: 0xABCD)
        let imported = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Fixture.now, sortIndex: 3)

        let sourceIDs = Set(source.timetables.map(\.id.uuid) + source.subjects.map(\.id.uuid) + source.lessons.map(\.id.uuid)
                            + source.bellSchedules.map(\.id.uuid) + source.terms.map(\.id.uuid) + source.breaks.map(\.id.uuid)
                            + source.tasks.map(\.id.uuid) + source.exams.map(\.id.uuid))
        #expect(Set(imported.allIDs).isDisjoint(with: sourceIDs))
        #expect(Set(imported.allIDs).count == imported.allIDs.count)
        let periodIDs = imported.bellSchedules.flatMap { $0.periods.map(\.id) }
        #expect(Set(periodIDs).count == 10) // shared across the two schedules (period-ID convention)
        #expect(imported.bellSchedules[0].periods.map(\.id) == imported.bellSchedules[1].periods.map(\.id))

        // Everything belongs to the new timetable, breaks included (never global).
        let tt = imported.timetable.id
        #expect(imported.subjects.allSatisfy { $0.timetableID == tt })
        #expect(imported.lessons.allSatisfy { $0.timetableID == tt })
        #expect(imported.breaks.allSatisfy { $0.timetableID == tt })
        #expect(imported.tasks.allSatisfy { $0.timetableID == tt && $0.completedAt == nil && $0.attachments.isEmpty })
        #expect(imported.timetable.sortIndex == 3)

        // Fresh metadata: live, created now by the injected clock, strictly increasing in generation order.
        let metas = [imported.timetable.meta] + imported.bellSchedules.map(\.meta) + imported.subjects.map(\.meta)
            + imported.terms.map(\.meta) + imported.breaks.map(\.meta) + imported.lessons.map(\.meta)
        #expect(metas.allSatisfy { !$0.isDeleted && $0.createdAt == $0.updatedAt && $0.fieldClocks.isEmpty })
        #expect(metas.allSatisfy { $0.createdAt.node == 0xABCD && $0.createdAt.physicalMillis == TabulaJSON.milliseconds(from: Fixture.now) })
        #expect(zip(metas, metas.dropFirst()).allSatisfy { $0.createdAt < $1.createdAt })

        // References resolve to the new entities.
        let subjectIDs = Set(imported.subjects.map(\.id))
        #expect(imported.lessons.allSatisfy { subjectIDs.contains($0.subjectID) })
        #expect(imported.tasks[1].linkedLesson?.lessonID == imported.lessons[1].id)
        #expect(imported.tasks[0].subtasks.map(\.title) == ["Osnova", "Koncept"])
        #expect(imported.tasks[0].subtasks.map(\.sortIndex) == [0, 1])
    }

    @Test func materializeIsDeterministic() throws {
        let payload = try ShareFixture.payload(ShareFixture.university(), ShareFixture.universityTimetableID, includeTasks: true)
        func run() throws -> ShareImportedTimetable {
            var ids = SequentialIDGenerator(namespace: 9)
            var clock = TestClock()
            return try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Fixture.now)
        }
        #expect(try run() == run())
    }

    @Test func insertingNeverOverwrites() throws {
        let existing = Fixture.fullDatabase()
        let payload = try ShareFixture.payload(ShareFixture.secondary(), ShareFixture.secondaryTimetableID, includeTasks: true)
        var ids = SequentialIDGenerator(namespace: 0x77)
        var clock = TestClock()
        let imported = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Fixture.now)
        let merged = try imported.inserted(into: existing)
        #expect(merged.timetables.count == existing.timetables.count + 1)
        #expect(merged.subjects.count == existing.subjects.count + 14)
        #expect(merged.lessons.count == existing.lessons.count + 32)
        #expect(Array(merged.subjects.prefix(existing.subjects.count)) == existing.subjects)
        #expect(Array(merged.lessons.prefix(existing.lessons.count)) == existing.lessons)
        #expect(merged.settings == existing.settings)
        #expect(merged.overrides == existing.overrides && merged.reminderRules == existing.reminderRules)
        #expect(merged.validate().filter { $0.severity == .error }.isEmpty)

        // Importing the same share twice creates a second, independent copy.
        let again = try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Fixture.now)
        let twice = try again.inserted(into: merged)
        #expect(twice.timetables.count == existing.timetables.count + 2)

        // An ID generator that collides with existing data inserts nothing.
        var colliding = SequentialIDGenerator(namespace: 0xF1) // the namespace of Fixture.fullDatabase()
        let clash = try ShareImport.materialize(payload, ids: &colliding, clock: &clock, now: Fixture.now)
        #expect(throws: ShareError.idCollision) { try clash.inserted(into: existing) }
    }

    @Test func materializeRevalidates() throws {
        var payload = ShareFixture.minimalPayload()
        payload.lessons[0].subject = 5
        var ids = SequentialIDGenerator()
        var clock = TestClock()
        #expect(throws: ShareError.danglingReference(path: "l[0].s")) {
            try ShareImport.materialize(payload, ids: &ids, clock: &clock, now: Fixture.now)
        }
        #expect(throws: ShareError.danglingReference(path: "l[0].s")) { try ShareImport.preview(payload) }
    }

    // MARK: Export sanitising

    @Test func exportCleansAndShortensHostileText() throws {
        var db = ShareFixture.secondary()
        db.subjects[0].name = "Mat\u{202E}hematika\u{0}\u{1B}[0m"
        db.subjects[1].name = String(repeating: "A", count: 10_000)
        db.subjects[2].name = String(repeating: "a", count: 99) + "👩‍🔬" // the emoji (3 scalars) would exceed 100
        db.subjects[3].shortName = "Line\nbreak"
        db.subjects[4].notes = "Windows\r\nline\rendings\u{2028}and\ttabs"
        db.subjects[5].colorName = .key("palette.neon.color.glow")
        db.subjects[6].symbol = .systemImage("Not A Symbol")
        db.subjects[7].symbol = .emoji(String(repeating: "😀", count: 20))
        db.lessons[0].bringList = (0..<60).map { "Item \($0)" }
        db.lessons[1].lessonType = LessonType(rawValue: "lab work") // not a vocabulary-shaped value
        db.timetables[0].rotation = .weekCycle(WeekCycle(length: 2, anchor: .isoWeekParity(policy: .strict, offset: 5), labels: ["A", "B"]))

        let result = try ShareExport.makePayload(from: db, timetableID: ShareFixture.secondaryTimetableID, includeTasks: false)
        let payload = result.payload
        #expect(result.warnings == [.textShortened(count: 2), .charactersRemoved(count: 3), .listsShortened(count: 1),
                                    .valuesDropped(count: 4)])
        let names = payload.subjects.map(\.name)
        #expect(names.contains("Mathematika[0m"))
        #expect(names.contains(String(repeating: "A", count: 100)))
        #expect(names.contains(String(repeating: "a", count: 99)))
        #expect(payload.subjects.contains { $0.shortName == "Line break" })
        #expect(payload.subjects.contains { $0.notes == "Windows\nline\nendings\nand\ttabs" })
        #expect(payload.subjects.allSatisfy { $0.colorName != .key("palette.neon.color.glow") })
        #expect(payload.lessons.contains { $0.bringList.count == 50 })
        if case .weekCycle(let cycle) = payload.timetable.rotation {
            #expect(cycle.anchor == .isoWeekParity(policy: .strict, offset: 1)) // 5 mod 2: same weeks
        }
        // What export produces always imports.
        #expect(try ShareCodec.decode(ShareCodec.encode(payload).text) == payload)
    }

    @Test func exportRefusesTooLargeCollections() throws {
        var db = ShareFixture.secondary()
        let lesson = db.lessons[0]
        db.lessons = (0..<2001).map { index in
            var copy = lesson
            copy.id = Lesson.ID(UUID(uuidString: "11110000-0000-4000-8000-\(PaddedNumber.hex(UInt64(index), width: 12))")!)
            return copy
        }
        #expect(throws: ShareError.tooMany(.lessons, count: 2001)) {
            try ShareExport.makePayload(from: db, timetableID: ShareFixture.secondaryTimetableID, includeTasks: false)
        }
        #expect(ShareError.tooMany(.lessons, count: 2001).message.args == [.integer(2000)])
    }

    @Test func exportOfTheStageOneFullDatabase() throws {
        let db = Fixture.fullDatabase()
        let school = try ShareExport.makePayload(from: db, timetableID: db.timetables[0].id, includeTasks: true)
        #expect(school.warnings.isEmpty)
        #expect(school.payload.subjects.count == 2)              // Matematika, Fyzika (Algebra belongs to College)
        #expect(school.payload.breaks.map(\.name) == ["Christmas", "Exams"]) // the global break and the timetable's own
        #expect(school.payload.tasks.map(\.title) == ["Úloha 3"]) // "Buy pens" is completed and has no timetable
        #expect(school.payload.exams.map(\.title) == ["Písomka"])
        if case let .bellSchedule(_, perWeekday) = school.payload.timetable.timeStructure {
            #expect(perWeekday.keys.sorted() == [.friday])
        } else {
            Issue.record("expected bell schedules")
        }
        let college = try ShareExport.makePayload(from: db, timetableID: db.timetables[1].id, includeTasks: true)
        #expect(college.payload.lessons.map(\.day) == [.cycleDay(1), .cycleDay(2)])
        #expect(college.payload.tasks.isEmpty && college.payload.exams.isEmpty)
    }
}
