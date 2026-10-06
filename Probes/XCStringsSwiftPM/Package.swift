// swift-tools-version: 6.0
// Isolated probe: is a String Catalog that is a SwiftPM *resource* compiled for iOS by xtool/SwiftBuild on Linux?
import PackageDescription

let package = Package(
    name: "XCStringsSwiftPM",
    defaultLocalization: "en",
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "XCStringsSwiftPM", targets: ["XCStringsSwiftPM"]),
    ],
    targets: [
        .target(name: "XCStringsSwiftPM", resources: [.process("Resources")]),
    ],
    swiftLanguageModes: [.v6]
)
