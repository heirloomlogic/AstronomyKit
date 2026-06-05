// swift-tools-version: 6.0

import PackageDescription
import Foundation

// Dev-only tooling (the Persnoop swift-format linter and swift-docc-plugin) must not leak
// into downstream consumers' dependency graphs. SwiftPM has no first-class dev-dependencies,
// so gate it on a gitignored `.dev-tooling` sentinel, present only in this package's own
// working clone (and created as a step in CI). `#filePath` anchors the lookup to this
// manifest's directory, independent of the current working directory.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let devSentinel = packageDir.appendingPathComponent(".dev-tooling").path
let isDevBuild = FileManager.default.fileExists(atPath: devSentinel)

let devDependencies: [Package.Dependency] = isDevBuild
    ? [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
        .package(url: "https://github.com/heirloomlogic/Persnicket", from: "2.0.0"),
    ]
    : []

let devPlugins: [Target.PluginUsage] = isDevBuild
    ? [.plugin(name: "Persnoop", package: "Persnicket")]
    : []

let package = Package(
    name: "AstronomyKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
    ],
    products: [
        .library(
            name: "AstronomyKit",
            targets: ["AstronomyKit"]
        ),
    ],
    dependencies: devDependencies,
    targets: [
        .target(
            name: "AstronomyKit",
            dependencies: ["CLibAstronomy"],
            plugins: devPlugins
        ),
        .target(
            name: "CLibAstronomy",
            path: "Sources/CLibAstronomy",
            sources: ["astronomy.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .testTarget(
            name: "AstronomyKitTests",
            dependencies: ["AstronomyKit"],
            plugins: devPlugins
        ),
    ]
)
