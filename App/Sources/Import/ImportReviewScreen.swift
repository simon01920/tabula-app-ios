// The review screen of the photo import (Phase 9 I2, PHASE9_PLAN decision 5). State: TimetableUI `ImportReview`
// (pure, Linux-tested); this file only renders it and forwards taps.
//   iPhone        segmented Image / Timetable switch; iPad and wide windows: both side by side.
//   Image         the picture, zoomable (pinch, double tap, VoiceOver zoom), uncertain cells outlined.
//   Timetable     name · counts ("32 lessons", "12 subjects", "3 need checking") · notices · Questions (one-tap
//                 answers) · the grid (days as rows, periods across, spans; uncertain cells outlined with a symbol) ·
//                 "Needs checking" with the reason per lesson · the bell schedule. At accessibility text sizes the grid
//                 becomes a list per day.
//   Edit          tap a cell → ImportLessonEditor (fields, "Apply to all identical cells", Looks Right, Remove).
//   Approve       builds the payload (`ImportReview.approve`) and pushes the share import preview: Add as New Timetable
//                 (default) or Replace with confirmation and an automatic backup (ShareImportPreview). Nothing is
//                 saved before that tap.
// Field rule: a lesson field without a value is absent (no placeholders or dashes).
// HIG: segmented-controls.md, lists-and-tables.md, generative-ai.md (show uncertainty, let people correct),
//      accessibility.md, writing.md.
import SwiftUI
import TimetableCore
import TimetableUI

struct ImportReviewScreen: View {
    @Bindable var flow: PhotoImportModel
    let profile: UserProfile?
    /// Called after the import was saved (`true`).
    let onFinish: (Bool) -> Void

    enum Pane: Hashable { case image, timetable }

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var pane: Pane = .timetable
    @State private var editing: EditTarget?
    @State private var resolved: ResolvedShare?
    @State private var showsPreview = false
    @State private var problem: String?

    struct EditTarget: Identifiable, Hashable { let id: Int }

    var body: some View {
        Group {
            if let review = flow.review {
                layout(review)
                    .safeAreaInset(edge: .bottom) { approveBar(review) }
            }
        }
        .sheet(item: $editing) { target in
            if let review = flow.review, let lesson = review.lesson(target.id) {
                ImportLessonEditor(lesson: lesson, identicalCount: review.identicalLessonIDs(to: target.id).count) { change in
                    apply(change, to: target.id)
                }
            }
        }
        .navigationDestination(isPresented: $showsPreview) {
            if let resolved {
                ShareImportPreview(resolved: resolved, profile: profile, onFinish: onFinish)
                    .navigationTitle(Text("import.approve.title"))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert(Text("import.error.title"), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button { } label: { Text("editor.warnings.ok") }
        } message: {
            if let problem { Text(verbatim: problem) }
        }
    }

    @ViewBuilder private func layout(_ review: ImportReview) -> some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                imagePane(review)
                Divider()
                ImportReviewList(review: review, flow: flow, edit: edit)
            }
        } else {
            VStack(spacing: 0) {
                Picker(selection: $pane) {
                    Text("import.review.pane.image").tag(Pane.image)
                    Text("import.review.pane.timetable").tag(Pane.timetable)
                } label: {
                    Text("import.review.pane")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                switch pane {
                case .image: imagePane(review)
                case .timetable: ImportReviewList(review: review, flow: flow, edit: edit)
                }
            }
        }
    }

    @ViewBuilder private func imagePane(_ review: ImportReview) -> some View {
        if let image = flow.image {
            ZoomableImportImage(image: image, highlights: highlights(review))
        } else {
            ContentUnavailableView { Label { Text("import.review.noImage") } icon: { Image(systemName: "photo") } }
        }
    }

    /// Boxes of the cells that still need checking (top-left normalised).
    private func highlights(_ review: ImportReview) -> [TimetableCore.NormalizedRect] {
        guard let cells = flow.table?.gridCells else { return [] }
        return review.lessons.filter(\.needsReview).compactMap { lesson in
            cells.first { $0.row == lesson.source.row && $0.column == lesson.source.column }?.box
        }
    }

