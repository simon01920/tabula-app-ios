import Foundation

/// A named colour of a palette pack. `nameKey` is the catalog key used as the colour's accessibility name.
public struct PaletteColor: Hashable, Sendable, Identifiable {
    /// Stable ID within the pack (e.g. `"red"`).
    public let id: String
    /// Catalog key of the colour name (`palette.<pack>.color.<id>`).
    public let nameKey: String
    /// The colour.
    public let value: ColorValue

    /// Black or white, whichever is more legible on this colour (≥ 4.5:1 for every built-in colour).
    public var textColor: ColorValue { value.preferredTextColor }
}

/// A palette pack: data only (no UI). Packs other than Classic require Pro (`ProFeature.themePacks`).
public struct PalettePack: Hashable, Sendable, Identifiable {
    /// Pack ID (persisted in settings/timetables).
    public let id: PalettePackID
    /// Catalog key of the pack name (`palette.<pack>.name`).
    public let nameKey: String
    /// About twelve colours in presentation order.
    public let colors: [PaletteColor]
    /// `true` when the pack is gated behind `ProFeature.themePacks`.
    public let requiresPro: Bool

    init(id: PalettePackID, requiresPro: Bool, colors: [(String, String)]) {
        self.id = id
        self.nameKey = "palette.\(id.rawValue).name"
        self.requiresPro = requiresPro
        self.colors = colors.map { colorID, hex in
            guard let value = ColorValue(hex: hex) else { preconditionFailure("Invalid palette colour \(hex)") }
            return PaletteColor(id: colorID, nameKey: "palette.\(id.rawValue).color.\(colorID)", value: value)
        }
    }

    /// The colour with `id`, if present.
    public func color(_ id: String) -> PaletteColor? { colors.first { $0.id == id } }

    /// The built-in packs in presentation order.
    public static let all: [PalettePack] = [.classic, .ocean, .sunset, .pastel]

    /// The built-in pack with `id`, or `nil` for unknown IDs.
    public static func pack(_ id: PalettePackID) -> PalettePack? { all.first { $0.id == id } }

    /// Bright, distinct primaries (free).
    public static let classic = PalettePack(id: .classic, requiresPro: false, colors: [
        ("red", "#E53935"), ("orange", "#FB8C00"), ("yellow", "#FDD835"), ("green", "#43A047"),
        ("teal", "#00897B"), ("cyan", "#00ACC1"), ("blue", "#1E88E5"), ("indigo", "#3949AB"),
        ("purple", "#8E24AA"), ("pink", "#D81B60"), ("brown", "#6D4C41"), ("gray", "#757575"),
    ])

    /// Blues, teals and sand (Pro).
    public static let ocean = PalettePack(id: .ocean, requiresPro: true, colors: [
        ("abyss", "#0B2545"), ("navy", "#13315C"), ("harbor", "#1B4965"), ("deepSea", "#2A6F97"),
        ("lagoon", "#168AAD"), ("teal", "#0F9D9A"), ("seafoam", "#52B69A"), ("aqua", "#76C893"),
        ("sky", "#61A5C2"), ("mist", "#A9D6E5"), ("sand", "#E9D8A6"), ("coral", "#EE6C4D"),
    ])

    /// Warm reds, oranges and purples (Pro).
    public static let sunset = PalettePack(id: .sunset, requiresPro: true, colors: [
        ("crimson", "#9B2226"), ("rust", "#AE2012"), ("ember", "#BB3E03"), ("tangerine", "#CA6702"),
        ("amber", "#EE9B00"), ("gold", "#F4C430"), ("peach", "#FFB4A2"), ("rose", "#E5989B"),
        ("magenta", "#B5179E"), ("plum", "#7209B7"), ("violet", "#560BAD"), ("dusk", "#3A0CA3"),
    ])

    /// Soft light tints (Pro). Text on these is always black.
    public static let pastel = PalettePack(id: .pastel, requiresPro: true, colors: [
        ("pink", "#FFADAD"), ("peach", "#FFD6A5"), ("lemon", "#FDFFB6"), ("mint", "#CAFFBF"),
        ("aqua", "#9BF6FF"), ("periwinkle", "#A0C4FF"), ("lavender", "#BDB2FF"), ("lilac", "#FFC6FF"),
        ("sage", "#B5E48C"), ("sky", "#BDE0FE"), ("blush", "#FFC8DD"), ("linen", "#E9EDC9"),
    ])
}
