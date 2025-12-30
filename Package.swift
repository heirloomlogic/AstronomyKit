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
        )
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
            path: "Sources/AstronomyKit"
        ),
        .testTarget(
            name: "AstronomyKitTests",
            dependencies: ["AstronomyKit"],
            path: "Tests/AstronomyKitTests"
        ),
    ]
)
