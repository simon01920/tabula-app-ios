// Subject-coloured primitives shared by the app, widgets and the watch (iOS + watchOS; no iOS-only modifiers).
// Text on a subject colour always uses `LessonTileStyle.foreground` (WCAG black/white), never the subject colour.
// APIs: RoundedRectangle, Capsule, Label(_:systemImage:), Image(systemName:), Text(verbatim:),
//   Text(LocalizedStringKey), accessibilityHidden(_:), accessibilityElement(children:), strokeBorder,
//   @Environment(\.colorScheme) (property wrapper, not a macro).
#if canImport(SwiftUI)
import SwiftUI
import TimetableCore

/// A small rounded square in the subject colour with its emoji / SF Symbol, else its short name, else its initial.
/// Decorative: hidden from VoiceOver (the subject name next to it is read instead).
public struct SubjectBadge: View {
    private let subject: SubjectSummary
    private let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    /// Creates a badge of `size` points (scaled with Dynamic Type by the caller if needed).
    public init(subject: SubjectSummary, size: CGFloat = 32) {
        self.subject = subject
        self.size = size
    }

    public var body: some View {
        let style = LessonTileStyle(color: subject.color)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(style.background))
            if style.needsOutline(isDark: colorScheme == .dark) {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
            }
            content(foreground: Color(style.foreground))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(foreground: Color) -> some View {
        switch subject.symbol {
        case .emoji(let emoji)?:
            Text(verbatim: emoji).font(.system(size: size * 0.55))
        case .systemImage(let name)?:
            Image(systemName: name).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(foreground)
        case nil:
            Text(verbatim: Self.fallbackLabel(for: subject))
                .font(.system(size: size * 0.38, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(2)
        }
    }

    /// Short name, else the first character of the name (user data, not localised).
    static func fallbackLabel(for subject: SubjectSummary) -> String {
        if let short = subject.shortName?.trimmingCharacters(in: .whitespacesAndNewlines), !short.isEmpty { return short }
        return subject.name.first.map { String($0) } ?? ""
    }
}

/// The status badge of a changed lesson: icon + short text in a capsule (meaning never carried by colour alone).
public struct LessonStatusBadge: View {
    private let model: LessonStatusBadgeModel

    /// Creates the badge; build the model with `LessonStatusBadgeModel.make(status:reasons:)`.
    public init(_ model: LessonStatusBadgeModel) {
        self.model = model
    }

    public var body: some View {
        Label {
            Text(LocalizedStringKey(model.titleKey))
        } icon: {
            Image(systemName: model.symbolName)
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // Material keeps the text legible on any tile colour; the tint is only a secondary cue.
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch model.kind {
        case .modified: return .orange
        case .cancelled: return .red
        case .added: return .green
        }
    }
}
#endif
