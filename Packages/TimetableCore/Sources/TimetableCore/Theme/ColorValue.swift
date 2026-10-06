import Foundation

/// An sRGB colour with 8-bit channels and alpha. JSON: `"#RRGGBB"` when opaque, else `"#RRGGBBAA"`
/// (uppercase on encode; decoding is case-insensitive and requires the `#` and 6 or 8 hex digits).
///
/// Integer channels keep the persisted value exact (no floating-point drift between platforms).
public struct ColorValue: Hashable, Sendable, CustomStringConvertible {
    /// Red, 0…255.
    public var red: UInt8
    /// Green, 0…255.
    public var green: UInt8
    /// Blue, 0…255.
    public var blue: UInt8
    /// Alpha, 0 (transparent) … 255 (opaque).
    public var alpha: UInt8

    /// Creates a colour from 8-bit channels.
    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `"#RRGGBB"` or `"#RRGGBBAA"` (case-insensitive); `nil` otherwise.
    public init?(hex: String) {
        let bytes = Array(hex.utf8)
        guard bytes.first == UInt8(ascii: "#"), bytes.count == 7 || bytes.count == 9 else { return nil }
        var channels: [UInt8] = []
        var index = 1
        while index < bytes.count {
            guard let high = Self.nibble(bytes[index]), let low = Self.nibble(bytes[index + 1]) else { return nil }
            channels.append(high << 4 | low)
            index += 2
        }
        self.init(red: channels[0], green: channels[1], blue: channels[2], alpha: channels.count == 4 ? channels[3] : 255)
    }

    /// Opaque black.
    public static let black = ColorValue(red: 0, green: 0, blue: 0)
    /// Opaque white.
    public static let white = ColorValue(red: 255, green: 255, blue: 255)

    /// `true` when `alpha == 255`.
    public var isOpaque: Bool { alpha == 255 }

    /// `"#RRGGBB"` or `"#RRGGBBAA"`, uppercase.
    public var hexString: String {
        var string = "#" + PaddedNumber.hex(UInt64(red), width: 2) + PaddedNumber.hex(UInt64(green), width: 2)
            + PaddedNumber.hex(UInt64(blue), width: 2)
        if !isOpaque { string += PaddedNumber.hex(UInt64(alpha), width: 2) }
        return string
    }

    /// Same as `hexString`.
    public var description: String { hexString }

    /// This colour alpha-composited over an opaque `background` (result is opaque).
    public func composited(over background: ColorValue) -> ColorValue {
        guard !isOpaque else { return self }
        let a = Double(alpha) / 255
        func mix(_ fg: UInt8, _ bg: UInt8) -> UInt8 {
            UInt8((Double(fg) * a + Double(bg) * (1 - a)).rounded())
        }
        return ColorValue(red: mix(red, background.red), green: mix(green, background.green),
                          blue: mix(blue, background.blue))
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

extension ColorValue: Codable {
    /// Decodes `"#RRGGBB[AA]"`; anything else is a `DecodingError.dataCorrupted`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = ColorValue(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid colour '\(string)'")
        }
        self = value
    }

    /// Encodes `hexString`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}
