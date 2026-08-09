// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PhotoAccessibilityStudio",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PhotoAccessibilityStudio", targets: ["PhotoAccessibilityStudio"])
    ],
    targets: [
        .executableTarget(
            name: "PhotoAccessibilityStudio",
            path: "Sources/PhotoAccessibilityStudio",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "PhotoAccessibilityStudioTests",
            dependencies: ["PhotoAccessibilityStudio"],
            path: "Tests/PhotoAccessibilityStudioTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
