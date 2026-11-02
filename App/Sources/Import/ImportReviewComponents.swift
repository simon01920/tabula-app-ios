// Parts of the import review screen (ImportReviewScreen.swift): counts, questions, the grid, the per-day lists
// (accessibility text sizes), the "Needs checking" rows and the zoomable picture.
// Uncertain cells: an outline in `changed` (amber, a non-text indicator ≥ 3:1 on cards) PLUS the warning symbol and
// the reason in VoiceOver, so colour is never the only signal. User text (subjects, rooms, OCR text) is verbatim.
import SwiftUI
import TimetableCore
import TimetableUI

// MARK: - Counts

/// "32 lessons" · "12 subjects" · "3 need checking" (or "All checked"): one localized plural string each.
struct ImportCountsRow: View {
    let counts: ImportReviewCounts
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        chip(count("import.review.count.lessons", counts.lessons), symbol: "square.grid.3x3", tint: .secondary)
        chip(count("import.review.count.subjects", counts.subjects), symbol: "books.vertical", tint: .secondary)
        if counts.needsReview > 0 {
            chip(count("import.review.count.needsReview", counts.needsReview), symbol: AppSymbol.warning.rawValue,
                 tint: Color.changed)
        } else {
            chip(model.renderer.string(forKey: "import.review.count.allChecked"), symbol: "checkmark.circle", tint: Color.ink)
        }
    }

    private func chip(_ text: String, symbol: String, tint: some ShapeStyle) -> some View {
        Label { Text(verbatim: text).foregroundStyle(.primary) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.fill.tertiary, in: Capsule())
            .fixedSize()
    }

    private func count(_ key: String, _ value: Int) -> String {
        model.renderer.format(key: key, arguments: [.integer(Int64(value))])
    }
}

// MARK: - Questions

/// "Is “Bio” Biology?" with one button per answer; the first answer is the value now in use.
struct ImportQuestionRow: View {
    let question: ImportQuestion
    let answer: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: model.renderer.string(question.prompt))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if question.lessonIDs.count > 1 {
                Text(verbatim: model.renderer.format(key: "import.question.appliesTo",
                                                     arguments: [.integer(Int64(question.lessonIDs.count))]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var buttons: some View {
        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
            Button { answer(option) } label: {
                Text(verbatim: option.isEmpty ? model.renderer.string(forKey: "import.question.none") : option)
                    .lineLimit(2)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .tint(index == 0 ? .secondary : Color.ink)
            .accessibilityHint(Text(index == 0 ? "import.question.keep.hint" : "import.question.use.hint"))
        }
    }
}

// MARK: - Grid

/// Days as rows, periods across (the aSc layout); a lesson spanning periods spans columns. Cycle-week lessons in one
/// slot stack. Each filled cell is a button that opens the editor; empty slots are quiet and hidden from VoiceOver.
struct ImportReviewGrid: View {
    let review: ImportReview
    let edit: (Int) -> Void
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .footnote) private var columnWidth: CGFloat = 78
    @ScaledMetric(relativeTo: .footnote) private var rowHeight: CGFloat = 58

    private var days: [Weekday] {
        let found = review.candidate.days
        return found.isEmpty ? Array(Set(review.lessons.map(\.day))).sorted() : found
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Color.clear.frame(width: 36, height: 1).gridCellUnsizedAxes(.vertical)
                    ForEach(review.periods) { period in
                        VStack(spacing: 0) {
                            Text(verbatim: period.number.formatted(.number.locale(model.formatter.locale)))
                                .font(.footnote.weight(.semibold))
                            Text(verbatim: model.formatter.time(period.start))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: columnWidth)
                        .accessibilityHidden(true)
                    }
                }
                ForEach(days, id: \.self) { day in
                    GridRow {
                        Text(verbatim: model.formatter.weekdayName(day, width: .abbreviated))
                            .font(.footnote.weight(.semibold))
                            .frame(width: 36, alignment: .leading)
                            .accessibilityHidden(true)
                        ForEach(slots(for: day), id: \.period) { slot in
                            cell(slot, day: day)
                                .gridCellColumns(slot.span)
                        }
                    }
                }
            }
            .padding(12)
        }
        .scrollIndicators(.visible)
    }

    private struct Slot { let period: Int; let span: Int; let lessons: [ImportLesson] }

    /// The day's slots in period order: one per lesson start (with its span) and one per free period.
    private func slots(for day: Weekday) -> [Slot] {
        let lessons = review.lessons.filter { $0.day == day }
        var result: [Slot] = []
        var index = 0
        let numbers = review.periods.map(\.number)
        while index < numbers.count {
            let number = numbers[index]
            let starting = lessons.filter { $0.period == number }
            if starting.isEmpty {
                result.append(Slot(period: number, span: 1, lessons: []))
                index += 1
            } else {
                let span = max(1, min(starting.map(\.span).max() ?? 1, numbers.count - index))
                result.append(Slot(period: number, span: span, lessons: starting))
                index += span
            }
        }
        return result
    }

    @ViewBuilder private func cell(_ slot: Slot, day: Weekday) -> some View {
        let width = columnWidth * CGFloat(slot.span) + 4 * CGFloat(slot.span - 1)
        if slot.lessons.isEmpty {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.fill.quaternary)
                .frame(width: width, height: rowHeight)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 2) {
                ForEach(slot.lessons) { lesson in
                    Button { edit(lesson.id) } label: { ImportCellLabel(lesson: lesson) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: ImportA11y.label(lesson, renderer: model.renderer,
                                                                             formatter: model.formatter)))
                        .accessibilityHint(Text(verbatim: ImportA11y.reasons(lesson, renderer: model.renderer)))
                        .accessibilityAddTraits(.isButton)
                }
            }
            .frame(width: width, height: rowHeight)
        }
    }
}

