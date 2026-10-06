import Foundation
import Testing
@testable import TimetableCore

@Suite("ColorValue")
struct ColorValueTests {
    @Test func hexParsingAndFormatting() throws {
        #expect(ColorValue(hex: "#E53935") == ColorValue(red: 0xE5, green: 0x39, blue: 0x35))
        #expect(ColorValue(hex: "#e53935") == ColorValue(red: 0xE5, green: 0x39, blue: 0x35))
        #expect(ColorValue(hex: "#1E88E580") == ColorValue(red: 0x1E, green: 0x88, blue: 0xE5, alpha: 0x80))
        for bad in ["E53935", "#E5393", "#E539355", "#GGGGGG", "#E53935FF0", "", "#"] {
            #expect(ColorValue(hex: bad) == nil, "\(bad)")
        }
        #expect(ColorValue(red: 1, green: 2, blue: 3).hexString == "#010203")
        #expect(ColorValue(red: 1, green: 2, blue: 3, alpha: 0).hexString == "#01020300")
        #expect(ColorValue(hex: "#123456FF")?.hexString == "#123456")   // opaque alpha is implicit
        #expect(try Fixture.json(ColorValue(hex: "#abcdef")!) == "\"#ABCDEF\"")
        #expect(try Fixture.roundTrip(ColorValue(hex: "#1E88E580")!) == ColorValue(hex: "#1E88E580"))
        #expect(throws: DecodingError.self) { try Fixture.decode(ColorValue.self, "\"red\"") }
    }

    @Test func compositing() {
        let half = ColorValue(red: 0, green: 0, blue: 0, alpha: 128)
        let result = half.composited(over: .white)
        #expect(result.isOpaque && result.red == 127 && result.green == 127)
        #expect(ColorValue.white.composited(over: .black) == .white)
    }
}

@Suite("WCAG contrast")
struct ContrastTests {
    @Test func luminanceAndRatios() {
        #expect(ColorValue.white.relativeLuminance == 1)
        #expect(ColorValue.black.relativeLuminance == 0)
        #expect(abs(Contrast.ratio(.black, .white) - 21) < 1e-9)
        #expect(Contrast.ratio(.white, .black) == Contrast.ratio(.black, .white))
        #expect(abs(Contrast.ratio(ColorValue(hex: "#777777")!, .white) - 4.48) < 0.01)   // classic "just fails AA"
        #expect(abs(Contrast.ratio(ColorValue(hex: "#767676")!, .white) - 4.54) < 0.01)   // classic "just passes AA"
        #expect(Contrast.meetsAA(foreground: ColorValue(hex: "#767676")!, background: .white))
        #expect(!Contrast.meetsAA(foreground: ColorValue(hex: "#777777")!, background: .white))
        #expect(Contrast.meetsAA(foreground: ColorValue(hex: "#777777")!, background: .white, size: .large))
        #expect(ColorValue(hex: "#808080")!.contrastRatio(with: .black) > 5)
    }

    @Test func preferredTextColour() {
        #expect(ColorValue(hex: "#FDD835")!.preferredTextColor == .black)   // yellow
        #expect(ColorValue(hex: "#3949AB")!.preferredTextColor == .white)   // indigo
        #expect(ColorValue.white.preferredTextColor == .black)
        #expect(ColorValue.black.preferredTextColor == .white)
    }

    /// Property: for any opaque colour, black or white text reaches ≥ 4.5:1 (minimum ≈ 4.58 at L ≈ 0.18).
    @Test func blackOrWhiteAlwaysMeetsAAOnOpaqueColours() {
        var rng = TestRNG(seed: 11)
        var budget = FailureBudget()
        for _ in 0..<20_000 {
            let color = ColorValue(red: .random(in: 0...255, using: &rng), green: .random(in: 0...255, using: &rng),
                                   blue: .random(in: 0...255, using: &rng))
            if Contrast.ratio(color.preferredTextColor, color) < 4.5 { budget.record("\(color) fails") }
        }
        #expect(budget.count == 0)
    }

    @Test func translucentForegroundIsCompositedFirst() {
        let translucentBlack = ColorValue(red: 0, green: 0, blue: 0, alpha: 26)   // ~10 %
        #expect(Contrast.ratio(translucentBlack, .white) < 1.5)
    }
}

@Suite("Palette packs")
struct PalettePackTests {
    @Test func everyPaletteColourHasLegibleText() {
        for pack in PalettePack.all {
            for color in pack.colors {
                let ratio = Contrast.ratio(color.textColor, color.value)
                #expect(ratio >= 4.5, "\(pack.id) \(color.id) \(color.value) → \(ratio)")
                #expect(color.value.isOpaque)
            }
        }
    }

    @Test func packsAreWellFormed() {
        #expect(PalettePack.all.map(\.id) == PalettePackID.knownValues)
        for pack in PalettePack.all {
            #expect((10...14).contains(pack.colors.count), "\(pack.id) has \(pack.colors.count) colours")
            #expect(Set(pack.colors.map(\.id)).count == pack.colors.count)
            #expect(Set(pack.colors.map(\.value)).count == pack.colors.count)
            #expect(pack.nameKey == "palette.\(pack.id.rawValue).name")
            #expect(pack.colors.allSatisfy { $0.nameKey == "palette.\(pack.id.rawValue).color.\($0.id)" })
        }
        #expect(!PalettePack.classic.requiresPro)
        #expect(PalettePack.all.filter(\.requiresPro).count == 3)
        #expect(PalettePack.pack(.ocean) == .ocean)
        #expect(PalettePack.pack(PalettePackID(rawValue: "neon")) == nil)
        #expect(PalettePack.classic.color("red")?.value == ColorValue(hex: "#E53935"))
        #expect(PalettePack.pastel.colors.allSatisfy { $0.textColor == .black })
    }
}
