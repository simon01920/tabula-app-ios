// The processing screen of the photo import (Phase 9 I2): the picture the import reads and three real steps
//   Reading the image → Finding the table → Understanding lessons
// Each step shows done (checkmark) / running (spinner) / waiting (empty circle) as the pipeline reaches it: no timer,
// no fake waiting. Cancel (toolbar, owned by PhotoImportView) cancels the running task.
// Accessibility: the steps are one element per step ("Finding the table, in progress"); the running step updates
// frequently; Reduce Motion drops the step transition.
// HIG: loading.md (show progress, let people cancel), progress-indicators.md (indeterminate spinner while a step runs).
import SwiftUI
import TimetableUI

/// The steps of the import, in order.
enum ImportStep: Int, CaseIterable, Comparable, Sendable {
    case reading, finding, understanding

    static func < (lhs: ImportStep, rhs: ImportStep) -> Bool { lhs.rawValue < rhs.rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .reading: return "import.step.reading"
        case .finding: return "import.step.finding"
        case .understanding: return "import.step.understanding"
        }
    }
}

struct ImportProcessingView: View {
    let image: UIImage?
    let step: ImportStep
    let usesAppleIntelligence: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .accessibilityLabel(Text("import.image.a11y"))
                }
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ImportStep.allCases, id: \.self) { item in
                        row(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .animation(reduceMotion ? nil : .smooth, value: step)
                Label {
                    Text(usesAppleIntelligence ? "import.processing.footer.ai" : "import.processing.footer")
                } icon: {
                    Image(systemName: usesAppleIntelligence ? "sparkles" : "lock.iphone")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func row(_ item: ImportStep) -> some View {
        HStack(spacing: 14) {
            Group {
                if item < step {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ink)
                } else if item == step {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            Text(item.titleKey)
                .font(item == step ? .body.weight(.semibold) : .body)
                .foregroundStyle(item > step ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(item < step ? "import.step.done" : item == step ? "import.step.running" : "import.step.waiting"))
        .accessibilityAddTraits(item == step ? .updatesFrequently : [])
    }
}
