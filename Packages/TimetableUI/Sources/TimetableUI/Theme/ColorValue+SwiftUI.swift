// SwiftUI bridge for TimetableCore colours and appearance. iOS + watchOS (watch-typecheck.sh).
// APIs: SwiftUI.Color.init(_:red:green:blue:opacity:) with Color.RGBColorSpace.sRGB, ColorScheme.
#if canImport(SwiftUI)
import SwiftUI
import TimetableCore

extension Color {
    /// The sRGB colour of a stored `ColorValue`.
    public init(_ value: ColorValue) {
        let rgba = RGBA(value)
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.opacity)
    }
}

extension AppearancePreference {
    /// For `.preferredColorScheme(_:)`: `nil` follows the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
#endif
