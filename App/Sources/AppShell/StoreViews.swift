// Persistence status UI: the banner above the shell (recovery, read-only, failed save, rejected change) and the
// blocking screen when nothing can be loaded. Icon + text, never colour alone; Dynamic Type friendly (no fixed
// heights, text wraps); the banner text is one VoiceOver element, the dismiss button a second.
// APIs: Label, Image(systemName:), Button, View.background(_:ignoresSafeAreaEdges:) with .bar material,
//       accessibilityElement(children:), accessibilityLabel(_:), ContentUnavailableView(label:description:actions:).
import SwiftUI
import TimetableUI

struct StoreBannerView: View {
    let banner: StoreBanner
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: banner.symbolName)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(banner.titleKey))
                    .font(.subheadline.weight(.semibold))
                Text(LocalizedStringKey(banner.messageKey))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if banner.isDismissible {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("store.banner.dismiss"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct StoreProblemView: View {
    let problem: StoreProblem

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(LocalizedStringKey(problem.titleKey))
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
            }
        } description: {
            Text(LocalizedStringKey(problem.messageKey))
        } actions: {
            EmptyView()
        }
    }
}
