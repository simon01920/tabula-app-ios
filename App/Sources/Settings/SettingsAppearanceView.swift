// Settings → Appearance: system/light/dark (applied at once by AppRootView's preferredColorScheme), palette pack
// picker with swatches and colour names, and a preview using the shared `LessonTileStyle` (text colour from WCAG
// contrast, outline for tiles close to the page background).
// Colour is never the only carrier: every swatch has its localised name (visible list + VoiceOver label).
// APIs: LazyVGrid(columns:) with GridItem.adaptive(minimum:maximum:), Circle().strokeBorder, Color(ColorValue),
//       accessibilityElement(children:), accessibilityAddTraits(.isSelected), @Environment(\.colorScheme).
import SwiftUI
import TimetableCore
import TimetableUI

struct SettingsAppearanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = PalettePackChoice.displayedPack(for: model.settings.palettePackID)
        Form {
            Section {
                Picker(selection: appearance) {
                    Text("settings.appearance.system").tag(Appearance.auto)
                    Text("settings.appearance.light").tag(Appearance.light)
                    Text("settings.appearance.dark").tag(Appearance.dark)
                } label: {
                    Text("settings.appearance.mode")
                }
                .pickerStyle(.inline)
            } header: {
                Text("settings.appearance.mode")
            }
            Section {
                ForEach(PalettePackChoice.all(isAllowed: model.entitlements.isAllowed)) { choice in
                    PackRow(choice: choice, isSelected: choice.pack.id == current.id) {
                        model.apply(.settings { $0.palettePackID = choice.pack.id })
                    }
                }
            } header: {
                Text("settings.appearance.palette.title")
            } footer: {
                Text("settings.appearance.palette.footer")
            }
            Section {
                ForEach(current.colors) { color in
                    HStack(spacing: 12) {
                        Swatch(color: color.value)
                        Text(LocalizedStringKey(color.nameKey))
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("settings.appearance.colors.title")
            }
            Section {
                PreviewTile(color: PalettePackChoice.previewColor(of: current))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("settings.appearance.preview.title")
            }
        }
        .navigationTitle(Text("settings.appearance.title"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isReadOnly)
    }

    private var appearance: Binding<Appearance> {
        Binding(get: { model.settings.appearance.effective }, set: { value in
            model.apply(.settings { $0.appearance = value })
        })
    }
}

/// A colour dot with a hairline edge so pale colours stay visible on any background.
private struct Swatch: View {
    let color: ColorValue
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .fill(Color(color))
            .overlay(Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One selectable pack: name, optional Pro marker, wrapped swatches, checkmark when selected.
private struct PackRow: View {
    @Environment(AppModel.self) private var model
    let choice: PalettePackChoice
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(LocalizedStringKey(choice.pack.nameKey)).font(.body.weight(.semibold))
                    if choice.pack.requiresPro {
                        Text("settings.appearance.palette.pro").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 24, maximum: 28), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(choice.pack.colors) { Swatch(color: $0.value, size: 24) }
                }
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!choice.isSelectable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
