// swift-tools-version: 6.0

import PackageDescription

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
    dependencies: {
        var deps: [Package.Dependency] = []
        #if os(macOS)
        deps.append(.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.5"))
        deps.append(.package(url: "https://github.com/HeirloomLogic/SwiftFormatPlugin", from: "1.3.0"))
        #endif
        return deps
    }(),
    targets: {
        let cLib: Target = .target(
            name: "CLibAstronomy",
            path: "Sources/CLibAstronomy",
            sources: ["astronomy.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        )
        var plugins: [Target.PluginUsage] = []
        #if os(macOS)
        plugins.append(.plugin(name: "SwiftFormatBuildToolPlugin", package: "SwiftFormatPlugin"))
        #endif
        let lib: Target = .target(
            name: "AstronomyKit",
            dependencies: ["CLibAstronomy"],
            plugins: plugins
        )
        let tests: Target = .testTarget(
            name: "AstronomyKitTests",
            dependencies: ["AstronomyKit"],
            plugins: plugins
        )
        return [cLib, lib, tests]
    }()
)
