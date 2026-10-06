import Foundation
import Testing
@testable import TimetableCore

/// Decision 6: load + save of a large database (5 000 tasks + 2 000 lessons) under 1 s on Linux.
@Suite("Sync performance")
struct SyncPerformanceTests {
    /// A heavy user's database. Every subject, lesson and task was edited once after creation, so its
    /// `fieldClocks` holds the one clock the stamper writes for that edit (canonical form since Stage 3:
    /// fields without an entry are at `createdAt`).
    static func largeDatabase() -> TabulaDatabase {
        var ids = SequentialIDGenerator(namespace: 0x9E)
        let created = SyncFixture.hlc(0, node: 0xABCDEF)
        let edited = SyncFixture.hlc(60_000, node: 0xABCDEF)
        func meta(_ type: EntityType, changed: String) -> EntityMeta {
            EntityMeta(createdAt: created, updatedAt: edited, fieldClocks: [changed: edited])
        }
        let timetableID: Timetable.ID = ids.next()
        let timetable = Timetable(id: timetableID, meta: .created(at: created), name: "Uni", enabledDays: Weekday.workweek,
                                  rotation: .none, timeStructure: .freeForm(defaultDurationMinutes: 90),
                                  fieldVisibility: .all, defaultView: .grid, density: .compact, sortIndex: 0)
        let subjects: [Subject] = (0..<40).map { index in
            Subject(id: ids.next(), meta: meta(.subject, changed: "name"), timetableID: timetableID, name: "Subject \(index)",
                    color: ColorValue(hex: "#1E88E5")!, defaultRoom: "R\(index)")
        }
        let lessons: [Lesson] = (0..<2_000).map { index in
            Lesson(id: ids.next(), meta: meta(.lesson, changed: "room"), timetableID: timetableID,
                   subjectID: subjects[index % subjects.count].id,
                   occurrence: LessonOccurrenceRule(day: .weekday(Weekday.workweek.sorted()[index % 5])),
                   slot: .time(start: LocalTime(minuteOfDay: 480 + (index % 8) * 60)!,
                               end: LocalTime(minuteOfDay: 525 + (index % 8) * 60)!),
                   room: "Room \(index)", teacher: "Teacher \(index % 30)", lessonType: .lecture,
                   notes: index % 3 == 0 ? "Bring the lab coat and the notebook" : nil, bringList: ["Notebook"])
        }
        let tasks: [TaskItem] = (0..<5_000).map { index in
            let subtasks: [Subtask] = index % 4 == 0
                ? (0..<3).map { Subtask(id: ids.next(), meta: .created(at: created), title: "Step \($0)", sortIndex: $0) }
                : []
            return TaskItem(id: ids.next(), meta: meta(.task, changed: "completedAt"), title: "Exercise \(index) on page \(index % 300)",
                            kind: .homework, subjectID: subjects[index % subjects.count].id, timetableID: timetableID,
                            due: .dateTime(LocalDate(year: 2026, month: 10, day: 1 + index % 28)!, LocalTime(minuteOfDay: 480)!),
                            priority: .normal, notes: index % 2 == 0 ? "Remember to show the working" : nil,
                            completedAt: index % 3 == 0 ? Fixture.now : nil, subtasks: subtasks)
        }
        return TabulaDatabase(settings: AppSettings(meta: .created(at: created)), timetables: [timetable],
                              subjects: subjects, lessons: lessons, tasks: tasks)
    }

    @Test func largeDatabaseLoadAndSaveUnderOneSecond() async throws {
        let dir = SyncTempDirectory()
        defer { dir.remove() }
        let db = Self.largeDatabase()
        let repository = FileRepository(directory: dir.url)
        try await repository.save(db)                      // warm-up + creates the file the next save rotates

        let clock = ContinuousClock()
        // Best of 3 rounds (the budget is about capability, not scheduler noise of a parallel test run).
        var save = Duration.seconds(3_600), load = Duration.seconds(3_600)
        var loaded = db
        for _ in 0..<3 {
            save = min(save, try await clock.measure { try await repository.save(loaded) })
            load = min(load, try await clock.measure { loaded = try await FileRepository(directory: dir.url).load() })
        }
        #expect(loaded == db.canonicalized())
        let data = try #require(dir.read("tabula.json"))
        let encode = try clock.measure { _ = try db.encoded() }
        let decode = try clock.measure { _ = try TabulaDatabase.decode(from: data) }
        var unedited = db
        for index in unedited.tasks.indices { unedited.tasks[index].meta.fieldClocks = [:] }
        for index in unedited.lessons.indices { unedited.lessons[index].meta.fieldClocks = [:] }
        let uneditedBytes = try unedited.encoded().count
        print("SyncPerformance: \(db.tasks.count) tasks + \(db.lessons.count) lessons, file \(data.count / 1024) KiB "
              + "(\(uneditedBytes / 1024) KiB without field clocks); "
              + "save \(save), load \(load), load+save \(save + load) (encode \(encode), decode \(decode))")
        #if DEBUG
        // Unoptimised test builds: generous bound; the < 1 s budget is asserted in release builds
        // (`swift test -c release -Xswiftc -enable-testing`).
        #expect(save + load < .seconds(5))
        #else
        #expect(save + load < .seconds(1))
        #endif
    }
}
