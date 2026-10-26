// Launch routes of the editors (stage B3). Every editor is a sheet over the Timetable tab; opened by route without
// ids (`-TabulaScreen editor.lesson`) each one picks something meaningful from the seed data.
//
//   editor.lesson        first lesson of the active timetable (Mon first), or a new lesson when there is none
//   editor.lesson-new    new lesson, prefilled the way a tapped empty grid cell does (2nd school day, 3rd period)
//   editor.subject       first subject (alphabetical)
//   editor.subjects      subjects list
//   editor.bell          bell schedule(s) of the active timetable
//   editor.bell-period   the bell schedule editor with its first period's detail page pushed (U5b)
//   editor.timetable     settings of the active timetable
//   editor.terms         terms & holidays of the active timetable
//   editor.day-change    "Change for this day" for today with its first lesson selected
//   editor.timetables    timetables manager
//
// HOW OTHER SCREENS OPEN THE EDITORS (Timetable/Today views, stage B2; they live in the same module):
//   .sheet(item: …) { LessonEditorView(target: .existing(lessonID)) }
//   .sheet(…)       { LessonEditorView(target: .new(NewLessonContext(day: .weekday(.wednesday), slot: .period(periodID, span: 1)))) }
//   .sheet(…)       { SubjectEditorView(subjectID: id) }     // nil id = new subject (optional timetableID:, onSaved:)
//   .sheet(…)       { SubjectsListView() }
//   .sheet(…)       { BellScheduleEditorView() }             // optional timetableID:
//   .sheet(…)       { TimetableEditorView() }                // optional timetableID:
//   .sheet(…)       { TermsEditorView() }                    // optional timetableID:
//   .sheet(…)       { DayChangeEditorView(date: localDate, lessonID: lessonID) }
//   .sheet(…)       { TimetablesManagerView() }
// Routes read `@Environment(\.editorContext)` (set by B2 sheets); `nil` = launch route -> seed defaults. Mapping:
// TimetableUI `EditorLaunchTarget`. Add entries here only; see Routing/RouteRegistry.swift.
import SwiftUI
import TimetableCore
import TimetableUI

enum EditorRoutes: RouteProvider {
    @MainActor static var routes: [AppRoute] {
        [
            AppRoute("editor.lesson", .sheet(over: .timetable)) { LessonEditorRoute() },
            AppRoute("editor.lesson-new", .sheet(over: .timetable)) { LessonEditorRoute(isNew: true) },
            AppRoute("editor.subject", .sheet(over: .timetable)) { SubjectEditorRoute() },
            AppRoute("editor.subjects", .sheet(over: .timetable)) { SubjectsListView() },
            AppRoute("editor.bell", .sheet(over: .timetable)) { BellScheduleEditorView() },
            AppRoute("editor.bell-period", .sheet(over: .timetable)) { BellScheduleEditorView(opensFirstPeriod: true) },
            AppRoute("editor.timetable", .sheet(over: .timetable)) { TimetableEditorView() },
            AppRoute("editor.terms", .sheet(over: .timetable)) { TermsEditorView() },
            AppRoute("editor.day-change", .sheet(over: .timetable)) { DayChangeEditorRoute() },
            AppRoute("editor.timetables", .sheet(over: .timetable)) { TimetablesManagerView() },
        ]
    }
}

/// `editor.lesson` / `editor.lesson-new` without ids.
private struct LessonEditorRoute: View {
    var isNew = false
    @Environment(AppModel.self) private var model
    @Environment(\.editorContext) private var editorContext

    var body: some View {
        switch EditorLaunchTarget(editorContext) {
        case .editLesson(let id, let timetableID):
            LessonEditorView(target: .existing(id), timetableID: timetableID)
        case .newLesson(let context, let timetableID):
            LessonEditorView(target: .new(context), timetableID: timetableID)
        default:
            seedBody
        }
    }

    @ViewBuilder private var seedBody: some View {
        if !isNew, let lesson = EditorSeedPicker.firstLesson(in: model) {
            LessonEditorView(target: .existing(lesson.id))
        } else {
            LessonEditorView(target: .new(newContext()))
        }
    }

    /// The second enabled day and the third lesson period (what tapping that empty cell would pass).
    private func newContext() -> NewLessonContext {
        guard let timetable = model.activeTimetable else { return NewLessonContext() }
        let days = DayChoices.keys(for: timetable, firstWeekday: model.calendarContext.firstWeekday)
        var schedule: BellSchedule?
        if case .bellSchedule(let id, _) = timetable.timeStructure {
            schedule = model.database?.bellSchedules.first { $0.id == id && !$0.isDeleted }
        }
        let periods = SlotDraft.lessonPeriods(of: schedule)
        let slot = periods.indices.contains(2) ? LessonSlot.period(periods[2].id, span: 1) : nil
        return NewLessonContext(day: days.indices.contains(1) ? days[1] : days.first, slot: slot)
    }
}

/// `editor.subject` without an id.
private struct SubjectEditorRoute: View {
    @Environment(AppModel.self) private var model
    @Environment(\.editorContext) private var editorContext

    var body: some View {
        if case .newSubject(let timetableID) = EditorLaunchTarget(editorContext) {
            // The quick-add sheet lists subjects live from the model, so the new subject appears there without a callback.
            SubjectEditorView(subjectID: nil, timetableID: timetableID)
        } else {
            SubjectEditorView(subjectID: EditorSeedPicker.firstSubject(in: model)?.id)
        }
    }
}

/// `editor.day-change`: the context's date and lesson, else today with the first lesson.
private struct DayChangeEditorRoute: View {
    @Environment(\.editorContext) private var editorContext

    var body: some View {
        if case .dayChange(let date, let lessonID, let timetableID) = EditorLaunchTarget(editorContext) {
            DayChangeEditorView(date: date, lessonID: lessonID, timetableID: timetableID)
        } else {
            DayChangeEditorView()
        }
    }
}
