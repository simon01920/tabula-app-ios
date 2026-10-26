// DEBUG: the Phase 4U U1 design foundation on one screen (`-TabulaScreen debug.design`, CI screenshot route and
// on-device checklist docs/checklists/UX_DEVICE.md §U1). Shows every token resolved in the current appearance with its
// tested contrast, every AppSymbol with a live `UIImage(systemName:)` existence check (the only way to verify SF Symbol
// names: ENVIRONMENT §33), the NowMarker, the type scale and the adaptive layout helpers.
// Developer-facing: strings are verbatim (not localised). Macro-free (validate.sh guards App/Sources/Debug).
// APIs: List, Section, LabeledContent, UIImage(systemName:) (iOS 13), Environment(\.colorScheme / \.colorSchemeContrast
//   / \.dynamicTypeSize).
#if DEBUG
import SwiftUI
import TimetableCore
import TimetableUI
import UIKit

struct DesignSystemDebugScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isDark: Bool { colorScheme == .dark }
    private var increased: Bool { contrast == .increased }

    var body: some View {
        List {
            Section {
                LabeledContent("Appearance", value: "\(isDark ? "dark" : "light")\(increased ? " · Increase Contrast" : "")")
                LabeledContent("Dynamic Type", value: "\(dynamicTypeSize)")
                LabeledContent("AdaptiveStack stacked", value: AdaptiveLayout.isStacked(dynamicTypeSize) ? "yes" : "no")
                LabeledContent("Missing symbols", value: "\(missingSymbols.count)")
            } header: {
                Text(verbatim: "Environment")
            }
            Section {
                tokenRow("ink", DesignTokens.ink, Color.ink)
                tokenRow("onInk", DesignTokens.onInk, Color.onInk)
                tokenRow("correction", DesignTokens.correction, Color.correction)
                tokenRow("highlighter", DesignTokens.highlighter, Color.highlighter)
                tokenRow("pencil", DesignTokens.pencil, Color.pencil)
            } header: {
                Text(verbatim: "Tokens (contrast on white card / dark card)")
            }
            Section {
                HStack(spacing: 16) {
                    NowMarker(size: .small)
                    NowMarker()
                    ProBadge()
                }
                Button {} label: { Text(verbatim: "Prominent with onInk").onInkLabel() }
                    .buttonStyle(.borderedProminent)
                Button {} label: { Text(verbatim: "Bordered (tint)") }
                    .buttonStyle(.bordered)
                Text(verbatim: "Correction text").foregroundStyle(Color.correction)
                Text(verbatim: "Pencil text (data on cards)").foregroundStyle(Color.pencil)
            } header: {
                Text(verbatim: "Signature + controls")
            }
            Section {
                Text(verbatim: "Current lesson · title2 semibold").font(TypeScale.currentLesson)
                Text(verbatim: "Row title · headline").font(TypeScale.rowTitle)
                Text(verbatim: "Room 214 · body").font(TypeScale.detail)
                Text(verbatim: "Metadata · footnote").font(TypeScale.metadata).foregroundStyle(.secondary)
                Text(verbatim: "08:55 – 09:40").font(.body).timeStyle()
                Text(verbatim: "25 min left").font(.title3).countdownStyle()
            } header: {
                Text(verbatim: "Type scale")
            }
            Section {
                AdaptiveStack(spacing: 12) {
                    ScaledIcon(.room).foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(verbatim: "Elementary school")
                            .font(TypeScale.rowTitle)
                        Text(verbatim: "Big tiles, simple words").font(.subheadline).foregroundStyle(Color.pencil)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                .listRowBackground(DesignTokens.Surface.page)
            } header: {
                Text(verbatim: "AdaptiveStack + ScaledIcon on a card")
            }
            Section {
                ForEach(AppSymbol.allCases, id: \.self) { symbol in
                    HStack {
                        Image(symbol).frame(width: 28)
                        Text(verbatim: "\(symbol)").font(.subheadline)
                        Spacer()
                        Text(verbatim: symbol.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Image(systemName: exists(symbol) ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(exists(symbol) ? Color.green : Color.correction)
                            .accessibilityLabel(Text(verbatim: exists(symbol) ? "exists" : "MISSING"))
                    }
                }
            } header: {
                Text(verbatim: "AppSymbol (\(AppSymbol.allCases.count), live UIImage check)")
            }
        }
        .navigationTitle(Text(verbatim: "Design system"))
    }

    private var missingSymbols: [AppSymbol] { AppSymbol.allCases.filter { !exists($0) } }

    private func exists(_ symbol: AppSymbol) -> Bool { UIImage(systemName: symbol.rawValue) != nil }

    private func tokenRow(_ name: String, _ token: ColorToken, _ color: Color) -> some View {
        let value = token.resolved(isDark: isDark, increasedContrast: increased)
        let onWhite = value.contrastRatio(with: DesignTokens.Reference.lightCard)
        let onDark = value.contrastRatio(with: DesignTokens.Reference.darkCard)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 36, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary, lineWidth: 1))
            VStack(alignment: .leading) {
                Text(verbatim: name).font(.headline)
                Text(verbatim: "\(value.hexString) · \(onWhite.formatted(.number.precision(.fractionLength(1)))):1 / "
                     + "\(onDark.formatted(.number.precision(.fractionLength(1)))):1")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif // DEBUG
