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
        .target(name: "TimetableCore"),
        .testTarget(name: "TimetableCoreTests", dependencies: ["TimetableCore"]),
    ],
    swiftLanguageModes: [.v6]
)
