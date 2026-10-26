// Settings → Colors (routes `settings.colours`, alias `settings.appearance`; Phase 4U U5a, D3 / M26).
//   - The in-app Light/Dark override is GONE (D3, HIG dark-mode.md "Avoid offering an app-specific appearance setting"):
//     the app follows the system. `AppSettings.appearance` stays in the frozen schema; nothing reads or writes it any more.
//   - The palette is a `Picker` (inline) whose rows show the name and a swatch strip; Pro palettes carry U1's `ProBadge`
//     plus `lock.fill` while the plan does not include them (choosing a locked palette does nothing).
//   - A live preview tile (the shared `LessonTileStyle`: text colour from WCAG contrast, outline near the page colour).
//   - "Apply to All Subjects" maps every subject's colour onto the chosen palette by index, after a confirmation, and
//     offers Undo through the normal write path (`PaletteRemap` + `DatabaseMutation`).
// Colour is never the only carrier: each pack row has its localised name and a VoiceOver label listing its colours.
// APIs: Picker(.inline), LazyVGrid(columns:) with GridItem.adaptive, Circle().strokeBorder, Color(ColorValue),
//       confirmationDialog(_:isPresented:titleVisibility:actions:message:), accessibilityElement(children:).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsColoursView: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false
    /// The subjects as they were before the last "Apply to All Subjects" (for Undo) and how many changed.
    @State private var applied: AppliedPalette?

    private struct AppliedPalette {
        var originals: [Subject]
    }

    var body: some View {
        let current = PalettePackChoice.displayedPack(for: model.settings.palettePackID)
        let choices = PalettePackChoice.all(isAllowed: model.entitlements.isAllowed)
        let pending = model.database.map { PaletteRemap.remapped(in: $0, to: current, locale: model.formatter.locale) } ?? []
        Form {
            Section {
                Picker(selection: palette(choices)) {
                    ForEach(choices) { choice in
                        PackRow(choice: choice).tag(choice.pack.id)
                    }
                } label: {
                    Text("settings.colors.palette.title")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("settings.colors.palette.title")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("settings.colors.palette.footer")
                    if choices.contains(where: { !$0.isSelectable }) { Text("settings.colors.pro.footer") }
                }
            }
            Section {
                PreviewTile(color: PalettePackChoice.previewColor(of: current))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("settings.appearance.preview.title")
            }
            Section {
                Button { confirming = true } label: {
                    Text("settings.colors.apply")
                }
                .disabled(pending.isEmpty || model.isReadOnly)
                if let applied {
                    HStack {
                        Text(verbatim: model.renderer.format(key: "settings.colors.applied",
                                                             arguments: [.integer(Int64(applied.originals.count))]))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button { undo(applied) } label: { Text("settings.colors.undo") }
                            .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("settings.colors.apply.footer")
            }
        }
        .navigationTitle(Text("settings.colors.title"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
        .confirmationDialog(
            Text(verbatim: model.renderer.format(key: "settings.colors.apply.confirm.title", arguments: [
                .text(model.renderer.string(forKey: current.nameKey)),
            ])),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button { apply(pending) } label: { Text("settings.colors.apply") }
            Button(role: .cancel) {} label: { Text("editor.common.cancel") }
        } message: {
            Text(verbatim: model.renderer.format(key: "settings.colors.apply.confirm.message",
                                                 arguments: [.integer(Int64(pending.count))]))
        }
    }

    /// Choosing a locked palette is ignored (the lock and the footer say why).
    private func palette(_ choices: [PalettePackChoice]) -> Binding<PalettePackID> {
        Binding(get: { PalettePackChoice.displayedPack(for: model.settings.palettePackID).id }, set: { id in
            guard choices.first(where: { $0.pack.id == id })?.isSelectable == true else { return }
            applied = nil
            model.apply(.settings { $0.palettePackID = id })
        })
    }

    private func apply(_ changes: [Subject]) {
        guard !changes.isEmpty, let database = model.database else { return }
        let originals = changes.compactMap { change in database.subjects.first { $0.id == change.id } }
        guard let mutation = PaletteRemap.mutation(for: changes) else { return }
        if case .applied = model.apply(mutation) { applied = AppliedPalette(originals: originals) }
    }

    private func undo(_ state: AppliedPalette) {
        guard let mutation = PaletteRemap.mutation(for: state.originals, label: "undo palette") else { return }
        if case .applied = model.apply(mutation) { applied = nil }
    }
}

/// A colour dot with a hairline edge so pale colours stay visible on any background.
private struct Swatch: View {
    let color: ColorValue
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(Color(color))
            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One palette option: name, Pro marker, wrapped swatch strip. Selection state comes from the enclosing `Picker`.
private struct PackRow: View {
    @Environment(AppModel.self) private var model
    let choice: PalettePackChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(choice.pack.nameKey)).font(.body.weight(.semibold))
                if choice.pack.requiresPro { proCapsule }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 22, maximum: 26), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(choice.pack.colors) { Swatch(color: $0.value) }
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// U1's `ProBadge`; the padlock only while the pack is locked.
    private var proCapsule: some View {
        HStack(spacing: 3) {
            if !choice.isSelectable { Image(AppSymbol.proLocked).font(.caption).foregroundStyle(.secondary) }
            ProBadge()
        }
    }

    /// "Ocean, Pro, Abyss, Navy, …" in the app language (catalog lookup, joined with the locale's list style).
    private var accessibilityLabel: String {
        let lookup = model.environment.catalogLookup
        var parts = [lookup(choice.pack.nameKey)]
        if choice.pack.requiresPro { parts.append(lookup("settings.appearance.palette.pro")) }
        parts.append(model.formatter.list(choice.pack.colors.map { lookup($0.nameKey) }))
        return parts.joined(separator: model.renderer.string(forKey: "a11y.separator"))
    }
}

/// A lesson-tile preview in the first colour of the shown pack.
private struct PreviewTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let color: PaletteColor

    var body: some View {
        let style = LessonTileStyle(color: color.value)
        let foreground = Color(style.foreground)
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(color.nameKey)).font(.headline)
            if let range = timeRange { Text(range).font(.subheadline) }
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(12)
        .background(Color(style.background), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if style.needsOutline(isDark: colorScheme == .dark) {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var timeRange: String? {
        guard let start = LocalTime(hour: 8, minute: 0), let end = LocalTime(hour: 8, minute: 45) else { return nil }
        return model.formatter.timeRange(start, end)
    }
}
