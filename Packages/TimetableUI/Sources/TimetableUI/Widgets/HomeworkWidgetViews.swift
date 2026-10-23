// SwiftUI views of the Homework widget (Stage B1), compiled into BOTH the widget extension and the app's DEBUG
// `widgets.gallery-homework` route (see NowNextWidgetViews.swift for why they live in TimetableUI, the rendering-mode
// rules and the API list). They only lay out a `HomeworkDisplay` (HomeworkPresentation.swift, Linux-tested).
//
// Families: small = the count and the top task (one `widgetURL` set by the extension: `Link` is not used in the small
// family); medium (3) and large (9) = one `Link` per row to `tabula://open/task/<id>` (`ItemLinkURL`), so a tap opens
// that task. The overdue mark is an icon + the word ("2 days overdue" / "Overdue"), never colour alone.
//
// B3 final QA: with the 44 × 44 pt checkbox (`withCheckbox: true`) rows are 44 pt tall with no extra spacing and the
// medium / large families show 2 / 7 rows (`HomeworkDisplay.capacity(for:withCheckbox:)`).
// SEAM FOR THE CHECKBOX (Stage B3, App Intents): `leading` is placed before every medium / large row, outside the row's
// `Link`. Stage B3 passes `{ line in Button(intent: MarkDoneIntent(taskID: line.id)) { Image(systemName: "circle") } }`;
// without it (`init(display:family:)`) rows start with the subject badge and the whole row is the link. A `Button`
// cannot be nested in a `Link`, which is why the seam sits beside the link, not inside it. On builds without App Intent
// metadata (xtool, RISKS #19) the seam stays empty and the row's link is the fallback.
//
// APIs (Apple docs, checked 2026-10-16): Link(destination:label:) iOS 14 / watchOS 7; Label(_:systemImage:);
//   View.accessibilityElement(children:) / accessibilityLabel(_:) / accessibilityAddTraits(_:).
#if canImport(SwiftUI) && canImport(WidgetKit)
import SwiftUI
import TimetableCore
import WidgetKit

/// The Homework widget for one family.
public struct HomeworkWidgetView<Leading: View>: View {
    private let display: HomeworkDisplay
    private let family: WidgetFamilyKind
    private let leading: (HomeworkDisplay.TaskLine) -> Leading
    private let withCheckbox: Bool

    /// `leading` is the checkbox seam (see the file header); it is shown in the medium and large families only.
    /// `withCheckbox`: `leading` is the 44 pt Mark done checkbox (B3 final QA m3), so rows are 44 pt tall and fewer fit
    /// (`HomeworkDisplay.capacity(for:withCheckbox:)`).
    public init(display: HomeworkDisplay, family: WidgetFamilyKind, withCheckbox: Bool = false,
                @ViewBuilder leading: @escaping (HomeworkDisplay.TaskLine) -> Leading) {
        self.display = display
        self.family = family
        self.withCheckbox = withCheckbox
        self.leading = leading
    }

    public var body: some View {
        Group {
            switch family {
            case .systemMedium, .systemLarge, .systemExtraLarge:
                HomeworkListColumn(display: display, family: family, withCheckbox: withCheckbox, leading: leading)
            default:
                HomeworkSmallColumn(display: display)
            }
        }
        // The small family is one VoiceOver element; the lists keep one element per row (Links) plus the header.
        .modifier(HomeworkAccessibility(display: display, isList: isListFamily))
    }

    private var isListFamily: Bool {
        family == .systemMedium || family == .systemLarge || family == .systemExtraLarge
    }
}

extension HomeworkWidgetView where Leading == EmptyView {
    /// Without a checkbox: rows start with the subject badge.
    public init(display: HomeworkDisplay, family: WidgetFamilyKind) {
        self.init(display: display, family: family) { _ in EmptyView() }
    }
}

private struct HomeworkAccessibility: ViewModifier {
    let display: HomeworkDisplay
    let isList: Bool

    func body(content: Content) -> some View {
        if isList, case .tasks = display.kind {
            content   // header and rows carry their own labels
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: display.accessibilityLabel))
        }
    }
}

// MARK: - Pieces

/// The overdue / due text of a task: a warning icon + bold text when overdue, plain secondary text otherwise.
struct HomeworkDueText: View {
    let line: HomeworkDisplay.TaskLine

    var body: some View {
        if line.isOverdue {
            // Primary text (contrast) with a red icon; the word carries the meaning, the icon the shape.
            Label {
                Text(verbatim: line.dueText).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            .font(.caption2.weight(.bold))
            .lineLimit(1)
        } else {
            Text(verbatim: line.dueText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Subject badge, or a neutral mark for a task without a subject.
struct HomeworkMark: View {
    let subject: SubjectSummary?
    let size: CGFloat

    var body: some View {
        if let subject {
            WidgetSubjectMark(subject: subject, size: size)
        } else {
            Image(systemName: "checklist")
                .font(.system(size: size * 0.6, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// Title + due text (+ priority icon) of one task.
struct HomeworkRowContent: View {
    let line: HomeworkDisplay.TaskLine
    var showsMark = true

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if showsMark { HomeworkMark(subject: line.subject, size: 20) }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: line.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                HomeworkDueText(line: line)
            }
            Spacer(minLength: 2)
            if line.isHighPriority {
                Image(systemName: "exclamationmark.2")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Small

struct HomeworkSmallColumn: View {
    let display: HomeworkDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch display.kind {
            case .tasks:
                Label {
                    Text(verbatim: display.title)
                } icon: {
                    Image(systemName: "checklist")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .widgetAccentable()
                Text(verbatim: display.countText)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let top = display.lines.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: top.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        HomeworkDueText(line: top)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case let .allDone(title, detail):
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
            case let .unavailable(title, detail):
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(2)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium / large

struct HomeworkListColumn<Leading: View>: View {
    let display: HomeworkDisplay
    let family: WidgetFamilyKind
    var withCheckbox = false
    let leading: (HomeworkDisplay.TaskLine) -> Leading

    var body: some View {
        VStack(alignment: .leading, spacing: withCheckbox ? 0 : 5) {
            switch display.kind {
            case .tasks:
                let shown = display.visible(for: family, withCheckbox: withCheckbox)
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: display.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .widgetAccentable()
                    Spacer(minLength: 4)
                    Text(verbatim: display.countText)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: display.listHeaderLabel))
                ForEach(shown.lines) { line in
                    HStack(alignment: .center, spacing: 6) {
                        leading(line)
                        Link(destination: ItemLinkURL.url(for: line.link)) {
                            HomeworkRowContent(line: line)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: line.accessibilityLabel))
                        .accessibilityAddTraits(.isLink)
                    }
                }
                if shown.hidden > 0 {
                    Text(verbatim: display.moreText(shown.hidden))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            case let .allDone(title, detail):
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title).font(.headline).lineLimit(2)
                        Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            case let .unavailable(title, detail):
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.title)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title).font(.headline).lineLimit(2)
                        Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
