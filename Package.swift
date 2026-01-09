// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AstronomyKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "AstronomyKit",
            targets: ["AstronomyKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.5"),
        .package(url: "https://github.com/simplydanny/swiftlintplugins", from: "0.63.0"),
    ],
    targets: [
        .target(
            name: "CLibAstronomy",
            path: "Sources/CLibAstronomy",
            sources: ["astronomy.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "AstronomyKit",
            dependencies: ["CLibAstronomy"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
        .testTarget(
            name: "AstronomyKitTests",
            dependencies: ["AstronomyKit"],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")
            ]
        ),
    ]
)
