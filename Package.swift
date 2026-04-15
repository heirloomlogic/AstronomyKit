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
        .package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", from: "1.3.0"),
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
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
        .testTarget(
            name: "AstronomyKitTests",
            dependencies: ["AstronomyKit"],
            plugins: [
                .plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin")
            ]
        ),
    ]
)
