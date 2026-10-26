// Building blocks of the Exams tab (stage B2): the featured next-exam card with its escalating emphasis, the list row,
// the exam-period header and the shared helpers (urgency colour, mark done / not done).
//
// Rules: urgency is never colour-only (icon + "Today"/"Tomorrow"/"in 3 days" text); text always uses primary /
// secondary colours, subject colours appear only in `SubjectBadge` (which picks a legible foreground); absent fields
// produce no view (no placeholders); every row/card is one VoiceOver element with a one-sentence label.
// Logic: Packages/TimetableUI/Sources/TimetableUI/Exams (Linux-tested).
// APIs: Label(title:icon:), RoundedRectangle(cornerRadius:style:), strokeBorder(_:lineWidth:), ScaledMetric
//   (property wrapper), accessibilityElement(children:), accessibilityLabel(_:), accessibilityHidden(_:),
//   swipeActions(edge:allowsFullSwipe:content:), Text(verbatim:), Image(systemName:).
import SwiftUI
import TimetableCore
import TimetableUI

extension ExamUrgency {
    /// Emphasis colour of the card border / icon: neutral far away, red for today and tomorrow.
    var tint: Color {
        switch self {
        case .later, .past: return .secondary
        case .thisWeek: return .accentColor
        case .soon: return .orange
        case .tomorrow, .today: return .red
        }
    }
}

/// What the mark done / not done actions do.
@MainActor
enum ExamActions {
    static func markDone(_ id: Exam.ID, model: AppModel) {
        model.apply(.completeExam(id, at: model.now))
    }

    static func reopen(_ id: Exam.ID, model: AppModel) {
        guard var exam = model.database?.exams.first(where: { $0.id == id && !$0.isDeleted }) else { return }
        exam.completedAt = nil
        model.apply(.upsert(exam))
    }
}

/// The subject badge, or a neutral icon for an exam without a subject.
struct ExamBadge: View {
    let subject: SubjectSummary?
    var size: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    var body: some View {
        if let subject {
            SubjectBadge(subject: subject, size: size * scale)
        } else {
            Image(AppSymbol.exam)
                .font(.system(size: size * 0.5 * scale))
                .foregroundStyle(.secondary)
                .frame(width: size * scale, height: size * scale)
                .accessibilityHidden(true)
        }
    }
}

/// Date, time and place lines shared by the card and the row.
private struct ExamFactLines: View {
    let exam: Exam
    let facts: ExamFacts
    let texts: ExamTexts

    var body: some View {
        Label { Text(verbatim: texts.date(exam.date)) } icon: { Image(AppSymbol.date) }
        if let time = texts.time(exam) {
            Label { Text(verbatim: time) } icon: { Image(AppSymbol.time) }
        }
        if let location = facts.location {
            Label { Text(verbatim: location) } icon: { Image(AppSymbol.room) }
        }
        if let topics = texts.topicsPreview(facts.topics) {
            Label { Text(verbatim: topics) } icon: { Image(AppSymbol.topics) }
        }
    }
}

/// "Subject · Type" line.
private struct ExamSubtitle: View {
    let row: ExamRow
    let texts: ExamTexts

    var body: some View {
        let kind = texts.kind(row.exam.kind)
        if let subject = row.subject {
            Text(verbatim: texts.renderer.format(key: "exams.subtitle", arguments: [.text(subject.name), .text(kind)]))
        } else {
            Text(verbatim: kind)
        }
    }
}

/// The next exam: large countdown, subject, title, date / time / place and a topics preview. Emphasis escalates as the
/// exam nears (tinted fill and border from "this week" on); the countdown text and icon carry the meaning too.
struct ExamFeaturedCard: View {
    let row: ExamRow
    let facts: ExamFacts
    let texts: ExamTexts
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let tint = row.urgency.tint
        let emphasised = row.urgency == .today || row.urgency == .tomorrow || row.urgency == .soon
        VStack(alignment: .leading, spacing: 10) {
            Text("exams.next.title")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Label { Text(verbatim: texts.when(row.when)).font(.largeTitle.weight(.bold)) } icon: {
                Image(systemName: row.urgency.symbolName).foregroundStyle(tint)
            }
            // Accessibility sizes: the badge sits above the title so the title keeps the full width.
            let titleStack = VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.exam.title).font(.title3.weight(.semibold))
                ExamSubtitle(row: row, texts: texts).foregroundStyle(.secondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ExamBadge(subject: row.subject, size: 44)
                    titleStack
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ExamBadge(subject: row.subject, size: 44)
                    titleStack
                }
            }
            ExamFactLines(exam: row.exam, facts: facts, texts: texts)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let period = row.periodName {
                Text(verbatim: texts.renderer.format(key: "exams.period.in", arguments: [.text(period)]))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(emphasised ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(emphasised ? 1 : 0.35), lineWidth: emphasised ? 2.5 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.accessibilityLabel(row, facts: facts)))
    }
}

/// One exam in a list: when (icon + text), title, subject · type, date / time / place, topics.
struct ExamRowView: View {
    let row: ExamRow
    let facts: ExamFacts
    let texts: ExamTexts
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            ExamBadge(subject: row.subject, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Label { Text(verbatim: texts.when(row.when)).font(.subheadline.weight(.semibold)) } icon: {
                    Image(systemName: row.exam.isCompleted ? "checkmark.circle.fill" : row.urgency.symbolName)
                        .foregroundStyle(row.exam.isCompleted ? Color.green : row.urgency.tint)
                }
                Text(verbatim: row.exam.title).font(.headline)
                ExamSubtitle(row: row, texts: texts).font(.subheadline).foregroundStyle(.secondary)
                ExamFactLines(exam: row.exam, facts: facts, texts: texts)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.accessibilityLabel(row, facts: facts)))
    }
}

/// Header of an exam period: name, date range, count and an "In progress" badge while today lies inside it.
struct ExamPeriodHeader: View {
    let section: ExamPeriodSection
    let texts: ExamTexts

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(verbatim: texts.periodTitle(section)).font(.headline)
                if section.isCurrent {
                    Text("exams.period.current")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.thinMaterial))
                }
            }
            Text(verbatim: texts.periodRange(section.range))
            Text(verbatim: texts.periodCount(section))
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