/// One lesson inside a grid cell: subject (two lines at most), room at bottom-trailing.
private struct ImportCellLabel: View {
    let lesson: ImportLesson

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 2) {
                Text(verbatim: lesson.subject)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if lesson.needsReview {
                    Image(AppSymbol.warning).font(.caption2.weight(.bold)).foregroundStyle(Color.changed)
                }
            }
            Spacer(minLength: 0)
            if let room = lesson.room {
                Text(verbatim: room)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(lesson.needsReview ? AnyShapeStyle(Color.changed) : AnyShapeStyle(.separator),
                              lineWidth: lesson.needsReview ? 2 : 1)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Accessibility text sizes: a list per day

struct ImportDayLists: View {
    let review: ImportReview
    let edit: (Int) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let days = review.candidate.days.isEmpty ? Array(Set(review.lessons.map(\.day))).sorted() : review.candidate.days
        ForEach(days, id: \.self) { day in
            let lessons = review.lessons.filter { $0.day == day }.sorted { $0.period < $1.period }
            if !lessons.isEmpty {
                Section {
                    ForEach(lessons) { lesson in
                        Button { edit(lesson.id) } label: { ImportFlaggedRow(lesson: lesson) }
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text(verbatim: model.formatter.weekdayName(day))
                }
            }
        }
    }
}

// MARK: - A lesson as a row (Needs checking, per-day lists)

struct ImportFlaggedRow: View {
    let lesson: ImportLesson
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: ImportA11y.position(lesson, renderer: model.renderer, formatter: model.formatter))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: lesson.subject).font(.body.weight(.semibold))
            ForEach([lesson.room, lesson.teacher].compactMap { $0 }, id: \.self) { value in
                Text(verbatim: value).font(.subheadline).foregroundStyle(.secondary)
            }
            if lesson.needsReview {
                ForEach(lesson.reasons.sorted(), id: \.self) { reason in
                    Label { Text(LocalizedStringKey(reason.l10nKey)) } icon: {
                        Image(AppSymbol.warning).foregroundStyle(Color.changed)
                    }
                    .font(.footnote)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// VoiceOver text of an imported lesson.
enum ImportA11y {
    /// "Monday, period 3" (or "Monday, periods 3–4").
    static func position(_ lesson: ImportLesson, renderer: LocalizedTextRenderer, formatter: TimetableFormatter) -> String {
        let day = formatter.weekdayName(lesson.day)
        if lesson.span > 1 {
            return renderer.format(key: "import.cell.positionSpan", arguments: [
                .text(day), .integer(Int64(lesson.period)), .integer(Int64(lesson.period + lesson.span - 1)),
            ])
        }
        return renderer.format(key: "import.cell.position", arguments: [.text(day), .integer(Int64(lesson.period))])
    }

    /// "Monday, period 3. Mathematics. 204. Needs checking."
    static func label(_ lesson: ImportLesson, renderer: LocalizedTextRenderer, formatter: TimetableFormatter) -> String {
        var parts = [position(lesson, renderer: renderer, formatter: formatter), lesson.subject]
        parts += [lesson.room, lesson.teacher].compactMap { $0 }
        if lesson.needsReview { parts.append(renderer.string(forKey: "import.cell.needsChecking")) }
        return parts.joined(separator: ". ")
    }

    /// The reasons, one sentence each (empty when nothing needs checking).
    static func reasons(_ lesson: ImportLesson, renderer: LocalizedTextRenderer) -> String {
        guard lesson.needsReview else { return "" }
        return lesson.reasons.sorted().map { renderer.string(forKey: $0.l10nKey) }.joined(separator: " ")
    }
}

// MARK: - Zoomable picture

/// The picture, fitted, with pinch / double-tap / VoiceOver zoom (1×–5×) and the uncertain cells outlined.
struct ZoomableImportImage: View {
    let image: UIImage
    let highlights: [TimetableCore.NormalizedRect]
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(in: proxy.size)
            let scale = min(5, max(1, zoom * pinch))
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width * scale, height: fitted.height * scale)
                    .overlay(alignment: .topLeading) {
                        ForEach(Array(highlights.enumerated()), id: \.offset) { _, box in
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.changed, lineWidth: 2)
                                .background(Color.changed.opacity(0.12))
                                .frame(width: box.width * fitted.width * scale, height: box.height * fitted.height * scale)
                                .offset(x: box.x * fitted.width * scale, y: box.y * fitted.height * scale)
                        }
                    }
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollIndicators(scale > 1 ? .visible : .hidden)
            .gesture(MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(5, max(1, zoom * value.magnification)) })
            .onTapGesture(count: 2) { setZoom(zoom > 1 ? 1 : 2.5) }
        }
        .background(Color(.secondarySystemBackground))
        .accessibilityElement()
        .accessibilityLabel(Text("import.image.a11y"))
        .accessibilityValue(Text(Double(zoom), format: .percent.precision(.fractionLength(0))))
        .accessibilityZoomAction { action in
            setZoom(action.direction == .zoomIn ? zoom * 1.5 : zoom / 1.5)
        }
    }

    private func setZoom(_ value: CGFloat) {
        let clamped = min(5, max(1, value))
        if reduceMotion { zoom = clamped } else { withAnimation(.smooth) { zoom = clamped } }
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let factor = min(container.width / size.width, container.height / size.height)
        return CGSize(width: size.width * factor, height: size.height * factor)
    }
}
