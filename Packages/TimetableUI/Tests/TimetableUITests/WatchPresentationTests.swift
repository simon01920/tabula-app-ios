import Foundation
import Testing
import TimetableCore
@testable import TimetableUI

// Phase 5 W1: the watch's transfer format, offline-cache validation, staleness and display.

private let zone = SampleScenarios.timeZone
private let context = CalendarContext(timeZone: zone, firstWeekday: .monday)
private let day1 = LocalDate(year: 2026, month: 10, day: 13)!
private let day2 = day1.adding(days: 1)
private let math = SubjectSummary(id: Subject.ID(UUID()), name: "Mathematics", shortName: "MAT",
                                  color: ColorValue(red: 30, green: 90, blue: 200))

private func lesson(_ name: String, _ day: LocalDate, _ start: Int, _ end: Int) -> WidgetSnapshot.Lesson {
    WidgetSnapshot.Lesson(id: "lesson:\(name):\(day.isoString)", subject: math, date: day,
                          startTime: LocalTime(hour: start, minute: 0)!, endTime: LocalTime(hour: end, minute: 0)!)
}

private func snapshot(tier: Tier = .pro) -> WidgetSnapshot {
    WidgetSnapshot(generatedAt: Date(timeIntervalSince1970: 0), timeZoneID: zone.identifier, followsDeviceTimeZone: true,
                   localeID: "en_GB", languageCode: "en", hourCycle: .h24, tier: tier, hasTimetable: true,
                   days: [WidgetSnapshot.Day(date: day1, kind: .school,
                                             lessons: [lesson("a", day1, 8, 9), lesson("b", day1, 9, 10),
                                                       lesson("c", day1, 10, 11)]),
                          WidgetSnapshot.Day(date: day2, kind: .school, lessons: [lesson("d", day2, 8, 9)])],
                   followingLesson: nil, tasks: [], overdueTaskCount: 0, nextExam: nil)
}

private func show(_ snapshot: WidgetSnapshot?, at hour: Int, on day: LocalDate = day1) -> WatchDisplay.Kind {
    WatchPresenter.display(snapshot: snapshot, now: context.date(day, LocalTime(hour: hour, minute: 30)!),
                           deviceTimeZone: zone, lookup: EnglishCatalog.lookup).kind
}

@Suite("Watch transfer + display (Phase 5 W1)")
struct WatchPresentationTests {
    @Test func transferRoundTripsAndRejectsWhatTheWatchCannotRead() throws {
        let data = try WidgetSnapshotStore.encode(snapshot())
        let context = try #require(WatchSnapshotTransfer.context(for: data))
        #expect(WatchSnapshotTransfer.snapshotData(in: context) == data)
        #expect(WatchSnapshotTransfer.context(for: Data(count: WidgetSnapshotBuilder.maxEncodedBytes + 1)) == nil)
        #expect(WatchSnapshotTransfer.snapshotData(in: [WatchSnapshotTransfer.key: Data("{".utf8)]) == nil)
        #expect(WatchSnapshotTransfer.snapshotData(in: [WatchSnapshotTransfer.key: "text"]) == nil)
        #expect(WatchSnapshotTransfer.snapshotData(in: [:]) == nil)
        var newer = snapshot()
        newer.version = WidgetSnapshot.currentVersion + 1
        let newerData = try WidgetSnapshotStore.encode(newer)
        #expect(WatchSnapshotTransfer.snapshotData(in: [WatchSnapshotTransfer.key: newerData]) == nil)
    }

    @Test func noSnapshotAsksToOpenThePhoneAndFreeTierIsGated() {
        #expect(show(nil, at: 9) == .openPhone(title: "Open Tabula on your iPhone",
                                               detail: "Your timetable appears here after your iPhone sends it."))
        #expect(show(snapshot(tier: .free), at: 9) == .pro(title: "Available in Tabula Pro"))
    }

    @Test func aSnapshotThatNoLongerCoversTodayIsOutdated() {
        #expect(show(snapshot(), at: 9, on: day1.adding(days: 2))
            == .openPhone(title: "Open Tabula on your iPhone", detail: "Open the app to update your timetable."))
    }

    @Test func duringALessonShowsNowTheRestOfTodayAndTomorrow() throws {
        guard case let .content(nowNext, today, tomorrow) = show(snapshot(), at: 9) else {
            Issue.record("expected content")
            return
        }
        guard case .current(let current) = nowNext.kind else {
            Issue.record("expected the lesson in progress")
            return
        }
        #expect(current.id == "lesson:b:\(day1.isoString)")
        #expect(nowNext.countdown?.mode == .timer && nowNext.countdown?.unitLabel == "left")
        #expect(try #require(today).rows.map(\.id) == ["lesson:c:\(day1.isoString)"])   // past + current dropped
        #expect(try #require(tomorrow).isTomorrow && tomorrow?.rows.map(\.id) == ["lesson:d:\(day2.isoString)"])
    }

    @Test func afterTheLastLessonTodayIsOmittedAndTomorrowStays() {
        guard case let .content(_, today, tomorrow) = show(snapshot(), at: 12) else {
            Issue.record("expected content")
            return
        }
        #expect(today == nil)
        #expect(tomorrow?.rows.count == 1)
    }
}
