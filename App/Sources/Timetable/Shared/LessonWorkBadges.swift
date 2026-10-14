// Task / exam badges of a lesson occurrence (Phase 3 C1): "☑ 2 tasks" and "🎓 Exam" capsules on tiles, list rows, the
// Now & Next header and the lesson detail, and a compact icon + count line inside grid cells and week time blocks.
// Data: `LessonWorkIndex` (TimetableUI, Linux-tested) from the environment (`\.lessonWork`), built by the screens
// that show lessons (`LessonWorkSupport.index`). The badges are hidden from VoiceOver: the lesson's single
// accessibility sentence already ends with "2 open tasks, exam on this day" (`LessonAccessibilityLabel` badges).
// Never colour-only: an SF Symbol plus words (or a count) on a material capsule / in the tile's legible foreground.
// APIs: ViewThatFits(in:) (iOS 16), Label(title:icon:), Capsule().fill(.regularMaterial), labelStyle(.titleAndIcon),
//       accessibilityHidden(_:), minimumScaleFactor(_:).
import SwiftUI
import TimetableCore
import TimetableUI

/// Full badges: icon + words on material capsules; wraps to a column when the row does not fit (long languages,
/// accessibility text sizes).
struct LessonWorkBadgeRow: View {
    let badges: LessonBadges
    @Environment(AppModel.self) private var model

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 4) { chips }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var chips: some View {
        if let text = badges.tasksText(renderer: model.renderer) {
            chip(symbol: LessonBadges.taskSymbol, text: text)
        }
        if let text = badges.examText(renderer: model.renderer) {
            chip(symbol: LessonBadges.examSymbol, text: text)
        }
    }

    private func chip(symbol: String, text: String) -> some View {
        Label {
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(.regularMaterial))
        .foregroundStyle(Color.primary)
    }
}

/// Compact badges for grid cells and narrow time blocks: "☑2 🎓" in the tile's legible foreground colour.
struct CompactLessonWorkBadges: View {
    let badges: LessonBadges

    var body: some View {
        HStack(spacing: 3) {
            if badges.openTasks > 0 {
                HStack(spacing: 1) {
                    Image(systemName: LessonBadges.taskSymbol)
                    Text(verbatim: badges.openTasks.formatted())
                        .monospacedDigit()
                }
            }
            if badges.hasExam {
                Image(systemName: LessonBadges.examSymbol)
            }
        }
        .font(.caption2.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityHidden(true)
    }
}

/// Builds the `LessonWorkIndex` for the days a screen shows.
@MainActor
enum LessonWorkSupport {
    /// The index for every occurrence on `dates` in `resolver`'s timetable (whole days, as the matching rule needs).
    static func index(dates: [LocalDate], resolver: ScheduleResolver, database: TabulaDatabase?) -> LessonWorkIndex {
        guard let database, !(database.tasks.isEmpty && database.exams.isEmpty) else { return .empty }
        var seen = Set<LocalDate>()
        let lessons = dates.filter { seen.insert($0).inserted }.flatMap { resolver.day($0).entries }
        return LessonWorkIndex.make(lessons: lessons, tasks: database.tasks, exams: database.exams)
    }
}
