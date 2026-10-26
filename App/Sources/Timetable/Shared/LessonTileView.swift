// Subject-coloured lesson tile shared by Today and the big-tiles view, plus the compact list row used by the grid's
// list fallback. Every optional field goes through `LessonFieldLines` (field rule), text on the subject colour uses
// `LessonTileStyle.foreground` (WCAG black/white), the status is an icon + text badge, and VoiceOver reads the single
// `LessonAccessibilityLabel` sentence (which ends with the task / exam badges of `\.lessonWork`, Phase 3 C1).
// APIs: RoundedRectangle(cornerRadius:style:), strokeBorder(_:lineWidth:), Label(title:icon:), Text(verbatim:),
//       strikethrough(_:pattern:color:), monospacedDigit(), accessibilityElement(children:), accessibilityLabel(_:),
//       accessibilityValue(_:), accessibilityHint(_:), accessibilityAddTraits(_:), @ScaledMetric,
//       Environment(\.colorScheme), Environment(\.colorSchemeContrast) — availability checked in Apple's docs.
import SwiftUI
import TimetableCore
import TimetableUI

/// Size variants of a lesson tile.
enum LessonTileSize {
    /// Today list.
    case regular
    /// Big vertical tiles view (elementary default): larger type and padding.
    case large
}

/// A subject-coloured lesson card.
struct LessonTileView: View {
    let lesson: ResolvedLesson
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    var timing: TodayItem.Timing = .upcoming
    var size: LessonTileSize = .regular
    var density: Density = .comfortable

    @Environment(AppModel.self) private var model
    @Environment(\.lessonWork) private var work
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 14

    var body: some View {
        let style = LessonTileStyle(color: lesson.subject.color)
        let badges = work.badges(for: lesson.id)
        let foreground = Color(style.foreground)
        let isCancelled = lesson.status == .cancelled
        let compact = density.effective == .compact
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SubjectSymbolText(subject: lesson.subject, font: size == .large ? .title2 : .title3)
                Text(verbatim: lesson.subject.name)
                    .font(size == .large ? .title2.weight(.semibold) : .headline)
                    .strikethrough(isCancelled, pattern: .solid, color: foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if timing == .past {
                    // Inline (not an overlay) so it never collides with the period number.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .accessibilityHidden(true)
                }
                if let number = lesson.periodNumber {
                    PeriodNumberBadge(number: number, foreground: foreground)
                }
            }
            HStack(spacing: 6) {
                Image(AppSymbol.time).imageScale(.small)
                Text(verbatim: model.formatter.timeRange(lesson.startTime, lesson.endTime))
                    .strikethrough(isCancelled, pattern: .solid, color: foreground)
            }
            .font(size == .large ? .body : .subheadline)
            .timeStyle()
            LessonFieldLinesView(lines: compact ? LessonFieldLines.make(lesson: lesson, visibility: visibility,
                                                                       only: [.room, .building, .teacher])
                                                : LessonFieldLines.make(lesson: lesson, visibility: visibility),
                                 font: size == .large ? .body : .subheadline)
            if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                // The badge draws its own material background; give it the label colour, not the tile's.
                LessonStatusBadge(badge)
                    .foregroundStyle(Color.primary)
                    .padding(.top, 2)
            }
            if let badges {
                LessonWorkBadgeRow(badges: badges)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(foreground)
        .padding(padding * (size == .large ? 1.25 : 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(style.background)))
        .overlay {
            if timing == .current {
                // The current lesson: a ring in the label colour (shape, not colour alone; VoiceOver says "in progress").
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary, lineWidth: 3)
            } else if style.needsOutline(isDark: colorScheme == .dark) || contrast == .increased {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(lesson: lesson, visibility: visibility,
                                                                         reasons: reasons, badges: badges,
                                                                         renderer: model.renderer)))
        .accessibilityValue(ifPresent: timingValue)
    }

    private var timingValue: LocalizedStringKey? {
        switch timing {
        case .current: return "today.a11y.inProgress"
        case .past: return "today.a11y.finished"
        case .upcoming: return nil
        }
    }
}

extension View {
    /// `accessibilityValue` only when there is one (no empty value is announced).
    @ViewBuilder
    func accessibilityValue(ifPresent key: LocalizedStringKey?) -> some View {
        if let key {
            accessibilityValue(Text(key))
        } else {
            self
        }
    }
}

/// The subject's emoji or SF Symbol, if it has one (nothing otherwise: the name is next to it).
struct SubjectSymbolText: View {
    let subject: SubjectSummary
    var font: Font = .title3

    var body: some View {
        switch subject.symbol {
        case .emoji(let emoji)?:
            Text(verbatim: emoji).font(font).accessibilityHidden(true)
        case .systemImage(let name)?:
            Image(systemName: name).font(font).accessibilityHidden(true)
        case nil:
            EmptyView()
        }
    }
}

/// The lesson number in a small capsule on a tile.
struct PeriodNumberBadge: View {
    let number: Int
    let foreground: Color

    var body: some View {
        Text(verbatim: number.formatted())
            .font(.subheadline.weight(.bold))
            .timeStyle()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(foreground, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// Icon + value lines of the visible, non-empty optional fields (nothing at all when there are none).
/// Values use the inherited foreground (primary on cards, the WCAG text colour on subject tiles: M9); `quietIcons`
/// draws only the icons in `.secondary` (cards, never on subject colours).
struct LessonFieldLinesView: View {
    let lines: [LessonFieldLine]
    var font: Font = .subheadline
    var quietIcons = false
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(lines) { line in
            Label {
                Text(verbatim: line.text(renderer: model.renderer))
                    .lineLimit(line.field == .notes ? 3 : 2)
            } icon: {
                if quietIcons {
                    Image(line.symbol).foregroundStyle(.secondary)
                } else {
                    Image(line.symbol)
                }
            }
            .font(font)
            .labelStyle(.titleAndIcon)
        }
    }
}

/// A compact lesson row for lists (grid list fallback, quick views): badge, name, time, fields, status.
struct LessonRowView: View {
    let lesson: ResolvedLesson
    let reasons: [ModificationReason]
    let visibility: FieldVisibility
    var isInConflict = false
    @Environment(AppModel.self) private var model
    @Environment(\.lessonWork) private var work

    var body: some View {
        let badges = work.badges(for: lesson.id)
        // H13 / F01: the subject badge stacks above the text at accessibility sizes (AdaptiveStack). M9: time and
        // room are primary data, so they use the primary colour; only the field icons are secondary.
        AdaptiveStack(horizontalAlignment: .top, spacing: 12) {
            SubjectBadge(subject: lesson.subject, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: lesson.subject.name)
                    .font(TypeScale.rowTitle)
                    .strikethrough(lesson.status == .cancelled)
                Text(verbatim: model.formatter.timeRange(lesson.startTime, lesson.endTime))
                    .font(.subheadline)
                    .timeStyle()
                LessonFieldLinesView(lines: LessonFieldLines.make(lesson: lesson, visibility: visibility),
                                     font: .subheadline, quietIcons: true)
                if let badge = LessonStatusBadgeModel.make(status: lesson.status, reasons: reasons) {
                    LessonStatusBadge(badge)
                }
                if let badges {
                    LessonWorkBadgeRow(badges: badges)
                }
                if isInConflict {
                    Label { Text("timetable.conflict.badge") } icon: { Image(AppSymbol.warning) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: LessonAccessibilityLabel.make(lesson: lesson, visibility: visibility,
                                                                         reasons: reasons, badges: badges,
                                                                         renderer: model.renderer)))
    }
}
