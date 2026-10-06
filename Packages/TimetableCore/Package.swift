// swift-tools-version: 6.0
// TimetableCore — pure Swift, no Apple-only imports. Must build and test on Linux (WSL) and macOS CI.
import PackageDescription

let package = Package(
    name: "TimetableCore",
    platforms: [
        .iOS("26.0"),
        .watchOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "TimetableCore", targets: ["TimetableCore"]),
    ],
    targets: [
        // System zlib (raw DEFLATE) for the share codec; internal, not a product. Not a package dependency:
        // Linux needs `zlib1g-dev`, Apple SDKs ship zlib.h + libz.tbd. See docs/specs/SHARE_FORMAT.md §6.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "TimetableCore", dependencies: ["CZlib"]),
        .testTarget(name: "TimetableCoreTests", dependencies: ["TimetableCore"]),
    ],
    swiftLanguageModes: [.v6]
)
