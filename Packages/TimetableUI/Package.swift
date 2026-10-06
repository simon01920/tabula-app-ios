// swift-tools-version: 6.0
// TimetableUI — shared SwiftUI components for iOS app, widgets and watchOS.
// Sources are wrapped in `#if canImport(SwiftUI)` so the manifest/package can be validated on Linux.
import PackageDescription

let package = Package(
    name: "TimetableUI",
    platforms: [
        .iOS("26.0"),
        .watchOS("26.0"),
        .macOS("15.0"),
    ],
    products: [
        .library(name: "TimetableUI", targets: ["TimetableUI"]),
    ],
    dependencies: [
        .package(path: "../TimetableCore"),
    ],
    targets: [
        .target(
            name: "TimetableUI",
            dependencies: [.product(name: "TimetableCore", package: "TimetableCore")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
