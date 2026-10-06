// swift-tools-version: 6.0
// Isolated probe: SwiftData macros under xtool. NOT part of the app. See docs/ENVIRONMENT.md §13.
import PackageDescription

let package = Package(
    name: "MacroProbeSwiftData",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "MacroProbeSwiftData", targets: ["MacroProbeSwiftData"]),
    ],
    targets: [
        .target(name: "MacroProbeSwiftData"),
    ],
    swiftLanguageModes: [.v6]
)
