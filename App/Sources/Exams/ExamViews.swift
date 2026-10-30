// Building blocks of the Exams tab (stage B2, reworked in Phase 4U U2): the featured next-exam card, the list row,
// the exam-period banner and the shared helpers (urgency colour, complete / reopen).
//
// U2 rules (Opus M24 / H13, Astra F16, D6): the title comes first, then the date, then the relative time; beyond 14 days
// only the date shows (`ExamRow.showsRelativeTime`); only the date line carries a calendar icon (the relative line has a
// symbol only when the exam is imminent); the countdown is never larger than the title; the whole card is one control
// with the chevron inside (the Exams tab pushes the detail from it); at accessibility sizes the badge stacks above the
// text (`AdaptiveStack`) and is capped (`scaledIconFrame`). Urgency is never colour-only (icon + "Today"/"Tomorrow"/
// "in 3 days" text); emphasis uses ink, because red is reserved for overdue, cancelled and destructive (D1); text uses
// primary / secondary colours, subject colours appear only in `SubjectBadge`; absent fields produce no view; every
// row/card is one VoiceOver element with a one-sentence label.
// HIG (apple-design references): lists-and-tables.md (rows lead with the title, secondary text is subordinate),
// typography.md "Consider adjusting your layout at large font sizes".
// Logic: Packages/TimetableUI/Sources/TimetableUI/Exams (Linux-tested).
// APIs: Label(title:icon:), RoundedRectangle(cornerRadius:style:), strokeBorder(_:lineWidth:), ScaledMetric
//   (property wrapper), accessibilityElement(children:), accessibilityLabel(_:), accessibilityHidden(_:),
//   Text(verbatim:), Image(systemName:).
import SwiftUI
import TimetableCore
import TimetableUI

extension ExamUrgency {
    /// Emphasis colour of the card border / icon: neutral far away, ink from "this week" on.
    var tint: Color {
        switch self {
        case .later, .past: return .secondary
        case .thisWeek, .soon, .tomorrow, .today: return Color.ink
        }
    }
}

/// What the done / not done actions do.
@MainActor
enum ExamActions {
    /// "I've Taken This Exam" and "Move to History" both complete the exam (D6: same semantics, two names by date).
    static func markDone(_ id: Exam.ID, model: AppModel) {
        model.apply(.completeExam(id, at: model.now))
    }

    static func reopen(_ id: Exam.ID, model: AppModel) {
        guard var exam = model.database?.exams.first(where: { $0.id == id && !$0.isDeleted }) else { return }
        exam.completedAt = nil
        model.apply(.upsert(exam))
    }

    /// The action an uncompleted exam offers today (name and place depend on the exam date).
    static func completion(of exam: Exam, model: AppModel) -> ExamCompletionAction {
        ExamCompletionAction(examDate: exam.date, today: model.today)
    }
}

/// The subject badge, or a neutral icon for an exam without a subject. Scales with text up to a cap (H13).
struct ExamBadge: View {
    let subject: SubjectSummary?
    var size: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    var body: some View {
        let side = min(size * scale, size * 1.6)
        if let subject {
            SubjectBadge(subject: subject, size: side)
        } else {
            Image(AppSymbol.exam)
                .font(.system(size: side * 0.5))
                .foregroundStyle(.secondary)
                .frame(width: side, height: side)
                .accessibilityHidden(true)
        }
    }
}

/// Date, relative time, time and place lines shared by the card and the row (date first, then the relative time).
private struct ExamFactLines: View {
    let row: ExamRow
    let facts: ExamFacts
    let texts: ExamTexts

    var body: some View {
        Label { Text(verbatim: texts.date(row.exam.date)) } icon: { Image(AppSymbol.date) }
        relative
        if let time = texts.time(row.exam) {
            Label { Text(verbatim: time) } icon: { Image(AppSymbol.time) }
        }
        if let location = facts.location {
            Label { Text(verbatim: location) } icon: { Image(AppSymbol.room) }
        }
        if let topics = texts.topicsPreview(facts.topics) {
            Label { Text(verbatim: topics) } icon: { Image(AppSymbol.topics) }
        }
    }

    /// "Completed", or the relative time within two weeks (a symbol only for imminent exams: one calendar icon per card).
    @ViewBuilder
    private var relative: some View {
        if row.exam.isCompleted {
            Label { Text("exams.status.done") } icon: { Image(AppSymbol.completed) }
        } else if row.showsRelativeTime {
            if let symbol = row.urgency.emphasisSymbolName {
                Label { Text(verbatim: texts.when(row.when)).fontWeight(.semibold) } icon: {
                    Image(systemName: symbol).foregroundStyle(row.urgency.tint)
                }
            } else {
                Text(verbatim: texts.when(row.when))
            }
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

/// The next exam: title and subject first, then date, relative time, time and place, and a topics preview. Emphasis
/// escalates as the exam nears (ink fill and border from "this week" on). The card is one control: the Exams tab wraps it
/// in a button and the chevron sits inside it.
struct ExamFeaturedCard: View {
    let row: ExamRow
    let facts: ExamFacts
    let texts: ExamTexts

    var body: some View {
        let tint = row.urgency.tint
        let emphasised = row.urgency == .today || row.urgency == .tomorrow || row.urgency == .soon
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                AdaptiveStack(horizontalAlignment: .top, spacing: 12) {
                    ExamBadge(subject: row.subject, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.exam.title).font(.title3.weight(.semibold))
                        ExamSubtitle(row: row, texts: texts).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ExamFactLines(row: row, facts: facts, texts: texts)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let period = row.periodName {
                    Text(verbatim: texts.renderer.format(key: "exams.period.in", arguments: [.text(period)]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(emphasised ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(emphasised ? 1 : 0.35), lineWidth: emphasised ? 2.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.accessibilityLabel(row, facts: facts)))
    }
}

/// One exam in a list: badge, title, subject · type, then date, relative time, time and place, topics.
struct ExamRowView: View {
    let row: ExamRow
    let facts: ExamFacts
    let texts: ExamTexts

    var body: some View {
        AdaptiveStack(horizontalAlignment: .top, spacing: 12) {
            ExamBadge(subject: row.subject, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.exam.title).font(.headline)
                ExamSubtitle(row: row, texts: texts).font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    ExamFactLines(row: row, facts: facts, texts: texts)
                }
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

/// Header of an exam period as a banner: name, "In progress" while today lies inside it, date range and count.
struct ExamPeriodHeader: View {
    let section: ExamPeriodSection
    let texts: ExamTexts

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AdaptiveStack(horizontalAlignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: texts.periodTitle(section)).font(.headline)
                if section.isCurrent {
                    Text("exams.period.current")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 1))
                }
            }
            AdaptiveStack(horizontalAlignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: texts.periodRange(section.range))
                Text(verbatim: texts.periodCount(section))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.primary)
        .textCase(nil)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
