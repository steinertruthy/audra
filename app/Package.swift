// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Audra",
    defaultLocalization: "pt",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Audra",
            path: "Sources/Audra",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AudraTests",
            dependencies: ["Audra"],
            path: "Tests/AudraTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