    private func approveBar(_ review: ImportReview) -> some View {
        Button(action: approve) {
            Text("import.review.approve")
                .frame(maxWidth: .infinity, minHeight: 44)
                .onInkLabel()
        }
        .buttonStyle(.borderedProminent)
        .disabled(review.lessons.isEmpty || review.timetableName.trimmingCharacters(in: .whitespaces).isEmpty
                  || (review.candidate.weekCycleLength != nil && flow.weekAIsThisWeek == nil) || model.isReadOnly)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Actions

    private func edit(_ id: Int) { editing = EditTarget(id: id) }

    private func apply(_ change: ImportLessonEditor.Change, to id: Int) {
        switch change {
        case .values(let values, let applyToIdentical):
            for (field, value) in values {
                flow.review?.setValue(value, field: field, lesson: id, applyToIdentical: applyToIdentical)
            }
        case .confirm(let applyToIdentical):
            flow.review?.confirm(lesson: id, applyToIdentical: applyToIdentical)
        case .remove(let applyToIdentical):
            flow.review?.removeLesson(id, applyToIdentical: applyToIdentical)
        }
    }

    private func approve() {
        guard let review = flow.review else { return }
        do throws(ShareError) {
            var payload = try review.approve(bellScheduleName: model.renderer.string(forKey: "import.review.bellScheduleName"))
            // A/B weeks: the core anchors them on ISO-week parity; the user's answer pins week A to a real week.
            if let length = review.candidate.weekCycleLength, let thisWeek = flow.weekAIsThisWeek {
                payload.timetable.rotation = .weekCycle(WeekCycle(length: length, anchor: .referenceWeek(
                    date: model.today.adding(days: thisWeek ? 0 : 7), cycleWeek: 1)))
            }
            resolved = ResolvedShare(payload: payload,
                                     summary: try ShareImportSummary(payload: payload, context: model.calendarContext))
            showsPreview = true
        } catch {
            problem = model.renderer.string(error.message)
        }
    }
}

// MARK: - The timetable pane

private struct ImportReviewList: View {
    let review: ImportReview
    @Bindable var flow: PhotoImportModel
    let edit: (Int) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            list.onAppear {
                guard let anchor = flow.initialAnchor else { return }
                flow.initialAnchor = nil
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                TextField(text: Binding(get: { flow.review?.timetableName ?? "" },
                                        set: { flow.review?.timetableName = $0 })) {
                    Text("import.review.name")
                }
                .font(.title3.weight(.semibold))
                .submitLabel(.done)
                ImportCountsRow(counts: review.counts)
            } footer: {
                if flow.usedAppleIntelligence {
                    Label { Text("import.capture.ai") } icon: { Image(systemName: "sparkles") }
                }
            }

            if !review.notices.isEmpty {
                Section {
                    ForEach(review.notices, id: \.self) { notice in
                        Label { Text(LocalizedStringKey(notice.l10nKey)) } icon: { Image(AppSymbol.info) }
                    }
                }
            }

            let questions = review.questions
            if !questions.isEmpty || review.candidate.weekCycleLength != nil {
                Section {
                    if review.candidate.weekCycleLength != nil { ImportWeekAQuestion(answer: $flow.weekAIsThisWeek) }
                    ForEach(questions) { question in
                        ImportQuestionRow(question: question) { option in
                            withAnimation(reduceMotion ? nil : .default) { flow.review?.answer(question.id, with: option) }
                        }
                    }
                } header: {
                    Text("import.review.questions")
                }
            }

            if typeSize.isAccessibilitySize {
                ImportDayLists(review: review, edit: edit)
            } else {
                Section {
                    ImportReviewGrid(review: review, edit: edit)
                        .listRowInsets(EdgeInsets())
                        .id("grid")
                } header: {
                    Text("import.review.grid")
                } footer: {
                    Text("import.review.grid.footer")
                }
            }

            let flagged = review.lessons.filter(\.needsReview)
            if !flagged.isEmpty {
                Section {
                    ForEach(flagged) { lesson in
                        Button { edit(lesson.id) } label: { ImportFlaggedRow(lesson: lesson) }
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("import.review.needsChecking")
                }
            }

            if !review.periods.isEmpty {
                Section {
                    ForEach(review.periods) { period in
                        LabeledContent {
                            Text(verbatim: model.formatter.timeRange(period.start, period.end)).monospacedDigit()
                        } label: {
                            Text(verbatim: period.number.formatted(.number.locale(model.formatter.locale)))
                        }
                    }
                } header: {
                    Text("import.review.bellSchedule")
                } footer: {
                    Text("import.review.bellSchedule.footer")
                }
            }
        }
    }
}
