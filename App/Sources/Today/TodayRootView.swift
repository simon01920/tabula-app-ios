// PLACEHOLDER (Stage A) — stage B2 replaces this file with the real Today screen (Now & Next, countdown, tiles).
// Keep the type name `TodayRootView` and its no-argument init: the app shell (AppShell/AppRootView.swift) uses it.
// Until then it lists today's lessons with the foundation primitives (SubjectBadge, LessonStatusBadge,
// VisibleLessonFields, LessonAccessibilityLabel) so they can be checked on a device / in CI screenshots.
// APIs: NavigationStack, List, Section, LabeledContent-free rows (HStack/VStack), navigationTitle(_:),
//       ContentUnavailableView(label:description:actions:), accessibilityElement(children:), accessibilityLabel(_:).
import SwiftUI
import TimetableCore
import TimetableUI

struct TodayRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("shell.tab.today"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let timetable = model.activeTimetable, let resolver = model.resolver(for: timetable.id) {
            let day = resolver.resolution(for: model.today)
            if day.schedule.entries.isEmpty {
                ContentUnavailableView {
                    Label { Text("today.placeholder.empty.title") } icon: { Image(systemName: "sun.max") }
                } description: {
                    Text(model.formatter.date(model.today, style: .full))
                } actions: {
                    EmptyView()
                }
            } else {
                List {
                    Section {
                        ForEach(day.schedule.entries) { lesson in
                            PlaceholderLessonRow(lesson: lesson, visibility: timetable.fieldVisibility,
                                                 reasons: day.reasons(for: lesson.id))
                        }
                    } header: {
                        Text(model.formatter.date(model.today, style: .full))
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label { Text("today.placeholder.noTimetable.title") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
            } description: {
                EmptyView()
            } actions: {
                EmptyView()
            }
        }
    }
}

/// A plain lesson row built only from foundation primitives (B2 replaces it with real tiles).
private struct PlaceholderLessonRow: View {
    let lesson: ResolvedLesson
    let visibility: FieldVisibility
    let reasons: [ModificationReason]
    @Environment(AppModel.self) private var model

    var body: some View {
        let fields = VisibleLessonFields(lesson: lesson, visibility: visibility)
        HStack(alignment: .top, spacing: 12) {
            SubjectBadge(subject: lesson.subject, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: lesson.subject.name)
                    .font(.headline)
                    .strikethrough(lesson.status == .cancelled)
                Text(verbatim: model.formatter.timeRange(lesson.startTime, lesson.endTime))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Field rule: only visible, non-empty fields; no placeholders.
                ForEach(Array(fieldLines(fields).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).font(.footnote).foregroundStyle(.secondary)
                }
                if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                    LessonStatusBadge(badge)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(
            lesson: lesson, visibility: visibility, reasons: reasons, renderer: model.renderer)))
    }

    private func fieldLines(_ fields: VisibleLessonFields) -> [String] {
        let renderer = model.renderer
        var lines: [String] = []
        if let room = fields.room { lines.append(renderer.format(key: "a11y.lesson.room", arguments: [.text(room)])) }
        if let teacher = fields.teacher { lines.append(teacher) }
        if let building = fields.building { lines.append(building) }
        if let type = fields.lessonType {
            lines.append(VisibleLessonFields.nameKey(of: type).map(renderer.string(forKey:)) ?? type.rawValue)
        }
        if let notes = fields.notes { lines.append(notes) }
        if !fields.bringList.isEmpty {
            lines.append(renderer.format(key: "a11y.lesson.bring", arguments: [.text(model.formatter.list(fields.bringList))]))
        }
        return lines
    }
}
